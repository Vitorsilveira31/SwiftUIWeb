// Protocol test for the main-thread side of the Swift worker. A fake Worker
// stands in for the real one, so this checks what the DOM host relies on: the
// facade answers synchronous reads from the newest snapshot, posts calls with
// their event bytes, and persists the worker's storage writes.
import assert from "node:assert/strict";

const posted = [];
let worker;
globalThis.Worker = class {
  constructor() { worker = this; }
  postMessage(message) { posted.push(message); }
  terminate() { this.terminated = true; }
};
const store = new Map();
const hostWindow = {
  localStorage: { length: 1, key: () => "swui:keep", getItem: () => "v", setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k), clear: () => store.clear() },
  sessionStorage: { length: 0, key: () => null, getItem: () => null, setItem() {}, removeItem() {}, clear() {} },
  addEventListener() {}, removeEventListener() {}, matchMedia: () => ({ matches: false }), dispatchEvent() {},
  navigator: { language: "pt-BR" },
  document: { querySelectorAll: selector => selector === 'meta[name="runtime-environment"]'
    ? [{ getAttribute: () => "SWIFTUIWEB_IMAGE_ASSETS=Brand=catalog-assets/Brand.svg" }, { getAttribute: () => "no-equals" }, { getAttribute: () => "SWIFTUIWEB_LANGUAGE=pt" }]
    : selector === "[data-web-mount-token]" ? mountedElements : [] }
};
// WebMount elements in the fake document; the DOM bridge tests below mutate this list.
let mountedElements = [];
function fakeElement(attributes) {
  const attrs = new Map(Object.entries(attributes));
  return {
    attributes: [...attrs].map(([name, value]) => ({ name, value })),
    getAttribute: name => (attrs.has(name) ? attrs.get(name) : null),
    setAttribute(name, value) { attrs.set(name, String(value)); },
    removeAttribute(name) { attrs.delete(name); },
    textContent: "", value: undefined, isConnected: true, shadowRoot: null,
    attachShadow() { this.shadowRoot = { children: [], replaceChildren() { this.children = []; } }; return this.shadowRoot; },
    dispatchEvent() { return true; }
  };
}

const { createWorkerInstance } = await import("./embedded-worker-client.js");
const creating = createWorkerInstance({}, { baseURL: "https://app.test/", window: hostWindow });
await new Promise(resolve => setTimeout(resolve, 0));

const init = posted.find(message => message.t === "init");
assert.ok(init, "init is posted");
assert.deepEqual(init.local, [["swui:keep", "v"]], "only swui: storage is mirrored");
assert.deepEqual(init.environment, ["SWIFTUIWEB_IMAGE_ASSETS=Brand=catalog-assets/Brand.svg", "SWIFTUIWEB_LANGUAGE=pt"], "document environment metas reach the worker; a pinned language beats navigator.language");

const html = new TextEncoder().encode("<div>hi</div>");
const publishedSecret = new Uint8Array([104, 105]);
worker.onmessage({ data: { t: "publish", seq: 1, html, lazy: [[10, 50]], secure: { field: publishedSecret }, fiber: [7] } });
const instance = await creating;
const api = instance.exports;

assert.equal(api.embedded_browser_html_length(), html.length);
assert.equal(api.embedded_browser_publish_seq(), 1);
assert.equal(api.embedded_browser_lazy_collection_count(), 1);
assert.equal(api.embedded_browser_lazy_item_count(0), 10);
assert.equal(api.embedded_browser_lazy_estimated_extent(0), 50);
assert.equal(api.embedded_browser_fiber_metric(0), 7);

// A secure value is looked up by the id the host pushes, then zeroed.
for (const byte of new TextEncoder().encode("field")) api.embedded_browser_event_value_push(byte);
assert.equal(api.embedded_browser_secure_value(), 2);
assert.equal(api.embedded_browser_secure_value_byte(1), 105);
api.embedded_browser_secure_value_reset();
assert.equal(api.embedded_browser_secure_value_byte(0), 0);

// The bulk shims: one write instead of a push per byte, and the secure value as bytes.
api.embedded_browser_event_value_write(new TextEncoder().encode("field"));
assert.equal(api.embedded_browser_secure_value(), 2);
assert.deepEqual([...api.embedded_browser_secure_value_bytes()], [104, 105]);
api.embedded_browser_secure_value_reset();
assert.equal(api.embedded_browser_secure_value_bytes().length, 0);
api.embedded_browser_event_value_write(Uint8Array.of(4, 5, 6));
api.embedded_browser_dispatch(10, 2);
assert.deepEqual([...posted.filter(message => message.t === "call").at(-1).v], [4, 5, 6], "a written value rides the next call");
// Mixing the two paths is safe: a push after a write extends it.
api.embedded_browser_event_value_write(Uint8Array.of(1));
api.embedded_browser_event_value_push(2);
api.embedded_browser_dispatch(11, 2);
assert.deepEqual([...posted.filter(message => message.t === "call").at(-1).v], [1, 2]);

