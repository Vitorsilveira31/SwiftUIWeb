// Page services through the BrowserIO host (operations `service` and `serviceEvents`, Tools/BrowserIO/service-host.mjs):
// the wire format Swift's `BrowserService` uses, lazy factories, results, failures and event subscriptions.
// Run with: bun Tools/BrowserIO/test-services.mjs
import assert from 'node:assert/strict';
import { createBrowserIO, Writer, Reader, safeErrorStack } from './browser-io.mjs';
import { createServiceHost, createServiceForwarder, createServiceResponder } from './service-host.mjs';
import { BrowserIOOperation, BrowserIOEvent } from './protocol.generated.mjs';

const memory = new WebAssembly.Memory({ initial: 1 });
let top = 16, next = 1;
const pending = new Map();
const alloc = n => { const p = top; top += n + 16; if (top > memory.buffer.byteLength) memory.grow(Math.ceil((top - memory.buffer.byteLength) / 65536)); return p; };
const instance = { exports: { memory, browser_io_alloc: alloc, browser_io_deliver(id, status, p, n) { pending.get(id)?.(status, new Uint8Array(memory.buffer, p, n).slice()); } } };

function hostFor(environment, options = {}) {
  return createBrowserIO({ getInstance: () => instance, environment, baseURL: 'https://example.test', ...options });
}
function start(host, op, packet, receive) {
  const id = next++;
  const p = alloc(packet.length);
  new Uint8Array(memory.buffer, p, packet.length).set(packet);
  pending.set(id, receive);
  assert.equal(host.imports.request(id, op, p, packet.length), 0);
  return id;
}
/** Calls `method` of service `name` and resolves with { status, text }. */
function call(host, name, method, payload = '') {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`no answer from ${name}.${method}`)), 3000);
    start(host, BrowserIOOperation.service, new Writer().text(name).text(method).text(payload).bytes(), (status, bytes) => {
      clearTimeout(timer);
      const text = status < 0 ? new TextDecoder().decode(bytes) : new Reader(bytes).text();
      resolve({ status, text });
    });
  });
}
const settle = () => new Promise(resolve => setTimeout(resolve, 20));
let tests = 0;

{ // A definition queued before the framework starts is adopted; its factory runs on the first call, once.
  let started = 0;
  const environment = { SwiftUIWebServices: { queue: [], define(name, factory) { this.queue.push([name, factory]); } } };
  environment.SwiftUIWebServices.define('analytics', () => {
    started += 1;
    return { track: payload => `tracked ${JSON.parse(payload).event}`, info: () => ({ ready: true }), nothing() {} };
  });
  const host = hostFor(environment);
  assert.equal(started, 0, 'a service starts on its first call, not when it is defined');
  assert.deepEqual(await call(host, 'analytics', 'track', JSON.stringify({ event: 'app_opened' })), { status: 0, text: 'tracked app_opened' });
  assert.deepEqual(await call(host, 'analytics', 'info'), { status: 0, text: '{"ready":true}' });
  assert.deepEqual(await call(host, 'analytics', 'nothing'), { status: 0, text: '' });
  assert.equal(started, 1);
  tests++;
}

{ // Async methods, missing methods and methods that throw. Messages go through the host's redaction.
  const environment = {};
  const host = hostFor(environment);
  environment.SwiftUIWebServices.define('purchases', async () => ({
    async offerings() { await settle(); return '[]'; },
    async buy() { throw new Error('payment refused by https://pay.example/checkout?token=abc123'); },
  }));
  assert.deepEqual(await call(host, 'purchases', 'offerings'), { status: 0, text: '[]' });
  const missing = await call(host, 'purchases', 'refund');
  assert.equal(missing.status, -8);
  assert.match(missing.text, /has no method "refund"/);
  const failed = await call(host, 'purchases', 'buy');
  assert.equal(failed.status, -6);
  assert.doesNotMatch(failed.text, /abc123/, 'a failure message is redacted like every host error');
  tests++;
}

