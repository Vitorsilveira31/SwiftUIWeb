import { safeErrorMessage } from './BrowserIO/browser-io.mjs';

/** `KEY=VALUE` entries from every `<meta name="runtime-environment">` of a
 * document, in document order. The build writes one per generated value
 * (asset manifests, the active language) and applications may add their own
 * in `Resources/head.html`; they reach Swift through `WebEnvironment`. */
export function readDocumentEnvironment(document, navigator = undefined) {
  const entries = [];
  if (document?.querySelectorAll) {
    for (const meta of document.querySelectorAll('meta[name="runtime-environment"]')) {
      const content = meta.getAttribute('content');
      if (typeof content === 'string' && content.includes('=')) entries.push(content);
    }
  }
  // Where the page lives: an application that needs an address of its own (an OAuth redirect) builds it from this.
  const base = document?.baseURI;
  if (typeof base === 'string' && base && !entries.some(entry => entry.startsWith('SWIFTUIWEB_BASE_URL='))) {
    entries.push(`SWIFTUIWEB_BASE_URL=${base.split(/[?#]/)[0]}`);
  }
  // The browser's UI language selects the localized strings table unless a
  // meta pinned SWIFTUIWEB_LANGUAGE for the application.
  const language = navigator?.language;
  if (typeof language === 'string' && language && !entries.some(entry => entry.startsWith('SWIFTUIWEB_LANGUAGE='))) {
    entries.push(`SWIFTUIWEB_LANGUAGE=${language}`);
  }
  // The address the page was opened at, so the first render already shows the screen it names (a deep link, a restored
  // TabView selection) instead of the start screen followed by a navigation. `SWIFTUIWEB_INITIAL_NAVIGATION_STATE=1`
  // says this history entry already carries a typed NavigationStack snapshot, which owns the route instead of the path.
  const location = document?.location;
  if (typeof location?.pathname === 'string' && !entries.some(entry => entry.startsWith('SWIFTUIWEB_INITIAL_LOCATION='))) {
    entries.push(`SWIFTUIWEB_INITIAL_LOCATION=${location.pathname}${location.search || ''}${location.hash || ''}`);
    try { const entry = document.defaultView?.history?.state; if (entry?.swuiNavigation?.depth > 0 && entry.swuiPath !== true) entries.push('SWIFTUIWEB_INITIAL_NAVIGATION_STATE=1'); } catch { /* sandboxed */ }
  }
  // `?stack-depth=1` turns on the render-depth and stack-headroom measurement (see stack-probe.js).
  if (stackDiagnosticsRequested(document)) entries.push('SWIFTUIWEB_STACK_DIAGNOSTICS=1');
  // `?render-stage=N` overrides how many view levels a render descends before it stages the rest (0 turns staging off).
  const stage = renderStageRequested(document);
  if (stage !== null) entries.push(`SWIFTUIWEB_RENDER_STAGE=${stage}`);
  return entries;
}

/** How the page asks Swift to publish (`set_initial_preferences` flags, Documentation/Architecture/BINARY_PATCHES.md):
 * 32 to attach a reference encoding of the tree to each publication for the page to compare the DOM it built with (`window.__binaryVerify = true`,
 * `?binary-verify=1`); 64 to build the subtrees of a publication in full instead of as shapes (`window.__binaryShapes = false`,
 * `?binary-shapes=0`). 8 and 16 are retired: they chose the HTML transport. */
export function publicationFlags(window) {
  const search = window?.location?.search || '';
  const verify = window?.__binaryVerify === true || /[?&]binary-verify=1\b/.test(search);
  const shapes = typeof window?.__binaryShapes === 'boolean' ? window.__binaryShapes : !/[?&]binary-shapes=0\b/.test(search);
  // Tuning of the shapes (0, the default, or 1 to 15): subtrees of a skeleton that make it worth defining, and elements in a shape.
  const tuning = (name, shift) => ((Number(window?.[name]) || 0) & 15) << shift;
  return (verify ? 32 : 0) | (shapes ? 0 : 64) | tuning('__binaryShapeInstances', 8) | tuning('__binaryShapeElements', 12);
}

/** Whether the page is served from this machine (localhost, 127.0.0.1, ::1, *.localhost). The diagnostic switches in the
 * address work only there: on a deployed site a link could otherwise turn render staging off (`?render-stage=0`), and a
 * deep screen would then overflow the browser's stack. */
export function developmentHost(document) {
  try {
    const host = String(document?.location?.hostname || '').toLowerCase();
    return host === 'localhost' || host === '127.0.0.1' || host === '[::1]' || host === '::1' || host.endsWith('.localhost');
  } catch { return false; }
}

