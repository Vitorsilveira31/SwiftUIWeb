import { createBrowserIO, safeErrorMessage } from './BrowserIO/browser-io.mjs';
import { mountEmbeddedBrowser } from './embedded-dom.js';
import { createHeadroomMeter, STACK_PROBE_MODULE } from './stack-probe.js';
import { createWasiHost, readDocumentEnvironment, stackDiagnosticsRequested, publicationFlags } from './wasi-host.js';
import { createWorkerInstance } from './embedded-worker-client.js';
import { watchCookies } from './cookie-watch.js';
import { writeEventValue } from './event-value.js';
import { createSplitLoader, isSplitModule } from './wasm-split-loader.js';

// The second half of a split release module (Tools/wasm-split-release.mjs): the functions the first screen did not run.
// A bundle that is not split has no such file, and its module has no placeholder to load it for. The launcher defines
// `globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER` as false for such a bundle, so the loader is not in its scripts at all; where it
// is not defined (development, the tests) the loader stays.
const SECONDARY_MODULE = './app-rest.wasm';
// The request for it that `instantiate` started early for a start on this thread, taken by the first loader that uses it.
let restRequest = null;

const encoder = new TextEncoder();
let instance = null;
let browserSession = null;
let browserIOHost = null;
let drainTimer = null;
let drainScheduled = false;

let workerInstance = null;
// A hot build of the development loop (Tools/side-module.js): the module that holds the framework and the standard
// library, and the application loaded into it as a side module. Both null in every other build.
let hotMain = null;
let hotSide = null;
// The loader, Tools/side-module.js. It is a file of a hot bundle only, imported by address when the page meets a hot
// build, so no other bundle carries it.
let sideModule = null;

/** Whether `module` is the main module of a hot build: every symbol exported, and no application entry of its own. */
function isHotMainModule(module) {
  let runtime = false;
  for (const entry of WebAssembly.Module.exports(module)) {
    if (entry.name === 'embedded_browser_start') return false;
    if (entry.name === 'swift_registerProtocolConformances') runtime = true;
  }
  return runtime;
}
// Main thread only: the worker client has its own watch, which keeps the worker's mirror current.
let cookieWatch = null;

function disposeCurrentSession() {
  try { cookieWatch?.dispose(); } catch { /* the page is going away */ }
  cookieWatch = null;
  try { workerInstance?.dispose?.(); } catch (error) { console.error('[SwiftUIWeb] worker dispose failed', safeErrorMessage(error)); }
  workerInstance = null;
  try { browserSession?.dispose?.(); } catch (error) { console.error('[SwiftUIWeb] session dispose failed', safeErrorMessage(error)); }
  try { browserIOHost?.dispose?.(); } catch (error) { console.error('[SwiftUIWeb] BrowserIO dispose failed', safeErrorMessage(error)); }
  if (drainTimer !== null) { clearInterval(drainTimer); drainTimer = null; }
  browserSession = null; browserIOHost = null; instance = null; drainScheduled = false;
  hotMain = null; hotSide = null;
}

/** A trap came out of the instance outside a call the DOM session made (a task drain). The instance is not used again:
 * a trap leaves it half-updated (a render pass left open, scopes not restored), so every later call would only trap
 * on that and bury the first error. The session reports it and stops its own entry points. */
function trapped(error) {
  if (drainTimer !== null) { clearInterval(drainTimer); drainTimer = null; }
  if (browserSession) browserSession.fail(error);
  else console.error('[SwiftUIWeb]', safeErrorMessage(error), typeof error?.stack === 'string' ? error.stack : '');
  instance = null; drainScheduled = false;
}

function scheduleTaskDrain() {
  if (drainScheduled || !instance) return;
  const drain = instance.exports?.embedded_browser_drain_tasks;
  if (typeof drain !== 'function') return;
  drainScheduled = true;
  queueMicrotask(() => {
    drainScheduled = false;
    if (!instance) return;
    let ran = 0;
    try { ran = Number(drain() || 0); } catch (error) { trapped(error); return; }
    // A BrowserIO callback can publish without running a task (a timer's): commit that publication too.
    if (ran || browserSession?.publicationPending?.()) browserSession?.flush();
    if (ran) scheduleTaskDrain();
  });
}

