// DOMView lifecycle host. A DOM component is a name the application registered in the page
// (`SwiftUIWebDOMComponents.define(name, factory)`, from a script served by the page's own origin) plus a
// state string that Swift sends. This module mounts, updates and disposes those components against the
// element's open ShadowRoot, in whichever thread owns the document: the page itself (direct BrowserIO host)
// or the main-thread applier of the worker's DOM bridge (remote-dom-host.js). Both use this module, so the
// lifecycle has one implementation and one set of error codes.
//
// Nothing here compiles or evaluates text: the state is data the component parses itself, and the code is
// whatever the application's own scripts defined. The page therefore needs no 'unsafe-eval'.
//
// The Swift side of the lifecycle is synchronous, the component's definition may not be:
//  - a component that is not defined yet (or whose factory is still loading) leaves the mount pending: the
//    host remembers the LATEST state, mounts when the definition arrives, and an unmount before that cancels
//    the mount;
//  - a failure that can only be seen later (a factory that rejects, a mount that throws after the definition
//    arrived, a name nobody defines) cannot be returned to Swift, so it goes to `report`, like every other
//    failed DOM operation.

/** A lifecycle failure with the BrowserIO status code the Swift side receives. */
export class DOMViewError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

const REGISTRY_NAME = 'SwiftUIWebDOMComponents';
const INTERNALS = Symbol.for('SwiftUIWeb.domComponents.internals');
const ERROR_ATTRIBUTE = 'data-dom-view-error';
// How long a mount waits for a name nobody has defined before it says so. The mount itself keeps waiting.
const UNDEFINED_REPORT_MS = 10_000;

const isThenable = value => value !== null && (typeof value === 'object' || typeof value === 'function') && typeof value.then === 'function';
const describe = error => String(error?.message || error);

function checkComponent(name, component) {
  if (component && typeof component.mount === 'function' && typeof component.update === 'function') return component;
  throw new DOMViewError(-1, `DOM component "${name}" must provide mount(host, root, emit, state) and update(instance, state)`);
}

/**
 * The page-level registry, shared by every host on `environment` (installing twice returns the same one).
 * An application script that runs before the framework starts may pre-create the global as
 * `{ queue: [], define(name, factory) { this.queue.push([name, factory]); } }`; its definitions are
 * adopted here and the same object becomes the live registry.
 */
export function installDOMComponentRegistry(environment) {
  const existing = environment[REGISTRY_NAME];
  if (existing && existing[INTERNALS]) return existing;

  // name -> { factory, status: 'idle' | 'loading' | 'ready', component, promise }
  const definitions = new Map();
  const watchers = new Map();
  const notify = (name, failure) => { for (const watcher of [...(watchers.get(name) ?? [])]) watcher(failure); };

  const define = (name, factory) => {
    if (typeof name !== 'string' || name === '') throw new TypeError(`${REGISTRY_NAME}.define needs a component name`);
    if (typeof factory !== 'function') throw new TypeError(`${REGISTRY_NAME}.define("${name}") needs a factory function`);
    if (definitions.has(name)) throw new Error(`DOM component "${name}" is already defined`);
    definitions.set(name, { factory, status: 'idle', component: undefined });
    notify(name);
  };

  const loadFailure = (name, error) => error instanceof DOMViewError ? error : new DOMViewError(-1, `DOM component "${name}" failed to load: ${describe(error)}`);

  // The factory runs on the first mount of a name, never at definition time, so a component's code is
  // fetched only when something shows it. A failed factory is forgotten: the next mount tries again.
  const lookup = name => {
    const definition = definitions.get(name);
    if (!definition) return { status: 'undefined' };
    if (definition.status === 'ready') return { status: 'ready', component: definition.component };
    if (definition.status === 'loading') return { status: 'loading' };
    try {
      const produced = definition.factory();
      if (isThenable(produced)) {
        definition.status = 'loading';
        Promise.resolve(produced).then(component => {
          definition.component = checkComponent(name, component);
          definition.status = 'ready';
          notify(name);
        }).catch(error => {
          definition.status = 'idle';
          notify(name, loadFailure(name, error));
        });
        return { status: 'loading' };
      }
      definition.component = checkComponent(name, produced);
      definition.status = 'ready';
      return { status: 'ready', component: definition.component };
    } catch (error) { return { status: 'failed', error: loadFailure(name, error) }; }
  };

  const watch = (name, watcher) => {
    let set = watchers.get(name);
    if (!set) { set = new Set(); watchers.set(name, set); }
    set.add(watcher);
    return () => { set.delete(watcher); if (set.size === 0) watchers.delete(name); };
  };

  const registry = existing && typeof existing === 'object' ? existing : {};
  const queued = Array.isArray(registry.queue) ? registry.queue.splice(0) : [];
  registry.define = define;
  Object.defineProperty(registry, INTERNALS, { value: { lookup, watch }, enumerable: false });
  environment[REGISTRY_NAME] = registry;
  // A bad queued entry (a duplicate name, a non-function) is reported and skipped, not allowed to stop the framework.
  for (const [name, factory] of queued) {
    try { define(name, factory); } catch (error) { environment.console?.error?.(`[SwiftUIWeb] ${describe(error)}`); }
  }
  return registry;
}

