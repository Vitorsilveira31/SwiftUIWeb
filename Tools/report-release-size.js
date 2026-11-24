#!/usr/bin/env bun
/* Report the transfer-sized release graph. This intentionally counts each
 * file independently because browsers fetch ESM/CSS/WASM resources as
 * separate HTTP objects. */
"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

// A release bundle names each framework file by its content (`app.3f9a1c2e.wasm`); the manifest and the budgets use
// the logical name (`app.wasm`), so every classification below goes through it.
const logicalName = (name) => name.replace(/\.[0-9a-f]{8}(\.[a-z0-9]+)$/, "$1");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const bundle = path.resolve(argument("--bundle", ".build/browser/ShowcaseApp"));
const manifestPath = path.resolve(argument("--manifest", path.join(bundle, "release-manifest.json")));
const output = argument("--output");
const manifest = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, "utf8")) : {};

function walk(directory) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(file));
    else if (entry.isFile()) files.push(file);
  }
  return files;
}

function category(file) {
  const relative = file.replaceAll(path.sep, "/");
  const name = path.basename(file).toLowerCase();
  if (name.includes("icon")) return "icons";
  if (/\.(?:png|jpe?g|gif|webp|avif|svg)$/.test(name)) return "images/assets";
  if (/\.(?:woff2?|ttf|otf)$/.test(name)) return "fonts";
  if (/\.wasm$/.test(name)) return "wasm";
  if (/\.(?:m?js|ts|tsx)$/.test(name)) return relative.includes("worker") ? "workers" : "js";
  if (/\.css$/.test(name)) return "css";
  return "other";
}

const lazyNames = new Set(manifest.runtime?.lazy || []);
const files = walk(bundle).filter((file) => {
  const relative = path.relative(bundle, file).replaceAll(path.sep, "/");
  return !["release-manifest.json", "release-size.json"].includes(relative) &&
    // Precompressed copies (Tools/precompress-bundle.mjs) and difference files (Tools/delta-compress-bundle.mjs) are the encoded form of a file already counted.
    !/\.(?:br|gz|dcb)$/.test(relative) &&
    !relative.endsWith(".wasm.size.json") &&
    !relative.endsWith(".wasm.objects.json") &&
    // Debug benchmark scripts/pages are not production transfer resources.
    // Keep application data such as `benchmark-data.json`—a real release
    // fixture fetches that file and reachability must account for its bytes.
    !/(?:^|\/)benchmark-[^/]+\.(?:js|html)$/i.test(relative);
});

const rows = [];
for (const file of files) {
  const relative = path.relative(bundle, file).replaceAll(path.sep, "/");
  const logical = logicalName(relative);
  const lazy = logical.startsWith("features/") || logical === "features-manifest.json" || lazyNames.has(path.basename(logical));
  const bytes = fs.readFileSync(file);
  rows.push({
    file: relative,
    scope: lazy ? "lazy" : "initial",
    category: category(file),
    raw: bytes.length,
    gzip: zlib.gzipSync(bytes, { level: 9, mtime: 0 }).length,
    brotli: zlib.brotliCompressSync(bytes, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11 } }).length
  });
}

function totals(scope, values = rows) {
  return values.filter((row) => !scope || row.scope === scope).reduce((sum, row) => {
    sum.raw += row.raw; sum.gzip += row.gzip; sum.brotli += row.brotli; return sum;
  }, { raw: 0, gzip: 0, brotli: 0 });
}

const byCategory = {};
for (const row of rows) {
  const key = `${row.scope}:${row.category}`;
  byCategory[key] = totals(null, rows.filter((candidate) => `${candidate.scope}:${candidate.category}` === key));
}
const report = {
  version: 1,
  product: manifest.product || path.basename(bundle),
  configuration: manifest.configuration || "release",
  initial: totals("initial"),
  lazy: totals("lazy"),
  byCategory,
  files: rows
};

if (output) {
  fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
}
console.log("scope,category,raw,gzip,brotli");
for (const [key, value] of Object.entries(byCategory)) {
  const [scope, categoryName] = key.split(":");
  console.log(`${scope},${categoryName},${value.raw},${value.gzip},${value.brotli}`);
}
console.log(`initial,total,${report.initial.raw},${report.initial.gzip},${report.initial.brotli}`);
console.log(`lazy,total,${report.lazy.raw},${report.lazy.gzip},${report.lazy.brotli}`);
