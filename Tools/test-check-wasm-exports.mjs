// The event ABI guard must require the bulk event/secure value block exactly when the
// source lowering says it generated the browser entry points, and ignore other products' reports.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const base = [
  "memory",
  ...["viewport", "scroll_ack", "scroll_prepare", "history_ack", "history_restore", "history_location", "dispatch_named"].map(n => "embedded_browser_" + n),
];
const bulk = ["event_value_alloc", "event_value_commit", "secure_value_pointer", "secure_ids_length", "secure_ids_pointer"].map(n => "embedded_browser_" + n);

const leb = (value) => { const out = []; do { let byte = value & 0x7f; value >>>= 7; if (value) byte |= 0x80; out.push(byte); } while (value); return out; };
const vec = (items) => [...leb(items.length), ...items.flat()];
const name = (text) => [...leb(text.length), ...new TextEncoder().encode(text)];
// A module that exports `functions` as empty functions and `memory` as a memory.
function wasm(exportNames) {
  const functions = exportNames.filter(n => n !== "memory");
  const sections = [
    [1, vec([[0x60, 0, 0]])], [3, vec(functions.map(() => [0]))], [5, vec([[0, 1]])],
    [7, vec([...functions.map((n, i) => [...name(n), 0, ...leb(i)]), ...(exportNames.includes("memory") ? [[...name("memory"), 2, 0]] : [])])],
    [10, vec(functions.map(() => [...leb(2), 0, 0x0b]))],
  ];
  return Uint8Array.from([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, ...sections.flatMap(([id, body]) => [id, ...leb(body.length), ...body])]);
}

const directory = mkdtempSync(join(tmpdir(), "swui-abi-"));
try {
  const plain = join(directory, "plain.wasm"), full = join(directory, "full.wasm");
  writeFileSync(plain, wasm(base));
  writeFileSync(full, wasm([...base, ...bulk]));
  const report = (product, generated) => {
    const file = join(directory, `${product}-${generated}.json`);
    writeFileSync(file, JSON.stringify({ product, rules: generated ? { "browser-reactor-entry-and-html-exports": 1 } : {} }));
    return file;
  };
  const check = (module, ...args) => spawnSync(process.execPath, ["Tools/check-wasm-exports.mjs", module, ...args], { cwd: new URL("..", import.meta.url).pathname, encoding: "utf8" });

  assert.equal(check(plain).status, 0, "without a lowering report the base ABI is enough");
  assert.equal(check(plain, "--product", "App", report("App", false)).status, 0, "a report that generated nothing requires nothing");
  const missing = check(plain, "--product", "App", report("App", true));
  assert.notEqual(missing.status, 0, "the lowerer generated the browser entry points, so a build without the bulk block must fail");
  for (const n of bulk) assert.ok(missing.stderr.includes(n), `the failure should name ${n}`);
  const complete = check(full, "--product", "App", report("App", true));
  assert.equal(complete.status, 0, complete.stderr);
  assert.match(complete.stdout, /bulk event\/secure value block required and present/);
  assert.equal(check(plain, "--product", "App", report("Other", true)).status, 0, "another product's report must not gate this build");
  assert.equal(check(plain, "--product", "App", directory).status, 1, "a reports directory is scanned for this product's generated exports");
  console.log("wasm export guard: ok");
} finally {
  rmSync(directory, { recursive: true, force: true });
}
