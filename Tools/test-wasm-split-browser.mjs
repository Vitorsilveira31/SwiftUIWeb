#!/usr/bin/env bun
// The loader of a split release module (Tools/wasm-split-loader.js) in a real browser.
//
// 1. A small module split by Binaryen's own wasm-split (one function moved to the second module) runs in a Worker and on
//    the page, split both without reference types (the placeholders sit in the indirect function table) and with them (as the
//    release modules are: wasm-split adds a table of their own next to it): in the Worker a call to the moved function before the second module arrived waits for it (a synchronous
//    load) and returns the right value; a background load fills the table so later calls go straight to the function;
//    the page, which cannot wait, loads both before it calls anything; a module that is not split is left alone.
// 2. With WASM_SPLIT_BUNDLE (a bundle built with SWIFTUIWEB_WASM_SPLIT=1, for example the Board:
//    `SWIFTUIWEB_WASM_SPLIT=1 BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh board`), the app reaches its first
//    screen in the Worker without waiting for app-rest.wasm, which arrives behind it; on the main thread
//    (`?render-in-worker=0`, where both modules download side by side), and after a move from the Worker to the main thread (the performance diagnostics'
//    forced overflow), it keeps working. WASM_SPLIT_ROUTE (default /) is the page it opens. The first module must declare
//    one table and import its placeholders (the module's own table holds them, with no forwarding stubs);
//    WASM_SPLIT_LAYOUT=two-tables expects the other layout, for a module that needs reference types.
//    The check the build runs on that move (the first module instrumented with `--instrument-memory`, `dataHook` counting the accesses to
//    the moved ranges before the second module is instantiated) reports nothing for that module, and reports the read of a module whose
//    hot function reads data that was moved.
//    A module whose cold function reads 1 KB of data nothing else reads has that data moved into the second module
//    (Tools/wasm-data-split.mjs): the first module alone holds none of it, a call that loads the second module reads it, and a thread that
//    copies a snapshot of memory over its own (the move from the Worker) can instantiate the second module after the copy
//    (`hold` and `release`) and still end up with the data.
//
// Needs Binaryen (wasm-as, wasm-split); without it part 1 is skipped with a message.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { launch, runSuite, serveBundle, serveStatic, ROOT } from "./browser-test-support.mjs";
import { moveData, readDataSegments, splitData } from "./wasm-data-split.mjs";
import { dataHook, instrumentation } from "./wasm-split-release.mjs";

const MODULE = `(module
  (memory (export "memory") 1)
  (type $unary (func (param i32) (result i32)))
  (table $functions (export "functions") 2 funcref)
  (elem (i32.const 0) $twice $twice)
  (func $twice (param $x i32) (result i32) (i32.mul (local.get $x) (i32.const 2)))
  (func $indirect (export "indirect") (param $x i32) (result i32) (call_indirect (type $unary) (local.get $x) (i32.const 1)))
  (global $offset (mut i32) (i32.const 40))
  (func $hot (export "hot") (result i32) (i32.const 1))
  (func $cold (param $x i32) (result i32) (i32.add (local.get $x) (global.get $offset)))
  (func $callCold (export "callCold") (param $x i32) (result i32) (call $cold (local.get $x))))`;

// The same module with data: 1 KB at 4096 that only $cold reads (its first word is 100), and a word at 8192 that $hot reads.
const COLD_DATA = "\\64\\00\\00\\00" + "\\07".repeat(1020);
const DATA_MODULE = MODULE
  .replace('(memory (export "memory") 1)', `(memory (export "memory") 1)\n  (data (i32.const 4096) "${COLD_DATA}")\n  (data (i32.const 8192) "\\05\\00\\00\\00")`)
  .replace('(func $hot (export "hot") (result i32) (i32.const 1))', '(func $hot (export "hot") (result i32) (i32.add (i32.const 1) (i32.load (i32.const 8192))))')
  .replace('(i32.add (local.get $x) (global.get $offset))', '(i32.add (i32.add (local.get $x) (global.get $offset)) (i32.load (i32.const 4096)))');
