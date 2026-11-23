// Headless services for Swift code (`BrowserService` in SwiftUIWebBrowserIO): JavaScript objects that work without a
// view of their own, such as an analytics, error-monitoring or messaging SDK. A page script registers one with
// `SwiftUIWebServices.define(name, factory)`. The factory runs on the first call or subscription that names it, so an
// SDK's code is fetched only once the app uses it, and receives `{ emit(event, payload) }` for the events Swift observes.
// A service is an object of methods: each takes the payload text (JSON by convention) and returns text, nothing or a
// promise of either; any other value is sent as its JSON text.
//
// This host always runs on the page, next to the document the SDKs need: a worker runtime forwards its calls and
// subscriptions here (embedded-host-core.js and embedded-worker-client.js).

import { safeErrorMessage } from './redact.mjs';

export class ServiceError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}

const REGISTRY_NAME = 'SwiftUIWebServices';
const INTERNALS = Symbol.for('SwiftUIWeb.services.internals');
// How long a call waits for a name nobody has defined yet (a page script may define it after the app starts).
const UNDEFINED_WAIT_MS = 10_000;

const isThenable = value => value !== null && (typeof value === 'object' || typeof value === 'function') && typeof value.then === 'function';
const describe = error => String(error?.message || error);
// What reaches the page console: the BrowserIO redaction (an SDK error can carry an authenticated URL).
const logError = (environment, error) => environment.console?.error?.(`[SwiftUIWeb] ${safeErrorMessage(error)}`);
// Only the framework's own failure codes (negative) cross the bridge: an SDK error's `code` (an HTTP 429, say) would read
// as a BrowserIO event status (100 and up) and leave the call pending, so every other failure is -6.
const failureCode = code => Number.isInteger(code) && code < 0 ? code : -6;
const asText = value => value === undefined || value === null ? '' : typeof value === 'string' ? value : JSON.stringify(value);

/**
 * The page-level registry, shared by every host on `environment` (installing twice returns the same one).
 * An application script that runs before the framework starts may pre-create the global as
 * `{ queue: [], define(name, factory) { this.queue.push([name, factory]); } }`; its definitions are
 * adopted here and the same object becomes the live registry.
 */
export function installServiceRegistry(environment) {
  const existing = environment[REGISTRY_NAME];
  if (existing && existing[INTERNALS]) return existing;

  // name -> { factory, status: 'idle' | 'loading' | 'ready', service, promise }
  const definitions = new Map();
  // name -> event -> Set of receivers
  const listeners = new Map();
  // name -> Set of callbacks waiting for the name to be defined
  const waiters = new Map();

  const emitter = name => ({
    emit(event, payload) {
      const receivers = listeners.get(name)?.get(String(event));
      if (!receivers) return;
      const text = asText(payload);
      for (const receive of [...receivers]) {
        try { receive(text); } catch (error) { logError(environment, error); }
      }
    },
  });

  const define = (name, factory) => {
    if (typeof name !== 'string' || name === '') throw new TypeError(`${REGISTRY_NAME}.define needs a service name`);
    if (typeof factory !== 'function') throw new TypeError(`${REGISTRY_NAME}.define("${name}") needs a factory function`);
    if (definitions.has(name)) throw new Error(`Service "${name}" is already defined`);
    definitions.set(name, { factory, status: 'idle', service: undefined, promise: null });
    for (const wake of [...(waiters.get(name) ?? [])]) wake();
  };

  const loadFailure = (name, error) => error instanceof ServiceError ? error : new ServiceError(-6, `Service "${name}" failed to start: ${describe(error)}`);

  // The factory runs once per page; a factory that fails is forgotten, so the next call starts it again.
  const start = (name, definition) => {
    if (definition.status === 'ready') return Promise.resolve(definition.service);
    if (definition.status === 'loading') return definition.promise;
    definition.status = 'loading';
    definition.promise = (async () => {
      try {
        const produced = definition.factory(emitter(name));
        const service = isThenable(produced) ? await produced : produced;
        if (!service || typeof service !== 'object') throw new ServiceError(-1, `Service "${name}" must be an object of methods`);
        definition.service = service;
        definition.status = 'ready';
        return service;
      } catch (error) {
        definition.status = 'idle';
        definition.promise = null;
        throw loadFailure(name, error);
      }
    })();
    return definition.promise;
  };

  const resolve = (name, waitMs = UNDEFINED_WAIT_MS) => {
    const definition = definitions.get(name);
    if (definition) return start(name, definition);
    return new Promise((done, fail) => {
      let set = waiters.get(name);
      if (!set) { set = new Set(); waiters.set(name, set); }
      const stop = () => { set.delete(wake); if (set.size === 0) waiters.delete(name); clearTimeout(timer); };
      const wake = () => { stop(); start(name, definitions.get(name)).then(done, fail); };
      const timer = setTimeout(() => {
        stop();
        fail(new ServiceError(-8, `Service "${name}" is not defined: call ${REGISTRY_NAME}.define("${name}", factory)`));
      }, waitMs);
      set.add(wake);
    });
  };

  const subscribe = (name, event, receive) => {
    let events = listeners.get(name);
    if (!events) { events = new Map(); listeners.set(name, events); }
    let receivers = events.get(event);
    if (!receivers) { receivers = new Set(); events.set(event, receivers); }
    receivers.add(receive);
    return () => {
      receivers.delete(receive);
      if (receivers.size === 0) events.delete(event);
      if (events.size === 0) listeners.delete(name);
    };
  };

  const registry = existing && typeof existing === 'object' ? existing : {};
  const queued = Array.isArray(registry.queue) ? registry.queue.splice(0) : [];
  registry.define = define;
  Object.defineProperty(registry, INTERNALS, { value: { resolve, subscribe }, enumerable: false });
  environment[REGISTRY_NAME] = registry;
  // A bad queued entry (a duplicate name, a non-function) is reported and skipped, not allowed to stop the framework.
  for (const [name, factory] of queued) {
    try { define(name, factory); } catch (error) { logError(environment, error); }
  }
  return registry;
}

