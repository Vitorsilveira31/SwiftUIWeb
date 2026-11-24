// The host of one Embedded Swift application instance: its WASM instance, task pump and BrowserIO host (fetch,
// IndexedDB, mirrored storage). It runs in a Worker (embedded-worker.js) or, once a Worker's call stack ran
// out, on the main thread (embedded-worker-client.js), and talks to the page through the same messages.
//   page -> core  init | call (an exported entry point plus its event bytes) | storage | cookies (document.cookie, when it
//                 changed) | mounts (the WebMount elements the page reports before a reconciliation)
//   core -> page  publish (the HTML snapshot and the small pieces of Swift state the host used to read synchronously)
//                 | ack (a call that published nothing has run; publish and ack carry the count of calls handled)
//                 | storage-write | cookie-write | error | dom (DOM writes queued by the core, applied in order by the page)
//                 | migrate (the Worker's stack ran out: the state to continue on the main thread) | forward | forward-done
//
// Stack overflow without losing state. A trap
// can leave the instance half-updated, so a core that may have to move keeps a snapshot of linear memory taken at the
// end of every pass that published (after the publication has gone out). When a call or a task drain overflows, the
// core sends the snapshot, the calls that ran since it, the call that failed and the host state to the page, which
// continues on the main thread, where the stack is far deeper: it instantiates the same module, copies the snapshot
// into its memory, runs those calls again and carries on.
import { createBrowserIO, safeErrorMessage } from './BrowserIO/browser-io.mjs';
import { createServiceForwarder } from './BrowserIO/service-host.mjs';
import { createWasiHost } from './wasi-host.js';
import { createHeadroomMeter } from './stack-probe.js';
import { writeEventValue, readSecureBytes, readSecureIDs } from './event-value.js';
import { createSplitLoader, isSplitModule } from './wasm-split-loader.js';

const PREFIX = 'embedded_browser_';
/** The frames a trap ran through (a trap carries no message): they name the Swift code that hit it. */
const stackOf = error => (typeof error?.stack === 'string' ? error.stack.slice(0, 4000) : '');
const SECURE_MARKER = new TextEncoder().encode('data-keep-secure-id');
const decoder = new TextDecoder();
const encoder = new TextEncoder();

/** Past this size a snapshot costs more than it is worth (a copy per pass); the app then restarts instead of moving. */
const SNAPSHOT_LIMIT = 192 * 1024 * 1024;
/** Calls that only acknowledge something. When one leaves the publication sequence alone it needs no snapshot of its
 * own: it is kept (a few bytes) and run again after the snapshot it follows. */
const LOG_ONLY = new Set(['publish_ack', 'scroll_ack', 'history_ack', 'timeline_tick', 'batch_begin', 'viewport']);

/** Named events that only report what the page measured: a newer report for the same element replaces an older one
 * (Swift keeps the previous value of a scroll geometry itself, so its action still sees old and new). */
const MEASURED_EVENTS = new Set(['geometry', 'geometryChange', 'layoutproposal', 'layoutsizes', 'scrollGeometry', 'textLayout']);
const nameDecoder = new TextDecoder();

/** The key a measurement call is known by (the viewport, one lazy collection's window, one element's geometry or layout
 * report), or null for any other call. Two calls with the same key only differ in the newest value, so the page may send
 * the later one alone, and a measurement that published nothing is replayed after a snapshot instead of costing one. */
export function measurementKey(message) {
  const [first, second] = message.a || [];
  if (message.n === 'viewport') return 'viewport';
  if (message.n === 'lazy_window') return 'lazy:' + first;
  if (message.n !== 'dispatch_named' || !message.v) return null;
  const length = Number(second);
  if (!Number.isInteger(length) || length <= 0 || length > message.v.length) return null;
  const name = nameDecoder.decode(message.v.subarray(0, length));
  return MEASURED_EVENTS.has(name) ? 'event:' + first + ':' + name : null;
}

/** `Storage` as BrowserIO uses it, backed by a snapshot taken on the main thread (workers have no localStorage).
 * Writes go through to the real one. */