/** True when the page address asks for the stack measurement (`?stack-depth=1`), on a development host. */
export function stackDiagnosticsRequested(document) {
  if (!developmentHost(document)) return false;
  try { return new URLSearchParams(document?.location?.search || '').get('stack-depth') === '1'; } catch { return false; }
}

/** The render staging budget the page address asks for (`?render-stage=N`), or null. A debugging and testing aid on a
 * development host: a small budget stages almost every container, which is how the suites check that staging changes
 * nothing. */
export function renderStageRequested(document) {
  if (!developmentHost(document)) return null;
  try {
    const value = new URLSearchParams(document?.location?.search || '').get('render-stage');
    return value !== null && /^\d{1,4}$/.test(value) ? Number(value) : null;
  } catch { return null; }
}

/** The WASI subset the Embedded Swift runtime needs, bound to whichever
 * instance `getInstance` returns. Shared by the main-thread runtime and the
 * worker that runs the Swift side off the main thread. `environment` lists
 * the `KEY=VALUE` strings `environ_get` exposes (see `readDocumentEnvironment`); `options.monotonicOffsetMs` may be
 * set later to shift the monotonic clock. */
export function createWasiHost(getInstance, options = {}) {
  const { environment = [] } = options;
  const environmentBytes = environment.map(entry => new TextEncoder().encode(String(entry)));
  function memoryView() {
    const memory = getInstance()?.exports?.memory;
    return memory instanceof WebAssembly.Memory ? new DataView(memory.buffer) : null;
  }
  function bytes() {
    const memory = getInstance()?.exports?.memory;
    return memory instanceof WebAssembly.Memory ? new Uint8Array(memory.buffer) : null;
  }
  function writeU32(ptr, value) { memoryView()?.setUint32(ptr >>> 0, value >>> 0, true); }
  function writeU64(ptr, value) { memoryView()?.setBigUint64(ptr >>> 0, BigInt(value), true); }

  function wasiFunction(name) {
    switch (name) {
      case 'args_sizes_get': return (argc, size) => { writeU32(argc, 0); writeU32(size, 0); return 0; };
      case 'args_get': return () => 0;
      case 'environ_sizes_get': return (count, size) => { writeU32(count, environmentBytes.length); writeU32(size, environmentBytes.reduce((total, entry) => total + entry.length + 1, 0)); return 0; };
      case 'environ_get': return (environ, buffer) => {
        const raw = bytes(); if (!raw) return 21;
        let cursor = buffer >>> 0;
        environmentBytes.forEach((entry, index) => { writeU32((environ >>> 0) + index * 4, cursor); raw.set(entry, cursor); raw[cursor + entry.length] = 0; cursor += entry.length + 1; });
        return 0;
      };
      case 'random_get': return (ptr, len) => { const out=bytes()?.subarray(ptr>>>0,(ptr>>>0)+(len>>>0)); if(!out) return 21; crypto.getRandomValues(out); return 0; };
      case 'clock_time_get': return (clock, _precision, out) => {
        // Monotonic clocks (id 1) read the high-resolution timer so Swift can
        // time phases below one millisecond; the realtime clock stays wall time.
        // `monotonicOffsetMs` keeps the clock continuous when the app moves from a worker to the main thread: the two
        // threads count from different time origins, and Swift holds timestamps taken on the first.
        const nanoseconds = (clock >>> 0) === 1 ? BigInt(Math.round((performance.now() + (options.monotonicOffsetMs || 0)) * 1e6)) : BigInt(Date.now()) * 1000000n;
        writeU64(out, nanoseconds); return 0;
      };
      case 'fd_write': return (fd, iovs, count, written) => { const mem=memoryView(), raw=bytes(); if(!mem||!raw) return 21; let text='', total=0; for(let i=0;i<(count>>>0);i++){ const p=mem.getUint32((iovs>>>0)+i*8,true), n=mem.getUint32((iovs>>>0)+i*8+4,true); total+=n; text+=new TextDecoder().decode(raw.subarray(p,p+n)); } writeU32(written,total); if(text) (fd===2?console.error:console.log)(safeErrorMessage(text.replace(/\n$/,''))); return 0; };
      case 'fd_fdstat_get': return (_fd, ptr) => { const raw=bytes(); if(!raw) return 21; raw.fill(0,ptr>>>0,(ptr>>>0)+24); return 0; };
      case 'fd_close': case 'fd_sync': case 'sched_yield': return () => 0;
      case 'proc_exit': return code => { throw new Error(`WASI proc_exit(${code})`); };
      default: return () => 52; // __WASI_ERRNO_NOSYS
    }
  }


  return wasiFunction;
}
