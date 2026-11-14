#!/usr/bin/env bun
/* The release index rewrite: worker preload, deferred classic helpers, unreachable helpers removed. */
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const REWRITE = path.join(ROOT, "Tools", "rewrite-release-index.js");
const TEMPLATE = fs.readFileSync(path.join(ROOT, "Tools", "browser-index.html"), "utf8");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "swui-index-"));

function rewrite(manifest, extra = [], source = TEMPLATE) {
  const index = path.join(temporary, "index.html"), manifestPath = path.join(temporary, "manifest.json");
  fs.writeFileSync(index, source);
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));
  const result = spawnSync(process.execPath, [REWRITE, "--index", index, "--manifest", manifestPath, ...extra], { encoding: "utf8" });
  assert.strictEqual(result.status, 0, result.stderr);
  return fs.readFileSync(index, "utf8");
}
const count = (text, needle) => text.split(needle).length - 1;
const classicOrder = (html) => [...html.matchAll(/<script(?![^>]*type="module")[^>]*src="\.\/([^"]+)"/g)].map((match) => match[1]);

try {
  const everything = rewrite({ runtime: { initial: ["feature-loader.js", "icon-adapter.js", "mesh-gradient.js"] }, icons: { asset: "icon-adapter.js" } });
  // 1. The worker script is announced next to the runtime module, once.
  assert.strictEqual(count(everything, '<link rel="modulepreload" href="./render-worker.js">'), 1, "worker modulepreload missing or duplicated");
  assert.ok(everything.indexOf('href="./index.js"') < everything.indexOf('href="./render-worker.js"'), "worker preload must follow the runtime preload");
  // Running the rewrite again must not add a second hint.
  const again = rewrite({ runtime: { initial: [] } }, [], everything);
  assert.strictEqual(count(again, 'href="./render-worker.js"'), 1, "the worker preload is not idempotent");
  // 2. Every classic helper is deferred and keeps the order feature-loader -> icons -> mesh-gradient -> module.
  assert.deepStrictEqual(classicOrder(everything), ["feature-loader.js", "icon-adapter.js", "mesh-gradient.js"]);
  for (const helper of classicOrder(everything)) assert.match(everything, new RegExp(`<script defer src="\\./${helper.replace(".", "\\.")}"></script>`), `${helper} is not deferred`);
  assert.ok(everything.lastIndexOf('src="./mesh-gradient.js"') < everything.indexOf('<script type="module">'), "the module must come after the deferred helpers");
  // 3. Helpers the manifest does not list are removed, deferred or not.
  const textOnly = rewrite({ runtime: { initial: [] } });
  assert.deepStrictEqual(classicOrder(textOnly), [], "unreachable helpers were left in the page");
  assert.ok(textOnly.includes('<script type="module">'), "the bootstrap module was removed");
  const partial = rewrite({ runtime: { initial: ["feature-loader.js"] }, icons: { asset: "icon-adapter.js" } });
  assert.deepStrictEqual(classicOrder(partial), ["feature-loader.js", "icon-adapter.js"]);
  // 4. A main-thread-only build never requests the worker.
  assert.strictEqual(count(rewrite({ runtime: { initial: [] } }, ["--no-worker"]), "render-worker.js"), 0, "--no-worker still preloads the worker");
  assert.strictEqual(count(rewrite({ runtime: { initial: [], worker: false } }), "render-worker.js"), 0, "runtime.worker=false still preloads the worker");
  console.log("release index rewrite: ok");
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