// The same document environment the worker client forwards, so both modes
// expose identical `WebEnvironment` values to Swift.
const wasiFunction = createWasiHost(() => instance, { environment: readDocumentEnvironment(globalThis.document, globalThis.navigator) });

function importsFor(module) {
  const imports = Object.create(null);
  for (const item of WebAssembly.Module.imports(module)) {
    imports[item.module] ||= Object.create(null);
    if (item.module === 'wasi_snapshot_preview1' && item.kind === 'function') imports[item.module][item.name] = wasiFunction(item.name);
  }
  let stackMeter = null;
  if (stackDiagnosticsRequested(globalThis.document)) { stackMeter = createHeadroomMeter(); globalThis.__stackProbe = stackMeter; }
  const browserIO = createBrowserIO({ getInstance: () => instance, wake: scheduleTaskDrain, stackMeter });
  browserIOHost = browserIO;
  imports.browser_io = browserIO.imports;
  return imports;
}

/** The page an OAuth server redirects a sign-in popup to (`<base>oauth-callback?code=...`): it hands the address to the
 * application window through Web Storage (the `oauth` namespace BrowserWebStorage reads) and closes, instead of
 * starting a second copy of the application. */
function finishOAuthCallback() {
  const location = globalThis.location;
  if (!location || !/\/oauth-callback\/?$/.test(location.pathname)) return false;
  try { globalThis.localStorage.setItem('swui:5:oauth:callback', location.href); } catch { /* storage blocked */ }
  try { globalThis.document.body.textContent = 'Signed in. You can close this window.'; globalThis.close(); } catch { /* not a popup */ }
  return true;
}

export async function instantiate(url = new URL('./app.wasm', import.meta.url), options = {}) {
  if (finishOAuthCallback()) return new Promise(() => {});
  disposeCurrentSession();
  const wantsWorker = workerRequested(options);
  // Unless a worker was asked for explicitly, check while the app module downloads that a Worker's
  // WebAssembly stack can hold a deep view tree (see `workerStackSufficient`).
  const stackCheck = wantsWorker && !workerForced(options) ? workerStackSufficient() : Promise.resolve(wantsWorker);
  // A split build that will run on this thread needs its second module before it starts: its download goes beside the
  // first one instead of after it (a Worker fetches it once the first screen is up). Only a split build defines the flag true.
  restRequest = null;
  if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER === true) {
    const requestRest = () => { restRequest ||= fetch(new URL(SECONDARY_MODULE, import.meta.url)); restRequest.catch(() => {}); };
    if (!wantsWorker) requestRest(); else stackCheck.then(sufficient => { if (!sufficient) requestRest(); });
  }
  // The page started this download itself (Tools/browser-index.html); a page without that script, or one that names
  // another module, is fetched here.
  const early = globalThis.__appModuleFetch;
  delete globalThis.__appModuleFetch;
  const response = early && early.href === new URL(url, globalThis.location?.href).href
    ? await early.response.catch(() => fetch(url))
    : await fetch(url);
  if (!response.ok) throw new Error(`Unable to fetch ${url}: ${response.status}`);
  const module = await WebAssembly.compileStreaming(response.clone()).catch(async () => WebAssembly.compile(await response.arrayBuffer()));
  // A hot build runs on this thread: the worker's host does not load side modules.
  if (wantsWorker && !isHotMainModule(module) && await stackCheck) {
    try {
      const facade = await instantiateWithWorker(module, options);
      // The probe is a proxy for the view tree; an app that still overflows the Worker's stack later (a deeper screen,
      // a state change that nests more) is restarted on the main thread, which has far more stack.
      facade.onStackOverflow?.(() => restartOnMainThread(module, options, 'after it started'));
      // The Worker hands the instance over with its state (section 12.11): nothing restarts, the app is on this thread.
      facade.onMigrated?.(() => noteWorkerOverflow('after it started', true));
      return facade;
    } catch (error) {
      if (!error?.stackOverflow) throw error;
      noteWorkerOverflow('while it started');
      disposeCurrentSession();
    }
  }
  return startOnMainThread(module, options, url);
}

