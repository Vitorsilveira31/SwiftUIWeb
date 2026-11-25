// Main-thread side of the Swift worker (see embedded-worker.js).
//
// It presents the same `exports` surface the DOM host already calls, so the
// host does not know the Swift side lives in another thread. Calls that change
// Swift state are posted; the few the host used to read synchronously are
// answered from the newest snapshot the worker published.
import { readDocumentEnvironment, stackDiagnosticsRequested, publicationFlags } from './wasi-host.js';
import { createRemoteDOMHost } from './remote-dom-host.js';
import { createServiceResponder } from './BrowserIO/service-host.mjs';
import { safeErrorStack } from './BrowserIO/browser-io.mjs';
import { watchCookies } from './cookie-watch.js';
import { createHostCore, measurementKey } from './embedded-host-core.js';
import { BINARY_ATOMS } from './binary-atoms.generated.js';

const PREFIX = 'embedded_browser_';
const STORAGE_PREFIX = 'swui:';

function snapshotStorage(storage) {
  const entries = [];
  try {
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (key && key.startsWith(STORAGE_PREFIX)) entries.push([key, storage.getItem(key)]);
    }
  } catch { /* storage can be blocked */ }
  return entries;
}

/** Starts the worker, waits for its first snapshot and returns the facade. */
/** A window this page opens for `openURL` shows another site, which must not reach back through `window.opener` and
 * navigate the application's own tab to a page of its choosing. The link is cut right after `open`, while the new window
 * still holds its initial blank document; `noopener` would cut it too, but then `open` returns null and a blocked popup
 * could not be told from an opened one. True when a window was opened. */
function severOpener(opened) {
  if (!opened) return false;
  try { opened.opener = null; } catch { /* the window is already gone */ }
  return true;
}