// The same, whose $hot copies 16 bytes out of the data that moved (a bulk copy, which the instrumentation only sees as loops).
const COPY_MODULE = DATA_MODULE.replace('(i32.add (i32.const 1) (i32.load (i32.const 8192)))', '(i32.add (i32.const 1) (block (result i32) (memory.copy (i32.const 8200) (i32.const 4096) (i32.const 16)) (i32.const 0)))');
// The linker's map of that module, in wasm-ld's columns.
const mapRow = (address, size, text, depth = 0) => `${address.toString(16).padStart(8)} ${"275cf5".padStart(8)} ${size.toString(16).padStart(8)} ${" ".repeat(depth)}${text}`;
const DATA_MAP = [
  "    Addr      Off     Size Out     In      Symbol", mapRow(0, 0x25c0e, "DATA").replace(/^ {7}0/, "       -"),
  mapRow(4096, 1024, ".rodata"), mapRow(4096, 1024, "/app/A.o:(.rodata.cold)", 8), mapRow(4096, 1024, "cold", 16),
  mapRow(8192, 4, ".data"), mapRow(8192, 4, "/app/A.o:(.data.hot)", 8), mapRow(8192, 4, "hot", 16),
].join("\n") + "\n";

const PAGE = `<!doctype html><meta charset="utf-8"><script type="module">
import { createSplitLoader, isSplitModule, loadAroundCopy } from './wasm-split-loader.js';
globalThis.runPage = async (variant) => {
  const module = await WebAssembly.compileStreaming(fetch('./primary' + variant + '.wasm'));
  const plain = await WebAssembly.compileStreaming(fetch('./plain.wasm'));
  const loader = createSplitLoader(module, { url: new URL('./secondary' + variant + '.wasm', location.href).href });
  const loading = loader.load();
  const instance = await WebAssembly.instantiate(module, loader.imports);
  loader.attach(instance);
  await loading;
  return { split: isSplitModule(module), plainSplit: isSplitModule(plain), hot: instance.exports.hot(), cold: instance.exports.callCold(2), indirect: instance.exports.indirect(4), loaded: loader.loaded };
};
// The second module's data segments are written when it is instantiated: not by the first module, not while it is held.
globalThis.runData = async () => {
  const start = async () => {
    const module = await WebAssembly.compileStreaming(fetch('./primary-data.wasm'));
    const loader = createSplitLoader(module, { url: new URL('./secondary-data.wasm', location.href).href });
    const instance = await WebAssembly.instantiate(module, loader.imports);
    loader.attach(instance);
    return { loader, instance, word: (at) => new DataView(instance.exports.memory.buffer).getUint32(at, true) };
  };
  const { loader, instance, word } = await start();
  const alone = { cold: word(4096), hot: word(8192) };
  loader.hold();
  await loader.load();
  const held = { loaded: loader.loaded, cold: word(4096) };
  loader.release();
  const released = { loaded: loader.loaded, cold: word(4096), last: new Uint8Array(instance.exports.memory.buffer)[5119], hot: instance.exports.hot(), call: instance.exports.callCold(2) };
  // The move from the Worker: a snapshot taken before the second half was loaded holds zeros where its data goes, and the half
  // is instantiated after the copy, which leaves the data; one taken after holds the data (here, a value the program wrote), and
  // the half is instantiated before the copy, which leaves the snapshot's bytes.
  const before = await start();
  await loadAroundCopy(before.loader, false, () => new Uint8Array(before.instance.exports.memory.buffer).fill(0, 4096, 5120));
  const snapshotBefore = { loaded: before.loader.loaded, cold: before.word(4096), last: new Uint8Array(before.instance.exports.memory.buffer)[5119] };
  const after = await start();
  await loadAroundCopy(after.loader, true, () => new Uint8Array(after.instance.exports.memory.buffer).set([171, 0, 0, 0], 4096));
  const snapshotAfter = { loaded: after.loader.loaded, cold: after.word(4096), last: new Uint8Array(after.instance.exports.memory.buffer)[5119] };
  let copied = false;
  await loadAroundCopy(null, undefined, () => { copied = true; });
  return { alone, held, released, snapshotBefore, snapshotAfter, copied };
};
// The check of a data move: the first module's accesses to the moved ranges before its second module is instantiated.
globalThis.runWatched = async (variant, hook) => {
  (0, eval)(hook);
  const module = await WebAssembly.compileStreaming(fetch('./primary-' + variant + '.wasm'));
  const loader = createSplitLoader(module, { url: new URL('./secondary-' + variant + '.wasm', location.href).href });
  const instance = await WebAssembly.instantiate(module, loader.imports);
  loader.attach(instance);
  instance.exports.hot();
  const before = [...globalThis.__swiftuiwebDataReads];
  await loader.load();
  instance.exports.callCold(2);
  return { before, after: [...globalThis.__swiftuiwebDataReads] };
};
// The same check with the instrumented module in a Worker that the page ends as soon as it has run: what the Worker recorded is posted to
// the page as it happens, so the page has it after the Worker is gone.
globalThis.runForwarded = (hook) => new Promise((done, fail) => {
  (0, eval)(hook);
  const worker = new Worker('./watch-worker.js', { type: 'module' });
  worker.onmessage = (event) => {
    worker.terminate();
    setTimeout(() => done({ error: event.data.error ?? null, worker: event.data.own ?? null, page: [...globalThis.__swiftuiwebDataReads] }), 150);
  };
  worker.onerror = (event) => fail(new Error(event.message));
  worker.postMessage({ hook });
});
globalThis.runWorker = (background, variant) => new Promise((done, fail) => {
  const worker = new Worker('./worker.js', { type: 'module' });
  worker.onmessage = (event) => { worker.terminate(); done(event.data); };
  worker.onerror = (event) => fail(new Error(event.message));
  worker.postMessage({ background, variant });
});
globalThis.ready = true;
</script>`;

