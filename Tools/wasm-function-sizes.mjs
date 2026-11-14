#!/usr/bin/env bun
// Per-function size report for a WebAssembly module.
//
// Reads the code section (one body per defined function) and, when present, the `name` custom section, then
// groups bytes by Swift module, by kind of symbol (generic specialization, protocol witness, thunk, plain) and
// lists the largest functions. Two reports can be diffed by symbol name.
//
//     bun Tools/wasm-function-sizes.mjs app.wasm [--top 40] [--json out.json]
//     bun Tools/wasm-function-sizes.mjs --diff before.json after.json [--top 40]
//
// Works on a stripped module too (no names): it still reports the function count and the size distribution,
// which is enough to tell "more functions" from "bigger functions" between two builds.
import { readFileSync, writeFileSync } from "node:fs";
import { dumps, parseArguments } from "./format-compat.mjs";

const comma = (value) => Math.trunc(value).toLocaleString("en-US");
const right = (text, width) => String(text).padStart(width);
const signedComma = (value) => `${value < 0 ? "-" : "+"}${comma(Math.abs(value))}`;
const cut = (name, length) => Array.from(name).slice(0, length).join("");

function leb(data, start) {
  let value = 0;
  let scale = 1;
  let i = start;
  for (;;) {
    const byte = data[i];
    if (byte === undefined) throw new RangeError("index out of range");
    i += 1;
    value += (byte & 0x7f) * scale;
    scale *= 128;
    if (!(byte & 0x80)) return [value, i];
  }
}

function* sections(data) {
  let i = 8;
  while (i < data.length) {
    const kind = data[i];
    i += 1;
    let size;
    [size, i] = leb(data, i);
    yield [kind, data.subarray(i, i + size)];
    i += size;
  }
}

export function parse(path) {
  const data = readFileSync(path);
  let imports = 0;
  const bodies = [];
  const names = new Map();
  const decoder = new TextDecoder("utf-8");
  for (const [kind, payload] of sections(data)) {
    if (kind === 2) {
      // import section: count function imports (index space)
      let count;
      let i;
      [count, i] = leb(payload, 0);
      for (let item = 0; item < count; item += 1) {
        let n;
        [n, i] = leb(payload, i);
        i += n;
        [n, i] = leb(payload, i);
        i += n;
        const desc = payload[i];
        i += 1;
        if (desc === 0) {
          [, i] = leb(payload, i);
          imports += 1;
        } else if (desc === 1) {
          i += 1;
          const flags = payload[i];
          i += 1;
          [, i] = leb(payload, i);
          if (flags & 1) [, i] = leb(payload, i);
        } else if (desc === 2) {
          const flags = payload[i];
          i += 1;
          [, i] = leb(payload, i);
          if (flags & 1) [, i] = leb(payload, i);
        } else if (desc === 3) i += 2;
      }
    } else if (kind === 10) {
      // code
      let count;
      let i;
      [count, i] = leb(payload, 0);
      for (let item = 0; item < count; item += 1) {
        let size;
        [size, i] = leb(payload, i);
        bodies.push(size);
        i += size;
      }
    } else if (kind === 0) {
      let n;
      let i;
      [n, i] = leb(payload, 0);
      if (Buffer.from(payload.subarray(i, i + n)).equals(Buffer.from("name"))) {
        i += n;
        while (i < payload.length) {
          const sub = payload[i];
          i += 1;
          let size;
          [size, i] = leb(payload, i);
          const end = i + size;
          if (sub === 1) {
            // function names
            let count;
            [count, i] = leb(payload, i);
            for (let item = 0; item < count; item += 1) {
              let index;
              [index, i] = leb(payload, i);
              [n, i] = leb(payload, i);
              names.set(index, decoder.decode(payload.subarray(i, i + n)));
              i += n;
            }
          }
          i = end;
        }
      }
    }
  }
  const rows = bodies.map((size, offset) => {
    const index = imports + offset;
    return [names.has(index) ? names.get(index) : `func[${index}]`, size];
  });
  return { file: path, bytes: data.length, functions: rows, named: names.size > 0 };
}

const MODULE = /^\$[seS](\d+)/;

export function moduleOf(name) {
  // Swift mangling: $s<len>Module... ; host ABI and C/C++ symbols keep their prefix.
  const match = MODULE.exec(name);
  if (match) {
    const length = Number(match[1]);
    const start = match[0].length;
    return name.slice(start, start + length) || "?";
  }
  if (["browser_io_", "embedded_browser_", "embedded_core_", "embedded_string_"].some((prefix) => name.startsWith(prefix))) return "host-abi";
  if (name.startsWith("_ZN")) return "c++";
  if (name.startsWith("swift_") || name.startsWith("_swift")) return "swift-runtime";
  if (name.startsWith("func[")) return "(unnamed)";
  return "c/other";
}

export function kindOf(name) {
  if (!(name.startsWith("$s") || name.startsWith("$e"))) return "non-swift";
  if (/Tg[5m]?$|TG$|Tgq$/.test(name) || name.includes("Tg5") || name.includes("TgQ")) return "generic-specialization";
  if (name.endsWith("TW") || name.slice(-4).includes("TW")) return "protocol-witness";
  if (["Tf", "TA", "TR", "Tm", "Te", "TE", "Tv", "To", "TD"].some((ending) => name.endsWith(ending)) || /Tf\d/.test(name)) return "thunk/specialized";
  return "plain";
}

