#!/usr/bin/env bun
"use strict";

const fs = require("fs");

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) throw new Error(`Missing ${name}`);
  return process.argv[index + 1];
}

const indexPath = argument("--index");
const manifestPath = argument("--manifest");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
// `runtime.lazy` files are copied into the release bundle for dynamic
// `import()` activation, but must not be script tags in the bootstrap HTML.
// Keeping them here would turn an optional provider/helper into an initial
// transfer despite the reachability manifest classifying it as lazy.
const files = new Set([...(manifest.runtime?.initial || [])]);
if (manifest.icons?.asset) files.add(manifest.icons.asset);

let html = fs.readFileSync(indexPath, "utf8");
for (const asset of [
  "feature-loader.js",
  "image-pipeline.js",
  "avfoundation.js",
  "mesh-gradient.js",
  "icon-adapter.js"
]) {
  if (files.has(asset)) continue;
  const escaped = asset.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  html = html.replace(new RegExp(`^\\s*<script[^>]+${escaped}[^>]*></script>\\s*\\n?`, "gm"), "");
}

// The Swift side runs in a Worker unless the page opts out (`?render-in-worker=0`,
// `window.__renderWorker = false`). Without a hint the worker script only starts
// downloading after index.js has been fetched and evaluated, so announce it next to
// the runtime module. `--no-worker` (or `runtime.worker: false` in the manifest)
// builds a main-thread-only page that never requests it.
const workerActive = !process.argv.includes("--no-worker") && manifest.runtime?.worker !== false;
const workerPreload = '<link rel="modulepreload" href="./render-worker.js">';
if (workerActive && !html.includes(workerPreload)) {
  const runtimePreload = /^([ \t]*)<link rel="modulepreload" href="\.\/index\.js">[ \t]*\n/m;
  if (runtimePreload.test(html)) html = html.replace(runtimePreload, (line, indent) => line + indent + workerPreload + "\n");
}
fs.writeFileSync(indexPath, html);