const WORKER = `import { createSplitLoader } from './wasm-split-loader.js';
self.onmessage = async ({ data }) => {
  try {
    const module = await WebAssembly.compileStreaming(fetch('./primary' + data.variant + '.wasm'));
    const loader = createSplitLoader(module, { url: new URL('./secondary' + data.variant + '.wasm', location.href).href, canBlock: true });
    const instance = await WebAssembly.instantiate(module, loader.imports);
    loader.attach(instance);
    if (data.background) await loader.load();
    const before = loader.loaded;
    const cold = instance.exports.callCold(5);
    const again = instance.exports.callCold(6);
    const indirect = instance.exports.indirect(4);
    const mark = performance.getEntriesByName('swiftuiweb-app-rest')[0]?.detail ?? null;
    self.postMessage({ before, cold, again, indirect, loaded: loader.loaded, mark });
  } catch (error) { self.postMessage({ error: String(error) }); }
};`;

const WATCH_WORKER = `import { createSplitLoader } from './wasm-split-loader.js';
self.onmessage = async ({ data }) => {
  try {
    (0, eval)(data.hook);
    const module = await WebAssembly.compileStreaming(fetch('./primary-wrong.wasm'));
    const loader = createSplitLoader(module, { url: new URL('./secondary-wrong.wasm', location.href).href, canBlock: true });
    const instance = await WebAssembly.instantiate(module, loader.imports);
    loader.attach(instance);
    instance.exports.hot();
    self.postMessage({ own: [...globalThis.__swiftuiwebDataReads] });
  } catch (error) { self.postMessage({ error: String(error) }); }
};`;