// A call carries the bytes pushed before it; a newer snapshot replaces the old.
api.embedded_browser_event_value_reset();
for (const byte of [1, 2, 3]) api.embedded_browser_event_value_push(byte);
api.embedded_browser_dispatch(9, 1);
const dispatch = posted.filter(message => message.t === "call").at(-1);
assert.equal(dispatch.n, "dispatch");
assert.deepEqual(dispatch.a, [9, 1]);
assert.deepEqual([...dispatch.v], [1, 2, 3]);
assert.equal(api.embedded_browser_dispatch_named(3, 4), 0, "no synchronous veto from a worker");

let notified = 0;
instance.subscribe(() => { notified++; });
worker.onmessage({ data: { t: "publish", seq: 2, html: new Uint8Array(4), lazy: [], secure: {}, fiber: null } });
// The previous publication's SecureField bytes are zeroed once it is replaced.
assert.deepEqual([...publishedSecret], [0, 0]);
assert.equal(notified, 1);
assert.equal(api.embedded_browser_html_length(), 4);
assert.equal(api.embedded_browser_lazy_collection_count(), 0);

// Storage writes from the worker reach the real storage.
worker.onmessage({ data: { t: "storage-write", scope: 0, op: "set", key: "swui:a", value: "1" } });
assert.equal(store.get("swui:a"), "1");

// WebMount over the worker: the element is reported before reconciliation, the worker's writes
// come back as a batch, and an unmount still reaches an element that has just left the DOM.
const errors = [];
const originalError = console.error;
console.error = (...args) => errors.push(args.join(" "));
try {
  const element = fakeElement({ "data-web-mount-key": "dom-view", "data-web-mount-token": "view-token", "data-dom-view": "true" });
  mountedElements = [element];
  api.embedded_browser_webmount_reconcile();
  const first = posted.filter(message => message.t === "mounts").at(-1);
  assert.equal(first.table.length, 1, "the mounted element is reported");
  assert.equal(first.table[0].key, "dom-view");
  assert.equal(first.table[0].attributes["data-dom-view"], "true");
  assert.equal(posted.at(-1).n, "webmount_reconcile", "reconciliation is requested after the table");
  // The application registers its component in the page; the worker only names it.
  const lifecycle = [];
  hostWindow.SwiftUIWebDOMComponents.define("probe", () => ({
    mount(host, root, emit, state) { lifecycle.push(`mount:${state}`); host.setAttribute("data-mounted", state); return {}; },
    update(instance, state) { lifecycle.push(`update:${state}`); },
    dispose() { lifecycle.push("dispose"); }
  }));
  // A batch for that snapshot: a write, then the lifecycle, applied in order.
  worker.onmessage({ data: { t: "dom", seq: first.seq, ops: [
    { op: "attr", node: first.table[0].node, name: "data-x", value: "1" },
    { op: "dom-view", node: first.table[0].node, phase: "mount", component: "probe", state: "yes" },
    { op: "dom-view", node: first.table[0].node, phase: "update", state: "again" }
  ] } });
  assert.equal(element.getAttribute("data-x"), "1");
  assert.equal(element.getAttribute("data-mounted"), "yes");
  assert.deepEqual(lifecycle, ["mount:yes", "update:again"]);
  // The element leaves the DOM: the worker reconciles against the empty table and unmounts it.
  mountedElements = [];
  api.embedded_browser_webmount_reconcile();
  const second = posted.filter(message => message.t === "mounts").at(-1);
  assert.equal(second.table.length, 0, "the empty table tells the worker the mount is gone");
  worker.onmessage({ data: { t: "dom", seq: second.seq, ops: [
    { op: "dom-view", node: first.table[0].node, phase: "unmount" }
  ] } });
  assert.deepEqual(lifecycle, ["mount:yes", "update:again", "dispose"], "the removed element is still reachable for its unmount");
  // Once that batch has been applied the handle is retired: a later write to it is reported.
  worker.onmessage({ data: { t: "dom", seq: second.seq, ops: [{ op: "attr", node: first.table[0].node, name: "data-late", value: "1" }] } });
  assert.equal(element.getAttribute("data-late"), null, "a retired handle is not written");
  assert.ok(errors.some(text => text.includes("Unknown mount handle")), "the failed write is reported on the console");
} finally {
  console.error = originalError;
}

