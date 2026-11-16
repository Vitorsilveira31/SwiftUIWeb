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
//    (`?render-in-worker=0`), and after a move from the Worker to the main thread (the performance diagnostics'
//    forced overflow), it keeps working. WASM_SPLIT_ROUTE (default /) is the page it opens.
//
// Needs Binaryen (wasm-as, wasm-split); without it part 1 is skipped with a message.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { launch, runSuite, serveBundle, serveStatic, ROOT } from "./browser-test-support.mjs";

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

const PAGE = `<!doctype html><meta charset="utf-8"><script type="module">
import { createSplitLoader, isSplitModule } from './wasm-split-loader.js';
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
    copyFileSync(join(ROOT, "Tools/wasm-split-loader.js"), join(dir, "wasm-split-loader.js"));
    writeFileSync(join(dir, "index.html"), PAGE);
    writeFileSync(join(dir, "worker.js"), WORKER);
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
      await page.close();
      console.log("ok: a module split by wasm-split loads its second half in a Worker (waiting or in the background) and on the page");
    } finally {
      await server.stop();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

async function splitBundle(browser, bundle) {
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
      await page.goto(`${server.base}${route}${query ? `?${query}` : ""}`, { waitUntil: "domcontentloaded" });
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000, state: "attached" });
      // The rest arrives behind the first screen (the Worker), or before it (the main thread).
      await page.waitForFunction(async () => true);
      for (let tries = 0; tries < 100 && !(await marks(page)).length; tries++) await new Promise((done) => setTimeout(done, 100));
      const loaded = await marks(page);
      assert.ok(loaded.length >= 1, `${label}: app-rest.wasm was instantiated`);
      if (label === "worker") assert.ok(loaded.every((detail) => detail?.waited === false), `${label}: the first screen did not wait for app-rest.wasm`);
      if (label === "moved to the main thread") {
        await page.evaluate(() => window.__renderWorker.forceOverflow());
        // Any call carries the forced overflow: a resize of the window is one the app always handles.
        await page.setViewportSize({ width: 1100, height: 800 });
        await page.waitForFunction(() => window.__renderWorker.migrated === true, null, { timeout: 30_000 });
        // The Worker is gone; the mark is the main thread's own.
        const after = await page.evaluate(() => performance.getEntriesByName("swiftuiweb-app-rest").length);
        assert.ok(after >= 1, `${label}: the main thread loaded app-rest.wasm for the instance it adopted`);
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
