import { BrowserIOOperation, BrowserIOEvent } from './protocol.generated.mjs';
import { DOMViewError, createDOMViewHost } from './dom-view-host.mjs';
import { foldText, formatNumber } from './text-format.mjs';
import { createPredicates } from './predicate-engine.mjs';
import { createUnicodeImports } from './unicode-data.mjs';

const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
const MAX_PACKET = 64 * 1024 * 1024;
// Operations a host can start again from their packet when the app moves to another thread (observers and timers; a
// read-only fetch joins them once its request is parsed). Writes and transactions are reported as cancelled instead.
const RESTARTABLE = new Set([BrowserIOOperation.timer, BrowserIOOperation.storageChanges, BrowserIOOperation.connectivityChanges, BrowserIOOperation.media]);
// Whether starting the operation again could repeat a side effect: every operation except the observers and a fetch
// whose method only reads (GET, HEAD). Used when the app moves threads (see `fenceUnstarted` and `refuseReplayed`).
function mayRepeatEffect(operation, packet) {
  if (RESTARTABLE.has(operation)) return false;
  if (operation !== BrowserIOOperation.fetch) return true;
  try { const input = new Reader(packet); input.text(); return !['GET', 'HEAD'].includes(input.text().toUpperCase()); }
  catch { return true; }
}
function sameBytes(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
const MAX_U64 = 0xffffffffffffffffn;
class IOError extends Error { constructor(code, message) { super(message); this.code = code; } }
/** A window this page opens for `openURL` shows another site, which must not reach back through `window.opener` and
 * navigate the application's own tab to a page of its choosing. The link is cut right after `open`, while the new window
 * still holds its initial blank document; `noopener` would cut it too, but then `open` returns null and a blocked popup
 * could not be told from an opened one. True when a window was opened. */
export function severOpener(opened) {
  if (!opened) return false;
  try { opened.opener = null; } catch { /* the window is already gone */ }
  return true;
}

export class Writer {
  constructor() { this.parts = []; this.size = 0; }
  raw(bytes) { const value = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes); this.parts.push(value); this.size += value.length; return this; }
  u32(value) { const out = new Uint8Array(4); new DataView(out.buffer).setUint32(0, value >>> 0, true); return this.raw(out); }
  u64(value) { const n = BigInt(value); if (n < 0n || n > MAX_U64) throw new IOError(-8, 'Unsigned 64-bit value is out of range'); return this.u32(Number(n & 0xffffffffn)).u32(Number((n >> 32n) & 0xffffffffn)); }
  f64(value) { const out=new Uint8Array(8); new DataView(out.buffer).setFloat64(0, Number(value), true); return this.raw(out); }
  data(value) { return this.u32(value.length).raw(value); }
  text(value) { return this.data(encoder.encode(String(value))); }
  bytes() { if (this.size > MAX_PACKET) throw new IOError(-1, 'Host packet exceeds its limit'); const out = new Uint8Array(this.size); let at = 0; for (const part of this.parts) { out.set(part, at); at += part.length; } return out; }
}
export class Reader {
  constructor(bytes) { this.bytes = bytes; this.at = 0; this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength); }
  u32() { if (this.at + 4 > this.bytes.length) throw new IOError(-1, 'Truncated host packet'); const result = this.view.getUint32(this.at, true); this.at += 4; return result; }
  u64() { return BigInt(this.u32()) | (BigInt(this.u32()) << 32n); }
  f64() { if(this.at+8>this.bytes.length) throw new IOError(-1, 'Truncated host packet'); const result=this.view.getFloat64(this.at,true); this.at+=8; return result; }
  data() { const n = this.u32(); if (n > this.bytes.length - this.at) throw new IOError(-1, 'Invalid host packet length'); const result = this.bytes.slice(this.at, this.at + n); this.at += n; return result; }
  text() { return decoder.decode(this.data()); }
  finish() { if (this.at !== this.bytes.length) throw new IOError(-1, 'Unexpected trailing host packet data'); }
}
function classify(error) {
  if (error instanceof IOError) return error;
  if (error instanceof DOMViewError) return new IOError(error.code, error.message);
  const code = error?.name === 'QuotaExceededError' ? -3 : error?.name === 'SecurityError' || error?.name === 'NotAllowedError' ? -2 : error?.name === 'AbortError' ? -4 : -6;
  return new IOError(code, safeErrorMessage(error));
}
// Host diagnostics must never echo credentials, cookies, request bodies or
// query strings into the RenderNode/DOM error channel or console. Keep the
// stable error class/name because callers use the code, not an opaque message.
export function safeErrorMessage(error) {
  const raw = String(error?.message || error || 'Browser host error');
  return raw
    .replace(/([?&](?:token|access_token|refresh_token|code|key|secret|password|authorization))=[^&#\s]*/gi, '$1=[redacted]')
    .replace(/(authorization\s*:\s*)(?:bearer\s+)?[^,;\s]+/gi, '$1[redacted]')
    .replace(/(cookie\s*:\s*)([^,;\s]+)/gi, '$1[redacted]')
    .replace(/(bearer\s+)[^\s]+/gi, '$1[redacted]')
    .replace(/https?:\/\/[^\s]+/gi, value => {
      try { const url = new URL(value); url.username = ''; url.password = ''; url.search = ''; url.hash = ''; return url.href; }
      catch { return '[redacted-url]'; }
    })
    .slice(0, 512);
}
/** Per-instance host. Never replace blocked persistence with a fake success. */
// `remoteDOM` is the worker side of the DOM bridge: the worker has no document, so
// DOM reads answer from a mirror of the mounted elements that the main thread reported
// before the last reconciliation, and DOM writes are queued for the main thread
// (remote-dom-host.js) to apply in order. See Documentation/EmbeddedWorker.md.
export function createBrowserIO({ getInstance, environment = globalThis, baseURL, onError = (e) => console.error(safeErrorMessage(e)), wake = () => {}, remoteDOM = false, stackMeter = null, onCookieWrite = () => {} }) {
  const operations = new Map(); const replies = new Map(); const databases = new Map(); let nextReply = 1; let disposed = false;
  // Side-effecting fetches started since the last snapshot (their id, operation and packet), and on a thread that took
  // the app over, the ones the Worker already sent: a replay asking for one of them again fails instead of sending it.
  let sent = []; const refusals = new Map();
  const takeRefusal = (id, operation, packet) => {
    const key = `${id}:${operation}`; const packets = refusals.get(key); if (!packets) return false;
    const at = packets.findIndex(candidate => sameBytes(candidate, packet)); if (at < 0) return false;
    packets.splice(at, 1); if (!packets.length) refusals.delete(key);
    return true;
  };
  const domIDs = new WeakMap(); const domElements = new Map(); let nextDOMID = 1;
  // Handles of elements that left the document. They are released one WebMount reconcile late, so the
  // reconcile that notices the removal can still unmount through them (a DOM component's dispose).
  let detachedDOMHandles = [];
  const domViews = remoteDOM ? null : createDOMViewHost(environment, { report: (element, error) => reportDOMError(element, error) });
  const mirror = { seq: 0, nodes: new Map(), ops: [], reported: new Set() };
  const domID = (element) => { if (!element) return 0; let id=domIDs.get(element); if (!id) { while (!nextDOMID || domElements.has(nextDOMID)) nextDOMID=(nextDOMID+1)>>>0; id=nextDOMID; nextDOMID=(nextDOMID+1)>>>0; domIDs.set(element,id); domElements.set(id,element); } return id; };
  const memory = () => {
    const value = getInstance()?.exports?.memory;
    if (!(value instanceof WebAssembly.Memory)) throw new IOError(-7, 'BrowserIO has no WASM memory');
    return value;
  };
  const read = (pointer, length) => {
    pointer >>>= 0; length >>>= 0;
    const bytes = new Uint8Array(memory().buffer);
    if (length > MAX_PACKET || pointer > bytes.length || length > bytes.length - pointer) throw new IOError(-1, 'Out-of-bounds host packet');
    return bytes.slice(pointer, pointer + length);
  };
  const cleanupOperation = (op, abort = false) => {
    if (!op) return;
    if (op.timer !== null) { clearTimeout(op.timer); op.timer = null; }
    try { op.cleanup?.(); } finally { op.cleanup = null; }
    if (abort) {
      try { op.controller?.abort(); } catch {}
      try { op.transaction?.abort(); } catch {}
      // Aborting fetch may already have errored its body. reader.cancel()
      // then rejects asynchronously; cancellation is delivered below through
      // the operation callback, so cleanup must not leak an unhandled promise.
      try { op.reader?.cancel?.().catch(() => {}); } catch {}
    }
    op.transaction = null; op.reader = null;
  };
  const emit = (id, code, payload = new Uint8Array()) => {
    const current = operations.get(id);
    if (!current || disposed) return;
    if (code < 100) { cleanupOperation(current); operations.delete(id); }
    const instance = getInstance(); const alloc = instance?.exports?.browser_io_alloc; const deliver = instance?.exports?.browser_io_deliver; const receive = instance?.exports?.browser_io_receive; const release = instance?.exports?.browser_io_free;
    if (typeof alloc !== 'function' || (typeof deliver !== 'function' && typeof receive !== 'function')) throw new IOError(-7, 'BrowserIO C exports are missing');
    const ptr = alloc(payload.length) >>> 0;
    if (!ptr) throw new IOError(-6, 'WASM allocation failed');
    new Uint8Array(memory().buffer, ptr, payload.length).set(payload);
    // The C trampoline owns and frees this buffer after copying it into Swift.
    if (typeof receive === 'function' && typeof release === 'function') {
      receive(id, code, ptr, payload.length);
      release(ptr);
    } else {
      deliver(id, code, ptr, payload.length);
    }
    // Resuming a Swift continuation enqueues its waiting task on the
    // Embedded browser executor. Give the host a chance to drain it.
    wake();
  };
  const fail = (id, error) => { const value = classify(error); emit(id, value.code, encoder.encode(value.message)); };
  const responseHeader = (response) => {
    const out = new Writer().u32(response.status).text(response.url);
    const headers = [...response.headers.entries()].filter(([key]) => {
      const normalized = key.toLowerCase();
      return normalized !== 'set-cookie' && normalized !== 'set-cookie2';
    });
    out.u32(headers.length);
    // Set-Cookie is a forbidden response header in browsers, but some native
    // fetch implementations expose it. Never move session material across
    // the Swift bridge: cookies stay owned by the browser's cookie jar and
    // are sent back through the request credentials policy only.
    for (const [key, value] of headers) out.text(key).text(value);
    return out;
  };
  // fetch rejects with a TypeError for every network-level failure (DNS, TCP, TLS, CORS, offline).
  // Browsers do not expose which one occurred, so the host reports the phase and offline state only.
  function networkFailure(error, phaseCode) {
    if (error?.name !== 'TypeError') return error;
    if (environment.navigator?.onLine === false) return new IOError(-12, 'The device is offline');
    return new IOError(phaseCode, 'The network request failed');
  }
  // XMLHttpRequest is the only browser API that reports request-body progress. It cannot omit
  // same-origin cookies or refuse redirects, so fetchRequest uses it only for the modes it can honor.
  // Download progress of a buffered response, as the host reads it. Reports are throttled to one per 50 ms or per
  // 64 KiB, so a large download does not flood the bridge, and `finish` always reports the whole body. The host
  // sends the length headers it can see; Swift applies Foundation's rule, so no length policy lives here.
  function downloadProgressReporter(id, response) {
    const contentLength = response.headers.get('content-length') ?? '';
    const contentEncoding = response.headers.get('content-encoding') ?? '';
    const now = () => (typeof performance?.now === 'function' ? performance.now() : Date.now());
    let reportedAt = -Infinity; let reportedBytes = -1;
    const report = (received) => {
      reportedAt = now(); reportedBytes = received;
      emit(id, BrowserIOEvent.fetchDownloadProgress, new Writer().u64(received).text(contentLength).text(contentEncoding).bytes());
    };
    return {
      update(received) { if (received - reportedBytes >= 65536 || now() - reportedAt >= 50) report(received); },
      finish(received) { report(received); },
    };
  }
  function xhrRequest(id, op, target, method, headers, credentials, body, limit) {
    return new Promise((resolve, reject) => {
      const xhr = new environment.XMLHttpRequest();
      xhr.open(method, target.href, true);
      xhr.responseType = 'arraybuffer';
      xhr.withCredentials = credentials === 'include';
      headers.forEach((value, name) => xhr.setRequestHeader(name, value));
      const abort = () => { try { xhr.abort(); } catch {} };
      const settle = () => op.controller.signal.removeEventListener('abort', abort);
      op.controller.signal.addEventListener('abort', abort, { once: true });
      xhr.upload.onprogress = (event) => {
        if (!event.lengthComputable || !operations.has(id)) return;
        try { emit(id, BrowserIOEvent.fetchUploadProgress, new Writer().u64(event.loaded).u64(event.total).bytes()); }
        catch (error) { onError(error); }
      };
      // Stop downloading once the body passes the limit; the first settle wins, so this is the error the caller sees.
      xhr.onprogress = (event) => {
        if (event.loaded <= limit) return;
        settle();
        reject(new IOError(-14, 'Response exceeded maximumResponseBytes'));
        try { xhr.abort(); } catch {}
      };
      xhr.onload = () => {
        settle();
        const responseHeaders = new Headers();
        for (const line of (xhr.getAllResponseHeaders() || '').split(/\r?\n/)) {
          const index = line.indexOf(':');
          if (index > 0) responseHeaders.append(line.slice(0, index).trim(), line.slice(index + 1).trim());
        }
        resolve({ response: { status: xhr.status, url: xhr.responseURL || target.href, headers: responseHeaders }, bytes: new Uint8Array(xhr.response || new ArrayBuffer(0)) });
      };
      xhr.onerror = () => { settle(); reject(networkFailure(new TypeError('Network request failed'), -9)); };
      xhr.onabort = () => { settle(); reject(Object.assign(new Error('Operation cancelled'), { name: 'AbortError' })); };
      xhr.send(body);
    });
  }
  async function fetchRequest(id, packet) {
    const input = new Reader(packet); const url = input.text(); const method = input.text().toUpperCase(); const credentials = input.text(); const redirect = input.text();
    const timeout = input.u32(); const limit = input.u32(); const mode = input.u32(); const count = input.u32();
    if (mode > 7) throw new IOError(-1, 'Invalid request mode');
    const streaming = (mode & 1) === 1; const reportsUpload = (mode & 2) === 2; const reportsDownload = (mode & 4) === 4;
    if (count > 256 || !limit || limit > MAX_PACKET - 65536) throw new IOError(-1, 'Invalid request bounds');
    if (!['omit', 'same-origin', 'include'].includes(credentials)) throw new IOError(-1, 'Invalid request credentials');
    if (!['follow', 'manual', 'error'].includes(redirect)) throw new IOError(-1, 'Invalid redirect policy');
    const headers = new Headers(); for (let i = 0; i < count; i++) headers.append(input.text(), input.text());
    const hasBody = input.u32(); const body = input.data();
    // The cache mode is the packet's last field; an older encoding ends before it and keeps the default.
    const cache = input.at < input.bytes.length ? input.text() : 'default';
    input.finish();
    if (!['default', 'no-store', 'reload', 'no-cache'].includes(cache)) throw new IOError(-1, 'Invalid request cache mode');
    let target;
    try { target = new URL(url, baseURL || environment.location?.href); }
    catch { throw new IOError(-16, 'The request URL is invalid'); }
    if (!['http:', 'https:'].includes(target.protocol)) throw new IOError(-15, 'Only HTTP and HTTPS requests are supported');
    if (hasBody && ['GET', 'HEAD'].includes(method)) throw new IOError(-1, 'GET and HEAD requests cannot have a body');
    const op = operations.get(id); if (!op) return;
    // A request that only reads can run again after the app moved threads; anything else is reported as cancelled.
    op.restart = !hasBody && ['GET', 'HEAD'].includes(method);
    if (!op.restart) { op.packet = null; sent.push({ id, operation: BrowserIOOperation.fetch, packet }); }
    if (typeof environment.fetch !== 'function') throw new IOError(-7, 'Fetch is unavailable');
    if (timeout) op.timer = setTimeout(() => { if (!operations.has(id)) return; op.controller.abort(); fail(id, new IOError(-5, 'Request timed out')); }, Math.min(timeout, 2147483647));
    if (reportsUpload && hasBody && !streaming && credentials !== 'omit' && redirect === 'follow' && typeof environment.XMLHttpRequest === 'function') {
      // XHR has no cache mode, and this path only sends bodies (uploads), whose answers the HTTP cache does not keep. A
      // Cache-Control header would be a non-safelisted header and make a cross-origin upload need a CORS preflight.
      const xhr = await xhrRequest(id, op, target, method, headers, credentials, body, limit);
      if (!operations.has(id)) return;
      if (xhr.bytes.length > limit) throw new IOError(-14, 'Response exceeded maximumResponseBytes');
      emit(id, 0, responseHeader(xhr.response).data(xhr.bytes).bytes());
      return;
    }
    let response;
    try { response = await environment.fetch(target.href, { method, headers, credentials, redirect, cache, body: hasBody ? body : undefined, signal: op.controller.signal }); }
    catch (error) { throw networkFailure(error, -9); }
    if (!operations.has(id)) return;
    if (streaming) emit(id, BrowserIOEvent.fetchHeaders, responseHeader(response).bytes());
    // A streamed body needs no download reports: its chunks already reach Swift, which counts them.
    const progress = reportsDownload && !streaming ? downloadProgressReporter(id, response) : null;
    const chunks = []; let size = 0;
    if (response.body) {
      const reader = response.body.getReader(); op.reader = reader;
      try {
        for (;;) {
          const item = await reader.read().catch((error) => { throw networkFailure(error, -13); }); if (!operations.has(id)) return;
          if (item.done) break;
          size += item.value.length;
          if (size > limit) { await reader.cancel(); throw new IOError(-14, 'Response exceeded maximumResponseBytes'); }
          if (streaming) emit(id, BrowserIOEvent.fetchChunk, item.value); else { chunks.push(item.value); progress?.update(size); }
        }
      } finally { reader.releaseLock(); op.reader = null; }
    }
    if (!operations.has(id)) return;
    if (streaming) emit(id, 0);
    else { progress?.finish(size); const bytes = new Uint8Array(size); let at = 0; for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.length; } emit(id, 0, responseHeader(response).data(bytes).bytes()); }
  }
  async function timerRequest(id, packet) {
    const input = new Reader(packet); const seconds = input.f64(); input.finish();
    if (!Number.isFinite(seconds) || seconds < 0 || seconds > 2_147_483.647) throw new IOError(-1, 'Invalid timer duration');
    const op = operations.get(id); if (!op) return;
    op.due = performance.now() + seconds * 1000;
    op.timer = setTimeout(() => { if (operations.has(id)) emit(id, 0); }, Math.round(seconds * 1000));
  }
  // The document's cookie jar as script sees it: HttpOnly cookies never appear here and cannot be written from
  // script, so the browser keeps them to itself. Action 0 reads `document.cookie`; action 1 assigns one
  // `Set-Cookie`-style string. Reads answer the cookie string, the page host and whether the page is secure.
  function cookieJar(packet) {
    const input = new Reader(packet); const action = input.u32(); const text = input.text(); input.finish();
    // A worker has no document: its host supplies the jar as a mirror of the page's cookies (see the worker).
    const jar = environment.cookieJar;
    if (jar) {
      if (action === 0) {
        const snapshot = jar.snapshot();
        return new Writer().u32(0).text(snapshot.cookieString).text(snapshot.host).u32(snapshot.secure ? 1 : 0).bytes();
      }
      if (action === 1) {
        if (text.length > 4096) throw new IOError(-1, 'Cookie is too large');
        jar.write(text);
        return new Writer().u32(0).bytes();
      }
      throw new IOError(-1, 'Invalid cookie action');
    }
    const document = environment.document;
    if (!document || typeof document.cookie !== 'string') throw new IOError(-7, 'Document cookies are unavailable');
    if (action === 0) {
      const location = environment.location;
      return new Writer().u32(0).text(document.cookie).text(location?.hostname ?? '').u32(location?.protocol === 'https:' ? 1 : 0).bytes();
    }
    if (action === 1) {
      if (text.length > 4096) throw new IOError(-1, 'Cookie is too large');
      document.cookie = text;
      // The page's cookie watcher learns of its own write, as the worker's host tells it (Tools/cookie-watch.js).
      onCookieWrite();
      return new Writer().u32(0).bytes();
    }
    throw new IOError(-1, 'Invalid cookie action');
  }

  function webStorage(packet) {
    const input = new Reader(packet); const scope = input.u32(); const namespace = input.text(); const action = input.u32(); const key = input.text(); const value = input.text(); input.finish();
    if (scope > 1 || !namespace || namespace.length > 1024) throw new IOError(-1, 'Invalid storage namespace or scope');
    const store = scope ? environment.sessionStorage : environment.localStorage;
    if (!store) throw new IOError(-7, 'Web Storage is unavailable');
    const prefix = `swui:${namespace.length}:${namespace}:`; const revisionKey = prefix + '__revision'; const out = new Writer().u32(0);
    if (action <= 2 && (!key || key === '__revision' || key.length > 1024 || value.length > 16_777_216)) throw new IOError(-1, 'Invalid or reserved storage key/value');
    if (action === 0) { const result = store.getItem(prefix + key); out.u32(result === null ? 0 : 1); if (result !== null) out.text(result); }
    else if (action === 1 || action === 2) {
      const itemKey = prefix + key; const previous = store.getItem(itemKey); const previousRevision = store.getItem(revisionKey);
      try {
        if (action === 1) store.setItem(itemKey, value); else store.removeItem(itemKey);
        const current = storedRevision(previousRevision);
        store.setItem(revisionKey, String(nextStorageRevision(current, 1n)));
      } catch (error) {
        try { if (previous === null) store.removeItem(itemKey); else store.setItem(itemKey, previous); } catch {}
        try { if (previousRevision === null) store.removeItem(revisionKey); else store.setItem(revisionKey, previousRevision); } catch {}
        throw error;
      }
    }
    else if (action === 3 || action === 4) {
      const keys = []; for (let i = 0; i < store.length; i++) { const candidate = store.key(i); if (candidate?.startsWith(prefix)) keys.push(candidate); }
      if (action === 3) {
        const previous = new Map(keys.map(candidate => [candidate, store.getItem(candidate)]));
        try {
          for (const candidate of keys) store.removeItem(candidate);
          const current = storedRevision(previous.get(revisionKey) ?? null);
          store.setItem(revisionKey, String(nextStorageRevision(current, 1n)));
        } catch (error) {
          for (const [candidate, value] of previous) { if (value === null) store.removeItem(candidate); else store.setItem(candidate, value); }
          throw error;
        }
      } else {
        const visible = keys.filter((candidate) => candidate !== prefix + '__revision'); out.u32(visible.length); for (const candidate of visible) out.text(candidate.slice(prefix.length));
      }
    } else throw new IOError(-1, 'Unknown Web Storage operation');
    return out.bytes();
  }
  function webStorageRevision(packet) {
    const input = new Reader(packet); const scope = input.u32(); const namespace = input.text(); input.finish();
    if (scope > 1 || !namespace || namespace.length > 1024) throw new IOError(-1, 'Invalid storage namespace or scope');
    const store = scope ? environment.sessionStorage : environment.localStorage;
    if (!store) throw new IOError(-7, 'Web Storage is unavailable');
    const prefix = `swui:${namespace.length}:${namespace}:`;
    const raw = store.getItem(prefix + '__revision');
    const revision = storedRevision(raw);
    // A repaired revision is written back, so every reader and the next write agree on it.
    if (raw !== null && raw !== String(revision)) { try { store.setItem(prefix + '__revision', String(revision)); } catch {} }
    return new Writer().u64(revision).bytes();
  }
  // The revision a namespace holds. One that does not read (another script wrote over it) is replaced by a fresh random
  // one instead of failing every later write: a writer holding the old revision then sees a conflict and reads again.
  function storedRevision(raw) {
    if (raw === null) return 0n;
    try { return parseStorageRevision(raw); }
    catch {
      const words = new Uint32Array(2);
      try { environment.crypto.getRandomValues(words); } catch { words[0] = Math.floor(Math.random() * 2 ** 32); words[1] = Math.floor(Math.random() * 2 ** 32); }
      // Below 2^62, so a long run of writes cannot exhaust it.
      return ((BigInt(words[1] & 0x3fffffff) << 32n) | BigInt(words[0])) + 1n;
    }
  }
  function parseStorageRevision(raw) {
    if (typeof raw !== 'string' || !/^(0|[1-9][0-9]*)$/.test(raw)) throw new IOError(-8, 'Invalid storage revision');
    try {
      const value = BigInt(raw);
      if (value > MAX_U64) throw new IOError(-8, 'Storage revision exceeds the 64-bit ABI');
      return value;
    } catch (error) {
      if (error instanceof IOError) throw error;
      throw new IOError(-8, 'Invalid storage revision');
    }
  }
  function nextStorageRevision(current, delta) {
    if (current < 0n || delta < 0n || current > MAX_U64 - delta) throw new IOError(-8, 'Storage revision exhausted');
    return current + delta;
  }
  function intlDateOptions(text) {
    const allowed = {weekday:/^(long|short|narrow)$/, era:/^(long|short|narrow)$/, year:/^(numeric|2-digit)$/,
      month:/^(numeric|2-digit|long|short|narrow)$/, day:/^(numeric|2-digit)$/, hour:/^(numeric|2-digit)$/,
      minute:/^(numeric|2-digit)$/, second:/^(numeric|2-digit)$/, timeZoneName:/^(short|long)$/,
      hour12:/^(true|false)$/, dateStyle:/^(full|long|medium|short)$/, timeStyle:/^(full|long|medium|short)$/};
    const options = {}; let local = false;
    for (const pair of String(text || '').split(';')) {
      const index = pair.indexOf('='); if (index <= 0) continue;
      const name = pair.slice(0, index), value = pair.slice(index + 1);
      if (name === 'timeZone') { local = value === 'local'; continue; }
      if (allowed[name]?.test(value)) options[name] = name === 'hour12' ? value === 'true' : value;
    }
    return {options, local};
  }
  // The page opens the window (a worker has no window to open): `environment.openWindow` forwards the request.
  function openWindow(packet) {
    const input = new Reader(packet); const url = input.text(); input.finish();
    if (!/^https?:\/\//i.test(url) || url.length > 8192) throw new IOError(-1, 'Invalid window URL');
    if (typeof environment.openWindow === 'function') return environment.openWindow(url) !== false;
    return severOpener(environment.open?.(url, 'popup-window', 'popup,width=520,height=720'));
  }
  // A message for the console at a level (OSLog's `Logger`, WebOSLog): debug, info, log, warn, error.
  function consoleWrite(packet) {
    const input = new Reader(packet);
    const level = input.u32(), text = input.text();
    input.finish();
    const method = ['debug', 'info', 'log', 'warn', 'error'][level];
    if (!method) throw new IOError(-1, 'Invalid console level');
    // One argument: the console formats only when more follow, so `%c` or `%s` in app text is printed as written.
    console[method](text);
  }
  // `Intl.NumberFormat` with a CLDR unit. Foundation rounds half to even, so the rounding mode is pinned.
  function numberUnitFormat(packet) {
    const input = new Reader(packet);
    const value = input.f64(), locale = input.text(), identifier = input.text(), display = input.text(), fraction = input.u32();
    input.finish();
    if (!Number.isFinite(value)) return new Writer().u32(0).bytes();
    if (!/^[a-z-]{1,40}$/.test(identifier) || !['short', 'narrow', 'long'].includes(display) || fraction > 20) throw new IOError(-1, 'Invalid unit format request');
    let text;
    try {
      text = new Intl.NumberFormat(String(locale || '').replace(/_/g, '-') || undefined, {style: 'unit', unit: identifier, unitDisplay: display, maximumFractionDigits: fraction, roundingMode: 'halfEven'}).format(value);
    } catch { return new Writer().u32(0).bytes(); }
    return new Writer().u32(1).text(text).bytes();
  }
  // Number formatting (kind 0: the number's decimal text and `name=value;...` options) and text folding (kind 1: flags
  // 1 diacritics, 2 case, and the text). The answer is a present flag and the text; a malformed number or option is absent.
  function textOperation(packet) {
    const input = new Reader(packet); const kind = input.u32();
    let result;
    if (kind === 0) { const number = input.text(); result = formatNumber(number, input.text()); }
    else if (kind === 1) { const flags = input.u32(); result = foldText(input.text(), (flags & 1) !== 0, (flags & 2) !== 0); }
    else throw new IOError(-1, 'Unknown text operation');
    input.finish();
    return result == null ? new Writer().u32(0).bytes() : new Writer().u32(1).text(result).bytes();
  }

  // A release whose application builds no NSPredicate leaves the engine out (Tools/build-runtime-bundle.mjs); a request
  // then answers as for a format Foundation rejects.
  const predicates = (typeof SWIFTUIWEB_HAS_PREDICATES === 'undefined' || SWIFTUIWEB_HAS_PREDICATES) ? createPredicates() : null;
  /** NSPredicate: the predicate's id, format, argument values, variable dictionaries and, to evaluate it, the object under
   * test. Without an object the answer is whether the format parses, with its `predicateFormat` and the keys it reads. */
  function predicateRequest(packet) {
    const input = new Reader(packet);
    const id = input.u32(), format = input.text(), args = input.data(), bindings = input.data(), object = input.data();
    input.finish();
    if (!predicates) return new Writer().u32(0).bytes();
    if (object.length) return new Writer().u32(predicates.evaluate(id, format, args, bindings, object)).bytes();
    const found = predicates.describe(id, format, args, bindings);
    if (!found) return new Writer().u32(0).bytes();
    const out = new Writer().u32(1).text(found.format).u32(found.depth).u32(found.names.length);
    for (const name of found.names) out.text(name);
    return out.bytes();
  }
  function intlFormat(packet) {
    const input = new Reader(packet);
    const epochSeconds = input.f64(); const style = input.u32();
    const locale = input.text(); const calendar = input.text(); const offsetSeconds = input.u32() | 0;
    // Style 10 carries Swift `Date.FormatStyle`/Text options as `name=value;...`.
    const custom = style === 10 ? intlDateOptions(input.text()) : null; input.finish();
    if (!Number.isFinite(epochSeconds) || !Number.isSafeInteger(offsetSeconds) || Math.abs(offsetSeconds) > 86400 * 2) throw new IOError(-1, 'Invalid Intl request');
    const styles = [
      {dateStyle:'medium'}, {timeStyle:'short'}, {dateStyle:'medium',timeStyle:'short'},
      {dateStyle:'long'}, {timeStyle:'short'}, {timeStyle:'long'},
      {dateStyle:'long',timeStyle:'short'}, {dateStyle:'long',timeStyle:'long'},
      {year:'numeric',month:'long'}, {weekday:'narrow'}
    ];
    const options = custom ? custom.options : styles[style];
    if (!options) throw new IOError(-1, 'Unknown Intl format style');
    const local = custom?.local === true;
    const date = new Date((epochSeconds + (local ? 0 : offsetSeconds)) * 1000);
    if (!Number.isFinite(date.getTime())) return new Writer().u32(0).bytes();
    // The epoch is shifted by the requested offset above.  Format it as UTC
    // so the browser's local timezone cannot shift it a second time. A
    // `timeZone=local` request formats in the user's own time zone.
    const base = local ? {...options} : {...options, timeZone: 'UTC'};
    if (/^[A-Za-z0-9_-]{1,32}$/.test(calendar)) base.calendar = calendar;
    let result = null;
    if (typeof environment.Intl?.DateTimeFormat !== 'function') return new Writer().u32(0).bytes();
    try { result = new environment.Intl.DateTimeFormat(locale || undefined, base).format(date); }
    catch { try { result = new environment.Intl.DateTimeFormat('en-US', base).format(date); } catch { result = null; } }
    return result == null ? new Writer().u32(0).bytes() : new Writer().u32(1).text(result).bytes();
  }
  // The browser's own offset from UTC at an instant, in seconds east (DST included). Swift's `Calendar.current` uses it,
  // so calendar arithmetic and the default `Date.FormatStyle` (`timeZone=local`) agree on the day and the hour.
  function timeZoneOffset(packet) {
    const input = new Reader(packet); const epochSeconds = input.f64(); input.finish();
    if (!Number.isFinite(epochSeconds)) throw new IOError(-1, 'Invalid time zone request');
    const minutesWestOfUTC = new Date(epochSeconds * 1000).getTimezoneOffset();
    if (!Number.isFinite(minutesWestOfUTC)) return new Writer().u32(0).bytes();
    return new Writer().u32(1).u32(-minutesWestOfUTC * 60).bytes();
  }
  // The browser's IANA time zone name (`America/Sao_Paulo`), as Intl resolves it. Absent when Intl cannot say.
  function timeZoneIdentifier() {
    const DateTimeFormat = environment.Intl?.DateTimeFormat;
    if (typeof DateTimeFormat !== 'function') return new Writer().u32(0).bytes();
    let name = null;
    try { name = new DateTimeFormat().resolvedOptions().timeZone; } catch { name = null; }
    return name ? new Writer().u32(1).text(name).bytes() : new Writer().u32(0).bytes();
  }
  // The week of a locale tag (empty means the browser's language): `firstDay` as Intl spells it (1 = Monday ... 7 =
  // Sunday) and `minimalDays`. Intl.Locale exposes it as `getWeekInfo()` in current engines and `weekInfo` before.
  function weekInfo(packet) {
    const input = new Reader(packet); const requested = input.text(); input.finish();
    const tag = requested || environment.navigator?.language || '';
    const Locale = environment.Intl?.Locale;
    if (typeof Locale !== 'function' || !tag) return new Writer().u32(0).bytes();
    let info = null;
    try {
      const locale = new Locale(tag);
      info = typeof locale.getWeekInfo === 'function' ? locale.getWeekInfo() : locale.weekInfo;
    } catch { info = null; }
    if (!info || !Number.isInteger(info.firstDay)) return new Writer().u32(0).bytes();
    const minimalDays = Number.isInteger(info.minimalDays) ? info.minimalDays : 1;
    return new Writer().u32(1).u32(info.firstDay).u32(minimalDays).bytes();
  }
  function webStorageTransaction(packet) {
    const input = new Reader(packet); const scope = input.u32(); const namespace = input.text();
    const hasExpected = input.u32() !== 0; const expected = input.u64(); const count = input.u32();
    if (scope > 1 || !namespace || namespace.length > 1024 || count > 100_000) throw new IOError(-1, 'Invalid storage transaction');
    const mutations = [];
    for (let index = 0; index < count; index++) {
      const action = input.u32(); const key = input.text(); const value = input.text();
      if (!key || key === '__revision' || (action !== 1 && action !== 2) || value.length > 16_777_216) throw new IOError(-1, 'Invalid storage mutation');
      mutations.push({action, key, value});
    }
    input.finish();
    const store = scope ? environment.sessionStorage : environment.localStorage;
    if (!store) throw new IOError(-7, 'Web Storage is unavailable');
    const prefix = `swui:${namespace.length}:${namespace}:`; const revisionKey = prefix + '__revision';
    const current = storedRevision(store.getItem(revisionKey));
    if (hasExpected && expected !== current) throw new IOError(-9, `Storage revision conflict (expected ${expected}, actual ${current})`);
    const previous = new Map();
    for (const mutation of mutations) {
      const full = prefix + mutation.key;
      if (!previous.has(full)) previous.set(full, store.getItem(full));
    }
    previous.set(revisionKey, store.getItem(revisionKey));
    try {
      for (const mutation of mutations) {
        const full = prefix + mutation.key;
        if (mutation.action === 1) store.setItem(full, mutation.value); else store.removeItem(full);
      }
      const next = nextStorageRevision(current, BigInt(mutations.length || 1));
      store.setItem(revisionKey, String(next));
      return new Writer().u64(next).bytes();
    } catch (error) {
      for (const [key, value] of previous) { if (value === null) store.removeItem(key); else store.setItem(key, value); }
      throw error;
    }
  }
  // DOM actions 9, 11 and 12 are the DOM component lifecycle: mount (name = component, value = state), update
  // (value = state) and unmount. Action 10 is a failure report.
  const DOM_PHASES = new Map([[9, 'mount'], [11, 'update'], [12, 'unmount']]);
  function domBridge(packet) {
    const input = new Reader(packet); const action=input.u32(), id=input.u32(), name=input.text(), value=input.text(); input.finish();
    const out=new Writer();
    if (remoteDOM) remoteBridge(action, id, name, value, out);
    else localBridge(action, id, name, value, out);
    return out.bytes();
  }
  function localBridge(action, id, name, value, out) {
    if (action===0) {
      const document=environment.document; if (!document?.querySelectorAll) throw new IOError(-7,'DOM is unavailable');
      const nodes=[...document.querySelectorAll('[data-web-mount-token]')]; out.u32(nodes.length);
      for (const element of nodes) out.u32(domID(element)).text(element.getAttribute('data-web-mount-key')||'').text(element.getAttribute('data-web-mount-token')||'');
      for (const handle of detachedDOMHandles) { const element=domElements.get(handle); if (element && !element.isConnected) domElements.delete(handle); }
      detachedDOMHandles = [];
      for (const [handle,element] of domElements) if (!element.isConnected) detachedDOMHandles.push(handle);
    } else if (action===10) {
      reportDOMError(id ? domElements.get(id) : undefined, value);
    } else {
      const element=domElements.get(id); if (!element) throw new IOError(-8,'Unknown DOM element handle');
      if (action===1) out.u32(element.isConnected?1:0);
      else if (action===2) { const v=element.getAttribute(name); out.u32(v===null?0:1); if(v!==null) out.text(v); }
      else if (action===3) element.setAttribute(name,value);
      else if (action===4) element.removeAttribute(name);
      else if (action===5) element.value=value;
      else if (action===6) { const v=element.textContent; out.u32(v==null?0:1); if(v!=null) out.text(v); }
      else if (action===7) element.textContent=value;
      else if (action===8) { const v=element.value; out.u32(v==null?0:1); if(v!=null) out.text(String(v)); }
      else if (DOM_PHASES.has(action)) domViews.lifecycle(DOM_PHASES.get(action), element, { component: name, state: value });
      else throw new IOError(-1,'Unknown DOM bridge action');
    }
  }
  // Worker mode: every answer comes from the mirror; every write is queued as an op.
  function remoteBridge(action, id, name, value, out) {
    if (action===0) {
      const mounts=[...mirror.nodes].filter(([,node])=>node.token);
      out.u32(mounts.length);
      for (const [handle,node] of mounts) out.u32(handle).text(node.key).text(node.token);
      return;
    }
    if (action===10) {
      // A failure that repeats (a media read every frame, say) is reported once per element and message.
      const key=`${id}|${value}`;
      if (!mirror.reported.has(key)) { mirror.reported.add(key); mirror.ops.push({op:'report', node:id, message:value}); }
      return;
    }
    if (action===1) { out.u32(mirror.nodes.has(id)?1:0); return; }
    // A lifecycle call is queued without the table check: an element that has just left the DOM still
    // needs its `unmount`, and the main thread still holds its handle until that batch is applied.
    if (DOM_PHASES.has(action)) {
      const phase=DOM_PHASES.get(action);
      mirror.ops.push(phase==='mount' ? {op:'dom-view', node:id, phase, component:name, state:value} : phase==='update' ? {op:'dom-view', node:id, phase, state:value} : {op:'dom-view', node:id, phase});
      return;
    }
    const node=mirror.nodes.get(id); if (!node) throw new IOError(-8,'Unknown DOM element handle');
    if (action===2) { const v=node.attributes.get(name); out.u32(v===undefined?0:1); if(v!==undefined) out.text(v); }
    else if (action===3) { node.attributes.set(name,value); mirror.ops.push({op:'attr', node:id, name, value}); }
    else if (action===4) { node.attributes.delete(name); mirror.ops.push({op:'remove-attr', node:id, name}); }
    else if (action===5) { node.value=value; mirror.ops.push({op:'value', node:id, value}); }
    else if (action===6) { out.u32(node.text==null?0:1); if(node.text!=null) out.text(node.text); }
    else if (action===7) { node.text=value; mirror.ops.push({op:'text', node:id, value}); }
    else if (action===8) { out.u32(node.value==null?0:1); if(node.value!=null) out.text(String(node.value)); }
    else throw new IOError(-1,'Unknown DOM bridge action');
  }
  // A failed mount must never vanish: the console and a diagnostic attribute both
  // say so. Without an element (handle 0) the attribute lands on the app root.
  function reportDOMError(element, message) {
    const text = safeErrorMessage(message);
    environment.console?.error?.(`[SwiftUIWeb] ${text}`);
    const target = element ?? environment.document?.getElementById?.('embedded-app-root') ?? environment.document?.body;
    try { target?.setAttribute?.('data-dom-view-error', text); } catch { /* detached or not a document */ }
  }
  function mediaBridge(packet) {
    const input=new Reader(packet); const action=input.u32(), id=input.u32(), text=input.text(), number=input.f64(), flag=input.u32()===1; input.finish();
    // Worker mode has no media elements: a synchronous media call cannot be answered there. It fails with the
    // "unavailable in this runtime" status, which the Swift side reports instead of returning a silent default.
    const element=domElements.get(id);
    if (!element) throw remoteDOM ? new IOError(-7,'Media playback is not bridged from the worker runtime; run with ?render-in-worker=0') : new IOError(-8,'Unknown media element handle');
    const out=new Writer();
    const ranges=(value)=>{ const n=value?.length>>>0; out.u32(n); for(let i=0;i<n;i++) out.f64(value.start(i)).f64(value.end(i)); };
    if(action===0) out.f64(element.currentTime||0);
    else if(action===1) element.currentTime=Math.max(0,number);
    else if(action===2) out.f64(Number(element.duration));
    else if(action===3) out.f64(Number(element.playbackRate)||1);
    else if(action===4) element.playbackRate=Math.max(0,number);
    else if(action===5) out.f64(Number(element.volume));
    else if(action===6) element.volume=Math.min(1,Math.max(0,number));
    else if(action===7) out.u32(element.muted?1:0);
    else if(action===8) element.muted=flag;
    else if(action===9) { const promise=element.play?.(); promise?.catch?.(()=>{}); }
    else if(action===10) element.pause?.();
    else if(action===11) { element.src=text; element.load?.(); }
    else if(action===12) out.u32(element.canPlayType?.(text)?1:0);
    else if(action===13) out.u32(element.readyState>>>0);
    else if(action===14) out.u32(element.networkState>>>0);
    else if(action===15) ranges(element.buffered);
    else if(action===16) ranges(element.seekable);
    else if(action===17) { const p=element.requestFullscreen?.() ?? element.webkitRequestFullscreen?.(); p?.catch?.(()=>{}); }
    else if(action===18) { const d=environment.document; const p=d?.exitFullscreen?.() ?? d?.webkitExitFullscreen?.(); p?.catch?.(()=>{}); }
    else if(action===19) out.u32((environment.document?.pictureInPictureEnabled && typeof element.requestPictureInPicture==='function') || typeof element.webkitSetPresentationMode==='function' ? 1:0);
    else if(action===20) { if(flag) { const p=element.requestPictureInPicture?.(); if(p?.catch) p.catch(()=>{}); else element.webkitSetPresentationMode?.('picture-in-picture'); } else { const p=environment.document?.exitPictureInPicture?.(); if(p?.catch) p.catch(()=>{}); else element.webkitSetPresentationMode?.('inline'); } }
    else if(action===21) { if(typeof environment.__attachAdaptiveMedia==='function') environment.__attachAdaptiveMedia(element,text); else if(typeof environment.__loadAdaptiveMedia==='function') environment.__loadAdaptiveMedia(element,text); }
    else if(action===22) { if(typeof environment.__detachAdaptiveMedia==='function') environment.__detachAdaptiveMedia(element); else if(typeof environment.__cancelAdaptiveMedia==='function') environment.__cancelAdaptiveMedia(element); }
    else throw new IOError(-1,'Unknown media bridge action');
    return out.bytes();
  }
  function observeMedia(id, packet) {
    const input=new Reader(packet); const handle=input.u32(), event=input.text(); input.finish(); const element=domElements.get(handle);
    if(!element?.addEventListener) throw new IOError(-8,'Unknown media element handle');
    const listener=(value)=>{ if(!operations.has(id)) return; if(event==='__keydown') emit(id,100,new Writer().text(String(value.key||'')).u32(value.repeat?1:0).bytes()); else emit(id,100); };
    const actual=event==='__keydown'?'keydown':event; element.addEventListener(actual,listener);
    const op=operations.get(id); if(op) op.cleanup=()=>element.removeEventListener(actual,listener);
  }
  async function openDatabase(name, operation, requestedVersion = 1) {
    if (!environment.indexedDB) throw new IOError(-7, 'IndexedDB is unavailable');
    if (!Number.isInteger(requestedVersion) || requestedVersion < 1 || requestedVersion > 2_147_483_647) throw new IOError(-1, 'Invalid IndexedDB version');
    const cached = databases.get(name);
    if (cached && cached.version >= requestedVersion) return cached;
    if (cached) { cached.close(); databases.delete(name); }
    const db = await new Promise((resolve, reject) => {
      const request = environment.indexedDB.open('swui:' + name, requestedVersion);
      let finished = false;
      const timer = setTimeout(() => { finished = true; if (operation.timer === timer) operation.timer = null; reject(new IOError(-5, 'IndexedDB open timed out or is blocked')); }, 10000);
      operation.timer = timer;
      request.onupgradeneeded = () => { if (!request.result.objectStoreNames.contains('records')) request.result.createObjectStore('records'); };
      request.onerror = () => { clearTimeout(timer); if (operation.timer === timer) operation.timer = null; finished = true; reject(request.error); };
      request.onsuccess = () => {
        clearTimeout(timer);
        if (operation.timer === timer) operation.timer = null;
        if (finished || operation.controller.signal.aborted || disposed) { request.result.close(); reject(new IOError(-4, 'IndexedDB operation cancelled')); return; }
        finished = true; resolve(request.result);
      };
    });
    db.onversionchange = () => { db.close(); if (databases.get(name) === db) databases.delete(name); };
    databases.set(name, db); return db;
  }
  async function indexedDBRequest(id, packet) {
    const input = new Reader(packet); const name = input.text(); const action = input.u32(); const key = input.text(); const value = input.data();
    const version = input.at < input.bytes.length ? input.u32() : 1; input.finish();
    // `security:` names the keychain's own databases (secure store `X` is `security:X`): an application database of that
    // name would open the keychain's key and records.
    if (!name || name.length > 1024 || name.startsWith('security:') || action > 4 || value.length > 16777216) throw new IOError(-1, 'Invalid IndexedDB request');
    if ((action === 0 || action === 1 || action === 2) && (!key || key.length > 1024)) throw new IOError(-1, 'Invalid IndexedDB key');
    const op = operations.get(id); if (!op) return;
    const db = await openDatabase(name, op, version); if (!operations.has(id)) return;
    const result = await new Promise((resolve, reject) => {
      const tx = db.transaction('records', action === 0 || action === 4 ? 'readonly' : 'readwrite'); op.transaction = tx;
      const store = tx.objectStore('records'); let request;
      if (action === 0) request = store.get(key);
      else if (action === 1) request = store.put(value, key);
      else if (action === 2) request = store.delete(key);
      else if (action === 3) request = store.clear();
      else request = store.getAllKeys();
      let record; request.onsuccess = () => { record = request.result; };
      tx.oncomplete = () => { op.transaction = null; resolve(record); };
      tx.onabort = () => { op.transaction = null; reject(tx.error || new IOError(-4, 'IndexedDB transaction aborted')); };
      tx.onerror = () => {};
    });
    if (!operations.has(id)) return;
    const out = new Writer();
    if (action === 0) { out.u32(result === undefined ? 0 : 1); if (result !== undefined) { if (!(result instanceof Uint8Array)) throw new IOError(-8, 'Unexpected stored IndexedDB value type'); out.data(result); } }
    else if (action === 4) { if (!Array.isArray(result) || result.length > 100000 || result.some((key) => typeof key !== 'string')) throw new IOError(-8, 'Invalid IndexedDB keys'); out.u32(result.length); for (const key of result) out.text(key); }
    emit(id, 0, out.bytes());
  }
  async function indexedDBTransaction(id, packet) {
    const input = new Reader(packet); const name = input.text(); const version = input.u32(); const count = input.u32();
    if (!name || name.length > 1024 || name.startsWith('security:') || count > 100_000) throw new IOError(-1, 'Invalid IndexedDB transaction');
    const mutations = [];
    for (let index = 0; index < count; index++) {
      const action = input.u32(); const key = input.text(); const value = input.data();
      if (action < 1 || action > 3 || value.length > 16_777_216 || ((action === 1 || action === 2) && (!key || key.length > 1024))) throw new IOError(-1, 'Invalid IndexedDB mutation');
      mutations.push({action, key, value});
    }
    input.finish();
    const op = operations.get(id); if (!op) return;
    const db = await openDatabase(name, op, version); if (!operations.has(id)) return;
    await new Promise((resolve, reject) => {
      const tx = db.transaction('records', 'readwrite'); op.transaction = tx;
      const store = tx.objectStore('records');
      for (const mutation of mutations) {
        if (mutation.action === 1) store.put(mutation.value, mutation.key);
        else if (mutation.action === 2) store.delete(mutation.key);
        else store.clear();
      }
      tx.oncomplete = () => { op.transaction = null; resolve(); };
      tx.onabort = () => { op.transaction = null; reject(tx.error || new IOError(-4, 'IndexedDB transaction aborted')); };
      tx.onerror = () => {};
    });
    if (operations.has(id)) emit(id, 0);
  }
  // WebSecurity's item store. Each item is encrypted with AES-GCM under one key per store that
  // Web Crypto creates as non-extractable: the key lives in IndexedDB as a CryptoKey and never
  // crosses into Swift or any JavaScript-visible bytes. The item id is the additional authenticated
  // data, so a ciphertext copied onto another id fails to decrypt. Operations on one store run in
  // order: an encryption still in flight cannot let a later removal land first.
  const secureQueues = new Map();
  const SECURE_KEY = 'key', SECURE_ITEM = 'item:';
  function secureRequest(db, mode, body) {
    return new Promise((resolve, reject) => {
      const tx = db.transaction('records', mode); const store = tx.objectStore('records'); let value;
      const result = body(store, (request) => { request.onsuccess = () => { value = request.result; }; });
      tx.oncomplete = () => resolve(value === undefined ? result : value);
      tx.onabort = () => reject(tx.error || new IOError(-4, 'Secure store transaction aborted'));
      tx.onerror = () => {};
    });
  }
  // The store's key: AES-GCM 256, extractable false, usable only to encrypt and decrypt. A
  // candidate is generated first (Web Crypto cannot run inside an IndexedDB transaction), then one
  // read-write transaction keeps whichever key is already stored and saves the candidate only if
  // none is. Two tabs opening the store for the first time therefore agree on a single key; with a
  // read and a write in separate transactions the second tab's key would replace the first, and
  // every item already encrypted under it would stop decrypting.
  async function secureKey(db, subtle) {
    const stored = await secureRequest(db, 'readonly', (store, capture) => capture(store.get(SECURE_KEY)));
    if (stored) return stored;
    const candidate = await subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    let kept = candidate;
    await secureRequest(db, 'readwrite', (store) => {
      const request = store.get(SECURE_KEY);
      request.onsuccess = () => { if (request.result) kept = request.result; else store.put(candidate, SECURE_KEY); };
    });
    return kept;
  }
  async function secureStoreOperation(id, name, action, key, value, subtle) {
    const op = operations.get(id); if (!op) return;
    const db = await openDatabase('security:' + name, op, 1);
    const out = new Writer();
    if (action === 3) {
      await secureRequest(db, 'readwrite', (store) => { store.clear(); });
    } else if (action === 2) {
      await secureRequest(db, 'readwrite', (store) => { store.delete(SECURE_ITEM + key); });
    } else {
      const cryptoKey = await secureKey(db, subtle);
      if (action === 1) {
        const iv = environment.crypto.getRandomValues(new Uint8Array(12));
        const additionalData = encoder.encode(name + '\u0000' + key);
        const sealed = new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv, additionalData }, cryptoKey, value));
        await secureRequest(db, 'readwrite', (store) => { store.put({ v: 1, iv, sealed }, SECURE_ITEM + key); });
      } else {
        const keys = await secureRequest(db, 'readonly', (store, capture) => capture(store.getAllKeys()));
        const ids = (Array.isArray(keys) ? keys : []).filter((k) => typeof k === 'string' && k.startsWith(SECURE_ITEM));
        const items = [];
        for (const recordKey of ids) {
          const record = await secureRequest(db, 'readonly', (store, capture) => capture(store.get(recordKey)));
          const itemID = recordKey.slice(SECURE_ITEM.length);
          try {
            const additionalData = encoder.encode(name + '\u0000' + itemID);
            const plain = await subtle.decrypt({ name: 'AES-GCM', iv: record.iv, additionalData }, cryptoKey, record.sealed);
            items.push([itemID, new Uint8Array(plain)]);
          } catch {
            // A record that no longer decrypts (key replaced, data altered) is skipped, never returned.
          }
        }
        out.u32(items.length); for (const [itemID, plain] of items) { out.text(itemID); out.data(plain); }
      }
    }
    if (operations.has(id)) emit(id, 0, out.bytes());
  }
  async function secureStoreRequest(id, packet) {
    const input = new Reader(packet); const name = input.text(); const action = input.u32(); const key = input.text(); const value = input.data(); input.finish();
    if (!name || name.length > 256 || action > 3 || value.length > 1_048_576) throw new IOError(-1, 'Invalid secure store request');
    if ((action === 1 || action === 2) && (!key || key.length > 256)) throw new IOError(-1, 'Invalid secure store item id');
    const subtle = environment.crypto?.subtle;
    if (!subtle || typeof environment.crypto.getRandomValues !== 'function') throw new IOError(-7, 'Web Crypto is unavailable; a secure context (HTTPS) is required');
    const previous = secureQueues.get(name) ?? Promise.resolve();
    const run = previous.catch(() => {}).then(() => secureStoreOperation(id, name, action, key, value, subtle));
    secureQueues.set(name, run);
    await run;
  }
  function observeStorage(id, packet) {
    const input = new Reader(packet); const namespace = input.text(); input.finish();
    if (!namespace || namespace.length > 1024) throw new IOError(-1, 'Invalid storage namespace');
    if (typeof environment.addEventListener !== 'function') throw new IOError(-7, 'Storage events are unavailable');
    const prefix = `swui:${namespace.length}:${namespace}:`;
    // Another tab writes a transaction one key at a time and its revision last. The changed keys are held until that
    // revision arrives, so this tab reads them only once the whole transaction is there, never half of it. A write that
    // bumps no revision (another script) is passed on after a short wait.
    const pending = [new Set(), new Set()];
    let timer = null;
    const flush = (scope) => {
      for (const key of pending[scope]) {
        const out = new Writer().u32(scope);
        if (key === null) out.u32(0); else out.u32(1).text(key);
        emit(id, 100, out.bytes());
      }
      pending[scope].clear();
    };
    const flushAll = () => { timer = null; if (operations.has(id)) { flush(0); flush(1); } };
    const listener = (event) => {
      if (!operations.has(id)) return;
      const scope = event.storageArea === environment.sessionStorage ? 1 : event.storageArea === environment.localStorage ? 0 : -1;
      if (scope < 0) return;
      if (event.key !== null && !event.key.startsWith(prefix)) return;
      if (event.key === prefix + '__revision') { flush(scope); return; }
      pending[scope].add(event.key === null ? null : event.key.slice(prefix.length));
      if (event.key === null) { flush(scope); return; }
      if (timer === null) timer = (typeof environment.setTimeout === 'function' ? environment.setTimeout.bind(environment) : setTimeout)(flushAll, 100);
    };
    environment.addEventListener('storage', listener);
    const op = operations.get(id);
    if (op) op.cleanup = () => { environment.removeEventListener('storage', listener); if (timer !== null) (typeof environment.clearTimeout === 'function' ? environment.clearTimeout.bind(environment) : clearTimeout)(timer); };
  }
  function observeConnectivity(id) {
    if (typeof environment.addEventListener !== 'function') throw new IOError(-7, 'Connectivity events are unavailable');
    const send = () => emit(id, 100, new Writer().u32(environment.navigator?.onLine === false ? 0 : 1).bytes());
    environment.addEventListener('online', send); environment.addEventListener('offline', send);
    const op = operations.get(id); if (op) op.cleanup = () => { environment.removeEventListener('online', send); environment.removeEventListener('offline', send); };
    send();
  }
  async function run(id, operation, packet) {
    try {
      const op = operations.get(id); if (!op) return;
      op.started = true;
      if (op.refused) throw new IOError(-6, 'This request was already sent before the app moved to the main thread, so it is not sent again');
      if (operation === BrowserIOOperation.fetch) await fetchRequest(id, packet);
      else if (operation === BrowserIOOperation.timer) await timerRequest(id, packet);
      else if (operation === BrowserIOOperation.indexedDB) await indexedDBRequest(id, packet);
      else if (operation === BrowserIOOperation.indexedDBTransaction) await indexedDBTransaction(id, packet);
      else if (operation === BrowserIOOperation.secureStore) await secureStoreRequest(id, packet);
      else if (operation === BrowserIOOperation.storageChanges) observeStorage(id, packet);
      else if (operation === BrowserIOOperation.connectivityChanges) observeConnectivity(id);
      else if (operation === BrowserIOOperation.media) observeMedia(id, packet);
      else throw new IOError(-1, 'Unknown asynchronous BrowserIO operation');
    } catch (error) { try { fail(id, error); } catch (deliveryError) { onError(deliveryError); } }
  }
  function cancel(id) {
    id >>>= 0; const op = operations.get(id); if (!op) return;
    cleanupOperation(op, true);
    fail(id, new IOError(-4, 'Operation cancelled'));
  }
  const imports = {
    request(id, operation, pointer, length) {
      id >>>= 0; operation >>>= 0;
      if (disposed || !id || operations.has(id)) return -7;
      let packet; try { packet = read(pointer, length); } catch { return -1; }
      // The packet stays with observers and timers (it is small and a restart needs it); a fetch keeps it too and
      // `fetchRequest` drops it again unless the request is safe to repeat. See `inflight()`.
      const keepsPacket = RESTARTABLE.has(operation) || operation === BrowserIOOperation.fetch;
      const refused = operation === BrowserIOOperation.fetch && takeRefusal(id, operation, packet);
      operations.set(id, { controller: new AbortController(), timer: null, transaction: null, reader: null, cleanup: null, operation, packet: keepsPacket ? packet : null, restart: RESTARTABLE.has(operation), due: 0, sideEffects: mayRepeatEffect(operation, packet), started: false, refused });
      queueMicrotask(() => run(id, operation, packet)); return 0;
    },
    cancel(id) { try { cancel(id); } catch (error) { onError(error); } },
    sync(operation, pointer, length) {
      if (disposed) return 0;
      let bytes;
      try {
        const op = operation >>> 0;
        if (op === BrowserIOOperation.storage) bytes = webStorage(read(pointer, length));
        else if (op === BrowserIOOperation.storageTransaction) bytes = new Writer().u32(0).raw(webStorageTransaction(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.storageRevision) bytes = new Writer().u32(0).raw(webStorageRevision(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.connectivity) bytes = new Writer().u32(0).u32(environment.navigator?.onLine === false ? 0 : 1).bytes();
        else if (op === BrowserIOOperation.dom) bytes = new Writer().u32(0).raw(domBridge(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.media) bytes = new Writer().u32(0).raw(mediaBridge(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.openWindow) bytes = new Writer().u32(0).u32(openWindow(read(pointer, length)) ? 1 : 0).bytes();
        else if (op === BrowserIOOperation.intl) bytes = new Writer().u32(0).raw(intlFormat(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.timeZoneOffset) bytes = new Writer().u32(0).raw(timeZoneOffset(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.timeZoneIdentifier) bytes = new Writer().u32(0).raw(timeZoneIdentifier()).bytes();
        else if (op === BrowserIOOperation.weekInfo) bytes = new Writer().u32(0).raw(weekInfo(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.numberUnit) bytes = new Writer().u32(0).raw(numberUnitFormat(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.text) bytes = new Writer().u32(0).raw(textOperation(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.predicate) bytes = new Writer().u32(0).raw(predicateRequest(read(pointer, length))).bytes();
        else if (op === BrowserIOOperation.console) { consoleWrite(read(pointer, length)); bytes = new Writer().u32(0).bytes(); }
        else if (op === BrowserIOOperation.cookies) bytes = cookieJar(read(pointer, length));
        else throw new IOError(-1, 'Unknown synchronous operation');
      } catch (error) { const e = classify(error); bytes = new Writer().u32(e.code).text(e.message).bytes(); }
      while (!nextReply || replies.has(nextReply)) nextReply = (nextReply + 1) >>> 0;
      const handle = nextReply; nextReply = (nextReply + 1) >>> 0; replies.set(handle, bytes); return handle;
    },
    length(handle) { return replies.get(handle >>> 0)?.length || 0; },
    copy(handle, pointer, capacity) {
      const bytes = replies.get(handle >>> 0); pointer >>>= 0; capacity >>>= 0;
      if (!bytes || bytes.length > capacity) return -1;
      const view = new Uint8Array(memory().buffer);
      if (pointer > view.length || bytes.length > view.length - pointer) return -1;
      view.set(bytes, pointer); return bytes.length;
    },
    release(handle) { replies.delete(handle >>> 0); },
    // The Swift executor queued a job outside a drain: drain on the next microtask.
    wake() { if (!disposed) wake(); },
    // Debug only (`?stack-depth=1`): the renderer reports its recursion depth; the meter probes the stack left.
    stack_headroom(depth) { stackMeter?.sample(depth >>> 0); },
    // The standard library's Unicode character data (Sources/CSwiftUIWebBrowserIO/UnicodeData.c).
    ...createUnicodeImports(() => new Uint8Array(memory().buffer)),
  };
  return { imports,
    /** Worker mode: the elements the main thread mounted, as of table `seq`. */
    domTable(seq, entries) {
      mirror.seq = Number(seq) || 0;
      mirror.nodes = new Map((Array.isArray(entries) ? entries : []).map(entry => [entry.node, {
        key: String(entry.key ?? ''), token: String(entry.token ?? ''),
        attributes: new Map(Object.entries(entry.attributes || {})),
        value: entry.value ?? null, text: entry.text ?? null
      }]));
    },
    /** Worker mode: the queued DOM writes, or null, for the main thread to apply. */
    domFlush() {
      if (!mirror.ops.length) return null;
      const ops = mirror.ops; mirror.ops = [];
      return { seq: mirror.seq, ops };
    },
    /** The operations Swift still waits for, with what a host on another thread needs to run them again: the packet
     * of a timer (shortened to the time left), an observer or a read-only fetch, and null for the rest (a write, an
     * IndexedDB transaction), which that host reports as cancelled. */
    inflight() {
      const now = performance.now();
      return [...operations].map(([id, op]) => {
        let packet = op.restart ? op.packet : null;
        if (packet && op.operation === BrowserIOOperation.timer && op.due) packet = new Writer().f64(Math.max(0, (op.due - now) / 1000)).bytes();
        return { id, operation: op.operation, packet };
      });
    },
    /** Takes over operations listed by another host's `inflight()`. Call it once the instance the ids belong to is ready. */
    resume(list) {
      for (const { id, operation, packet } of list) {
        if (operations.has(id)) continue;
        operations.set(id, { controller: new AbortController(), timer: null, transaction: null, reader: null, cleanup: null, operation, packet, restart: packet !== null, due: 0 });
        if (packet) queueMicrotask(() => run(id, operation, packet));
        else queueMicrotask(() => { try { fail(id, new IOError(-4, 'Operation cancelled')); } catch (error) { onError(error); } });
      }
    },
    /** Worker mode, before the app moves to another thread: the side-effecting fetches started since the last snapshot. */
    sentSinceSnapshot() { return sent.slice(); },
    /** Called when the app takes a snapshot: earlier sends are no longer replayed, so they are forgotten. */
    snapshotTaken() { sent = []; },
    /** Worker mode, before the app moves to another thread: operations that have not started yet and may repeat an effect
     * are dropped here, silently. The thread that takes over starts them when its replay asks again, so each is sent once. */
    fenceUnstarted() {
      for (const [id, op] of [...operations]) {
        if (!op.sideEffects || op.started) continue;
        operations.delete(id); cleanupOperation(op);
      }
    },
    /** Main thread, taking over: `list` is what the Worker sent since the snapshot (`sentSinceSnapshot`). A replayed request
     * that matches one of them fails instead of being sent again. An empty list clears the refusals. */
    refuseReplayed(list) {
      refusals.clear();
      for (const { id, operation, packet } of list ?? []) {
        const key = `${id}:${operation}`;
        if (!refusals.has(key)) refusals.set(key, []);
        refusals.get(key).push(packet);
      }
    },
    /** Worker mode: the mirror of mounted elements and its sequence, for a host that takes over. */
    domState() { return { seq: mirror.seq, table: [...mirror.nodes].map(([node, entry]) => ({ node, key: entry.key, token: entry.token, attributes: Object.fromEntries(entry.attributes), value: entry.value, text: entry.text })) }; },
    dispose() {
      if (disposed) return;
      for (const id of [...operations.keys()]) { try { cancel(id); } catch (error) { onError(error); } }
      disposed = true; replies.clear(); for (const db of databases.values()) db.close(); databases.clear();
    },
    diagnostics() { return { activeOperations: operations.size, resultBuffers: replies.size, openDatabases: databases.size, disposed }; },
  };
}
