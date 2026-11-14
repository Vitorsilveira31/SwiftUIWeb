#!/usr/bin/env bun
// The direct build of the development profile `fast` (Tools/dev-direct-build.mjs) on a real build of Tests/Apps/MotionApp:
// after one `swift build -v` through the launcher, edits made in the lowered tree are compiled by replaying the recorded
// commands, the module that results holds them, and the saves the direct build does not know are handed back (status 3).
// The last step runs the launcher again: its lowering puts the tree back, and that save takes the direct build too.
// Run by `make direct-build-test`; builds into .build/direct-build-test.
import assert from "node:assert/strict";
import { appendFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { ROOT } from "./browser-test-support.mjs";
import { build, hotPaths, hotStatus, isBeneath, markHotFailed, moduleRoots, parseLog, splitCommand } from "./dev-direct-build.mjs";

// --- the folders of the modules and the state of a hot split, without a build ---------------------------------------------
assert.deepEqual(moduleRoots({ A: ["/p/Sources/A/x.swift", "/p/Sources/A/Sub/y.swift"] }), ["/p/Sources/A"]);
assert.deepEqual(moduleRoots({ A: ["/p/Sources/A/x.swift"] }), ["/p/Sources/A"], "a module of one file has its file's folder");
assert.deepEqual(moduleRoots({ A: ["/p/Sources/A/x.swift"], B: ["/p/Sources/A/Inner/b.swift"], C: [] }), ["/p/Sources/A"], "a root inside another is covered by it");
assert.ok(isBeneath("/p/Sources/A/New/z.swift", ["/p/Sources/A"]) && !isBeneath("/p/Sources/AB/z.swift", ["/p/Sources/A"]) && !isBeneath("/p/Tests/z.swift", ["/p/Sources/A"]));
{
  const hotCache = join(ROOT, ".build/direct-build-test-hot-state");
  rmSync(hotCache, { recursive: true, force: true });
  mkdirSync(join(hotCache, "hot"), { recursive: true });
  const paths = hotPaths(hotCache);
  writeFileSync(paths.main, "m"); writeFileSync(paths.side, "s");
  assert.equal(hotStatus({ cache: hotCache }), false, "no plan: not hot");
  // A split that was linked from older objects than the current ones (the builds since were ordinary) is not hot.
  writeFileSync(join(hotCache, "direct-build-plan.json"), JSON.stringify({ fingerprint: "f", generation: 2, linked: { hot: 1, ordinary: 2 }, hot: { ok: true, application: "App" } }));
  assert.equal(hotStatus({ cache: hotCache }), false, "a split behind the objects is not hot");
  writeFileSync(join(hotCache, "direct-build-plan.json"), JSON.stringify({ fingerprint: "f", generation: 2, linked: { hot: 2, ordinary: 1 }, hot: { ok: true, application: "App" } }));
  assert.equal(hotStatus({ cache: hotCache }), true);
  assert.equal(hotStatus({ cache: hotCache, fingerprint: "f" }), true);
  assert.equal(hotStatus({ cache: hotCache, fingerprint: "other" }), false, "a plan of other flags is not hot");
  rmSync(paths.side);
  assert.equal(hotStatus({ cache: hotCache }), false, "a missing module is not hot");
  writeFileSync(paths.side, "s");
  markHotFailed(hotCache, JSON.parse(readFileSync(join(hotCache, "direct-build-plan.json"), "utf8")), "the main module lacks symbols");
  assert.equal(hotStatus({ cache: hotCache }), false);
  assert.ok(!existsSync(paths.main) && !existsSync(paths.side), "a failed split leaves no module behind");
  const after = JSON.parse(readFileSync(join(hotCache, "direct-build-plan.json"), "utf8"));
  assert.deepEqual(after.hot, { ok: false, reason: "the main module lacks symbols" });
  rmSync(hotCache, { recursive: true, force: true });
}

// --- the log reader, without a build ----------------------------------------------------------------------------------
assert.deepEqual(splitCommand("a b\\ c  --export\\=x\nd"), ["a", "b c", "--export=x", "d"]);
{
  const log = [
    "SwiftDriver App normal wasm32 (in target 'App' from project 'P')",
    "    cd /work",
    "    builtin-SwiftDriver -- /t/swiftc -module-name App @/i/App.SwiftFileList -incremental -output-file-map /i/App-OutputFileMap.json -c",
    "Copy /p/Lib.swiftmodule/wasm32.swiftmodule /i/Lib.swiftmodule",
    "    cd /work",
    "    builtin-copy -exclude .git -resolve-src-symlinks -rename /i/Lib.swiftmodule /p/Lib.swiftmodule/wasm32.swiftmodule",
    "Ld /p/App.wasm normal",
    "    cd /work/tree",
    "    /t/swiftc -target wasm32-unknown-wasip1 -emit-executable -Xclang-linker -rdynamic -Xlinker --export\\=start @/i/App.LinkFileList -o /p/App.wasm warning: text printed after the command",
  ].join("\n");
  const parsed = parseLog(log);
  assert.deepEqual(Object.keys(parsed.modules), ["App"]);
  assert.equal(parsed.modules.App.cwd, "/work");
  assert.equal(parsed.modules.App.argv[0], "/t/swiftc");
  assert.deepEqual(parsed.copies, [{ from: "/i/Lib.swiftmodule", to: "/p/Lib.swiftmodule/wasm32.swiftmodule" }]);
  assert.deepEqual(parsed.link, { cwd: "/work/tree", argv: ["/t/swiftc", "-target", "wasm32-unknown-wasip1", "-emit-executable", "-Xlinker", "--export=start", "@/i/App.LinkFileList", "-o", "/p/App.wasm"] });
}

// --- a real build -----------------------------------------------------------------------------------------------------
const work = join(ROOT, ".build/direct-build-test");
const cache = join(work, "cache"), bundle = join(work, "browser/MotionApp/app.wasm");
const planCache = join(cache, "full-swift"), tree = join(planCache, "tree");
rmSync(work, { recursive: true, force: true });

function launcher(extra = {}) {
  const result = Bun.spawnSync(["/bin/bash", join(ROOT, "Tools/run-browser.sh"), "motion"], {
    cwd: ROOT, stdout: "pipe", stderr: "pipe",
    env: { ...process.env, SWIFTUIWEB_DEV_PROFILE: "fast", CONFIGURATION: "debug", BUILD_ONLY: "1", SWIFTUIWEB_DEV_CACHE: cache, SWIFTUIWEB_BUNDLE_ROOT: join(work, "browser"), ...extra },
  });
  const output = result.stdout.toString() + result.stderr.toString();
  assert.equal(result.exitCode, 0, output.slice(-3000));
  return output;
}
const plan = () => JSON.parse(readFileSync(join(planCache, "direct-build-plan.json"), "utf8"));
const holds = (path, text) => readFileSync(path).includes(text);
const edit = (relative, change) => { const path = join(tree, relative); const before = readFileSync(path, "utf8"); const after = change(before); assert.notEqual(after, before, relative); writeFileSync(path, after); };
const direct = (treeChanges) => build({ cache: planCache, fingerprint: plan().fingerprint, treeChanges });
const stepNames = (result) => result.steps.map(([name]) => name);

const first = launcher();
const known = first.match(/Direct build: the commands of (\d+) of (\d+) modules are known/);
assert.ok(known, "the first build records its commands");
assert.equal(known[1], known[2], "a clean build prints every module's command");
const product = plan().link.argv.at(-1);

// Nothing changed: nothing compiles.
{
  const result = await direct(0);
  assert.equal(result.status, 0);
  assert.equal(result.nothing, true);
}

// An application file: its module and the link, nothing else.
const APP = "Tests/Apps/MotionApp/MotionRootView.swift";
edit(APP, (text) => text.replace('Button("Add")', 'Button("zz-direct-app-edit")'));
{
  const result = await direct(1);
  assert.equal(result.status, 0, result.output);
  assert.deepEqual(stepNames(result), ["MotionApp", "link"]);
  assert.ok(holds(product, "zz-direct-app-edit"), "the linked module holds the edit");
}

// A staged package gives the list of files its sync wrote instead of a count. A Swift file that no module compiles (the
// second copy of a package that lives in the framework's repository) does not stop the direct build; a manifest or a
// file that is not Swift does.
{
  const listed = (files) => build({ cache: planCache, fingerprint: plan().fingerprint, treeChanges: files.length, changedFiles: files });
  edit(APP, (text) => text.replace("zz-direct-app-edit", "zz-direct-app-list"));
  assert.equal((await listed([join(tree, APP), join(tree, "Package.swift")])).status, 3);
  assert.equal((await listed([join(tree, APP), join(tree, "Tools/styles.css")])).status, 3);
  const result = await listed([join(tree, APP), join(tree, "Tests/ConsumerRegression/Sources/ConsumerRegression/main.swift")]);
  assert.equal(result.status, 0, result.output);
  assert.deepEqual(stepNames(result), ["MotionApp", "link"]);
  assert.ok(holds(product, "zz-direct-app-list"));
}

// A framework function body: the library, and the link reads the library's new object.
const CORE = "Sources/SwiftUIWebCore/KeyEquivalent.swift";
edit(CORE, (text) => text.replace("public init(_ character: Character) { self.character = character }", 'public init(_ character: Character) { self.character = character; _ = "zz-direct-core-body" }'));
{
  const result = await direct(1);
  assert.equal(result.status, 0, result.output);
  assert.equal(stepNames(result)[0], "SwiftUIWebCore");
  assert.equal(stepNames(result).at(-1), "link");
  assert.ok(holds(product, "zz-direct-core-body"), "the link read the library's new object");
}

// A new public function of the framework, used by the application in the same save: the modules between them see it.
appendFileSync(join(tree, CORE), '\npublic func zzDirectProbe() -> String { "zz-direct-interface" }\n');
edit(APP, (text) => text.replace('Text("Box")', "Text(verbatim: zzDirectProbe())"));
{
  const result = await direct(2);
  assert.equal(result.status, 0, result.output);
  assert.ok(stepNames(result).indexOf("SwiftUIWebCore") < stepNames(result).indexOf("MotionApp"));
  assert.ok(holds(product, "zz-direct-interface"));
}

// A library whose interface changed is published before the application that no longer compiles against it fails. The
// retry finds the library's interface as it left it, and still owes the application its compile: it does not link the
// application's old objects and call that a build.
edit(CORE, (text) => text.replace("func zzDirectProbe()", "func zzDirectRenamed()"));
for (const attempt of ["first", "retry"]) {
  const result = await direct(1);
  assert.equal(result.status, 1, `${attempt}: ${stepNames(result)}`);
  assert.equal(result.failed, "MotionApp", attempt);
  assert.match(result.output, /error: .*zzDirectProbe/);
}
edit(APP, (text) => text.replace("zzDirectProbe()", "zzDirectRenamed()"));
{
  const result = await direct(2);
  assert.equal(result.status, 0, result.output);
  assert.ok(stepNames(result).includes("MotionApp"));
  assert.equal(plan().owed, undefined, "a build that finished owes nothing");
}

// A compile error is the compiler's, with its output.
edit(APP, (text) => text.replace("Text(verbatim: zzDirectRenamed())", "Text(verbatim: zzDirectMissing())"));
{
  const result = await direct(1);
  assert.equal(result.status, 1);
  assert.equal(result.failed, "MotionApp");
  assert.match(result.output, /MotionRootView\.swift:\d+:\d+: .*error: .*zzDirectMissing/);
}

// Saves the direct build hands back.
{
  // More files changed in the tree than Swift sources it found: one of them is not its to compile.
  assert.equal((await direct(2)).status, 3);
  // The lowering did not report what it changed.
  assert.equal((await direct(null)).status, 3);
  // Another set of flags.
  assert.equal((await build({ cache: planCache, fingerprint: "other", treeChanges: 1 })).status, 3);
  // A new file in a folder no module had a source in: it is beneath the application's folder, so SwiftPM would compile it.
  // The count path and the list path both hand it back.
  const folder = join(tree, "Tests/Apps/MotionApp/ZZDirectNewFolder", "Deeper");
  mkdirSync(folder, { recursive: true });
  const deep = join(folder, "ZZDeep.swift");
  writeFileSync(deep, "let zzDeep = 1\n");
  for (const result of [await direct(1), await build({ cache: planCache, fingerprint: plan().fingerprint, treeChanges: 1, changedFiles: [deep] })]) {
    assert.equal(result.status, 3);
    assert.match(result.reason, /ZZDeep\.swift is new/);
  }
  // A Swift file outside every module's folders is still no one's (the ConsumerRegression copy is accepted above).
  rmSync(join(tree, "Tests/Apps/MotionApp/ZZDirectNewFolder"), { recursive: true, force: true });
  // A new source file.
  const added = join(tree, "Tests/Apps/MotionApp/ZZDirectNew.swift");
  writeFileSync(added, "let zzDirectNew = 1\n");
  const result = await direct(1);
  assert.equal(result.status, 3);
  assert.match(result.reason, /is new/);
}

// The launcher again: the lowering puts the tree back (the application file, the framework file, and the new file goes),
// which is a set of changes the direct build cannot take (a removed file), so `swift build` runs and records again; a
// save after it takes the direct build through the launcher.
launcher();
assert.ok(!holds(bundle, "zz-direct-app-edit") && !holds(bundle, "zz-direct-interface"), "the bundle is the sources' again");
edit(APP, (text) => text.replace('Button("Add")', 'Button("zz-direct-app-edit")'));
{
  const output = launcher();
  assert.match(output, /Direct build: MotionApp [\d.]+ s, link [\d.]+ s/, output.slice(-2000));
  assert.doesNotMatch(output, /Build complete!/);
  assert.ok(!holds(bundle, "zz-direct-app-edit"), "the lowering restored the source, and the direct build compiled it");
  assert.ok(existsSync(join(planCache, "last-build.stamp")), "a direct build leaves the stamp a build leaves");
  assert.match(output, /Bundle ready: .*MotionApp\n/, "without the watcher's word that only Swift was saved, the whole bundle is written");
}

// When the watcher says only Swift sources were saved, the direct build's module replaces app.wasm in the bundle and the
// other bundle steps are skipped; the page files the last build wrote stay.
edit(APP, (text) => text.replace('Button("Add")', 'Button("zz-direct-app-edit")'));
{
  const index = readFileSync(join(work, "browser/MotionApp/index.html"), "utf8");
  const output = launcher({ SWIFTUIWEB_WATCH_SWIFT_ONLY: "1" });
  assert.match(output, /Direct build: MotionApp/);
  assert.match(output, /\(app\.wasm replaced\)/);
  assert.doesNotMatch(output, /Generated stylesheet/);
  assert.equal(readFileSync(join(work, "browser/MotionApp/index.html"), "utf8"), index);
  assert.ok(Buffer.compare(readFileSync(bundle), readFileSync(product)) === 0, "the bundle holds the module the direct build linked");
}

console.log("PASS direct build: recorded commands compile an app edit, a library edit and an interface change, errors are the compiler's, and unknown saves go back to swift build");