/** The worker's stack ran out: remember it for this tab session, so a reload goes straight to the main thread. */
function noteWorkerOverflow(when, kept = false) {
  try { globalThis.sessionStorage?.setItem(WORKER_OVERFLOW_KEY, '1'); } catch { /* storage blocked */ }
  console.warn(`[SwiftUIWeb] The app overflowed the Worker's call stack ${when}; running it on the main thread instead${kept ? ', with its state' : ''}.`);
}

function restartOnMainThread(module, options, when) {
  noteWorkerOverflow(when);
  disposeCurrentSession();
  return startOnMainThread(module, options).catch(error => {
    console.error('[SwiftUIWeb] restarting on the main thread failed', safeErrorMessage(error));
    try { globalThis.dispatchEvent(new CustomEvent('runtime-error', { detail: { message: safeErrorMessage(error) } })); } catch { /* no window */ }
  });
}

async function fetchBytes(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`Unable to fetch ${url}: ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

async function startOnMainThread(module, options, url) {
  const hot = isHotMainModule(module);
  const imports = importsFor(module);
  // The framework calls a few entry points the application defines; in a hot build they are the side module's.
  if (hot) {
    sideModule = await import(new URL('./side-module.js', import.meta.url).href);
    imports.env = { ...(imports.env ?? {}), ...sideModule.applicationImports(module, () => hotSide) };
    // The main module of a hot build carries the whole standard library, whose static initializer seeds hashing from
    // /dev/urandom; the page has no files, and the runtime skips the seed when it is told to hash deterministically.
    const wasi = createWasiHost(() => instance, { environment: [...readDocumentEnvironment(globalThis.document, globalThis.navigator), 'SWIFT_DETERMINISTIC_HASHING=1'] });
    for (const name of Object.keys(imports.wasi_snapshot_preview1 ?? {})) imports.wasi_snapshot_preview1[name] = wasi(name);
  }
  // This thread cannot wait for the second half of a split module in the middle of a call, so it loads both before the
  // application runs; the download of the second starts with the instantiation of the first.
  let split = null, secondHalf = null;
  if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && !hot && isSplitModule(module)) {
    split = createSplitLoader(module, { url: new URL(SECONDARY_MODULE, import.meta.url).href, response: restRequest });
    restRequest = null;
    secondHalf = split.load();
    // Awaited below; a failure that lands while the first half instantiates is not an unhandled rejection meanwhile.
    secondHalf.catch(() => {});
    Object.assign(imports, split.imports);
  }
  const result = await WebAssembly.instantiate(module, imports);
  if (globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && split) { split.attach(result); await secondHalf; }
  instance = result;
  if (typeof instance.exports._initialize === 'function') instance.exports._initialize();
  if (hot) {
    hotMain = result;
    hotSide = sideModule.loadSideModule(hotMain, await fetchBytes(new URL('./app-side.wasm', url)));
    // The host calls the application's entry points and the framework's through one object, which a swap refills.
    instance = { exports: sideModule.mergedExports(hotMain, hotSide) };
  }
  launchApplication();
  finishMainThreadStart(options);
  return instance;
}

/** The application's start: the page's preferences and size first, so the first render lays out at them. */
function launchApplication() {
  const initialPreferences = instance.exports.embedded_browser_set_initial_preferences;
  if (typeof initialPreferences === 'function') {
    const dark = window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 1 : 0;
    const reducedMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ? 1 : 0;
    initialPreferences(dark, reducedMotion | publicationFlags(window));
    // The window before the start, so the first render lays out at it (the page reports it again after its first commit).
    const width = document.documentElement.clientWidth || window.innerWidth, height = window.visualViewport?.height || window.innerHeight;
    if (width > 0 && height > 0) instance.exports.embedded_browser_viewport?.(width, height, dark, reducedMotion);
  }
  if (typeof instance.exports.embedded_browser_start !== 'function') throw new Error('Embedded browser entry export is missing');
  instance.exports.embedded_browser_start();
}

/**
 * Hot swap (development loop, main thread): loads the side module at `url` into the running main module and starts the
 * application again in this page, with the state it can keep (the module saves it and the new one reads it, as on a
 * reload). Resolves false when this page is not running a hot build, so the caller reloads.
 */
async function swapApplication(url, options) {
  if (!hotMain || !instance) return false;
  const bytes = await fetchBytes(url);
  instance.exports.embedded_browser_state_save?.();
  try { browserSession?.dispose?.(); } catch (error) { console.error('[SwiftUIWeb] session dispose failed', safeErrorMessage(error)); }
  hotSide = sideModule.loadSideModule(hotMain, bytes);
  sideModule.mergedExports(hotMain, hotSide, instance.exports);
  launchApplication();
  browserSession = mountEmbeddedBrowser(instance, options);
  scheduleTaskDrain();
  return true;
}

function finishMainThreadStart(options) {
  // A host callback normally wakes the pump when BrowserIO completes. Keep a
  // small event-loop tick as a safety net for tasks that are enqueued by a
  // host callback that does not pass through BrowserIO (timers, storage, or
  // future WASM bridges).
  // The executor wakes the host when it queues a job, so this timer is only a safety net.
  drainTimer = setInterval(scheduleTaskDrain, 250);
  browserSession = mountEmbeddedBrowser(instance, options);
  globalThis.__swiftuiwebSwap = (url) => swapApplication(url, options);
  // Live literals, main thread only: the development loop's page script hands the replacements here.
  // State kept across a reload (development loop, main thread): the module writes its states to sessionStorage. False
  // when this module cannot (a release, a build without the development exports).
  globalThis.__swiftuiwebSaveState = () => {
    const save = instance?.exports?.embedded_browser_state_save;
    return typeof save === 'function' && save() > 0;
  };
  globalThis.__swiftuiwebLiveLiterals = text => {
    const apply = instance?.exports?.embedded_browser_live_literals;
    if (typeof apply !== 'function') return -1;
    const started = performance.now();
    writeEventValue(name => instance.exports[`embedded_browser_${name}`], instance.exports.memory, new TextEncoder().encode(text));
    const taken = apply();
    browserSession?.flush();
    globalThis.__swiftuiwebLiveLiteralsMs = performance.now() - started;
    return taken;
  };
  // The page's jar is read directly here. A change reaches the app through the export the worker also calls, then the
  // session commits the DOM the app publishes and any tasks its observers queued run.
  cookieWatch = watchCookies({ window: globalThis.window, onChange: () => {
    instance?.exports?.embedded_browser_cookies_changed?.();
    browserSession?.flush();
    scheduleTaskDrain();
  } });
  // The first lifecycle pass can enqueue URLSession/BrowserIO work. Drain it
  // only after the DOM session exists so an immediate response can publish its
  // state transition instead of losing the flush while browserSession is nil.
  scheduleTaskDrain();
}

/** The Swift side runs in a Worker when the browser has Workers, so renders do
 * not block input. Opt out with `instantiate(url, {worker: false})`,
 * `window.__renderWorker = false` or `?render-in-worker=0`. */
function workerForced(options) {
  if (options.worker === true || globalThis.__renderWorker === true) return true;
  try { return new URLSearchParams(globalThis.location?.search || '').get('render-in-worker') === '1'; } catch { return false; }
}

// WebKit runs a Worker's WebAssembly on a call stack about 13 times shallower than its main thread's: a minimal
// recursive function reaches about 555 frames in a WebKit Worker against about 7,100 on its main thread (Chromium:
// about 63,500 and 15,400). A Worker whose stack cannot take STACK_PROBE_DEPTH frames of that function runs the app on
// the main thread instead. A probe that cannot run (no Worker, a blocked blob: URL) keeps the Worker.
//
// The threshold comes from measurement: the
// deepest real screen measured in a WebKit Worker (`?stack-depth=1`) needed about 273 probe frames, and the threshold
// is twice that (WebKit holds 555 to 558, so the margin over the threshold is a few frames). Since then the render is
// staged (section 12.4): the render recursion no longer grows with the depth of the view tree, the same screens need
// 145 to 191 frames, and the probe and the restart below are a safety net for the cases staging cannot cut (a long
// run of modifiers or conditionals with no stack, ZStack or layout in it), not the way deep trees are handled. An app
// that overflows anyway is restarted on the main thread (`restartOnMainThread`).
const STACK_PROBE_DEPTH = 546;
const STACK_PROBE_VERSION = 2;
const WORKER_OVERFLOW_KEY = 'swui:worker-overflow';
function workerStackSufficient() {
  try { if (globalThis.sessionStorage?.getItem(WORKER_OVERFLOW_KEY) === '1') return Promise.resolve(false); } catch { /* storage blocked */ }
  const key = `swui:worker-stack:v${STACK_PROBE_VERSION}:${STACK_PROBE_DEPTH}`;
  try { const cached = globalThis.sessionStorage?.getItem(key); if (cached !== null && cached !== undefined) return Promise.resolve(cached === '1'); } catch { /* storage blocked */ }
  return new Promise(resolve => {
    let worker, url, timer;
    const finish = sufficient => {
      clearTimeout(timer); try { worker?.terminate(); } catch { /* gone */ } if (url) URL.revokeObjectURL(url);
      try { globalThis.sessionStorage?.setItem(key, sufficient ? '1' : '0'); } catch { /* storage blocked */ }
      resolve(sufficient);
    };
    try {
      const source = `let ok=true;try{new WebAssembly.Instance(new WebAssembly.Module(new Uint8Array([${STACK_PROBE_MODULE}]))).exports.f(${STACK_PROBE_DEPTH});}catch(error){ok=error instanceof RangeError?false:true;}postMessage(ok);`;
      url = URL.createObjectURL(new Blob([source], { type: 'text/javascript' }));
      worker = new Worker(url);
    } catch { resolve(true); return; }
    timer = setTimeout(() => finish(true), 3000);
    worker.onmessage = event => finish(event.data === true);
    worker.onerror = () => finish(true);
  });
}

function workerRequested(options) {
  if (typeof Worker !== 'function') return false;
  if (options.worker === false || options.worker === true) return options.worker;
  if (typeof globalThis.__renderWorker === 'boolean') return globalThis.__renderWorker;
  try { return new URLSearchParams(globalThis.location?.search || '').get('render-in-worker') !== '0'; } catch { return true; }
}

async function instantiateWithWorker(module, options) {
  const secondary = globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER !== false && isSplitModule(module) ? new URL(SECONDARY_MODULE, import.meta.url).href : null;
  const facade = await createWorkerInstance(module, { baseURL: document.baseURI, secondary, diagnostics: options.performanceDiagnostics === true || window.__performanceDiagnostics === true });
  workerInstance = facade;
  browserSession = mountEmbeddedBrowser(facade, options);
  // State kept across a reload: the worker is asked to save, and its storage write reaches this thread a moment later
  // (the page script waits for the key).
  globalThis.__swiftuiwebSaveState = () => facade.exports.embedded_browser_state_save() > 0;
  // Live literals: the worker takes the replacements as an event value and publishes what it renders.
  globalThis.__swiftuiwebLiveLiterals = text => {
    facade.exports.embedded_browser_event_value_write(new TextEncoder().encode(text));
    return facade.exports.embedded_browser_live_literals();
  };
  return facade;
}
