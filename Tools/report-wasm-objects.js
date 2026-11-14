#!/usr/bin/env bun
/* Summarize Swift object inputs as a module-level size proxy. Link-time DCE
 * means object bytes are not identical to final code bytes, but this report
 * identifies where to look before changing source and complements the final
 * Wasm section report. */
"use strict";

const fs = require("fs");
const path = require("path");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const root = path.resolve(argument("--root", path.join(__dirname, "..", ".build", "out", "Intermediates.noindex")));
const output = argument("--output");
const configuration = argument("--configuration", "Release-webassembly-wasm32");
const onlyModules = argument("--modules");
const moduleFilter = onlyModules ? new Set(onlyModules.split(",").map((value) => value.trim()).filter(Boolean)) : null;
if (!fs.existsSync(root)) {
  console.error(`object root does not exist: ${root}`);
  process.exit(2);
}

function walk(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(file));
    else if (entry.isFile() && entry.name.endsWith(".o")) files.push(file);
  }
  return files;
}

const rows = new Map();
for (const file of walk(root)) {
  const relative = path.relative(root, file).replaceAll(path.sep, "/");
  if (!relative.includes(`/${configuration}/`)) continue;
  const moduleMatch = relative.match(/\/([^/]+?)-t\.build\//);
  const module = moduleMatch ? moduleMatch[1] : "other";
  if (moduleFilter && !moduleFilter.has(module)) continue;
  const bytes = fs.statSync(file).size;
  const row = rows.get(module) || { module, raw: 0, objects: 0, largestObject: { file: "", raw: 0 } };
  row.raw += bytes;
  row.objects += 1;
  if (bytes > row.largestObject.raw) row.largestObject = { file: relative, raw: bytes };
  rows.set(module, row);
}

const report = {
  version: 1,
  root,
  modules: [...rows.values()].sort((a, b) => b.raw - a.raw)
};
if (output) {
  fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
}
console.log("module,objectBytes,objectCount,largestObject,largestObjectBytes");
for (const row of report.modules) {
  console.log(`${row.module},${row.raw},${row.objects},${row.largestObject.file},${row.largestObject.raw}`);
}