class MirrorStorage {
  constructor(scope, entries, post) { this.scope = scope; this.map = new Map(entries); this.post = post; }
  get length() { return this.map.size; }
  key(index) { return [...this.map.keys()][index] ?? null; }
  getItem(key) { return this.map.has(key) ? this.map.get(key) : null; }
  setItem(key, value) { this.map.set(String(key), String(value)); this.post({ t: 'storage-write', scope: this.scope, op: 'set', key: String(key), value: String(value) }); }
  removeItem(key) { this.map.delete(String(key)); this.post({ t: 'storage-write', scope: this.scope, op: 'remove', key: String(key) }); }
  clear() { this.map.clear(); this.post({ t: 'storage-write', scope: this.scope, op: 'clear' }); }
}

/** The page's cookie jar as the core sees it: a mirror of `document.cookie` taken on the main thread. Reads answer from
 * the mirror; writes update it and go to the main thread, which assigns `document.cookie` (HttpOnly cookies are never
 * in the mirror). */
class CookieMirror {
  constructor(message, post) { this.cookies = message.cookies || ''; this.host = message.hostname || ''; this.secure = message.secure === true; this.post = post; }
  snapshot() { return { cookieString: this.cookies, host: this.host, secure: this.secure }; }
  /** The main thread re-read `document.cookie` (another tab or a response changed it). */
  replace(cookies) { this.cookies = String(cookies || ''); }
  write(line) {
    const text = String(line);
    const [pair, ...attributes] = text.split(';');
    const equals = pair.indexOf('=');
    const name = equals < 0 ? '' : pair.slice(0, equals).trim();
    const expired = attributes.some(attribute => /^\s*expires\s*=\s*thu, 01 jan 1970/i.test(attribute) || /^\s*max-age\s*=\s*0\s*$/i.test(attribute));
    const parts = this.cookies ? this.cookies.split('; ').filter(part => part && part.split('=')[0] !== name) : [];
    if (!expired && name) parts.push(pair.trim());
    this.cookies = parts.join('; ');
    this.post({ t: 'cookie-write', line: text });
  }
}

/** The engine's call stack ran out: V8 and JavaScriptCore throw a RangeError ("Maximum call stack size exceeded"), Firefox
 * an InternalError ("too much recursion"). */
export function isStackOverflow(error) {
  return /call stack|too much recursion/i.test(String(error?.message ?? error)) && (error instanceof RangeError || error?.name === 'InternalError');
}

/** `scope` is where the host's browser APIs come from (`self` in a Worker, `globalThis` on the main thread).
 * `canMigrate` keeps the end-of-pass snapshots a move to the main thread needs. */
