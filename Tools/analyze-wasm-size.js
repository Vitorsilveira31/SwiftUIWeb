#!/usr/bin/env bun
/*
 * Inspect a WebAssembly artifact without depending on Binaryen, wasm-tools or
 * a platform-specific objdump.  The section parser is deliberately small: it
 * reports the bytes that are actually transferred and identifies the sections
 * which dominate the artifact.  Compression values are for the complete file
 * (section compression is not additive and is therefore not reported).
 */
"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const input = argument("--wasm") || process.argv[2];
const output = argument("--output");
if (!input || !fs.existsSync(input)) {
  console.error("usage: analyze-wasm-size.js --wasm path/to/app.wasm [--output report.json]");
  process.exit(64);
}

const file = path.resolve(input);
const bytes = fs.readFileSync(file);
if (bytes.length < 8 || bytes.readUInt32LE(0) !== 0x6d736100 || bytes.readUInt32LE(4) !== 1) {
  console.error(`${file} is not a WebAssembly binary`);
  process.exit(65);
}

function readULEB(offset) {
  let value = 0;
  let shift = 0;
  let cursor = offset;
  while (cursor < bytes.length) {
    const byte = bytes[cursor++];
    value += (byte & 0x7f) * 2 ** shift;
    if ((byte & 0x80) === 0) return { value, next: cursor };
    shift += 7;
    if (shift > 53) throw new Error("Wasm section length is too large");
  }
  throw new Error("Truncated Wasm LEB128 value");
}

function customName(start, end) {
  try {
    const name = readULEBAt(start, end);
    return name.value ? bytes.toString("utf8", name.next, Math.min(name.next + name.value, end)) : "custom";
  } catch (_) {
    return "custom";
  }
}

function readULEBAt(offset, limit) {
  let value = 0;
  let shift = 0;
  let cursor = offset;
  while (cursor < limit) {
    const byte = bytes[cursor++];
    value += (byte & 0x7f) * 2 ** shift;
    if ((byte & 0x80) === 0) return { value, next: cursor };
    shift += 7;
    if (shift > 53) throw new Error("Wasm custom name is too large");
  }
  throw new Error("Truncated custom section name");
}

const standardNames = new Map([
  [0, "custom"], [1, "type"], [2, "import"], [3, "function"],
  [4, "table"], [5, "memory"], [6, "global"], [7, "export"],
  [8, "start"], [9, "element"], [10, "code"], [11, "data"],
  [12, "data_count"], [13, "tag"]
]);

const sections = [];
let cursor = 8;
while (cursor < bytes.length) {
  const start = cursor;
  const id = bytes[cursor++];
  const length = readULEB(cursor);
  cursor = length.next;
  const end = cursor + length.value;
  if (end > bytes.length) throw new Error("Truncated Wasm section");
  const name = id === 0 ? customName(cursor, end) : (standardNames.get(id) || `section-${id}`);
  sections.push({ id, name, raw: end - start });
  cursor = end;
}

const gzip = zlib.gzipSync(bytes, { level: 9, mtime: 0 }).length;
const brotli = zlib.brotliCompressSync(bytes, {
  params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11 }
}).length;
const report = {
  version: 1,
  artifact: file,
  raw: bytes.length,
  gzip,
  brotli,
  sections: sections.sort((a, b) => b.raw - a.raw),
  flags: {
    hasDebugSections: sections.some((section) => section.name.startsWith(".debug_")),
    hasNameSection: sections.some((section) => section.name === "name"),
    hasProducersSection: sections.some((section) => section.name === "producers")
  }
};

if (output) {
  fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
}

console.log("artifact,raw,gzip,brotli");
console.log(`${file},${report.raw},${report.gzip},${report.brotli}`);
console.log("section,raw");
for (const section of report.sections) console.log(`${section.name},${section.raw}`);