function binaryen(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error?.code === "ENOENT") return null;
  assert.equal(result.status, 0, `${command} failed: ${result.stderr}`);
  return result;
}

async function synthetic(browser) {
  const dir = mkdtempSync(join(tmpdir(), "swiftuiweb-split-test-"));
  try {
    writeFileSync(join(dir, "module.wat"), MODULE);
    if (!binaryen("wasm-as", [join(dir, "module.wat"), "-g", "-o", join(dir, "plain.wasm")])) {
      console.log("skip: Binaryen (wasm-as, wasm-split) is not installed");
      return;
    }
    for (const [variant, features] of [["", []], ["-rt", ["--enable-reference-types"]]]) {
      binaryen("wasm-split", ["--split", join(dir, "plain.wasm"), "--split-funcs", "cold", "-o1", join(dir, `primary${variant}.wasm`), "-o2", join(dir, `secondary${variant}.wasm`),
        "--placeholder-namespace", "p", "--import-namespace", "primary", ...features]);
    }
    // The data module: split by Binaryen, then its data moved by Tools/wasm-data-split.mjs.
    writeFileSync(join(dir, "data.wat"), DATA_MODULE);
    binaryen("wasm-as", [join(dir, "data.wat"), "-g", "-o", join(dir, "data.wasm")]);
    binaryen("wasm-split", ["--split", join(dir, "data.wasm"), "--split-funcs", "cold", "-o1", join(dir, "primary-data0.wasm"), "-o2", join(dir, "secondary-data0.wasm"),
      "--placeholder-namespace", "p", "--import-namespace", "primary"]);
    const moved = splitData({ primary: new Uint8Array(readFileSync(join(dir, "primary-data0.wasm"))), secondary: new Uint8Array(readFileSync(join(dir, "secondary-data0.wasm"))), linkMap: DATA_MAP });
    assert.equal(moved.reason, undefined, "the data of the test module moves");
    assert.equal(moved.moved.bytes, 1024, "the 1 KB only $cold reads moves, the word $hot reads stays");
    writeFileSync(join(dir, "primary-data.wasm"), moved.primary);
    writeFileSync(join(dir, "secondary-data.wasm"), moved.secondary);
    // A bulk copy of moved data by $hot: the check must see it.
    writeFileSync(join(dir, "copy.wat"), COPY_MODULE);
    binaryen("wasm-as", [join(dir, "copy.wat"), "--enable-bulk-memory", "-g", "-o", join(dir, "copy.wasm")]);
    binaryen("wasm-split", ["--split", join(dir, "copy.wasm"), "--split-funcs", "cold", "-o1", join(dir, "primary-copy0.wasm"), "-o2", join(dir, "secondary-copy0.wasm"),
      "--placeholder-namespace", "p", "--import-namespace", "primary", "--enable-bulk-memory"]);
    const copied = moveData(new Uint8Array(readFileSync(join(dir, "primary-copy0.wasm"))), new Uint8Array(readFileSync(join(dir, "secondary-copy0.wasm"))), [[4096, 5120]]);
    writeFileSync(join(dir, "primary-copy1.wasm"), copied.primary);
    writeFileSync(join(dir, "secondary-copy.wasm"), copied.secondary);
    binaryen("wasm-opt", [...instrumentation(["--enable-bulk-memory"]), join(dir, "primary-copy1.wasm"), "-o", join(dir, "primary-copy.wasm")]);
    // The same split with the word $hot reads moved as well, which a correct plan never does, and both of them instrumented.
    const wrong = moveData(new Uint8Array(readFileSync(join(dir, "primary-data0.wasm"))), new Uint8Array(readFileSync(join(dir, "secondary-data0.wasm"))), [[4096, 5120], [8192, 8196]]);
    writeFileSync(join(dir, "primary-wrong0.wasm"), wrong.primary);
    writeFileSync(join(dir, "secondary-wrong.wasm"), wrong.secondary);
    binaryen("wasm-opt", ["--instrument-memory", join(dir, "primary-data.wasm"), "-o", join(dir, "primary-watched.wasm")]);
    binaryen("wasm-opt", ["--instrument-memory", join(dir, "primary-wrong0.wasm"), "-o", join(dir, "primary-wrong.wasm")]);
    writeFileSync(join(dir, "secondary-watched.wasm"), moved.secondary);
    copyFileSync(join(ROOT, "Tools/wasm-split-loader.js"), join(dir, "wasm-split-loader.js"));
    writeFileSync(join(dir, "index.html"), PAGE);
    writeFileSync(join(dir, "worker.js"), WORKER);
    writeFileSync(join(dir, "watch-worker.js"), WATCH_WORKER);
    const server = serveStatic(dir);
    try {
      const page = await browser.newPage();
      const requests = [];
      page.on("request", (request) => requests.push(new URL(request.url()).pathname));
      await page.goto(`${server.base}/index.html`);
      await page.waitForFunction(() => globalThis.ready === true);

      for (const variant of ["", "-rt"]) {
        const label = variant ? "with reference types" : "without reference types";
        assert.deepEqual(await page.evaluate((v) => globalThis.runPage(v), variant), { split: true, plainSplit: false, hot: 1, cold: 42, indirect: 8, loaded: true }, `${label}: the page loads both halves, then calls`);

        const waited = await page.evaluate((v) => globalThis.runWorker(false, v), variant);
        assert.equal(waited.error, undefined, waited.error);
        assert.deepEqual(waited, { before: false, cold: 45, again: 46, indirect: 8, loaded: true, mark: { waited: true } }, `${label}: a call before the second half arrived waits for it`);

        const background = await page.evaluate((v) => globalThis.runWorker(true, v), variant);
        assert.deepEqual(background, { before: true, cold: 45, again: 46, indirect: 8, loaded: true, mark: { waited: false } }, `${label}: a background load fills the table first`);
        assert.ok(requests.filter((path) => path === `/secondary${variant}.wasm`).length >= 3, `${label}: each instance fetched the second half`);
      }
      // The data that moved with the cold function.
      assert.deepEqual(await page.evaluate(() => globalThis.runData()), {
        alone: { cold: 0, hot: 5 }, held: { loaded: false, cold: 0 },
        released: { loaded: true, cold: 100, last: 7, hot: 6, call: 142 },
        snapshotBefore: { loaded: true, cold: 100, last: 7 }, snapshotAfter: { loaded: true, cold: 171, last: 7 }, copied: true,
      }, "the first module alone has none of the moved data; held, the second module is not instantiated; released, its data is written; around a copy, the data or the snapshot wins by when the snapshot was taken");
      const dataWorker = await page.evaluate(() => globalThis.runWorker(false, "-data"));
      assert.equal(dataWorker.error, undefined, dataWorker.error);
      assert.deepEqual(dataWorker, { before: false, cold: 145, again: 146, indirect: 8, loaded: true, mark: { waited: true } }, "a call that waits for the second module reads its data");
      // The check the build runs on a move: nothing for a correct one, and the read of a wrong one.
      const runs = moved.moved.ranges;
      for (const [variant, expected] of [["watched", { before: [], after: [] }], ["wrong", { before: ["read 8192"], after: ["read 8192"] }]]) {
        const watching = await browser.newPage();
        await watching.goto(`${server.base}/index.html`);
        await watching.waitForFunction(() => globalThis.ready === true);
        const hook = dataHook(variant === "wrong" ? [[4096, 5120], [8192, 8196]] : runs);
        assert.deepEqual(await watching.evaluate(([name, source]) => globalThis.runWatched(name, source), [variant, hook]), expected, `the check of the moved data (${variant})`);
        await watching.close();
      }
      // What a Worker's instrumented module touches reaches the page as it happens, and stays there when the Worker is ended.
      const forwarding = await browser.newPage();
      await forwarding.goto(`${server.base}/index.html`);
      await forwarding.waitForFunction(() => globalThis.ready === true);
      assert.deepEqual(await forwarding.evaluate((source) => globalThis.runForwarded(source), dataHook([[4096, 5120], [8192, 8196]])), { error: null, worker: ["read 8192"], page: ["read 8192"] },
        "the page has what the Worker's check recorded, after the Worker ended");
      await forwarding.close();
      // A bulk copy of moved data is lowered to loads before the instrumentation, so it is seen as well.
      const bulk = await browser.newPage();
      await bulk.goto(`${server.base}/index.html`);
      await bulk.waitForFunction(() => globalThis.ready === true);
      const bulkReads = await bulk.evaluate(([name, source]) => globalThis.runWatched(name, source), ["copy", dataHook([[4096, 5120]])]);
      assert.ok(bulkReads.before.length > 0 && bulkReads.before.every((entry) => /^read 41(0[0-9]|1[01])$|^read 409[6-9]$/.test(entry)), "the check sees a bulk copy out of moved data");
      await bulk.close();
      await page.close();
      console.log("ok: a module split by wasm-split loads its second half in a Worker (waiting or in the background) and on the page, and its data comes with it");
    } finally {
      await server.stop();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** How many tables a module defines or imports: the count of its table section plus its table imports. */
function tableCount(bytes) {
  let at = 8;
  const leb = () => { let value = 0, shift = 0, byte; do { byte = bytes[at++]; value += (byte & 0x7f) * 2 ** shift; shift += 7; } while (byte & 0x80); return value; };
  let defined = 0;
  while (at < bytes.length) {
    const id = bytes[at++], size = leb(), end = at + size;
    if (id === 4) { defined = leb(); break; }
    at = end;
  }
  return defined + WebAssembly.Module.imports(new WebAssembly.Module(bytes)).filter((entry) => entry.kind === "table").length;
}

// The layout of the first module: the placeholders sit in the module's own table, which is then its only table. A module
// that needs reference types (or lists a feature without a Binaryen flag) keeps a table of its own for them, and
// WASM_SPLIT_LAYOUT=two-tables says the bundle is one of those.
function checkLayout(bundle) {
  const name = readdirSync(bundle).find((file) => /^app(\.[0-9a-f]{8})?\.wasm$/.test(file));
  assert.ok(name, "the bundle has an app.wasm");
  const bytes = new Uint8Array(readFileSync(join(bundle, name)));
  const placeholders = WebAssembly.Module.imports(new WebAssembly.Module(bytes)).filter((entry) => entry.module.startsWith("p.") && entry.kind === "function").length;
  assert.ok(placeholders > 0, `${name} imports the placeholders of the functions it moved`);
  const tables = tableCount(bytes);
  if (process.env.WASM_SPLIT_LAYOUT === "two-tables") assert.equal(tables, 2, `${name} has the two-table layout`);
  else assert.equal(tables, 1, `${name} declares one table and imports its placeholders (the single-table layout)`);
  console.log(`ok: ${name} has ${tables} table${tables === 1 ? "" : "s"} and ${placeholders} placeholder imports`);
}

/** A word the second module's data segments write (address, value), or null when the bundle moved no data. */
function movedWord(bundle) {
  const name = readdirSync(bundle).find((file) => /^app-rest(\.[0-9a-f]{8})?\.wasm$/.test(file));
  const bytes = new Uint8Array(readFileSync(join(bundle, name)));
  for (const segment of readDataSegments(bytes).segments) {
    for (let at = 0; at + 4 <= segment.size; at += 4) {
      const value = new DataView(bytes.buffer, bytes.byteOffset + segment.at + at, 4).getUint32(0, true);
      if (value !== 0 && (segment.offset + at) % 4 === 0) return { address: segment.offset + at, value };
    }
  }
  return null;
}

async function splitBundle(browser, bundle) {
  checkLayout(bundle);
  const moved = movedWord(bundle);
  console.log(moved ? `ok: app-rest.wasm carries data (for example the word ${moved.value} at ${moved.address})` : "note: this bundle moved no data into app-rest.wasm");
  const route = process.env.WASM_SPLIT_ROUTE ?? "/";
  const server = await serveBundle({ bundle, logName: null });
  const marks = async (page) => {
    const all = [];
    for (const scope of [...page.workers(), page]) all.push(...await scope.evaluate(() => performance.getEntriesByName("swiftuiweb-app-rest").map((mark) => mark.detail)).catch(() => []));
    return all;
  };
  try {
    for (const [label, query, init] of [
      ["worker", "", null],
      ["main thread", "render-in-worker=0", null],
      ["moved to the main thread", "render-in-worker=1", "window.__performanceDiagnostics = true"],
    ]) {
      const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
      const page = await context.newPage();
      const errors = [];
      page.on("pageerror", (error) => errors.push(String(error)));
      if (init) await page.addInitScript(init);
      // On the main thread the second module is needed before the start, so its request must not wait for the first one:
      // app.wasm is held until app-rest.wasm has been asked for (or 10 s).
      let restAsked = false, restAskedWhileHeld = null;
      if (label === "main thread") {
        await page.route(/\/app-rest(\.[0-9a-f]{8})?\.wasm$/, (route) => { restAsked = true; return route.continue(); });
        await page.route(/\/app(\.[0-9a-f]{8})?\.wasm$/, async (route) => {
          for (let waited = 0; waited < 100 && !restAsked; waited++) await new Promise((done) => setTimeout(done, 100));
          restAskedWhileHeld = restAsked;
          await route.continue();
        });
      }
      await page.goto(`${server.base}${route}${query ? `?${query}` : ""}`, { waitUntil: "domcontentloaded" });
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000, state: "attached" });
      // The rest arrives behind the first screen (the Worker), or before it (the main thread).
      await page.waitForFunction(async () => true);
      for (let tries = 0; tries < 100 && !(await marks(page)).length; tries++) await new Promise((done) => setTimeout(done, 100));
      const loaded = await marks(page);
      assert.ok(loaded.length >= 1, `${label}: app-rest.wasm was instantiated`);
      if (label === "main thread") assert.equal(restAskedWhileHeld, true, `${label}: app-rest.wasm was asked for while app.wasm was still on its way`);
      if (label === "worker") assert.ok(loaded.every((detail) => detail?.waited === false), `${label}: the first screen did not wait for app-rest.wasm`);
      if (label === "moved to the main thread") {
        await page.evaluate(() => window.__renderWorker.forceOverflow());
        // Any call carries the forced overflow: a resize of the window is one the app always handles.
        await page.setViewportSize({ width: 1100, height: 800 });
        await page.waitForFunction(() => window.__renderWorker.migrated === true, null, { timeout: 30_000 });
        // The Worker is gone; the mark is the main thread's own.
        const after = await page.evaluate(() => performance.getEntriesByName("swiftuiweb-app-rest").length);
        assert.ok(after >= 1, `${label}: the main thread loaded app-rest.wasm for the instance it adopted`);
        if (moved) assert.equal(await page.evaluate(([address, value]) => window.__renderWorker.holds(address, value), [moved.address, moved.value]), true, `${label}: the adopted memory holds the data app-rest.wasm carries`);
      }
      assert.deepEqual(errors, [], `${label}: no page error`);
      await context.close();
      console.log(`ok: split bundle, ${label}`);
    }
  } finally {
    await server.stop();
  }
}

await runSuite(async () => {
  const browser = await launch();
  try {
    await synthetic(browser);
    if (process.env.WASM_SPLIT_BUNDLE) await splitBundle(browser, resolve(process.env.WASM_SPLIT_BUNDLE));
  } finally {
    await browser.close();
  }
});