export async function createWorkerInstance(module, { baseURL, secondary = null, diagnostics = false, window: hostWindow = globalThis.window } = {}) {
  const workerName = './render-worker.js';
  const worker = new Worker(new URL(workerName, import.meta.url), { type: 'module' });
  let latest = { seq: 0, html: new Uint8Array(0), lazy: [], secure: {}, fiber: null };
  const subscribers = new Set();
  let value = [];
  let secure = null;
  let failure = null;
  let disposed = false;
  const overflowHandlers = new Set();
  const migratedHandlers = new Set();
  // Where messages for the Swift side go: the worker, or (after its call stack ran out, see `migrate`) a host core on
  // this thread. While the move is under way they wait in `held`.
  let target = 'worker', localCore = null, migrated = false;
  const held = [], forwarded = [];
  const send = (message, transfer) => {
    if (target === 'worker') worker.postMessage(message, transfer || []);
    else if (target === 'local') queueLocal(message);
    else held.push(message);
  };
  // The core delivers in order and never inside the call that produced the message, like a worker would.
  let localQueue = Promise.resolve();
  const queueLocal = message => { localQueue = localQueue.then(() => localCore.handle(message)).catch(error => fail(safeText(error))); };
  const safeText = error => String(error?.message ?? error);
  let stackStats = { samples: 0, maxDepth: 0, capacity: 0, minHeadroom: -1, minDepth: 0, used: 0 };
  // `?stack-depth=1`: measurements of the worker's render recursion, read by tooling as `window.__stackProbe`.
  if (hostWindow && stackDiagnosticsRequested(hostWindow.document)) {
    hostWindow.__stackProbe = {
      snapshot: () => ({ ...stackStats }),
      reset: () => { stackStats = { ...stackStats, samples: 0, maxDepth: 0, minHeadroom: -1, minDepth: 0, used: 0 }; send({ t: 'stack-reset' }); }
    };
  }
  // Diagnostics: `window.__renderWorker.forceOverflow()` makes the worker's next call fail as if its stack had run out, to
  // exercise the move to the main thread on any app; `holds(address, word)` says whether a 32-bit word of the memory the app moved to is `word`.
  if (hostWindow && diagnostics) hostWindow.__renderWorker = { forceOverflow: () => send({ t: 'force-overflow' }), holds: (address, word) => localCore?.holds(address, word) ?? false, get migrated() { return migrated; } };
  let firstPublish;
  // The worker has no document: WebMount elements are reported to it and its
  // writes come back as `dom` messages (see remote-dom-host.js).
  const remote = hostWindow?.document?.querySelectorAll ? createRemoteDOMHost({ document: hostWindow.document, window: hostWindow }) : null;
  // The page's headless services (BrowserIO/service-host.mjs): the core forwards Swift's calls and subscriptions here.
  // Subscriptions belong to the core that made them, so a move to the main thread or a dispose ends them all; the new
  // core subscribes again.
  const pageServices = createServiceResponder(hostWindow, message => send(message));
  let workerHasMounts = false;
  const firstPublished = new Promise((resolve, reject) => { firstPublish = { resolve, reject }; });

  let callsSent = 0;
  // Calls the Swift side has run: every call ends in a publication or an `ack`, and both carry the count.
  let callsHandled = 0;
  const behind = () => callsSent > callsHandled;
  // Measurements (the viewport, a lazy collection's window, geometry and layout reports, see `measurementKey`) only
  // say what the newest value is. While the Swift side is still running earlier calls they wait here, a newer one
  // replacing the one with its key, and go out once it has caught up: a window resized faster than Swift renders costs
  // a pass per pass Swift can do, not one per frame queued behind the others. Any other call sends them first, so they
  // keep their order relative to it. They go out together in one batch, so Swift runs one pass for all of them (a lone
  // one, or ones sent inside a batch already posted, need no batch of their own).
  const waiting = new Map();
  // One entry per open batch_begin: true once posted. A batch that opens while Swift is behind is held with the
  // measurements inside it, and posted only if another call needs it.
  const batches = [];
  const post = message => { callsSent++; send(message); };
  const openBatches = () => {
    for (let level = 0; level < batches.length; level++) {
      if (!batches[level]) { batches[level] = true; post({ t: 'call', n: 'batch_begin', a: [] }); }
    }
  };
  const sendWaiting = () => {
    if (!waiting.size) return;
    const batch = waiting.size > 1 && !batches.some(Boolean);
    if (batch) post({ t: 'call', n: 'batch_begin', a: [] });
    for (const message of waiting.values()) post(message);
    if (batch) post({ t: 'call', n: 'batch_end', a: [] });
    waiting.clear();
  };
  const holding = () => (batches.length ? !batches[batches.length - 1] : behind());
  const call = (name, args = [], withValue = true) => {
    const message = { t: 'call', n: name, a: args, v: withValue && value.length ? (value instanceof Uint8Array ? value : Uint8Array.from(value)) : undefined };
    if (name === 'batch_begin') {
      const hold = holding();
      batches.push(!hold);
      if (!hold) post(message);
      return;
    }
    if (name === 'batch_end' && batches.length) {
      if (batches.pop()) post(message);
      if (!batches.length && !behind()) sendWaiting();
      return;
    }
    // A timeline's tick only says what time it is now: while Swift is behind, a newer tick replaces the one waiting, as a
    // measurement does.
    const key = name === 'timeline_tick' ? 'timeline' : measurementKey(message);
    if (key !== null && holding()) {
      waiting.delete(key);
      waiting.set(key, message);
      return;
    }
    // An acknowledgement says nothing about the measurements and arrives with every commit, and a tick arrives at every
    // frame of an animated timeline: both pass them. A tick that sent them on its way made Swift draw every width a
    // sliding sidebar went through, one after the other, a second and a half behind the page (Food Truck's animated
    // header ticks at every frame).
    if (name !== 'publish_ack' && name !== 'timeline_tick') { sendWaiting(); openBatches(); }
    post(message);
  };
  /** The Swift side reported how many calls it has run; once it has run them all, what waited goes out. */
  const handled = count => {
    callsHandled = Number.isFinite(count) ? Math.max(callsHandled, count) : callsSent;
    if (!behind() && !batches.length) sendWaiting();
  };

  const storages = { 0: safely(() => hostWindow.localStorage), 1: safely(() => hostWindow.sessionStorage) };
  function safely(read) { try { return read(); } catch { return null; } }
  function wipeSecure(values) { for (const bytes of Object.values(values ?? {})) bytes?.fill?.(0); }

  // The worker's cookie mirror is a copy of `document.cookie`: every change the watch reports is sent to the worker.
  const cookieWatch = watchCookies({ window: hostWindow, onChange: cookies => send({ t: 'cookies', cookies }) });

  worker.onmessage = ({ data }) => receive(data);
  // Chromium holds the messages a worker posts to the page until the next frame once the page has handled a pointer event
  // (the scheduler favours rendering after input), so the answer to a click waits up to a frame however fast Swift was.
  // A BroadcastChannel is not held. The worker sends everything it posts on one, so the messages keep their order; the name is
  // random and only this page and its worker know it. Without the API the worker's own messages carry on as before.
  let replies = null;
  if (typeof hostWindow?.BroadcastChannel === 'function' && typeof hostWindow.crypto?.randomUUID === 'function') {
    try {
      replies = new hostWindow.BroadcastChannel(`swui-replies-${hostWindow.crypto.randomUUID()}`);
      replies.onmessage = ({ data }) => receive(data);
      replies.onmessageerror = () => fail('SwiftUIWeb worker sent a message the page could not read');
    } catch { replies = null; }
  }
  function receive(data) {
    if (data.t === 'migrate') {
      beginMigration(data.state);
    } else if (data.t === 'forward') {
      forwarded.push(data.data);
    } else if (data.t === 'forward-done') {
      finishMigration();
    } else if (data.t === 'publish') {
      // SecureField values live only until the next publication replaces them.
      wipeSecure(latest.secure);
      latest = data;
      firstPublish.resolve();
      handled(data.calls);
      for (const subscriber of subscribers) subscriber();
    } else if (data.t === 'ack') {
      handled(data.calls);
    } else if (data.t === 'cookie-write') {
      // The page's own cookie jar applies the line: HttpOnly and refused cookies are the browser's to decide.
      try { if (hostWindow?.document) hostWindow.document.cookie = data.line; } catch { /* refused by the browser */ }
      cookieWatch.wrote();
    } else if (data.t === 'storage-write') {
      const storage = storages[data.scope];
      try {
        if (!storage) return;
        if (data.op === 'set') storage.setItem(data.key, data.value);
        else if (data.op === 'remove') storage.removeItem(data.key);
        else storage.clear();
      } catch { /* quota or blocked storage: the worker's mirror keeps working */ }
    } else if (data.t === 'dom') {
      remote?.apply(data.seq, data.ops);
    } else if (data.t === 'service' || data.t === 'service-observe' || data.t === 'service-unobserve') {
      if (!disposed) pageServices.receive(data);
    } else if (data.t === 'open-window') {
      try { severOpener(hostWindow?.open(String(data.url), 'popup-window', 'popup,width=520,height=720')); } catch { /* blocked */ }
    } else if (data.t === 'stack-stats') {
      stackStats = data.stats;
    } else if (data.t === 'error') {
      fail(data.message, data.stackOverflow === true, data.stack);
    }
  }

  // The worker's call stack ran out in the middle of a pass. It sent the state to continue from (a snapshot of the
  // instance's memory taken after the last complete pass, the calls since, the call that failed, the host's state); the
  // messages it had not read yet come back as `forward`, ending with `forward-done`, and the page's own new messages wait
  // in `held`. Then the same module runs in a host core on this thread (embedded-host-core.js), which
  // continues from that state with the page's DOM, layout and event wiring untouched.
  let migration = null;
  function beginMigration(state) {
    migration = state;
    pageServices.end();
    target = 'migrating';
    worker.postMessage({ t: 'drain-marker' });
  }
  async function finishMigration() {
    const state = migration; migration = null;
    try { worker.terminate(); } catch { /* gone */ }
    if (disposed || !state) return;
    localCore = createHostCore({ post: message => queueMicrotask(() => receive(message)), scope: hostWindow ?? globalThis, canMigrate: false });
    try {
      await localCore.adopt(module, state);
      migrated = true;
      target = 'local';
      for (const message of [...forwarded.splice(0), ...held.splice(0)]) queueLocal(message);
      for (const handler of migratedHandlers) handler();
    } catch (error) {
      // The state could not be carried over: report it as the overflow it was, so the page restarts the app instead.
      target = 'local';
      fail(safeText(error), true);
    }
  }
  // A worker that cannot load its script (a dropped connection, a 404) reports through `error`, and a
  // message the browser cannot deserialize reports through `messageerror`. Both must fail the boot here:
  // otherwise the first publication never arrives and the page stays blank without a message.
  worker.onerror = event => {
    fail(event.message || 'SwiftUIWeb worker failed to load');
  };
  worker.onmessageerror = () => fail('SwiftUIWeb worker sent a message the page could not read');
  function fail(message, stackOverflow = false, stack = '') {
    failure ??= new Error(message);
    if (stackOverflow) failure.stackOverflow = true;
    firstPublish.reject(failure);
    console.error(`[SwiftUIWeb] ${failure.message}`, typeof stack === 'string' ? stack : '');
    window_dispatchError(failure.message, stack);
    // The app ran out of call stack in the worker. Whoever started the worker decides what happens next (the
    // runtime restarts the app on the main thread, whose stack is far deeper).
    if (stackOverflow && !disposed) for (const handler of overflowHandlers) handler(failure);
  }
  function window_dispatchError(message, stack) {
    try { hostWindow?.dispatchEvent(new hostWindow.CustomEvent('runtime-error', { detail: { message, stack: safeErrorStack(stack) } })); } catch { /* no window */ }
  }
  const onStorage = event => {
    const scope = event.storageArea === storages[1] ? 1 : event.storageArea === storages[0] ? 0 : -1;
    if (scope < 0) return;
    send({ t: 'storage', scope, key: event.key, newValue: event.newValue, oldValue: event.oldValue });
  };
  hostWindow?.addEventListener?.('storage', onStorage);

  const prefersDark = hostWindow?.matchMedia?.('(prefers-color-scheme: dark)').matches === true;
  const prefersReduced = hostWindow?.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
  worker.postMessage({
    // The binary publication atoms: a release app.wasm reads them from its host instead of carrying them (BinaryAtomTable).
    atoms: BINARY_ATOMS.join('\0'),
    t: 'init', module, baseURL, secondary, diagnostics, replies: replies?.name ?? null, migrate: hostWindow?.__renderWorkerMigration !== false, dark: prefersDark, reducedMotion: prefersReduced, publication: hostWindow ? publicationFlags(hostWindow) : 0,
    // Swift's first render lays out at the window (`embedded_browser_viewport` before the start).
    viewport: hostWindow ? { width: hostWindow.document?.documentElement?.clientWidth || hostWindow.innerWidth, height: hostWindow.visualViewport?.height || hostWindow.innerHeight } : null,
    environment: readDocumentEnvironment(hostWindow?.document, hostWindow?.navigator),
    local: snapshotStorage(storages[0]), session: snapshotStorage(storages[1]),
    cookies: cookieWatch.current(), hostname: hostWindow?.location?.hostname ?? '',
    secure: hostWindow?.location?.protocol === 'https:'
  });
  try { await firstPublished; } catch (error) {
    // The boot failed (for instance the app overflowed the worker's stack): nothing will use this worker.
    disposed = true;
    wipeSecure(latest.secure);
    hostWindow?.removeEventListener?.('storage', onStorage);
    cookieWatch.dispose();
    try { worker.terminate(); } catch { /* gone */ }
    throw error;
  }

  // A copy, so zeroing it on reset leaves the publication's value for the next commit.
  const secureBytes = id => latest.secure?.[id]?.slice() ?? null;
  const exports = {
    [PREFIX + 'start']: () => {},
    [PREFIX + 'event_value_reset']: () => { value = []; },
    [PREFIX + 'event_value_push']: byte => { if (value instanceof Uint8Array) value = Array.from(value); value.push(byte); },
    // One copy instead of a call per byte; the host prefers this over push.
    [PREFIX + 'event_value_write']: bytes => { value = Uint8Array.from(bytes); },
    [PREFIX + 'dispatch']: (id, code) => call('dispatch', [id, code]),
    // The worker cannot answer synchronously, so an `onKeyPress` action can no
    // longer veto the browser's default from here.
    [PREFIX + 'dispatch_named']: (id, nameLength) => { call('dispatch_named', [id, nameLength]); return 0; },
    // The reconciliation runs in the worker against a snapshot of the mounted elements taken
    // now, after this commit's patch. Both messages are posted in order, so the snapshot
    // is in place before the worker reconciles.
    [PREFIX + 'webmount_reconcile']: () => {
      if (!remote) return;
      const { seq, entries } = remote.snapshot();
      if (!entries.length && !workerHasMounts) return;
      workerHasMounts = entries.length > 0;
      send({ t: 'mounts', seq, table: entries });
      call('webmount_reconcile', [], false);
    },
    // Live literals: the pending event value holds the replacements. The worker cannot answer, so 1 is "sent".
    [PREFIX + 'live_literals']: () => { call('live_literals'); return 1; },
    // State kept across a reload: the worker writes its states to its storage, which is mirrored to this thread.
    [PREFIX + 'state_save']: () => { call('state_save'); return 1; },
    [PREFIX + 'timeline_tick']: () => call('timeline_tick', [], false),
    [PREFIX + 'batch_begin']: () => call('batch_begin', [], false),
    [PREFIX + 'batch_end']: () => call('batch_end', [], false),
    [PREFIX + 'viewport']: (width, height, dark, reduced) => call('viewport', [width, height, dark, reduced], false),
    [PREFIX + 'lazy_window']: (index, start, count, before, after, lanes, row) => call('lazy_window', [index, start, count, before, after, lanes, row], false),
    [PREFIX + 'lazy_collection_count']: () => latest.lazy.length,
    [PREFIX + 'lazy_item_count']: index => latest.lazy[index]?.[0] ?? 0,
    [PREFIX + 'lazy_estimated_extent']: index => latest.lazy[index]?.[1] ?? 44,
    [PREFIX + 'scroll_ack']: sequence => call('scroll_ack', [sequence], false),
    [PREFIX + 'scroll_prepare']: () => { call('scroll_prepare'); return 0; },
    [PREFIX + 'history_ack']: sequence => call('history_ack', [sequence], false),
    [PREFIX + 'history_restore']: () => call('history_restore'),
    [PREFIX + 'history_location']: () => call('history_location'),
    [PREFIX + 'publish_seq']: () => latest.seq,
    // The worker processes calls in order: a publication reflects every call up to `calls`, and so does the latest one
    // for a call the worker answered with an `ack` (it changed nothing to publish).
    [PREFIX + 'calls_sent']: () => callsSent,
    [PREFIX + 'calls_reflected']: () => Math.max(latest.calls ?? callsSent, callsHandled),
    [PREFIX + 'publish_ack']: sequence => call('publish_ack', [sequence], false),
    [PREFIX + 'publish_full']: () => call('publish_full', [], false),
    [PREFIX + 'html_length']: () => latest.html.length,
    [PREFIX + 'html_byte']: index => latest.html[index],
    [PREFIX + 'secure_value']: () => {
      secure = secureBytes(new TextDecoder().decode(value instanceof Uint8Array ? value : Uint8Array.from(value)));
      return secure ? secure.length : 0;
    },
    [PREFIX + 'secure_value_byte']: index => secure?.[index] ?? 0,
    [PREFIX + 'secure_value_bytes']: () => secure ?? new Uint8Array(0),
    [PREFIX + 'secure_value_reset']: () => { secure?.fill(0); secure = null; },
    fiber_metric_unused: undefined
  };
  exports.embedded_browser_fiber_metric = index => latest.fiber?.[index] ?? 0;
  delete exports.fiber_metric_unused;

  return {
    exports,
    /** The newest snapshot's bytes, so the host need not copy them byte by byte. */
    htmlBytes: () => latest.html,
    subscribe(callback) { subscribers.add(callback); return () => subscribers.delete(callback); },
    get failure() { return failure; },
    /** Calls `handler` when the worker reports that the app overflowed the call stack after it started. */
    onStackOverflow(handler) { overflowHandlers.add(handler); },
    /** True once the app moved from the worker to the main thread with its state (see `finishMigration`). */
    get migrated() { return migrated; },
    /** Calls `handler` when the worker's call stack ran out and the app carried on, state intact, on the main thread. */
    onMigrated(handler) { migratedHandlers.add(handler); },
    dispose() {
      if (disposed) return;
      disposed = true;
      pageServices.end({ final: true });
      wipeSecure(latest.secure);
      hostWindow?.removeEventListener?.('storage', onStorage);
      cookieWatch.dispose();
      if (target === 'local') localQueue = localQueue.then(() => localCore.handle({ t: 'dispose' }));
      else worker.postMessage({ t: 'dispose' });
      setTimeout(() => { worker.terminate(); replies?.close(); }, 50);
    }
  };
}