{ // A service defined after the call waits for it; one never defined fails; a factory that throws is retried.
  const environment = {};
  const host = hostFor(environment, { services: createServiceHost(environment, { undefinedWaitMs: 100 }) });
  const late = call(host, 'messaging', 'token');
  await settle();
  environment.SwiftUIWebServices.define('messaging', () => ({ token: () => 'fcm-token' }));
  assert.deepEqual(await late, { status: 0, text: 'fcm-token' });
  const absent = await call(host, 'nobody', 'anything');
  assert.equal(absent.status, -8);
  assert.match(absent.text, /is not defined/);
  let attempts = 0;
  environment.SwiftUIWebServices.define('flaky', () => { attempts += 1; if (attempts === 1) throw new Error('SDK download failed'); return { ping: () => 'pong' }; });
  const first = await call(host, 'flaky', 'ping');
  assert.equal(first.status, -6);
  assert.match(first.text, /failed to start/);
  assert.deepEqual(await call(host, 'flaky', 'ping'), { status: 0, text: 'pong' });
  assert.equal(attempts, 2);
  assert.throws(() => environment.SwiftUIWebServices.define('flaky', () => ({})), /already defined/);
  tests++;
}

{ // Events reach the observer that asked for them, starting the service; cancelling the observation unsubscribes.
  const environment = {};
  const host = hostFor(environment);
  let emit = null;
  environment.SwiftUIWebServices.define('push', context => { emit = context.emit; return {}; });
  const received = [];
  const id = start(host, BrowserIOOperation.serviceEvents, new Writer().text('push').text('message').bytes(), (status, bytes) => {
    received.push({ status, text: status === BrowserIOEvent.serviceEvent ? new Reader(bytes).text() : '' });
  });
  await settle();
  assert.ok(emit, 'observing starts the service');
  emit('message', { title: 'Novo capítulo' });
  emit('other', 'ignored');
  emit('message', 'second');
  assert.deepEqual(received, [
    { status: BrowserIOEvent.serviceEvent, text: '{"title":"Novo capítulo"}' },
    { status: BrowserIOEvent.serviceEvent, text: 'second' },
  ]);
  host.imports.cancel(id);
  await settle();
  const afterCancel = received.length;
  emit('message', 'after cancel');
  assert.equal(received.filter(event => event.text === 'after cancel').length, 0, 'a cancelled observation receives nothing');
  assert.ok(received.length >= afterCancel);
  tests++;
}

{ // A worker runtime without a services bridge says so instead of failing silently.
  const host = hostFor({}, { remoteDOM: true });
  const answer = await call(host, 'analytics', 'track');
  assert.equal(answer.status, -7);
  tests++;
}

{ // A worker runtime reaches the page's services through messages (embedded-host-core.js ↔ embedded-worker-client.js).
  const page = {};
  let toPage = null, toRuntime = null;
  const deliver = (target, message) => setTimeout(() => target(structuredClone(message)), 0); // like postMessage
  const forwarder = createServiceForwarder(message => deliver(toPage, message));
  const responder = createServiceResponder(page, message => deliver(toRuntime, message));
  toPage = message => assert.equal(responder.receive(message), true);
  toRuntime = message => assert.equal(forwarder.receive(message), true);
  const host = hostFor({}, { remoteDOM: true, services: forwarder.services });
  let emit = null;
  page.SwiftUIWebServices.define('monitoring', context => {
    emit = context.emit;
    return { capture: payload => `captured ${payload}`, fail() { throw new Error('transport closed'); } };
  });
  assert.deepEqual(await call(host, 'monitoring', 'capture', 'boom'), { status: 0, text: 'captured boom' });
  const failure = await call(host, 'monitoring', 'fail');
  assert.equal(failure.status, -6);
  assert.match(failure.text, /transport closed/);

  const received = [];
  const id = start(host, BrowserIOOperation.serviceEvents, new Writer().text('monitoring').text('state').bytes(), (status, bytes) => {
    if (status === BrowserIOEvent.serviceEvent) received.push(new Reader(bytes).text());
  });
  await settle();
  emit('state', 'online');
  await settle();
  assert.deepEqual(received, ['online']);
  host.imports.cancel(id);
  await settle();
  emit('state', 'after cancel');
  await settle();
  assert.deepEqual(received, ['online'], 'cancelling in the worker unsubscribes on the page');

  // A move to the main thread ends the old runtime's subscriptions on the page; the new runtime subscribes again.
  const moved = [];
  start(host, BrowserIOOperation.serviceEvents, new Writer().text('monitoring').text('state').bytes(), (status, bytes) => {
    if (status === BrowserIOEvent.serviceEvent) moved.push(new Reader(bytes).text());
  });
  await settle();
  responder.end();
  emit('state', 'after the move');
  await settle();
  assert.deepEqual(moved, [], 'a runtime that went away receives nothing');
  tests++;
}