export function createDOMViewHost(environment, { report, undefinedReportMs = UNDEFINED_REPORT_MS } = {}) {
  const registry = installDOMComponentRegistry(environment);
  const { lookup, watch } = registry[INTERNALS];
  // element -> { name, root, state, component, instance, live, alive, stopWatching, timer, reported }
  const entries = new WeakMap();

  const surface = (element, error) => {
    if (typeof report === 'function') report(element, error);
    else environment.console?.error?.(`[SwiftUIWeb] ${describe(error)}`);
  };

  const emitter = (element, entry) => value => {
    if (!entry.alive) return;
    const event = new environment.CustomEvent('dom-view-event', {
      bubbles: true, composed: true, detail: { name: 'domView', value: String(value ?? '') }
    });
    element.dispatchEvent(event);
  };

  const stopWaiting = entry => {
    entry.stopWatching?.(); entry.stopWatching = undefined;
    if (entry.timer !== undefined) { environment.clearTimeout?.(entry.timer); entry.timer = undefined; }
  };

  // Disposes whatever the entry holds. The root is cleared and the entry forgotten even if dispose throws.
  const teardown = (element, entry) => {
    entry.alive = false;
    stopWaiting(entry);
    try { if (entry.live) entry.component.dispose?.(entry.instance); }
    finally { entry.root.replaceChildren(); if (entries.get(element) === entry) entries.delete(element); }
  };

  // Runs the component's mount against the entry's current state. Throws when the component fails; the
  // root is left empty then.
  const create = (element, entry, component) => {
    try {
      const instance = component.mount(element, entry.root, emitter(element, entry), entry.state);
      if (isThenable(instance)) throw new DOMViewError(-1, `DOM component "${entry.name}" must mount synchronously; load code in its factory`);
      entry.component = component; entry.instance = instance; entry.live = true;
      if (entry.reported) { try { element.removeAttribute?.(ERROR_ATTRIBUTE); } catch { /* detached */ } entry.reported = false; }
    } catch (error) {
      entry.alive = false;
      entry.root.replaceChildren();
      if (entries.get(element) === entry) entries.delete(element);
      throw error;
    }
  };

  // The state of a pending mount's name changed (defined, loaded or failed): continue it if it is still wanted.
  const advance = (element, entry, failed) => {
    if (!entry.alive || entry.live || entries.get(element) !== entry) return;
    const found = failed ? { status: 'failed', error: failed } : lookup(entry.name);
    if (found.status === 'ready') {
      stopWaiting(entry);
      try { create(element, entry, found.component); } catch (error) { surface(element, error); }
    } else if (found.status === 'failed') {
      stopWaiting(entry);
      entry.alive = false; entry.root.replaceChildren(); entries.delete(element);
      surface(element, found.error);
    } else if (found.status === 'loading' && entry.timer !== undefined) {
      // Defined now: the wait for a definition is over, only the load remains.
      environment.clearTimeout?.(entry.timer); entry.timer = undefined;
    }
  };

  const mount = (element, name, state) => {
    if (typeof name !== 'string' || name === '') throw new DOMViewError(-1, 'DOMView needs a component name');
    const old = entries.get(element);
    if (old) teardown(element, old);
    const root = element.shadowRoot || element.attachShadow({ mode: 'open' });
    root.replaceChildren();
    const entry = { name, root, state, component: undefined, instance: undefined, live: false, alive: true, stopWatching: undefined, timer: undefined, reported: false };
    entries.set(element, entry);
    const found = lookup(name);
    if (found.status === 'ready') { create(element, entry, found.component); return; }
    if (found.status === 'failed') { entry.alive = false; entries.delete(element); throw found.error; }
    // Pending: wait for the definition (or the load), keeping only the latest state.
    entry.stopWatching = watch(name, failed => advance(element, entry, failed));
    if (found.status === 'undefined' && typeof environment.setTimeout === 'function' && undefinedReportMs > 0) {
      entry.timer = environment.setTimeout(() => {
        entry.timer = undefined;
        if (!entry.alive || entry.live || lookup(name).status !== 'undefined') return;
        entry.reported = true;
        surface(element, new DOMViewError(-8, `DOM component "${name}" is not defined: call ${REGISTRY_NAME}.define("${name}", factory)`));
      }, undefinedReportMs);
      entry.timer?.unref?.();
    }
  };

  const update = (element, state) => {
    const entry = entries.get(element);
    if (!entry) throw new DOMViewError(-8, 'DOMView instance is not mounted');
    entry.state = state;
    if (!entry.live) return;
    const result = entry.component.update(entry.instance, state);
    if (isThenable(result)) result.then(undefined, error => surface(element, error));
  };

  const unmount = element => {
    const entry = entries.get(element);
    if (entry) teardown(element, entry);
  };

  return {
    /**
     * Runs one lifecycle phase for `element`: `mount` ({ component, state }), `update` ({ state }) or
     * `unmount`. A mount of a component that is not available yet returns at once and completes later.
     */
    lifecycle(phase, element, { component, state } = {}) {
      if (phase === 'mount') mount(element, component, String(state ?? ''));
      else if (phase === 'update') update(element, String(state ?? ''));
      else if (phase === 'unmount') unmount(element);
      else throw new DOMViewError(-1, 'Unknown DOMView lifecycle phase');
    },
  };
}
