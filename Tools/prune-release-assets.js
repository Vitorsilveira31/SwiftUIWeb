#!/usr/bin/env bun
/*
 * Apply a release reachability manifest to an already generated browser
 * artifact. Swift/LLVM remains responsible for Swift symbol DCE; this pass
 * removes browser-side helpers and static assets that are proven absent from
 * the application graph. Unknown JavaScript/WASM files are retained.
 */
"use strict";

const fs = require("fs");
const path = require("path");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const bundleArgument = argument("--bundle");
if (!bundleArgument) throw new Error("Missing --bundle");
const bundle = path.resolve(bundleArgument);
const manifestPath = path.resolve(argument("--manifest", path.join(bundle, "release-manifest.json")));
const dryRun = process.argv.includes("--dry-run");

if (!bundle || bundle === path.parse(bundle).root || !fs.existsSync(bundle) || !fs.statSync(bundle).isDirectory()) {
  throw new Error("--bundle must point to an existing non-root browser artifact directory");
}
if (!fs.existsSync(manifestPath)) throw new Error(`Reachability manifest not found: ${manifestPath}`);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

const knownHelpers = new Set([
  "feature-loader.js",
  "image-pipeline.js",
  "avfoundation.js",
  "shaka-loader.js",
  "mesh-gradient.js",
  "icon-adapter.js"
]);
const reachableHelpers = new Set([
  ...(manifest.runtime?.initial || []),
  ...(manifest.runtime?.lazy || [])
]);
if (manifest.icons?.asset) reachableHelpers.add(manifest.icons.asset);

const reachableAssets = new Set(manifest.assets?.retain || []);
for (const entry of manifest.assets?.files || []) {
  if (entry && typeof entry.destination === "string") reachableAssets.add(entry.destination.replaceAll("\\", "/"));
}
const dynamicAssets = manifest.assets?.dynamic === true ||
  manifest.assets?.proof?.dynamicReferenceDetected === true ||
  manifest.proof?.dynamicAssets === true;
// New manifests carry the complete candidate set discovered under the
// application/framework asset roots. Only those candidates may be removed;
// generated metadata or an opaque JSON/config file outside that set remains
// untouched. Empty/legacy manifests intentionally disable asset deletion
// rather than guessing a closed world.
const candidateAssets = new Set((manifest.assets?.candidates || []).map(value => String(value).replaceAll("\\", "/")));
const candidateProofComplete = manifest.assets?.proof?.complete === true ||
  manifest.proof?.safeToPruneUnlistedAssets === true;

function walk(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(file));
    else if (entry.isFile()) files.push(file);
  }
  return files;
}

function isStaticAsset(relative) {
  return /\.(?:png|jpe?g|gif|webp|avif|svg|woff2?|ttf|otf|json|worker\.js|js|css)$/i.test(relative);
}

// Keep the generated browser module graph, metadata required by the
// bootstrap, and reports used by CI. Only known helpers and static assets are
// candidates for deletion; an unfamiliar file is never guessed to be dead.
const alwaysKeep = new Set([
  "index.html",
  "index.js",
  "instantiate.js",
  "instantiate.d.ts",
  "runtime.js",
  "runtime.d.ts",
  "package.json",
  "release-manifest.json",
  "release-size.json",
  "styles.css",
  "features-manifest.json"
]);
const removed = [];
for (const file of walk(bundle)) {
  const relative = path.relative(bundle, file).replaceAll(path.sep, "/");
  if (alwaysKeep.has(relative) || relative.startsWith("platforms/") || relative.startsWith("features/")) continue;
  const basename = path.basename(relative);
  let shouldRemove = false;
  if (knownHelpers.has(basename) && !reachableHelpers.has(basename)) shouldRemove = true;
  const isProvenCandidate = candidateProofComplete && candidateAssets.size > 0 &&
    (candidateAssets.has(relative) ||
      (!relative.includes("/") && candidateAssets.has(basename)));
  if (!dynamicAssets && isProvenCandidate && isStaticAsset(relative) &&
      !reachableAssets.has(relative) && !reachableAssets.has(basename)) shouldRemove = true;
  if (!shouldRemove) continue;
  removed.push(relative);
  if (!dryRun) fs.rmSync(file);
}

for (const directory of ["features", "optional", "chunks"]) {
  const candidate = path.join(bundle, directory);
  if (fs.existsSync(candidate) && !fs.readdirSync(candidate).length && !dryRun) fs.rmdirSync(candidate);
}

console.log(JSON.stringify({
  bundle,
  dryRun,
  dynamicAssets,
  candidateProofComplete,
  candidateAssets: [...candidateAssets].sort(),
  keptHelpers: [...reachableHelpers].sort(),
  keptAssets: [...reachableAssets].sort(),
  removed
}, null, 2));