instance.dispose();

// Boot failures before the first publication must reject the boot with the reason. A worker that
// never loads, or a message it cannot deserialize, used to leave the page blank with no message.
async function bootFailure(trigger, pattern) {
  const logged = [];
  const originalLog = console.error;
  console.error = (...args) => logged.push(args.join(" "));
  try {
    const booting = createWorkerInstance({}, { baseURL: "https://app.test/", window: hostWindow });
    await new Promise(resolve => setTimeout(resolve, 0));
    trigger(worker);
    await assert.rejects(booting, pattern);
    assert.ok(logged.some(text => pattern.test(text)), "the failure is also logged on the console");
  } finally {
    console.error = originalLog;
  }
}
await bootFailure(w => w.onerror({ message: "Failed to load render-worker.js" }), /Failed to load render-worker\.js/);
await bootFailure(w => w.onerror({}), /failed to load/);
await bootFailure(w => w.onmessageerror({}), /could not read/);
await bootFailure(w => w.onmessage({ data: { t: "error", message: "Embedded browser entry export is missing" } }), /entry export is missing/);

// The cookie mirror: the main thread re-reads document.cookie on cookieStore changes and posts the string to the worker
// only when it differs; a write from the worker is applied and announced to other tabs on the BroadcastChannel.
{
  let jar = "a=1";
  let changed = null;
  const channels = [];
  const cookieDocument = {
    get cookie() { return jar; },
    set cookie(line) { const [pair] = line.split(";"); jar = [...jar.split("; ").filter(part => part.split("=")[0] !== pair.split("=")[0]), pair].join("; "); },
    querySelectorAll: () => [], addEventListener() {}, removeEventListener() {}
  };
  class FakeChannel {
    constructor(name) { this.name = name; this.sent = []; channels.push(this); }
    postMessage(message) { this.sent.push(message); }
    close() { this.closed = true; }
  }
  const cookieWindow = {
    ...hostWindow, document: cookieDocument, location: { hostname: "shop.test", protocol: "https:" },
    cookieStore: { addEventListener(type, listener) { if (type === "change") changed = listener; }, removeEventListener(type) { if (type === "change") changed = null; } },
    BroadcastChannel: FakeChannel
  };
  const before = posted.length;
  const cookieInstance = createWorkerInstance({}, { baseURL: "https://shop.test/", window: cookieWindow });
  await new Promise(resolve => setTimeout(resolve, 0));
  const cookieWorker = worker;
  const cookieInit = posted.slice(before).find(message => message.t === "init");
  assert.equal(cookieInit.cookies, "a=1", "the mirror starts from the page's cookies");
  cookieWorker.onmessage({ data: { t: "publish", seq: 1, html: new Uint8Array(0), lazy: [], secure: {}, fiber: null } });
  const instance2 = await cookieInstance;

  // Another tab changes the jar: the change event reaches the worker once.
  const countCookies = () => posted.filter(message => message.t === "cookies").length;
  jar = "a=1; b=2";
  changed();
  assert.equal(countCookies(), 1, "a changed jar is posted");
  assert.deepEqual(posted.filter(message => message.t === "cookies").at(-1), { t: "cookies", cookies: "a=1; b=2" });
  changed();
  assert.equal(countCookies(), 1, "an unchanged jar is not posted again");

  // A write from the worker goes to the page, and the page's new string is not echoed back to the worker.
  cookieWorker.onmessage({ data: { t: "cookie-write", line: "c=3; Path=/" } });
  assert.ok(jar.includes("c=3"), "the write reaches document.cookie");
  changed();
  assert.equal(countCookies(), 1, "the worker's own write is not reported back");
  assert.deepEqual(channels[0].sent, ["changed"], "other tabs hear about the write");

  instance2.dispose();
  assert.equal(channels[0].closed, true, "the channel closes with the instance");
  assert.equal(changed, null, "the cookieStore listener is removed");
}

