// Migration replay (embedded-host-core.js): when a Worker's call stack runs out, the app continues on the main thread from
// the last snapshot, replaying the calls since it and the failing message or drain. A side-effecting request (a POST) must
// reach the network once: never once in the Worker and again in the replay. Reads (GET) keep the replay they always had.
//
// No browser and no real WebAssembly app: the instance is a stand-in whose drain and calls follow a script, and it uses
// the real BrowserIO and host core. Swift's request counter lives in the stand-in's memory, as it does in the app's, so a
// replay from the snapshot asks for the same request ids the Worker used.
import assert from "node:assert/strict";
import { createHostCore } from "./embedded-host-core.js";
import { Writer } from "./BrowserIO/browser-io.mjs";
import { BrowserIOOperation, BrowserIOEvent } from "./BrowserIO/protocol.generated.mjs";

const MODULE = { standIn: true };
const URL_BASE = "https://app.test/";
const PACKET_AT = 4096;
const SCRATCH_AT = 8192;
const SCHEMA = { phase: 0, idCounter: 4, eventSeen: 8, replySeen: 9 };

const realModuleImports = WebAssembly.Module.imports;
const realInstantiate = WebAssembly.instantiate;
let scenario = null;
let instances = 0;
const standIns = [];
WebAssembly.Module.imports = module => (module === MODULE ? [] : realModuleImports(module));
WebAssembly.instantiate = async (module, imports) => {
  if (module !== MODULE) return realInstantiate(module, imports);
  // The first instance is the Worker's, every later one a main-thread replay.
  const exports = standIn(imports, instances++ === 0);
  standIns.push(exports);
  return { exports };
};

function fetchPacket(method, url, body) {
  return new Writer()
    .text(url).text(method).text("same-origin").text("follow")
    .u32(0).u32(1 << 20).u32(0).u32(0)
    .u32(body ? 1 : 0).data(body ?? new Uint8Array())
    .bytes();
}

const overflow = () => new RangeError("Maximum call stack size exceeded");

/** The stand-in app. Phase 0 is a pass that starts nothing; the scenario decides what the next phase does. */
function standIn(imports, onWorker) {
  const memory = new WebAssembly.Memory({ initial: 1 });
  const bytes = () => new Uint8Array(memory.buffer);
  const io = imports.browser_io;
  const phase = () => bytes()[SCHEMA.phase];
  const setPhase = value => { bytes()[SCHEMA.phase] = value; };
  let armed = false;
  const crash = () => { if (onWorker && scenario.overflows) throw overflow(); };
  // Issues one fetch the way Swift does: a new id from the counter in memory, then the request import.
  const issue = (method) => {
    const packet = method === "GET" ? fetchPacket("GET", URL_BASE + "items") : fetchPacket("POST", URL_BASE + "items", new TextEncoder().encode("name=1"));
    const view = new DataView(memory.buffer);
    const id = view.getUint32(SCHEMA.idCounter, true) + 1;
    view.setUint32(SCHEMA.idCounter, id, true);
    bytes().set(packet, PACKET_AT);
    const status = io.request(id, BrowserIOOperation.fetch, PACKET_AT, packet.length);
    assert.equal(status, 0, "the request import accepts the request");
  };
  // Calls a page service the way BrowserService does; its reply is watched in browser_io_receive.
  let serviceCall = 0;
  const callService = (name, method) => {
    const packet = new Writer().text(name).text(method).text("").bytes();
    const view = new DataView(memory.buffer);
    const id = view.getUint32(SCHEMA.idCounter, true) + 1;
    view.setUint32(SCHEMA.idCounter, id, true);
    serviceCall = id;
    bytes().set(packet, PACKET_AT);
    assert.equal(io.request(id, BrowserIOOperation.service, PACKET_AT, packet.length), 0);
  };
  // Observes a page service's events the way BrowserService does.
  const observe = (name, event) => {
    const packet = new Writer().text(name).text(event).bytes();
    const view = new DataView(memory.buffer);
    const id = view.getUint32(SCHEMA.idCounter, true) + 1;
    view.setUint32(SCHEMA.idCounter, id, true);
    bytes().set(packet, PACKET_AT);
    assert.equal(io.request(id, BrowserIOOperation.serviceEvents, PACKET_AT, packet.length), 0);
  };
  return {
    memory,
    browser_io_alloc: () => SCRATCH_AT,
    browser_io_receive: (id, code) => {
      completions.push({ onWorker, id, code });
      // A service event changes Swift state without starting a task, then the next drain overflows.
      if (code === BrowserIOEvent.serviceEvent) { bytes()[SCHEMA.eventSeen] = 1; armed = true; }
      // A service's reply resumes Swift the same way, and the drain it wakes overflows.
      if (id === serviceCall && code === 0) { bytes()[SCHEMA.replySeen] = 1; armed = true; }
    },
    browser_io_free: () => {},
    embedded_browser_start() {},
    embedded_browser_viewport() { scenario.viewport?.({ issue, observe, callService, crash, arm: () => { armed = true; } }); },
    embedded_browser_drain_tasks() {
      if (phase() === 0) { setPhase(1); return 1; }
      if (phase() === 1 && scenario.drainPost) { issue(scenario.method); crash(); setPhase(2); return 1; }
      if (phase() === 1 && scenario.drainArmed && armed) { crash(); setPhase(2); return 1; }
      return 0;
    }
  };
}

