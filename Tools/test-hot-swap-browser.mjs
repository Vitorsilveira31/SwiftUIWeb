#!/usr/bin/env bun
// Hot swap in a real browser (Tests/Apps/MotionApp, development profile fast, SWIFTUIWEB_HOT_SWAP=1): the launcher links the
// product as a main module and a side module, the page starts from the two, and an application edit compiled and linked
// as a new side module is loaded into the running page, which starts the application again in place: the page is the
// same page, the edit shows, the plain state is kept and the application keeps working. A framework edit changes the main
// module, which is a reload.
// Run by `make hot-swap-browser-test`; builds into .build/hot-swap-test. Chromium (the profile fast's engine).
import assert from "node:assert/strict";
import { copyFileSync, existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { build, hotPaths, hotStatus, markHotFailed } from "./dev-direct-build.mjs";
import { isHotMainModule, relativeFields } from "./side-module.js";
import { existsSync as exists } from "node:fs";

const work = join(ROOT, ".build/hot-swap-test");
const cache = join(work, "cache"), planCache = join(cache, "full-swift"), tree = join(planCache, "tree");
const bundle = join(work, "browser/MotionApp");
const APP = "Tests/Apps/MotionApp/MotionRootView.swift", CORE = "Sources/SwiftUIWebCore/KeyEquivalent.swift";

await runSuite(async () => {
  rmSync(work, { recursive: true, force: true });
  const launched = Bun.spawnSync(["/bin/bash", join(ROOT, "Tools/run-browser.sh"), "motion"], {
    cwd: ROOT, stdout: "pipe", stderr: "pipe",
    env: { ...process.env, SWIFTUIWEB_HOT_SWAP: "1", SWIFTUIWEB_LIVE_LITERALS: "1", SWIFTUIWEB_DEV_PROFILE: "fast", CONFIGURATION: "debug", BUILD_ONLY: "1", SWIFTUIWEB_DEV_CACHE: cache, SWIFTUIWEB_BUNDLE_ROOT: join(work, "browser") },
  });
  const output = launched.stdout.toString() + launched.stderr.toString();
  assert.equal(launched.exitCode, 0, output.slice(-3000));
  assert.match(output, /Hot swap: the application is a side module/);

  // The bundle: a main module without the application's entry, and the application as a side module.
  const mainModule = new WebAssembly.Module(readFileSync(join(bundle, "app.wasm")));
  assert.ok(isHotMainModule(mainModule), "app.wasm is the main module");
  const sideBytes = new Uint8Array(readFileSync(join(bundle, "app-side.wasm")));
  const sideModule = new WebAssembly.Module(sideBytes);
  assert.equal(WebAssembly.Module.customSections(sideModule, "dylink.0").length, 1, "app-side.wasm is a side module");
  assert.ok(WebAssembly.Module.exports(sideModule).some((entry) => entry.name === "embedded_browser_start"));
  assert.ok(relativeFields(sideBytes).length > 0, "the linker kept the relocations the loader reads");
  assert.ok(exists(join(bundle, "side-module.js")), "a hot bundle carries the loader");
  assert.ok(!readFileSync(join(bundle, "index.js"), "utf8").includes("dylink.0"), "and the runtime itself does not");

  const plan = () => JSON.parse(readFileSync(join(planCache, "direct-build-plan.json"), "utf8"));
  const edit = (relative, change) => { const path = join(tree, relative); const before = readFileSync(path, "utf8"); const after = change(before); assert.notEqual(after, before, relative); writeFileSync(path, after); };
  // The tree holds the lowered sources, where each literal of the application is `_live(id, literal)`. An edit of the
  // application is written as in the source (`from` and `to` with the same literals in the same order) and keeps the
  // identifiers, as the lowering does for an edit that adds no literal.
  const literal = /("(?:[^"\\]|\\.)*")/;
  const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const lowered = (text, from, to) => {
    const match = new RegExp(from.split(literal).map((part, index) => index % 2 ? `_live\\((\\d+), ${escape(part)}\\)` : escape(part)).join("")).exec(text);
    if (!match) return text;
    const ids = match.slice(1);
    const written = to.split(literal).map((part, index) => index % 2 ? `_live(${ids[(index - 1) / 2]}, ${part})` : part).join("");
    return text.slice(0, match.index) + written + text.slice(match.index + match[0].length);
  };
  const editApp = (...pairs) => edit(APP, (text) => pairs.reduce((result, [from, to]) => lowered(result, from, to), text));
  const liveId = (code) => new RegExp(`${escape(code).replace(/"(.*)"/, (_, value) => `_live\\((\\d+), "${value}"\\)`)}`).exec(readFileSync(join(tree, APP), "utf8"))?.[1];
  const rebuild = (treeChanges) => build({ cache: planCache, fingerprint: plan().fingerprint, treeChanges, hot: true });

  const server = await serveBundle({ bundle, port: await freePort() });
  const browser = await launch({ engine: "chromium" });
  try {
    const page = await (await browser.newContext({ viewport: { width: 800, height: 900 } })).newPage();
    const problems = [];
    page.on("pageerror", (error) => problems.push(String(error)));
    page.on("console", (message) => { if (message.type() === "error") problems.push(message.text()); });
    await page.goto(`${server.base}/`);
    await page.waitForSelector('[data-testid="row-1"]');
    const rows = () => page.evaluate(() => document.querySelectorAll('[data-testid^="row-"]').length);
    const label = () => page.evaluate(() => document.querySelector('[data-testid="add"]')?.textContent);
    const initial = await rows();
    await page.click('[data-testid="add"]');
    await page.click('[data-testid="add"]');
    await page.waitForFunction((count) => document.querySelectorAll('[data-testid^="row-"]').length === count, initial + 2);
    await page.evaluate(() => { window.__samePage = "kept"; });

    // An application edit that is not a literal's value (a new modifier, a new label): the side module alone is linked.
    editApp(['Button("Add")', 'Button("Add hot")'], ['.accessibilityIdentifier("add")', '.bold().accessibilityIdentifier("add")']);
    const built = await rebuild(1);
    assert.equal(built.status, 0, built.output);
    assert.equal(built.hot, "side");
    assert.deepEqual(built.steps.map(([name]) => name), ["MotionApp", "side module"]);
    copyFileSync(hotPaths(planCache).side, join(bundle, "app-side.wasm"));
    assert.equal(await page.evaluate(() => globalThis.__swiftuiwebSwap(new URL("app-side.wasm", document.baseURI).href)), true);
    await page.waitForFunction(() => document.querySelector('[data-testid="add"]')?.textContent === "Add hot");
    assert.equal(await page.evaluate(() => window.__samePage), "kept", "the page did not reload");
    assert.equal(await rows(), initial + 2, "the rows added before the swap are still there");
    // The application the page runs now is the new one, and it works: its button adds a row.
    await page.click('[data-testid="add"]');
    await page.waitForFunction((count) => document.querySelectorAll('[data-testid^="row-"]').length === count, initial + 3);

    // A second swap on top of the first.
    editApp(['Button("Add hot")', 'Button("Add again")'], ['.bold().accessibilityIdentifier("add")', '.accessibilityIdentifier("add")']);
    const again = await rebuild(1);
    assert.equal(again.status, 0, again.output);
    copyFileSync(hotPaths(planCache).side, join(bundle, "app-side.wasm"));
    assert.equal(await page.evaluate(() => globalThis.__swiftuiwebSwap(new URL("app-side.wasm", document.baseURI).href)), true);
    await page.waitForFunction(() => document.querySelector('[data-testid="add"]')?.textContent === "Add again");
    assert.equal(await page.evaluate(() => window.__samePage), "kept");
    assert.equal(await rows(), initial + 3);

    // Live literals, then a swap. A literal-only save gives the running framework module a replacement; the next save
    // changes the same label again along with the structure, and the swapped application shows the compiled value, not
    // the replacement the page held for the module before it.
    const id = liveId('Button("Add again")');
    assert.ok(id, "the label is a live literal");
    const replaced = `${id}\ts\tAdd live`;
    assert.ok(await page.evaluate((text) => window.__swiftuiwebLiveLiterals(text), replaced) > 0);
    await page.waitForFunction(() => document.querySelector('[data-testid="add"]')?.textContent === "Add live");
    editApp(['Button("Add again")', 'Button("Add swapped")'], ['.accessibilityIdentifier("add")', '.bold().accessibilityIdentifier("add")']);
    const structural = await rebuild(1);
    assert.equal(structural.status, 0, structural.output);
    copyFileSync(hotPaths(planCache).side, join(bundle, "app-side.wasm"));
    assert.equal(await page.evaluate(() => globalThis.__swiftuiwebSwap(new URL("app-side.wasm", document.baseURI).href)), true);
    await page.waitForFunction(() => document.querySelector('[data-testid="add"]')?.textContent === "Add swapped");
    assert.equal(await rows(), initial + 3);
    editApp(['Button("Add swapped")', 'Button("Add again")'], ['.bold().accessibilityIdentifier("add")', '.accessibilityIdentifier("add")']);
    assert.equal((await rebuild(1)).status, 0);
    assert.deepEqual(problems, []);

    // A framework edit is in the main module: both are linked, and the page that runs the old main module must reload.
    edit(CORE, (text) => text.replace("public init(_ character: Character) { self.character = character }", 'public init(_ character: Character) { self.character = character; _ = "zz-hot-core" }'));
    const framework = await rebuild(1);
    assert.equal(framework.status, 0, framework.output);
    assert.equal(framework.hot, "main");
    assert.ok(readFileSync(hotPaths(planCache).main).includes("zz-hot-core"));

    // A change of mode with nothing saved. The hot builds above linked the two modules and left the ordinary executable
    // as it was, so a build without hot swap links it (and compiles nothing); the split stays current, so going back
    // links nothing. After an ordinary build of an edit the split is behind, and a hot build links both modules again.
    const ordinary = plan().link.argv.at(-1);
    assert.ok(!readFileSync(ordinary).includes("Add again"), "the ordinary executable is behind the hot builds");
    const left = await build({ cache: planCache, fingerprint: plan().fingerprint, treeChanges: 0, hot: false });
    assert.equal(left.status, 0, left.output);
    assert.deepEqual(left.steps.map(([name]) => name), ["link"]);
    assert.ok(readFileSync(ordinary).includes("Add again"), "leaving hot swap links the ordinary executable from the current objects");
    const back = await rebuild(0);
    assert.equal(back.status, 0);
    assert.equal(back.nothing, true, "the split was current");
    editApp(['Button("Add again")', 'Button("Add ordinary")']);
    const plainEdit = await build({ cache: planCache, fingerprint: plan().fingerprint, treeChanges: 1, hot: false });
    assert.deepEqual(plainEdit.steps.map(([name]) => name), ["MotionApp", "link"]);
    assert.equal(hotStatus({ cache: planCache }), false, "the split is behind an ordinary build");
    const caughtUp = await rebuild(0);
    assert.equal(caughtUp.status, 0, caughtUp.output);
    assert.deepEqual(caughtUp.steps.map(([name]) => name), ["main module", "side module"]);
    assert.ok(readFileSync(hotPaths(planCache).side).includes("Add ordinary"));
    assert.equal(hotStatus({ cache: planCache }), true);

    // The launcher bundles the split only when the plan says it is valid now. After a split is refused (a check that runs
    // after both files were written), the status says so, the files are gone, and the next build links one module.
    const status = () => Bun.spawnSync(["bun", join(ROOT, "Tools/dev-direct-build.mjs"), "hot-status", "--cache", planCache, "--fingerprint", plan().fingerprint]).exitCode;
    assert.equal(hotStatus({ cache: planCache }), true);
    assert.equal(status(), 0, "a valid split is hot");
    markHotFailed(planCache, plan(), "the main module lacks 1 symbol(s) the application uses (test)");
    assert.equal(status(), 1, "a refused split is not hot");
    assert.ok(!existsSync(hotPaths(planCache).main) && !existsSync(hotPaths(planCache).side), "its modules are deleted");
    assert.equal(plan().hot.ok, false);
    editApp(['Button("Add ordinary")', 'Button("Add last")']);
    const single = await rebuild(1);
    assert.equal(single.status, 0, single.output);
    assert.equal(single.hot, undefined, "a plan that is not hot links the ordinary module");
    assert.deepEqual(single.steps.map(([name]) => name), ["MotionApp", "link"]);
    assert.equal(status(), 1, "and it stays not hot");
    assert.ok(!existsSync(hotPaths(planCache).main), "without writing the split again");
    await page.close();
  } finally {
    await browser.close();
    await server.stop();
  }
  // A save through the launcher, as the watcher makes it: the lowering puts the tree back, the application and the
  // framework compile, and the launcher says which module the bundle got.
  assert.ok(existsSync(join(bundle, "app-side.wasm")));
  console.log("PASS hot swap: an application edit is loaded into the running page, which keeps its state and keeps working; a framework edit relinks the main module");
});