{ // After a move, a reply for the old runtime never reaches the new one, whose request numbers start again at 1.
  const page = {};
  const later = [];
  page.SwiftUIWebServices = { queue: [], define(name, factory) { this.queue.push([name, factory]); } };
  page.SwiftUIWebServices.define('slow', () => ({ wait: () => new Promise(resolve => later.push(resolve)) }));
  let runtime = null;
  const responder = createServiceResponder(page, message => setTimeout(() => runtime.receive(structuredClone(message)), 0));
  const toPage = message => setTimeout(() => responder.receive(structuredClone(message)), 0);
  const old = createServiceForwarder(toPage);
  runtime = old;
  const oldAnswer = old.services.call('slow', 'wait', '');
  await settle();
  responder.end();                     // the worker moved: the page now answers the core on the main thread
  const moved = createServiceForwarder(toPage);
  runtime = moved;
  const newAnswer = moved.services.call('slow', 'wait', '');
  await settle();
  assert.equal(later.length, 2);
  later[0]('for the old runtime');
  await settle();
  later[1]('for the new runtime');
  assert.equal(await newAnswer, 'for the new runtime');
  let oldSettled = false;
  oldAnswer.then(() => { oldSettled = true; }, () => { oldSettled = true; });
  await settle();
  assert.equal(oldSettled, false, 'the old runtime is gone: nothing answers it');
  tests++;
}

{ // What a service logs to the page console goes through the host's redaction.
  const logged = [];
  const environment = { console: { error: (...parts) => logged.push(parts.join(' ')) } };
  const host = createServiceHost(environment);
  environment.SwiftUIWebServices.define('leaky', () => { throw new Error('failed https://api.example/?token=PRIVATE_SECRET'); });
  const unsubscribe = host.observe('leaky', 'anything', () => {});
  await settle();
  unsubscribe();
  assert.equal(logged.length, 1);
  assert.doesNotMatch(logged[0], /PRIVATE_SECRET/);
  tests++;
}

{ // An SDK error's own `code` (an HTTP status, say) never becomes a BrowserIO status: the call fails with -6.
  const page = {};
  const host = hostFor(page);
  page.SwiftUIWebServices.define('http', () => ({
    limited() { throw Object.assign(new Error('Too Many Requests'), { code: 429 }); },
    aborted() { throw new DOMException('The user aborted a request.', 'AbortError'); },
  }));
  assert.equal((await call(host, 'http', 'limited')).status, -6, 'on the main thread');
  assert.equal((await call(host, 'http', 'aborted')).status, -6, 'an SDK AbortError is the method failing, not a BrowserIO cancel');
  let runtime = null;
  const responder = createServiceResponder(page, message => setTimeout(() => runtime.receive(structuredClone(message)), 0));
  runtime = createServiceForwarder(message => setTimeout(() => responder.receive(structuredClone(message)), 0));
  const worker = hostFor({}, { remoteDOM: true, services: runtime.services });
  assert.equal((await call(worker, 'http', 'limited')).status, -6, 'through a worker');
  tests++;
}

{ // A reply still in transit when the app moves threads (handed back by the worker) never resolves the new runtime's call.
  const page = {};
  page.SwiftUIWebServices = { queue: [], define(name, factory) { this.queue.push([name, factory]); } };
  page.SwiftUIWebServices.define('echo', () => ({ say: payload => payload }));
  const inTransit = [];
  const responder = createServiceResponder(page, message => inTransit.push(message));
  const old = createServiceForwarder(message => setTimeout(() => responder.receive(structuredClone(message)), 0));
  old.services.call('echo', 'say', 'for the old runtime');
  await settle();
  assert.equal(inTransit.length, 1, 'the old runtime\'s reply left the page before the move');
  const moved = createServiceForwarder(() => {});
  const pending = moved.services.call('echo', 'say', 'for the new runtime');   // request 1 again
  let settled = false;
  pending.then(() => { settled = true; }, () => { settled = true; });
  assert.equal(moved.receive(inTransit[0]), true);   // forwarded to the new core by the move
  await settle();
  assert.equal(settled, false, 'the old reply did not answer the new request');
  tests++;
}