// Chromium holds the messages a worker posts until the next frame after a pointer event, so the page opens a BroadcastChannel
// of its own for the worker's replies and names it in `init`. The worker's port stays for what the page sends and for the move to
// the main thread.
{
  const channels = [];
  class ReplyChannel {
    constructor(name) { this.name = name; channels.push(this); }
    postMessage() {}
    close() { this.closed = true; }
  }
  const replyWindow = { ...hostWindow, BroadcastChannel: ReplyChannel, crypto: { randomUUID: () => "11111111-2222-3333-4444-555555555555" } };
  const before = posted.length;
  const creatingReplies = createWorkerInstance({}, { baseURL: "https://app.test/", window: replyWindow });
  await new Promise(resolve => setTimeout(resolve, 0));
  const init = posted.slice(before).find(message => message.t === "init");
  const replies = channels.find(channel => channel.name.startsWith("swui-replies-"));
  assert.ok(replies, "a channel for the replies");
  assert.equal(init.replies, replies.name, "the worker is told the channel's name");
  assert.match(init.replies, /^swui-replies-[0-9a-f-]{36}$/, "an unguessable name");
  replies.onmessage({ data: { t: "publish", seq: 1, html: new Uint8Array([1, 2, 3]), lazy: [], secure: {}, calls: 0 } });
  const replied = await creatingReplies;
  assert.equal(replied.exports.embedded_browser_html_length(), 3, "a publication that arrives on the channel is the newest snapshot");
  replied.dispose();
  assert.equal(replies.closed, undefined, "the channel stays open while the worker ends");
  await new Promise(resolve => setTimeout(resolve, 80));
  assert.equal(replies.closed, true, "the channel closes with the worker");
  // A page without the API keeps the worker's own port.
  const plain = posted.slice(0, before).find(message => message.t === "init");
  assert.equal(plain.replies, null, "no channel without BroadcastChannel");
}

// A stack overflow the worker reports after the app started reaches the handler the runtime registered; another
// error does not.
{
  const calls = [];
  instance.onStackOverflow(failure => calls.push(failure.message));
  const quiet = console.error; console.error = () => {};
  try {
    worker.onmessage({ data: { t: "error", message: "boom" } });
    assert.deepEqual(calls, [], "an ordinary error does not trigger the restart");
  } finally { console.error = quiet; }
}

// The worker's stack ran out and it handed the app over (section 12.11): the page asks it to forward what it had not read yet,
// holds its own calls until the worker says it is done, then ends the worker. A state the main thread cannot take over (here a
// module that is not WebAssembly) falls back to the restart through the same handler a plain overflow uses.
{
  const calls = [], handedOver = [];
  const creatingMoved = createWorkerInstance({}, { baseURL: "https://app.test/", window: hostWindow });
  await new Promise(resolve => setTimeout(resolve, 0));
  const firstWorker = worker;
  firstWorker.onmessage({ data: { t: "publish", seq: 1, html, lazy: [], secure: {} } });
  const moved = await creatingMoved;
  const api = moved.exports;
  moved.onStackOverflow(failure => calls.push(failure.stackOverflow === true));
  moved.onMigrated(() => handedOver.push(true));
  const quiet = console.error; console.error = () => {};
  const before = posted.length;
  try {
    firstWorker.onmessage({ data: { t: "migrate", state: { config: { environment: [] }, local: [], session: [], cookies: "", clock: { origin: 0 }, log: [], inflight: [], length: 0, memory: new ArrayBuffer(0) } } });
    assert.deepEqual(posted.slice(before).map(message => message.t), ["drain-marker"], "the worker is asked to forward what it holds");
    api.embedded_browser_dispatch(30, 2);
    assert.equal(posted.slice(before).filter(message => message.t === "call").length, 0, "a call made during the move waits for it");
    firstWorker.onmessage({ data: { t: "forward", data: { t: "call", n: "dispatch", a: [29, 2] } } });
    firstWorker.onmessage({ data: { t: "forward-done" } });
    assert.equal(firstWorker.terminated, true, "the worker ends once it has forwarded everything");
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.deepEqual(calls, [true], "a state that cannot be adopted restarts the app");
    assert.deepEqual(handedOver, [], "and is not reported as a move");
  } finally { console.error = quiet; }
}

