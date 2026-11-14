#!/usr/bin/env bun
// Tools/bundle-reuse.mjs: the key follows what a build reads and nothing else, and a stamped bundle is reused only while
// its inputs and its own bytes are unchanged.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { inputsKey, isReusable, restore, stamp } from "./bundle-reuse.mjs";

const ENV = { CONFIGURATION: "release", PATH: process.env.PATH };

function repository(files) {
  const root = mkdtempSync(join(tmpdir(), "bundle-reuse-"));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  assert.equal(spawnSync("git", ["init", "-q"], { cwd: root }).status, 0);
  assert.equal(spawnSync("git", ["add", "-A"], { cwd: root }).status, 0);
  return root;
}

const tests = [
  ["a source edit changes the key", (root) => {
    const before = inputsKey("showcase", ENV, root);
    writeFileSync(join(root, "Sources/A/A.swift"), "let a = 2\n");
    assert.notEqual(inputsKey("showcase", ENV, root), before);
  }],
  ["an untracked source file changes the key", (root) => {
    const before = inputsKey("showcase", ENV, root);
    writeFileSync(join(root, "Sources/A/New.swift"), "let b = 1\n");
    assert.notEqual(inputsKey("showcase", ENV, root), before);
  }],
  ["a test, a document or another example name", (root) => {
    const before = inputsKey("showcase", ENV, root);
    writeFileSync(join(root, "Tools/test-a.mjs"), "// changed\n");
    writeFileSync(join(root, "Tools/README.md"), "changed\n");
    assert.equal(inputsKey("showcase", ENV, root), before, "tests and documents are not build inputs");
    assert.notEqual(inputsKey("lumio", ENV, root), before, "another example is another bundle");
  }],
  ["build settings change the key, test switches do not", (root) => {
    const before = inputsKey("showcase", ENV, root);
    assert.notEqual(inputsKey("showcase", { ...ENV, CONFIGURATION: "debug" }, root), before);
    assert.notEqual(inputsKey("showcase", { ...ENV, SWIFTUIWEB_FIRST_PAINT: "1" }, root), before);
    assert.notEqual(inputsKey("showcase", { ...ENV, WASM_OPT: "0" }, root), before, "Binaryen settings change the release bundle");
    assert.notEqual(inputsKey("showcase", { ...ENV, WASM_OPT_ONE_CALLER_INLINE_MAX_SIZE: "40" }, root), before);
    assert.equal(inputsKey("showcase", { ...ENV, SWIFTUIWEB_BROWSER_ENGINE: "webkit" }, root), before);
  }],
  ["a stamped bundle is reused until it or its inputs change", (root) => {
    const bundle = join(root, ".build/browser/ShowcaseApp");
    mkdirSync(bundle, { recursive: true });
    writeFileSync(join(bundle, "app.wasm"), "wasm");
    writeFileSync(join(bundle, "index.html"), "<html>");
    const key = inputsKey("showcase", ENV, root);
    assert.equal(isReusable(bundle, key), false, "no stamp yet");
    stamp(bundle, key);
    assert.equal(isReusable(bundle, key), true);
    assert.equal(isReusable(bundle, "another-key"), false);
    writeFileSync(join(bundle, "index.html"), "<html><!-- edited -->");
    assert.equal(isReusable(bundle, key), false, "a bundle changed after its build is built again");
  }],
  ["a release bundle, whose module name carries its hash, is reused too", (root) => {
    const bundle = join(root, ".build/browser/ReleaseApp");
    mkdirSync(bundle, { recursive: true });
    writeFileSync(join(bundle, "app.3f9a1c2e.wasm"), "wasm");
    const key = inputsKey("release", ENV, root);
    stamp(bundle, key);
    assert.equal(isReusable(bundle, key), true);
  }],
  ["a configuration built earlier into the same folder comes back from the cache", (root) => {
    const bundle = join(root, ".build/browser/LoweringApp");
    const cacheRoot = join(root, ".build/bundle-cache");
    const build = (body) => {
      rmSync(bundle, { recursive: true, force: true });
      mkdirSync(bundle, { recursive: true });
      writeFileSync(join(bundle, "app.wasm"), body);
    };
    build("release");
    stamp(bundle, "release-key", { cacheRoot });
    build("debug");
    stamp(bundle, "debug-key", { cacheRoot });
    assert.equal(isReusable(bundle, "release-key"), false, "the folder holds the debug build now");
    assert.equal(restore(bundle, "release-key", { cacheRoot }), true);
    assert.equal(readFileSync(join(bundle, "app.wasm"), "utf8"), "release");
    assert.equal(isReusable(bundle, "release-key"), true);
    assert.equal(restore(bundle, "never-built", { cacheRoot }), false);
    writeFileSync(join(cacheRoot, "LoweringApp", "debug-key", "app.wasm"), "tampered");
    assert.equal(restore(bundle, "debug-key", { cacheRoot }), false, "a damaged copy is not restored");
  }],
];

let failed = 0;
for (const [name, body] of tests) {
  const root = repository({
    "Sources/A/A.swift": "let a = 1\n",
    "Tools/host.js": "export {}\n",
    "Tools/test-a.mjs": "// test\n",
    "Tools/README.md": "docs\n",
    "Package.swift": "// manifest\n",
  });
  try {
    body(root);
    console.log(`ok - ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`not ok - ${name}\n${error.message}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
if (failed) process.exit(1);