export function createHostCore({ post: send, scope, canMigrate: mayMigrate = false }) {
  let canMigrate = mayMigrate;
  let instance = null, exports = null, browserIO = null;
  // The second half of a split release module (Tools/wasm-split-loader.js); null for a module that is not split.
  let split = null;
  let stackMeter = null, stackSamples = 0;
  let drainTimer = 0, drainScheduled = false, lastSeq = 0, diagnostics = false;
  // Diagnostics only: when the call behind the next publication reached this thread and when Swift returned from it (epoch
  // milliseconds, comparable with the page's `performance.timeOrigin + performance.now()`); the publication adds when it left.
  let callTiming = null;
  const epochNow = () => performance.timeOrigin + performance.now();
  let halted = false;
  /** A trap left the instance half-updated (a render pass open, scopes not restored): nothing calls into it again, or
   * every later call would only trap on that and bury the first error. The page has been told; it decides what follows. */
  let poisoned = false;
  let config = null;
  const listeners = new Map();
  // Replies go out on the page's BroadcastChannel when it opened one (see embedded-worker-client.js); the move to the main thread
  // keeps the worker's own port, which also carries the page's messages back in order.
  let replies = null;
  const OWN_PORT = new Set(['migrate', 'forward', 'forward-done']);
  const post = (message, transfer) => {
    if (halted && !OWN_PORT.has(message.t)) return;
    if (replies && !OWN_PORT.has(message.t)) replies.postMessage(message); else send(message, transfer || []);
  };
  const clock = { monotonicOffsetMs: 0 };
  // Page services (BrowserIO/service-host.mjs) live with the document, so this core forwards calls and subscriptions to
  // the page (embedded-worker-client.js answers them). After a move to the main thread the new core subscribes again.
  const serviceForwarder = createServiceForwarder(message => post(message));
  const services = serviceForwarder.services;
  let localMirror = null, sessionMirror = null, cookieMirror = null;
  // Calls processed, in arrival order. Each publication carries the count, so the host knows which of the events
  // it sent a publication already reflects (a text field must not take back a value older than what was typed).
  let callsProcessed = 0;
  // The count the page last heard of, in a publication or an ack: the page holds measurements while it is behind.
  let callsReported = 0;
  // The end-of-pass snapshot (`bytes` is reused from pass to pass) and the calls that ran since it.
  let snapshot = null, snapshotSeq = 0, sinceSnapshot = [];
  const snapshotCost = { count: 0, ms: 0 };
  // Diagnostics only: the next call fails as if the stack had run out, so any app can exercise the move.
  let forcedOverflow = false;

  const exportOf = name => exports?.[PREFIX + name];
  const exportByName = name => exportOf(name);
  const memoryOf = () => exports?.memory;

  function scheduleTaskDrain() {
    if (halted || poisoned || drainScheduled || !exports) return;
    const drain = exports.embedded_browser_drain_tasks;
    if (typeof drain !== 'function') return;
    drainScheduled = true;
    queueMicrotask(() => {
      drainScheduled = false;
      if (halted || poisoned) return;
      let ran = 0;
      try { ran = Number(drain() || 0); } catch (error) { failed(error, null); return; }
      if (ran) { flushDOM(); publishIfChanged(); takeSnapshot(); scheduleTaskDrain(); }
      // A BrowserIO callback can publish without running a task (a timer's): send that publication too.
      else { flushDOM(); publishIfChanged(); }
    });
  }

  function containsSecureField(bytes) {
    const first = SECURE_MARKER[0];
    outer: for (let i = bytes.indexOf(first); i >= 0; i = bytes.indexOf(first, i + 1)) {
      for (let j = 1; j < SECURE_MARKER.length; j++) if (bytes[i + j] !== SECURE_MARKER[j]) continue outer;
      return true;
    }
    return false;
  }

  /** Secure field ids Swift published with this snapshot. Builds without the id export fall back to scanning the HTML,
   * which is why that path still exists. */
  function secureIDs(html) {
    const published = readSecureIDs(exportByName, memoryOf());
    if (published) return published;
    if (!containsSecureField(html)) return [];
    const ids = [];
    for (const match of decoder.decode(html).matchAll(/data-keep-secure-id="([^"]*)"/g)) ids.push(match[1]);
    return ids;
  }

  function readSecureValues(ids) {
    const values = {};
    const secureValue = exportOf('secure_value');
    const hasReader = ['secure_value_pointer', 'secure_value_byte'].some(name => typeof exportOf(name) === 'function');
    if (typeof secureValue !== 'function' || !hasReader) return values;
    for (const id of ids) {
      writeEventValue(exportByName, memoryOf(), encoder.encode(id));
      const length = Number(secureValue());
      if (!Number.isSafeInteger(length) || length < 0 || length > 16 * 1024) { exportOf('secure_value_reset')?.(); continue; }
      values[id] = readSecureBytes(exportByName, memoryOf(), length);
      exportOf('secure_value_reset')?.();
    }
    return values;
  }

  /** Sends the newest snapshot when Swift published since the last one. */
  function publishIfChanged() {
    const sequence = Number(exportOf('publish_seq')?.() || 0);
    if (!sequence || sequence === lastSeq) return;
    lastSeq = sequence;
    const length = Number(exportOf('html_length')());
    if (!Number.isSafeInteger(length) || length <= 0) return;
    const pointer = Number(exportOf('html_pointer')()) >>> 0;
    const html = new Uint8Array(exports.memory.buffer, pointer, length).slice();
    const lazy = [];
    const lazyCount = Number(exportOf('lazy_collection_count')?.() || 0);
    for (let i = 0; i < lazyCount; i++) lazy.push([Number(exportOf('lazy_item_count')(i)), Number(exportOf('lazy_estimated_extent')(i))]);
    const message = { t: 'publish', seq: sequence, html, lazy, calls: callsProcessed };
    callsReported = callsProcessed;
    const secure = secureIDs(html);
    if (secure.length) message.secure = readSecureValues(secure);
    if (diagnostics && callTiming) { message.timing = { ...callTiming, posted: epochNow() }; callTiming = null; }
    if (diagnostics && typeof exports.embedded_browser_fiber_metric === 'function') {
      message.fiber = Array.from({ length: 50 }, (_, index) => Number(exports.embedded_browser_fiber_metric(index)));
    }
    post(message, [html.buffer]);
  }

  /** Sends the DOM writes queued since the last flush; the main thread applies them after this batch's patch. */
  function flushDOM() {
    const batch = browserIO?.domFlush?.();
    if (batch) post({ t: 'dom', seq: batch.seq, ops: batch.ops });
  }

  /** Copies linear memory at the end of a pass. The publication has already gone out, so the page does not wait for
   * it; a pass that follows starts from a state no trap has touched. */
  function takeSnapshot() {
    sinceSnapshot = [];
    browserIO?.snapshotTaken();
    if (!canMigrate || !exports) return;
    const length = exports.memory.buffer.byteLength;
    if (length > SNAPSHOT_LIMIT) { snapshot = null; return; }
    if (!snapshot || snapshot.bytes.length < length) snapshot = { bytes: new Uint8Array(length + (length >> 3)), length: 0, calls: 0, inflight: [] };
    const started = diagnostics ? performance.now() : 0;
    snapshot.bytes.set(new Uint8Array(exports.memory.buffer, 0, length));
    snapshot.length = length; snapshot.calls = callsProcessed;
    snapshot.inflight = browserIO ? browserIO.inflight() : [];
    snapshotSeq = lastSeq;
    if (diagnostics) {
      snapshotCost.count++; snapshotCost.ms += performance.now() - started;
      if (snapshotCost.count % 25 === 0) console.info(`[SwiftUIWeb] snapshots: ${snapshotCost.count}, ${(snapshotCost.ms / snapshotCost.count).toFixed(2)} ms each, ${length} bytes`);
    }
  }

  /** A trap came out of the instance. A stack overflow in a Worker moves the app to the main thread when there is a
   * snapshot to continue from; anything else (or no snapshot) is reported and the page decides what happens next. */
  function failed(error, message) {
    if (isStackOverflow(error) && canMigrate && snapshot && !halted) { migrateOut(message); return; }
    // A stack-overflow error out of the app is the engine's call stack running out (WebKit's Worker has a far shallower one
    // than its main thread); the page restarts the app on the main thread instead of leaving the tree half rendered.
    poisoned = true;
    clearInterval(drainTimer);
    post({ t: 'error', message: safeErrorMessage(error), stackOverflow: isStackOverflow(error), stack: stackOf(error) });
  }

  function migrateOut(failing) {
    const state = {
      memory: snapshot.bytes.buffer, length: snapshot.length, calls: snapshot.calls, seq: snapshotSeq,
      inflight: snapshot.inflight, log: sinceSnapshot, failing: failing && failing.t !== 'init' ? failing : null,
      // The side-effecting fetches this thread already sent since the snapshot: the replay must not send them again.
      sent: browserIO?.sentSinceSnapshot() ?? [],
      dom: browserIO?.domState?.() ?? null, local: [...localMirror.map], session: [...sessionMirror.map], cookies: cookieMirror.cookies,
      config, clock: { origin: performance.timeOrigin }
    };
    // Requests this thread has not started yet are not sent from here: the replay starts them once, on the new thread.
    browserIO?.fenceUnstarted();
    const buffer = snapshot.bytes.buffer;
    snapshot = null; sinceSnapshot = [];
    clearInterval(drainTimer);
    post({ t: 'migrate', state }, [buffer]);
    halted = true;
    instance = null; exports = null;
  }

  function environmentFor() {
    return {
      fetch: (...args) => scope.fetch(...args),
      indexedDB: scope.indexedDB,
      cookieJar: cookieMirror,
      // Web Crypto for the secureStore operation (WebSecurity's encrypted items).
      crypto: scope.crypto,
      Intl: scope.Intl,
      navigator: scope.navigator,
      // A worker cannot open windows: the page does, on request.
      openWindow(url) { post({ t: 'open-window', url }); return true; },
      localStorage: localMirror,
      sessionStorage: sessionMirror,
      addEventListener(type, listener) { (listeners.get(type) || listeners.set(type, new Set()).get(type)).add(listener); },
      removeEventListener(type, listener) { listeners.get(type)?.delete(listener); }
    };
  }

  function fail(error) { post({ t: 'error', message: safeErrorMessage(error), stackOverflow: isStackOverflow(error), stack: stackOf(error) }); }

  /** Builds the instance's imports (WASI, BrowserIO) and instantiates; the caller decides how it starts. */
  async function instantiateModule(module) {
    const wasiFunction = createWasiHost(() => instance, { environment: config.environment, get monotonicOffsetMs() { return clock.monotonicOffsetMs; } });
    const imports = Object.create(null);
    for (const item of WebAssembly.Module.imports(module)) {
      imports[item.module] ||= Object.create(null);
      if (item.module === 'wasi_snapshot_preview1' && item.kind === 'function') imports[item.module][item.name] = wasiFunction(item.name);
    }
    // `?stack-depth=1`: the render recursion reports its depth and the stack left (stack-probe.js).
    if (config.environment.includes('SWIFTUIWEB_STACK_DIAGNOSTICS=1')) stackMeter = createHeadroomMeter();
    browserIO = createBrowserIO({ getInstance: () => (halted || poisoned ? null : instance), environment: environmentFor(), baseURL: config.baseURL, wake: scheduleTaskDrain, onError: fail, remoteDOM: true, stackMeter, binaryAtoms: config.atoms, services, onServiceDelivered: serviceCheckpoint });
    imports.browser_io = browserIO.imports;
    // A Worker may wait for the second half synchronously when a call needs it before it arrived; the main thread loads
    // it before the instance runs (`adopt`). The launcher leaves the loader out of a bundle that is not split (Tools/wasm-split-loader.js).
    if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && config.secondary && isSplitModule(module)) {
      split = createSplitLoader(module, { url: config.secondary, canBlock: typeof XMLHttpRequest === 'function' && typeof document === 'undefined' });
      Object.assign(imports, split.imports);
    }
    instance = await WebAssembly.instantiate(module, imports);
    exports = instance.exports;
    if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && split) split.attach(instance);
  }

  function setUp(message) {
    diagnostics = message.diagnostics === true;
    if (typeof message.replies === 'string' && typeof BroadcastChannel === 'function' && !replies) replies = new BroadcastChannel(message.replies);
    // `window.__renderWorkerMigration = false` keeps the app on the older recovery (a restart), for tests.
    if (message.migrate === false) canMigrate = false;
    config = { diagnostics, migrate: message.migrate !== false, baseURL: message.baseURL, environment: Array.isArray(message.environment) ? message.environment : [], dark: message.dark === true, reducedMotion: message.reducedMotion === true, hostname: message.hostname || '', secure: message.secure === true };
    // The binary publication atoms a release app.wasm reads from its host (BinaryAtomTable). Kept in the config, so a host
    // that adopts this app (`adopt`) has them too.
    config.atoms = typeof message.atoms === 'string' ? message.atoms : '';
    if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && typeof message.secondary === 'string') config.secondary = message.secondary;
    localMirror = new MirrorStorage(0, message.local || [], post);
    sessionMirror = new MirrorStorage(1, message.session || [], post);
    cookieMirror = new CookieMirror(message, post);
  }

  async function init(message) {
    setUp(message);
    await instantiateModule(message.module);
    if (typeof exports._initialize === 'function') exports._initialize();
    // The second argument is flags: 1 reduced motion, then the publication flags.
    exports.embedded_browser_set_initial_preferences?.(message.dark ? 1 : 0, (message.reducedMotion ? 1 : 0) | ((message.publication | 0) & 0xFF78));
    if (typeof exports.embedded_browser_start !== 'function') throw new Error('Embedded browser entry export is missing');
    // The window before the start, so the first render lays out at it (the page reports it again after its first commit).
    const viewport = message.viewport;
    if (viewport?.width > 0 && viewport?.height > 0) exports.embedded_browser_viewport?.(viewport.width, viewport.height, message.dark ? 1 : 0, message.reducedMotion ? 1 : 0);
    exports.embedded_browser_start();
    // The executor wakes the host when it queues a job, so this timer is only a safety net.
    drainTimer = setInterval(scheduleTaskDrain, 250);
    publishIfChanged();
    takeSnapshot();
    scheduleTaskDrain();
    // The first screen is published: the rest of a split module downloads now, behind it.
    if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && split) split.prefetch();
  }

  /** Continues an app another host gave up on (a Worker whose stack ran out): same module, the snapshot as memory. The
   * calls that ran after the snapshot, then the one that failed, run again here, in order. */
  async function adopt(module, state) {
    setUp({
      ...state.config, local: state.local, session: state.session, cookies: state.cookies
    });
    // The two threads count `performance.now()` from different origins, and Swift keeps timestamps taken on the first:
    // shift this thread's monotonic clock so it continues from the Worker's.
    clock.monotonicOffsetMs = performance.timeOrigin - state.clock.origin;
    await instantiateModule(module);
    // The snapshot may be anywhere in the app, so the whole module is here before the replay.
    if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && split) await split.load();
    const memory = exports.memory;
    const missing = Math.ceil(state.length / 65536) - memory.buffer.byteLength / 65536;
    if (missing > 0) memory.grow(missing);
    new Uint8Array(memory.buffer, 0, state.length).set(new Uint8Array(state.memory, 0, state.length));
    // The snapshot can hold what a SecureField held; the instance's memory is the only copy that stays.
    new Uint8Array(state.memory, 0, state.length).fill(0);
    lastSeq = state.seq; callsProcessed = callsReported = state.calls;
    if (state.dom) browserIO.domTable(state.dom.seq, state.dom.table);
    drainTimer = setInterval(scheduleTaskDrain, 250);
    // The replay asks again for what the Worker already sent; those requests fail here rather than going out twice.
    browserIO.refuseReplayed(state.sent ?? []);
    // A page service's answer or event that trapped while it went into the app on the Worker reaches the app here: this
    // thread's forwarder drops the Worker's messages (another runtime), as it must for every other one. A reply answers the
    // replay's request for that call when the Worker made it after the snapshot; otherwise its operation (or the event's
    // observation) is restored by `resume` and receives it then.
    const failing = state.failing;
    const serviceFailing = failing?.t === 'service-reply' || failing?.t === 'service-event';
    browserIO.answerReplayed(serviceFailing ? failing : null);
    for (const message of state.log) await handle(message);
    if (failing && !serviceFailing) await handle(failing);
    browserIO.refuseReplayed([]);
    browserIO.answerReplayed(null);
    browserIO.resume(state.inflight);
    if (serviceFailing) { try { browserIO.redeliverService(failing); } catch (error) { failed(error, failing); } }
    // Whatever the failed pass would have published (or the tasks it left) goes out now.
    publishIfChanged();
    scheduleTaskDrain();
  }

  function call(message, woke) {
    callsProcessed++;
    if (forcedOverflow) { forcedOverflow = false; throw new RangeError('Maximum call stack size exceeded (forced)'); }
    const fn = exportOf(message.n);
    if (typeof fn !== 'function') return;
    if (message.v) writeEventValue(exportByName, memoryOf(), message.v);
    fn(...(message.a || []));
    if (diagnostics) callTiming = { name: message.n, wake: woke, ran: epochNow() };
    flushDOM();
    publishIfChanged();
    // An acknowledgement or a measurement that published nothing is kept for the replay instead of costing a snapshot:
    // the reports of one batch take one snapshot, at the batch_end that publishes them.
    if ((LOG_ONLY.has(message.n) || measurementKey(message) !== null) && lastSeq === snapshotSeq && snapshot) sinceSnapshot.push(message);
    else takeSnapshot();
    scheduleTaskDrain();
  }

  /** Tells the page a call has run when no publication said so. */
  function reportCalls() {
    if (callsReported === callsProcessed || halted) return;
    callsReported = callsProcessed;
    post({ t: 'ack', calls: callsProcessed });
  }

  /** A fresh `document.cookie` from the main thread. Swift learns about it through its change export, which posts
   * HTTPCookieStorage's notification after the mirror already holds the new string. */
  function cookiesChanged(cookies) {
    if (!cookieMirror || cookieMirror.cookies === cookies) return;
    cookieMirror.replace(cookies);
    exportOf('cookies_changed')?.();
    flushDOM();
    publishIfChanged();
    takeSnapshot();
    scheduleTaskDrain();
  }

  /** A page service's answer or event: the forwarder hands it to BrowserIO, which delivers it into Swift. */
  function serviceDelivered(data) {
    serviceForwarder.receive(data);
  }

  /** BrowserIO's hook, right after a service reply or event reached Swift and before the task drain it wakes: like a
   * cookie change, what it changed is published and kept in a snapshot, so a move to the main thread cannot lose it. */
  function serviceCheckpoint() {
    if (halted || poisoned) return;
    flushDOM();
    publishIfChanged();
    takeSnapshot();
  }

  function storageEvent(message) {
    const mirror = message.scope === 1 ? sessionMirror : localMirror;
    if (!mirror) return;
    if (message.key === null) mirror.map.clear();
    else if (message.newValue === null) mirror.map.delete(message.key);
    else mirror.map.set(message.key, message.newValue);
    for (const listener of listeners.get('storage') || []) listener({ storageArea: mirror, key: message.key, newValue: message.newValue, oldValue: message.oldValue });
  }

  /** Handles one message from the page. */
  // A call into a split module (an input, a reply) may need a function of app-rest.wasm. Until it has arrived, calls wait
  // for the download that is already under way instead of running: a placeholder hit would load the module again with a
  // synchronous request, downloading it twice (Tools/wasm-split-loader.js). The messages behind such a call wait with it,
  // in order. A call that only the first screen's functions answer waits too; it would not have to, but a call cannot
  // be undone once a placeholder stops it.
  let queue = null;
  let queued = 0;

  function handle(data) {
    const waits = queue !== null || (data.t === 'call' && globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && split && !split.loaded && !halted && !poisoned);
    if (!waits) return handleNow(data);
    queue ||= split.load().catch(() => { /* the call still loads it synchronously */ });
    queued += 1;
    const turn = queue.then(() => handleNow(data)).finally(() => { if (--queued === 0) queue = null; });
    queue = turn.catch(() => {});
    return turn;
  }

  async function handleNow(data) {
    // After the move the Worker only hands back what the page already sent it, in order; `drain-marker` ends that.
    if (halted) {
      if (data.t === 'drain-marker') post({ t: 'forward-done' });
      else if (data.t !== 'dispose') post({ t: 'forward', data });
      return;
    }
    if (poisoned && data.t !== 'dispose') return;
    try {
      if (data.t === 'init') await init(data);
      else if (data.t === 'call') { call(data, diagnostics ? epochNow() : 0); reportCalls(); }
      else if (data.t === 'storage') storageEvent(data);
      else if (data.t === 'cookies') cookiesChanged(data.cookies);
      else if (data.t === 'mounts') browserIO?.domTable(data.seq, data.table);
      else if (data.t === 'service-reply' || data.t === 'service-event') serviceDelivered(data);
      else if (data.t === 'force-overflow') forcedOverflow = diagnostics;
      else if (data.t === 'stack-reset') { stackMeter?.reset(); stackSamples = 0; }
      else if (data.t === 'dispose') { clearInterval(drainTimer); browserIO?.dispose?.(); halted = true; replies?.close(); return 'dispose'; }
    } catch (error) { failed(error, data); }
    if (stackMeter) { const stats = stackMeter.snapshot(); if (stats.samples !== stackSamples) { stackSamples = stats.samples; post({ t: 'stack-stats', stats }); } }
  }

  return { handle, adopt, get halted() { return halted; } };
}