// Measurements wait while the worker is still running earlier calls: the newest per key goes out once the worker reports it
// has caught up, all of them in one batch. Any other call sends them first; an acknowledgement passes them.
{
  const creatingCoalesced = createWorkerInstance({}, { baseURL: "https://app.test/", window: hostWindow });
  await new Promise(resolve => setTimeout(resolve, 0));
  const coalescingWorker = worker;
  coalescingWorker.onmessage({ data: { t: "publish", seq: 1, html, lazy: [], secure: {}, calls: 0 } });
  const coalesced = await creatingCoalesced;
  const api = coalesced.exports;
  const encoder = new TextEncoder();
  const named = (id, name, payload) => { api.embedded_browser_event_value_write(encoder.encode(name + payload)); api.embedded_browser_dispatch_named(id, name.length); };
  const sent = from => posted.slice(from).filter(message => message.t === "call").map(message => {
    const label = message.n === "dispatch_named" ? `${message.n}:${message.a[0]}:${new TextDecoder().decode(message.v)}` : message.n;
    return message.n === "viewport" || message.n === "lazy_window" ? `${label}:${message.a.join(",")}` : label;
  });

  let mark = posted.length;
  api.embedded_browser_viewport(1000, 800, 0, 0);
  assert.deepEqual(sent(mark), ["viewport:1000,800,0,0"], "an idle worker gets the measurement right away");
  mark = posted.length;
  api.embedded_browser_viewport(990, 800, 0, 0);
  api.embedded_browser_viewport(980, 800, 0, 0);
  api.embedded_browser_lazy_window(0, 0, 10, 0, 100);
  api.embedded_browser_lazy_window(0, 5, 10, 50, 50);
  named(7, "geometry", "1");
  named(7, "geometry", "2");
  api.embedded_browser_batch_begin();
  named(8, "layoutproposal", "300,");
  api.embedded_browser_batch_end();
  named(6, "scrollGeometry", "0,0");
  named(6, "scrollGeometry", "0,4");
  api.embedded_browser_publish_ack(1);
  assert.deepEqual(sent(mark), ["publish_ack"], "measurements wait while the worker is behind; the acknowledgement passes them");

  mark = posted.length;
  coalescingWorker.onmessage({ data: { t: "ack", calls: 1 } });
  assert.deepEqual(sent(mark), [], "the worker has not run the acknowledgement yet");
  coalescingWorker.onmessage({ data: { t: "ack", calls: 2 } });
  assert.deepEqual(sent(mark), [
    "batch_begin", "viewport:980,800,0,0", "lazy_window:0,5,10,50,50", "dispatch_named:7:geometry2",
    "dispatch_named:8:layoutproposal300,", "dispatch_named:6:scrollGeometry0,4", "batch_end"
  ], "once it caught up the newest value of each goes out, all in one batch");

  // Behind again: a named event that is not a measurement is never held, and sends the waiting viewport first.
  mark = posted.length;
  api.embedded_browser_viewport(970, 800, 0, 0);
  named(9, "keyDown", "a");
  api.embedded_browser_dispatch(12, 2);
  assert.deepEqual(sent(mark), ["viewport:970,800,0,0", "dispatch_named:9:keyDowna", "dispatch"]);

  // A batch held while behind is posted when another call inside it needs it; what it measured before goes first.
  mark = posted.length;
  api.embedded_browser_batch_begin();
  named(10, "geometryChange", "5");
  api.embedded_browser_dispatch(13, 1);
  api.embedded_browser_batch_end();
  assert.deepEqual(sent(mark), ["dispatch_named:10:geometryChange5", "batch_begin", "dispatch", "batch_end"]);

  // Two held batches go out as one: a newer report replaces the older one's and takes its place in the order.
  mark = posted.length;
  api.embedded_browser_batch_begin();
  named(20, "geometry", "a");
  named(21, "geometryChange", "x");
  api.embedded_browser_batch_end();
  api.embedded_browser_batch_begin();
  named(20, "geometry", "b");
  api.embedded_browser_batch_end();
  api.embedded_browser_dispatch(14, 1);
  assert.deepEqual(sent(mark), [
    "batch_begin", "dispatch_named:21:geometryChangex", "dispatch_named:20:geometryb", "batch_end", "dispatch"
  ]);

  // A held batch that only measured posts nothing; its measurement goes out when the worker has run every call.
  mark = posted.length;
  api.embedded_browser_batch_begin();
  named(11, "geometry", "6");
  api.embedded_browser_batch_end();
  assert.deepEqual(sent(mark), []);
  coalescingWorker.onmessage({ data: { t: "publish", seq: 2, html, lazy: [], secure: {}, calls: api.embedded_browser_calls_sent() - 1 } });
  assert.deepEqual(sent(mark), [], "a publication short of the calls sent leaves them waiting");
  assert.equal(api.embedded_browser_calls_reflected(), api.embedded_browser_calls_sent() - 1);
  coalescingWorker.onmessage({ data: { t: "ack", calls: api.embedded_browser_calls_sent() } });
  assert.deepEqual(sent(mark), ["dispatch_named:11:geometry6"], "a lone measurement needs no batch");
  // A call answered with an ack changed nothing, so the latest publication reflects it too (a focus or a typed value
  // waiting on it is not held back until some later publication).
  const answered = api.embedded_browser_calls_sent();
  coalescingWorker.onmessage({ data: { t: "ack", calls: answered } });
  assert.equal(api.embedded_browser_calls_reflected(), answered);
  coalesced.dispose();
}

console.log("embedded worker client: ok");
