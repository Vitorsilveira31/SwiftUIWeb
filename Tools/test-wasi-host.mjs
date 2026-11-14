// The WASI shim exposes the document environment to Swift: `environ_get`
// writes the `KEY=VALUE` strings the runtime read from
// `<meta name="runtime-environment">`, NUL-terminated, in order.
import assert from "node:assert/strict";
import { createWasiHost, publicationFlags, readDocumentEnvironment } from "./wasi-host.js";

const memory = new WebAssembly.Memory({ initial: 1 });
const instance = { exports: { memory } };
const entries = ["SWIFTUIWEB_IMAGE_ASSETS=Brand=catalog-assets/Brand.svg;Poster=catalog-assets/Poster.png", "SWIFTUIWEB_LANGUAGE=pt-BR"];
const wasi = createWasiHost(() => instance, { environment: entries });
const view = new DataView(memory.buffer);

assert.equal(wasi("environ_sizes_get")(0, 4), 0);
assert.equal(view.getUint32(0, true), 2, "entry count");
const expectedSize = entries.reduce((total, entry) => total + new TextEncoder().encode(entry).length + 1, 0);
assert.equal(view.getUint32(4, true), expectedSize, "buffer size including NUL terminators");

assert.equal(wasi("environ_get")(16, 64), 0);
const bytes = new Uint8Array(memory.buffer);
let cursor = 64;
entries.forEach((entry, index) => {
  assert.equal(view.getUint32(16 + index * 4, true), cursor, `pointer of entry ${index}`);
  const encoded = new TextEncoder().encode(entry);
  assert.deepEqual(bytes.subarray(cursor, cursor + encoded.length), encoded);
  assert.equal(bytes[cursor + encoded.length], 0, "NUL terminator");
  cursor += encoded.length + 1;
});

// The monotonic clock (id 1) has sub-millisecond resolution so Swift can time
// phases; the realtime clock (id 0) stays wall-clock milliseconds.
const clockTime = wasi("clock_time_get");
assert.equal(clockTime(1, 1n, 96), 0);
const monotonicFirst = view.getBigUint64(96, true);
let monotonicLast = monotonicFirst;
for (let spin = 0; spin < 200000 && monotonicLast === monotonicFirst; spin++) {
  clockTime(1, 1n, 96);
  monotonicLast = view.getBigUint64(96, true);
}
assert.ok(monotonicLast > monotonicFirst, "monotonic clock advances below one millisecond granularity");
assert.ok(monotonicLast - monotonicFirst < 1000000n, "monotonic clock is finer than one millisecond");
assert.equal(clockTime(0, 1n, 96), 0);
assert.equal(view.getBigUint64(96, true) % 1000000n, 0n, "realtime clock stays in whole milliseconds");

const empty = createWasiHost(() => instance);
assert.equal(empty("environ_sizes_get")(0, 4), 0);
assert.equal(view.getUint32(0, true), 0);
assert.equal(view.getUint32(4, true), 0);

const document = { querySelectorAll: selector => selector === 'meta[name="runtime-environment"]'
  ? [{ getAttribute: () => "A=1" }, { getAttribute: () => "broken" }, { getAttribute: () => null }, { getAttribute: () => "B=x=y" }] : [] };
assert.deepEqual(readDocumentEnvironment(document), ["A=1", "B=x=y"]);
assert.deepEqual(readDocumentEnvironment(undefined), []);
assert.deepEqual(readDocumentEnvironment({}), []);
assert.deepEqual(readDocumentEnvironment(document, { language: "pt-BR" }), ["A=1", "B=x=y", "SWIFTUIWEB_LANGUAGE=pt-BR"], "the browser language is appended");
assert.deepEqual(readDocumentEnvironment(undefined, { language: "en-US" }), ["SWIFTUIWEB_LANGUAGE=en-US"]);
assert.deepEqual(readDocumentEnvironment(undefined, { language: "" }), []);
const pinned = { querySelectorAll: () => [{ getAttribute: () => "SWIFTUIWEB_LANGUAGE=pt" }] };
assert.deepEqual(readDocumentEnvironment(pinned, { language: "en-US" }), ["SWIFTUIWEB_LANGUAGE=pt"], "a pinned language meta wins");

const located = { querySelectorAll: () => [], location: { pathname: "/stackDepth", search: "?tab-selection=a%3Ab", hash: "#x" } };
assert.deepEqual(readDocumentEnvironment(located), ["SWIFTUIWEB_INITIAL_LOCATION=/stackDepth?tab-selection=a%3Ab#x"], "the page address reaches the first render");
const restored = { ...located, defaultView: { history: { state: { swuiNavigation: { depth: 1 } } } } };
assert.deepEqual(readDocumentEnvironment(restored), ["SWIFTUIWEB_INITIAL_LOCATION=/stackDepth?tab-selection=a%3Ab#x", "SWIFTUIWEB_INITIAL_NAVIGATION_STATE=1"],
  "an entry that carries a NavigationStack snapshot says so");

const root = { ...located, defaultView: { history: { state: { swuiNavigation: { depth: 0 } } } } };
assert.deepEqual(readDocumentEnvironment(root), ["SWIFTUIWEB_INITIAL_LOCATION=/stackDepth?tab-selection=a%3Ab#x"], "a depth-zero entry is a plain route");


// The publication flags Swift is told at start: 32 attaches a reference encoding for the page to verify against, 64 turns the shapes off.
const flags = (window) => publicationFlags(window);
assert.equal(flags(undefined), 0);
assert.equal(flags({}), 0);
assert.equal(flags({ location: { search: "?binary=0&keep-own=0" } }), 0, "the HTML transport is gone: its switches do nothing");
assert.equal(flags({ __binaryVerify: true }), 32);
assert.equal(flags({ location: { search: "?x=1&binary-verify=1" } }), 32);
assert.equal(flags({ location: { search: "?binary-shapes=0" } }), 64);
assert.equal(flags({ __binaryShapes: true, location: { search: "?binary-shapes=0" } }), 0, "the property wins over the address");

console.log("WASI host environment checks passed.");