const completions = [];
let requests = [];
const scope = {
  fetch: async (url, init) => {
    requests.push({ method: init.method, url: String(url) });
    return new Response("ok", { status: 200 });
  },
  crypto: globalThis.crypto, Intl, navigator: { onLine: true }
};

const settle = () => new Promise(resolve => setTimeout(resolve, 40));
const init = { t: "init", module: MODULE, baseURL: URL_BASE, environment: [], local: [], session: [], cookies: "", hostname: "app.test", secure: true, migrate: true, diagnostics: false, dark: false, reducedMotion: false, publication: 0 };

/** Runs one scenario: boots the Worker core, triggers the failing work, moves to the main thread if the Worker moved. */
async function run(name, options) {
  scenario = options; requests = []; completions.length = 0; instances = 0;
  const workerOut = [], mainOut = [];
  const worker = createHostCore({ post: message => workerOut.push(message), scope, canMigrate: true });
  await worker.handle(init);
  await settle();
  if (options.trigger) { await worker.handle({ t: "call", n: "viewport", a: [] }); await settle(); }
  const migrate = workerOut.find(message => message.t === "migrate");
  let main = null;
  if (migrate) {
    main = createHostCore({ post: message => mainOut.push(message), scope, canMigrate: false });
    await main.adopt(MODULE, migrate.state);
    await settle();
    await main.handle({ t: "dispose" });
  } else {
    await worker.handle({ t: "dispose" });
  }
  const posts = requests.filter(request => request.method === options.method).length;
  const refused = completions.filter(entry => entry.code < 0).length;
  console.log(`${name}: ${options.method} sent ${posts} time(s), migrated ${migrate ? "yes" : "no"}, refused replays ${refused}`);
  return { posts, migrated: !!migrate, refused, workerOut, mainOut };
}

const cases = [
  // Control: the same drain with no overflow sends the POST once.
  ["control: POST, no overflow", { method: "POST", drainPost: true, overflows: false }, { posts: 1, migrated: false }],
  // The failing drain starts a POST, then overflows. The POST was queued, never sent by the Worker.
  ["drain: POST queued by the failing drain", { method: "POST", drainPost: true, overflows: true }, { posts: 1, migrated: true }],
  // The failing call starts a POST, then overflows (the call is the failing message).
  ["call: POST queued by the failing call", { method: "POST", trigger: true, overflows: true, viewport: ({ issue, crash }) => { issue("POST"); crash(); } }, { posts: 1, migrated: true }],
  // A call starts a POST and returns; the Worker sends it; a later drain overflows, so the call is replayed.
  ["logged call: POST already sent by the Worker", { method: "POST", trigger: true, overflows: true, drainArmed: true, viewport: ({ issue, arm }) => { issue("POST"); arm(); } }, { posts: 1, migrated: true }],
  // Reads keep the replay they always had: a GET queued by the failing drain runs in the Worker and again on the main thread.
  ["drain: GET queued by the failing drain (unchanged)", { method: "GET", drainPost: true, overflows: true }, { posts: 2, migrated: true }]
];

