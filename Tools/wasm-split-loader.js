// The second half of a split release module (Tools/wasm-split-release.mjs, opt-in with SWIFTUIWEB_WASM_SPLIT=1).
//
// A split build ships `app.wasm` with the functions the first screen ran and `app-rest.wasm` with the rest. Binaryen's
// wasm-split leaves, in the first module, an import for every function it moved, from the namespace `p.deferred` (the
// prefix the build passes, kept short because it is repeated for each of them, and the second module's name), named by
// the function's slot in a table: the first module calls a moved function through that slot, which holds the placeholder
// until the second module is instantiated and its element segment writes the real function there. With reference types
// (the release modules) that table is one wasm-split adds for the moved functions alone, next to the indirect function
// table; without them it is the indirect function table itself. Both are exported for the second module. The
// second module imports the first one's memory, table, globals and the functions it calls (namespace `primary`).
//
// This file only loads: it gives the placeholders, and instantiates the second module once the first one is running.
//   - `prefetch()` starts the download in the background (the worker calls it once the first screen is published);
//   - `load()` waits for it (the main thread, which cannot block, loads both modules before the application starts);
//   - a placeholder that is called before the second module arrived loads it synchronously (`loadSync`, a synchronous
//     request and compile, which a Worker may do), then calls the real function: the call waits, it does not fail.
// A module that is not split has no placeholder import, and none of this runs.
//
// The thread's performance timeline gets the mark `swiftuiweb-app-rest` when the second module is instantiated; its
// detail says whether a call waited for it (`waited`), which the build's check and the benchmarks read.

/** The start of the import namespace of the placeholders wasm-split leaves in the first module. */
export const PLACEHOLDER_NAMESPACE = 'p';
const isPlaceholder = item => item.kind === 'function' && (item.module === PLACEHOLDER_NAMESPACE || item.module.startsWith(PLACEHOLDER_NAMESPACE + '.'));
/** The namespace the second module imports the first module's memory, table, globals and functions from. */
export const PRIMARY_NAMESPACE = 'primary';

/** Whether `module` is the first half of a split build. */
export function isSplitModule(module) {
  return WebAssembly.Module.imports(module).some(isPlaceholder);
}

/**
 * The loader of the second module for one instance of the first. `url` is the second module's address; `canBlock` says
 * whether this thread may load it synchronously (a Worker), `response` is a request for it already on its way (a promise
 * of a Response), and `onLoaded` runs once it is instantiated.
 */
export function createSplitLoader(module, { url, canBlock = false, response: early = null, onLoaded = null } = {}) {
  let primary = null, table = null, secondary = null, compiled = null, pending = null;
  // The placeholders, by namespace: what the first module's imports are completed with.
  const placeholders = Object.create(null);
  let slots = 0, firstSlot = -1, firstPlaceholder = null;
  for (const item of WebAssembly.Module.imports(module)) {
    if (!isPlaceholder(item)) continue;
    const slot = Number(item.name);
    const namespace = placeholders[item.module] ||= Object.create(null);
    const placeholder = namespace[item.name] = (...args) => {
      if (!secondary) loadSync();
      const target = table.get(slot);
      if (target === null || target === placeholder) throw new Error(`the second module did not fill table slot ${slot}`);
      return target(...args);
    };
    slots = Math.max(slots, slot + 1);
    if (firstPlaceholder === null) { firstSlot = slot; firstPlaceholder = placeholder; }
  }

  /** The table that holds the placeholders: the one whose slot holds a placeholder, or (an engine that hands a table's
   * host function back wrapped) the one exactly as long as the placeholders' slots. */
  function placeholderTable(exportsOfPrimary) {
    const tables = Object.values(exportsOfPrimary).filter(value => value instanceof WebAssembly.Table);
    if (tables.length <= 1) return tables[0] ?? null;
    return tables.find(candidate => candidate.length > firstSlot && candidate.get(firstSlot) === firstPlaceholder)
      ?? tables.find(candidate => candidate.length === slots) ?? null;
  }

  function instantiateNow(secondaryModule, waited = false) {
    if (secondary) return secondary;
    if (!primary) throw new Error('the split module is not instantiated yet');
    secondary = new WebAssembly.Instance(secondaryModule, { [PRIMARY_NAMESPACE]: primary });
    compiled = null;
    try { performance.mark('swiftuiweb-app-rest', { detail: { waited } }); } catch { /* no timeline */ }
    onLoaded?.();
    return secondary;
  }

  function loadSync() {
    if (compiled) return instantiateNow(compiled, true);
    if (!canBlock) throw new Error('a function of app-rest.wasm was called before it was loaded, on a thread that cannot wait for it');
    const request = new XMLHttpRequest();
    request.open('GET', url, false);
    request.responseType = 'arraybuffer';
    request.send();
    if (request.status !== 200) throw new Error(`Unable to fetch ${url}: ${request.status}`);
    return instantiateNow(new WebAssembly.Module(request.response), true);
  }

  async function compile() {
    const started = early;
    early = null;
    const response = started ? await started.catch(() => fetch(url)) : await fetch(url);
    if (!response.ok) throw new Error(`Unable to fetch ${url}: ${response.status}`);
    return WebAssembly.compileStreaming(response.clone()).catch(async () => WebAssembly.compile(await response.arrayBuffer()));
  }

  /** Starts the download and compile of the second module; it is instantiated as soon as it is compiled. */
  function load() {
    if (secondary) return Promise.resolve(secondary);
    pending ||= compile().then(secondaryModule => {
      // A placeholder may have loaded it synchronously in the meantime.
      if (secondary) return secondary;
      compiled = secondaryModule;
      return primary ? instantiateNow(secondaryModule) : null;
    }, error => { pending = null; throw error; });
    return pending;
  }

  return {
    /** The imports of the first module that stand in for the moved functions, by namespace (merge them into the imports). */
    imports: placeholders,
    /** Called with the first module's instance, before any of its code runs. */
    attach(instance) {
      primary = instance.exports;
      table = placeholderTable(primary);
      if (!table) throw new Error('the split module exports no table that holds its placeholders');
      if (compiled) instantiateNow(compiled);
    },
    load,
    /** A background download that reports its failure instead of rejecting: a placeholder still loads synchronously. */
    prefetch() {
      load().catch(error => console.warn('[SwiftUIWeb] app-rest.wasm did not load in the background:', error?.message ?? error));
    },
    get loaded() { return secondary !== null; }
  };
}