{ // A service call the worker already made is refused, not made again, when the main thread replays it after a move.
  const page = {};
  let calls = 0;
  page.SwiftUIWebServices = { queue: [], define(name, factory) { this.queue.push([name, factory]); } };
  page.SwiftUIWebServices.define('ledger', () => ({ record() { calls += 1; return 'ok'; } }));
  const worker = hostFor(page, { remoteDOM: true, services: createServiceHost(page) });
  const id = next;
  assert.equal((await call(worker, 'ledger', 'record', '{"entry":1}')).status, 0);
  const sent = worker.sentSinceSnapshot();
  assert.deepEqual(sent.map(entry => entry.operation), [BrowserIOOperation.service]);
  const mainThread = hostFor(page);
  mainThread.refuseReplayed(sent);
  next = id;                                          // the replay asks again with the same request id
  const replayed = await call(mainThread, 'ledger', 'record', '{"entry":1}');
  assert.equal(replayed.status, -6);
  assert.match(replayed.text, /already sent/);
  assert.equal(calls, 1, 'the page made the call once');
  tests++;
}

{ // On the main thread nothing moves threads, so finished calls are not kept for a replay that cannot happen.
  const page = {};
  page.SwiftUIWebServices = { queue: [], define(name, factory) { this.queue.push([name, factory]); } };
  page.SwiftUIWebServices.define('analytics', () => ({ capture: () => '' }));
  const mainThread = hostFor(page);
  for (let i = 0; i < 50; i++) assert.equal((await call(mainThread, 'analytics', 'capture', `{"n":${i}}`)).status, 0);
  assert.equal(mainThread.sentSinceSnapshot().length, 0);
  tests++;
}

{ // Diagnostics lose whole credentials: every cookie of a header, any Authorization scheme, quoted and assigned secrets.
  const cases = [
    ['Error: failed\nCookie: theme=light; session=SECRET\n    at f (x.js:1:1)', /SECRET/, /at f \(x\.js:1:1\)/],
    ['Authorization: Basic dXNlcjpwYXNz', /dXNlcjpwYXNz/, /Authorization/],
    ['Authorization: Bearer live-credential', /live-credential/, /Authorization/],
    ['Request failed: {"password":"hunter2","user":"ana"}', /hunter2/, /"user":"ana"/],
    ['refused: token=abc123', /abc123/, /refused/],
    ['token: PRIVATE_SECRET', /PRIVATE_SECRET/, /token/],
    ['password: PRIVATE_SECRET', /PRIVATE_SECRET/, /password/],
    ['key=PRIVATE_SECRET', /PRIVATE_SECRET/, /key/],
  ];
  for (const [text, secret, kept] of cases) {
    const safe = safeErrorStack(text);
    assert.doesNotMatch(safe, secret, text);
    assert.match(safe, kept, text);
  }
  assert.equal(safeErrorStack('at Object.token (file.js:10:5)'), 'at Object.token (file.js:10:5)', 'frames stay readable');
  tests++;
}

{ // The runtime-error event's stack: redacted like a message, capped, empty without one.
  const stack = 'RuntimeError: unreachable\n    at app.wasm.$s7Example4bodyyF (https://cdn.example/app.wasm?sig=abc123:wasm-function[61]:0x40ea9)\n' + 'x'.repeat(5000);
  const safe = safeErrorStack(stack);
  assert.match(safe, /\$s7Example4bodyyF/, 'the Swift frame stays');
  assert.doesNotMatch(safe, /abc123/);
  assert.ok(safe.length <= 4096);
  assert.equal(safeErrorStack(undefined), '');
  tests++;
}

console.log(`BrowserIO services: ${tests} tests passed`);