let failures = 0;
for (const [name, options, expected] of cases) {
  const result = await run(name, options);
  try {
    assert.equal(result.migrated, expected.migrated, `${name}: migration`);
    assert.equal(result.posts, expected.posts, `${name}: requests reaching the network`);
  } catch (error) {
    failures++;
    console.log(`FAIL ${error.message}`);
    continue;
  }
  console.log(`ok   ${name}`);
}

// A page service's event reaches Swift in the Worker and changes its state without starting a task; the next drain
// overflows. The change must be in the snapshot the main thread continues from (serviceDelivered in embedded-host-core.js).
{
  const name = "service event: state it changed survives the move";
  scenario = { method: "GET", trigger: true, overflows: true, drainArmed: true, viewport: ({ observe }) => observe("push", "message") };
  requests = []; completions.length = 0; instances = 0; standIns.length = 0;
  const workerOut = [], mainOut = [];
  const worker = createHostCore({ post: message => workerOut.push(message), scope, canMigrate: true });
  await worker.handle(init);
  await settle();
  await worker.handle({ t: "call", n: "viewport", a: [] });
  await settle();
  const observeMessage = workerOut.find(message => message.t === "service-observe");
  try {
    assert.ok(observeMessage, `${name}: the worker asks the page to observe`);
    await worker.handle({ t: "service-event", runtime: observeMessage.runtime, subscription: observeMessage.subscription, text: "chapter" });
    await settle();
    const migrate = workerOut.find(message => message.t === "migrate");
    assert.ok(migrate, `${name}: the next drain moved the app`);
    const main = createHostCore({ post: message => mainOut.push(message), scope, canMigrate: false });
    await main.adopt(MODULE, migrate.state);
    await settle();
    assert.equal(new Uint8Array(standIns.at(-1).memory.buffer)[SCHEMA.eventSeen], 1, `${name}: the main thread starts with the change`);
    await main.handle({ t: "dispose" });
    console.log(`ok   ${name}`);
  } catch (error) {
    failures++;
    console.log(`FAIL ${error.message}`);
    await worker.handle({ t: "dispose" });
  }
}

// A page service's reply reaches Swift and wakes a drain that overflows at once. The reply's change must already be in
// the snapshot the main thread continues from (BrowserIO's onServiceDelivered hook, before it wakes the drain).
{
  const name = "service reply: state it changed survives the drain it wakes";
  scenario = { method: "GET", trigger: true, overflows: true, drainArmed: true, viewport: ({ callService }) => callService("ledger", "record") };
  requests = []; completions.length = 0; instances = 0; standIns.length = 0;
  const workerOut = [], mainOut = [];
  const worker = createHostCore({ post: message => workerOut.push(message), scope, canMigrate: true });
  await worker.handle(init);
  await settle();
  await worker.handle({ t: "call", n: "viewport", a: [] });
  await settle();
  const request = workerOut.find(message => message.t === "service");
  try {
    assert.ok(request, `${name}: the worker forwards the call to the page`);
    await worker.handle({ t: "service-reply", runtime: request.runtime, request: request.request, ok: true, text: "ok" });
    await settle();
    const migrate = workerOut.find(message => message.t === "migrate");
    assert.ok(migrate, `${name}: the drain the reply woke moved the app`);
    const main = createHostCore({ post: message => mainOut.push(message), scope, canMigrate: false });
    await main.adopt(MODULE, migrate.state);
    await settle();
    assert.equal(new Uint8Array(standIns.at(-1).memory.buffer)[SCHEMA.replySeen], 1, `${name}: the main thread starts with the reply's change`);
    await main.handle({ t: "dispose" });
    console.log(`ok   ${name}`);
  } catch (error) {
    failures++;
    console.log(`FAIL ${error.message}`);
    await worker.handle({ t: "dispose" });
  }
}

if (failures) { console.log(`${failures} migration replay check(s) failed`); process.exit(1); }
console.log("embedded migration replay: ok");