/** Calls into and subscribes to the page's services. `call` resolves with the method's result as text. */
export function createServiceHost(environment, { undefinedWaitMs = UNDEFINED_WAIT_MS } = {}) {
  const { resolve, subscribe } = installServiceRegistry(environment)[INTERNALS];
  return {
    async call(name, method, payload) {
      const service = await resolve(name, undefinedWaitMs);
      const handler = service[method];
      if (typeof handler !== 'function') throw new ServiceError(-8, `Service "${name}" has no method "${method}"`);
      return asText(await handler.call(service, payload));
    },
    /** Delivers the service's `event` payloads to `receive` until the returned function is called. Subscribing also
     * starts the service, so an SDK that only produces events (a push listener) begins listening. */
    observe(name, event, receive) {
      const unsubscribe = subscribe(name, event, receive);
      resolve(name, undefinedWaitMs).catch(error => logError(environment, error));
      return unsubscribe;
    },
  };
}

/**
 * The runtime side of services for a runtime that is not on the page (a worker, or the core that took over after the
 * app moved to the main thread): calls and subscriptions go out through `post` as `service`, `service-observe` and
 * `service-unobserve` messages, and `receive` takes the page's `service-reply` and `service-event` answers (returning
 * true for those). A call still waiting when the runtime goes away is never answered: BrowserIO reports it cancelled.
 */
export function createServiceForwarder(post) {
  let next = 1;
  // Replies name the runtime that asked, so one still in transit when the app moves threads can never resolve the new
  // runtime's request of the same number (each runtime numbers its requests from 1).
  const runtime = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
  const replies = new Map();
  const receivers = new Map();
  const services = {
    call(name, method, payload) {
      const request = next++;
      return new Promise((resolve, reject) => {
        replies.set(request, { resolve, reject });
        post({ t: 'service', runtime, request, name, method, payload });
      });
    },
    observe(name, event, receive) {
      const subscription = next++;
      receivers.set(subscription, receive);
      post({ t: 'service-observe', runtime, subscription, name, event });
      return () => { if (receivers.delete(subscription)) post({ t: 'service-unobserve', runtime, subscription }); };
    },
  };
  function receive(data) {
    if ((data.t === 'service-reply' || data.t === 'service-event') && data.runtime !== runtime) return true;
    if (data.t === 'service-reply') {
      const pending = replies.get(data.request);
      if (!pending) return true;
      replies.delete(data.request);
      if (data.ok) pending.resolve(String(data.text ?? ''));
      else pending.reject(new ServiceError(failureCode(data.code), String(data.message ?? 'Page service failed')));
      return true;
    }
    if (data.t === 'service-event') { receivers.get(data.subscription)?.(String(data.text ?? '')); return true; }
    return false;
  }
  return { services, receive };
}

/**
 * The page side of `createServiceForwarder`: `receive` answers a runtime's `service*` messages with the page's
 * services through `send` (returning true for those messages), and `end` drops every subscription, for a runtime that
 * went away (moved to the main thread or disposed); its successor subscribes again.
 */
export function createServiceResponder(environment, send, options) {
  const host = environment ? createServiceHost(environment, options) : null;
  const subscriptions = new Map();
  let ended = false;
  // Each runtime numbers its requests from 1, so a reply is sent only to the runtime that asked: `end` starts a new
  // generation and the answers of calls still running for the old one are dropped.
  let generation = 0;
  function receive(data) {
    if (data.t === 'service') {
      const { request, runtime } = data;
      if (!host) { send({ t: 'service-reply', runtime, request, ok: false, code: -7, message: 'Page services are unavailable' }); return true; }
      const asked = generation;
      host.call(data.name, data.method, data.payload).then(
        text => { if (asked === generation) send({ t: 'service-reply', runtime, request, ok: true, text }); },
        error => { if (asked === generation) send({ t: 'service-reply', runtime, request, ok: false, code: error instanceof ServiceError ? failureCode(error.code) : -6, message: describe(error) }); });
      return true;
    }
    if (data.t === 'service-observe') {
      if (!host || ended) return true;
      const { subscription, runtime } = data;
      subscriptions.get(subscription)?.();
      subscriptions.set(subscription, host.observe(data.name, data.event, text => send({ t: 'service-event', runtime, subscription, text })));
      return true;
    }
    if (data.t === 'service-unobserve') {
      subscriptions.get(data.subscription)?.();
      subscriptions.delete(data.subscription);
      return true;
    }
    return false;
  }
  function end({ final = false } = {}) {
    generation += 1;
    for (const unsubscribe of subscriptions.values()) unsubscribe();
    subscriptions.clear();
    if (final) ended = true;
  }
  return { receive, end };
}