const bump = (map, key, size) => {
  const entry = map.get(key) ?? [0, 0];
  entry[0] += size;
  entry[1] += 1;
  map.set(key, entry);
};

export function summarize(report, top, out = (line) => console.log(line)) {
  const rows = report.functions;
  const total = rows.reduce((sum, [, size]) => sum + size, 0);
  const byModule = new Map();
  const byKind = new Map();
  for (const [name, size] of rows) {
    bump(byModule, moduleOf(name), size);
    bump(byKind, kindOf(name), size);
  }
  const sizes = rows.map(([, size]) => size).sort((a, b) => a - b);
  const n = sizes.length;
  const pct = (p) => (n ? sizes[Math.min(n - 1, Math.trunc(n * p))] : 0);
  const big = sizes.filter((size) => size > 4096);
  out(`${report.file}: ${comma(report.bytes)} bytes, ${comma(n)} functions, ${comma(total)} code bytes, names=${report.named ? "yes" : "no"}`);
  out(`  size percentiles: p50=${pct(0.5)} p90=${pct(0.9)} p99=${pct(0.99)} max=${n ? sizes[n - 1] : 0}; functions >4KB: ${big.length}, bytes in them: ${comma(big.reduce((sum, size) => sum + size, 0))}`);
  if (report.named) {
    out("  by module:");
    for (const [module, [size, count]] of [...byModule].sort((a, b) => b[1][0] - a[1][0]).slice(0, 25)) out(`    ${right(comma(size), 10)}  ${right(count, 6)}  ${module}`);
    out("  by kind:");
    for (const [kind, [size, count]] of [...byKind].sort((a, b) => b[1][0] - a[1][0])) out(`    ${right(comma(size), 10)}  ${right(count, 6)}  ${kind}`);
    out(`  top ${top} functions:`);
    for (const [name, size] of [...rows].sort((a, b) => b[1] - a[1]).slice(0, top)) out(`    ${right(comma(size), 8)}  ${cut(name, 150)}`);
  }
}

export function diff(before, after, top, out = (line) => console.log(line)) {
  const a = new Map();
  const b = new Map();
  for (const [name, size] of before.functions) a.set(name, (a.get(name) ?? 0) + size);
  for (const [name, size] of after.functions) b.set(name, (b.get(name) ?? 0) + size);
  const names = new Set([...a.keys(), ...b.keys()]);
  const byModule = new Map();
  const deltas = [];
  for (const name of names) {
    const d = (b.get(name) ?? 0) - (a.get(name) ?? 0);
    if (d) {
      deltas.push([d, name, a.get(name) ?? 0, b.get(name) ?? 0]);
      const module = moduleOf(name);
      byModule.set(module, (byModule.get(module) ?? 0) + d);
    }
  }
  const added = [...names].filter((name) => !a.has(name)).length;
  const removed = [...names].filter((name) => !b.has(name)).length;
  const sum = (map) => [...map.values()].reduce((total, value) => total + value, 0);
  out(`functions: ${comma(a.size)} -> ${comma(b.size)} (+${comma(added)} new, -${comma(removed)} gone); code bytes ${comma(sum(a))} -> ${comma(sum(b))}`);
  out("  delta by module:");
  for (const [module, d] of [...byModule].sort((x, y) => Math.abs(y[1]) - Math.abs(x[1])).slice(0, 25)) out(`    ${right(signedComma(d), 11)}  ${module}`);
  out(`  top ${top} growth:`);
  const descending = (x, y) => (x < y ? 1 : x > y ? -1 : 0);
  const ordered = deltas.sort((x, y) => descending(x[0], y[0]) || descending(x[1], y[1]) || descending(x[2], y[2]) || descending(x[3], y[3]));
  for (const [d, name, x, y] of ordered.slice(0, top)) out(`    ${right(signedComma(d), 9)}  (${comma(x)} -> ${comma(y)})  ${cut(name, 140)}`);
}

export function main(argv) {
  const args = parseArguments({
    prog: "wasm-function-sizes.mjs",
    description: "Per-function size report for a WebAssembly module.",
    options: [
      { names: ["--top"], dest: "top", type: "int", default: 40 },
      { names: ["--json"], dest: "json", type: "string" },
      { names: ["--diff"], dest: "diff", type: "flag" },
    ],
    positionals: [{ name: "paths", nargs: "+" }],
  }, argv);
  if (args.diff) {
    const [before, after] = args.paths.slice(0, 2).map((path) => JSON.parse(readFileSync(path, "utf8")));
    if (after === undefined) throw new Error("not enough values to unpack (expected 2, got 1)");
    diff(before, after, args.top);
    return;
  }
  for (const path of args.paths) {
    const report = parse(path);
    summarize(report, args.top);
    if (args.json) writeFileSync(args.json, dumps(report));
  }
}

if (import.meta.main) main(process.argv.slice(2));
