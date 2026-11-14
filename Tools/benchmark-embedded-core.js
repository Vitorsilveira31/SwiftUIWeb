#!/usr/bin/env bun
/*
 * Measure the small Embedded Swift Core artifact without a WASI or browser
 * host. Embedded Swift's current SDK targets wasm32-unknown-none-wasm; the
 * probe exports one deterministic function and has no imports. This keeps the
 * measurement about the Embedded runtime/Core slice rather than a WASI
 * shim or alternate browser bootstrap.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { performance } = require("node:perf_hooks");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const input = argument("--wasm") || process.argv[2];
const output = argument("--output");
const iterations = Math.max(3, Number(argument("--iterations", "25")) || 25);
const exportName = argument("--export", "embedded_core_start");
if (!input || !fs.existsSync(input)) {
  console.error("usage: benchmark-embedded-core.js --wasm path/to/probe.wasm [--output report.json]");
  process.exit(64);
}

const artifact = path.resolve(input);
const bytes = fs.readFileSync(artifact);

function percentile(values, p) {
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * p) - 1));
  return sorted[index];
}

async function measure() {
  const compile = [];
  const instantiate = [];
  const call = [];
  let result = null;
  let memoryPages = null;
  let imports = [];

  for (let index = 0; index < iterations + 2; index += 1) {
    const compileStart = performance.now();
    const module = await WebAssembly.compile(bytes);
    const compileEnd = performance.now();
    const instantiateStart = performance.now();
    const instance = await WebAssembly.instantiate(module, {});
    const instantiateEnd = performance.now();
    const callStart = performance.now();
    if (typeof instance.exports[exportName] !== "function") {
      throw new Error(`missing exported function ${exportName}`);
    }
    result = instance.exports[exportName](41);
    const callEnd = performance.now();

    if (index >= 2) {
      compile.push(compileEnd - compileStart);
      instantiate.push(instantiateEnd - instantiateStart);
      call.push(callEnd - callStart);
    }
    if (memoryPages === null && instance.exports.memory) {
      memoryPages = instance.exports.memory.buffer.byteLength / 65536;
    }
    if (index === 0) imports = WebAssembly.Module.imports(module);
  }

  const report = {
    version: 1,
    artifact,
    target: "wasm32-unknown-none-wasm",
    host: "bun-webassembly",
    iterations,
    export: exportName,
    result,
    imports: imports.length,
    memoryPages,
    compileMs: { median: percentile(compile, 0.5), p95: percentile(compile, 0.95), max: Math.max(...compile) },
    instantiateMs: { median: percentile(instantiate, 0.5), p95: percentile(instantiate, 0.95), max: Math.max(...instantiate) },
    callMs: { median: percentile(call, 0.5), p95: percentile(call, 0.95), max: Math.max(...call) }
  };

  if (output) {
    fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
  }
  console.log(JSON.stringify(report, null, 2));
}

measure().catch((error) => {
  console.error(error.stack || error);
  process.exit(1);
});
