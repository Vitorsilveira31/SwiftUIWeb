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
import { BrowserIOOperation } from "./BrowserIO/protocol.generated.mjs";

const MODULE = { standIn: true };
const URL_BASE = "https://app.test/";
const PACKET_AT = 4096;
const SCRATCH_AT = 8192;
const SCHEMA = { phase: 0, idCounter: 4 };

const realModuleImports = WebAssembly.Module.imports;
const realInstantiate = WebAssembly.instantiate;
let scenario = null;
let instances = 0;
WebAssembly.Module.imports = module => (module === MODULE ? [] : realModuleImports(module));
WebAssembly.instantiate = async (module, imports) => {
  if (module !== MODULE) return realInstantiate(module, imports);
  // The first instance is the Worker's, every later one a main-thread replay.
  return { exports: standIn(imports, instances++ === 0) };
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
  return {
    memory,
    browser_io_alloc: () => SCRATCH_AT,
    browser_io_receive: (id, code) => { completions.push({ onWorker, id, code }); },
    browser_io_free: () => {},
    embedded_browser_start() {},
    embedded_browser_viewport() { scenario.viewport?.({ issue, crash, arm: () => { armed = true; } }); },
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
const init = { t: "init", module: MODULE, baseURL: URL_BASE, environment: [], local: [], session: [], cookies: "", hostname: "app.test", secure: true, migrate: true, diagnostics: false, dark: false, reducedMotion: false, cssLayout: false, publication: 0 };

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

if (failures) { console.log(`${failures} migration replay check(s) failed`); process.exit(1); }
console.log("embedded migration replay: ok");
