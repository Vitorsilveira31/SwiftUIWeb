#!/usr/bin/env bun
// Where the code bytes of a named WebAssembly module go: by Swift module and by kind, the generic functions whose
// specialized copies weigh most, the code the application types caused, and, with a split profile, what the first
// screen runs and what the forwarding stubs of a split cost.
//
//     bun Tools/wasm-size-attribution.mjs <named.wasm> [--top 40] [--app-modules A,B] [--profile first-screen.prof]
//         [--split-primary app.wasm] [--json out.json]
//     bun Tools/wasm-size-attribution.mjs --diff before.json after.json [--top 40]
//
// The names come from the module's `name` section (build with SWIFTUIWEB_KEEP_OPTIMIZED_WASM_NAMES for the module as it
// ships) and are demangled by one `swift demangle` process. Without a name section the report keeps to what needs no names.
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { brotliCompressSync, constants } from "node:zlib";
import { dumps, parseArguments } from "./format-compat.mjs";
import { countFunctionImports, leb, moduleOf, parse, sections } from "./wasm-function-sizes.mjs";

const comma = (value) => Math.trunc(value).toLocaleString("en-US");
const right = (text, width) => String(text).padStart(width);
const cut = (text, length) => (Array.from(text).length > length ? `${Array.from(text).slice(0, length - 1).join("")}…` : text);
const sum = (values) => values.reduce((total, value) => total + value, 0);
const SECTION_NAMES = ["custom", "type", "import", "function", "table", "memory", "global", "export", "start", "element", "code", "data", "data_count", "tag"];
const SPLIT_SECTIONS = ["import", "element", "function", "export", "data"];

function brotli(bytes) {
  if (bytes.length === 0) return 0;
  return brotliCompressSync(bytes, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_LGWIN]: 24, [constants.BROTLI_PARAM_SIZE_HINT]: bytes.length } }).length;
}

function sectionName(kind, payload) {
  if (kind !== 0) return SECTION_NAMES[kind] ?? `#${kind}`;
  const [length, start] = leb(payload, 0);
  return `custom:${new TextDecoder().decode(payload.subarray(start, start + length))}`;
}

/** Raw and brotli-alone sizes of the sections of a module (payloads only), optionally just the named ones. */
function sectionRows(data, only = null) {
  const rows = [];
  for (const [kind, payload] of sections(data)) {
    const name = sectionName(kind, payload);
    if (!only || only.includes(name)) rows.push({ name, raw: payload.length, brotli: brotli(payload) });
  }
  return rows;
}

function sectionPayload(data, wanted) {
  for (const [kind, payload] of sections(data)) if (kind === wanted) return payload;
  return null;
}

// ---- Kinds and copies of the demangled names ----------------------------------------------------------------------

const WRAPPERS = [
  ["merged ", "merged"],
  ["partial apply forwarder for ", "partial-apply"],
  ["reabstraction thunk helper ", "reabstraction-thunk"],
  ["protocol witness for ", "protocol-witness"],
  ["outlined copy of ", "outlined-copy"],
  ["outlined destroy of ", "outlined-destroy"],
  ["outlined consume of ", "outlined-consume"],
  ["outlined retain of ", "outlined-retain"],
  ["outlined release of ", "outlined-release"],
  ["outlined init with copy of ", "outlined-init-copy"],
  ["outlined init with take of ", "outlined-init-take"],
  ["outlined assign with copy of ", "outlined-assign-copy"],
  ["outlined assign with take of ", "outlined-assign-take"],
  ["outlined bridged method ", "outlined-other"],
  ["outlined variable ", "outlined-other"],
  ["outlined read-only object ", "outlined-other"],
  ["outlined ", "outlined-other"],
  ["objectdestroy", "closure-context-destroy"],
];

const SPECIALIZATIONS = [
  ["generic specialization <", "generic-specialization"],
  ["function signature specialization <", "signature-specialization"],
  ["generic not re-abstracted specialization <", "generic-specialization"],
  ["generic partial specialization <", "generic-specialization"],
  ["inlined generic function <", "generic-specialization"],
];

// The index after the <...> group that opens at `at`; a `->` inside the group does not close it.
function skipAngles(text, at) {
  let depth = 0;
  for (let i = at; i < text.length; i += 1) {
    if (text[i] === "<") depth += 1;
    else if (text[i] === ">" && text[i - 1] !== "-") {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
  }
  return text.length;
}

/**
 * The kind of a demangled function, and the text left once its wrappers and specialization arguments are removed (the
 * function it is a copy of). A generic specialization is the kind whenever one wraps the function.
 */
export function classify(text, isSwift = true) {
  if (!isSwift) return { kind: "non-swift", base: text };
  const kinds = [];
  let rest = text;
  for (let guard = 0; guard < 12; guard += 1) {
    const wrapper = WRAPPERS.find(([prefix]) => rest.startsWith(prefix));
    if (wrapper) {
      kinds.push(wrapper[1]);
      rest = rest.slice(wrapper[0].length);
      continue;
    }
    const specialization = SPECIALIZATIONS.find(([prefix]) => rest.startsWith(prefix));
    if (!specialization) break;
    const [prefix, kind] = specialization;
    kinds.push(kind);
    rest = rest.slice(skipAngles(rest, prefix.length - 1)).replace(/^ of /, "");
  }
  const kind = kinds.includes("generic-specialization") ? "generic-specialization"
    : kinds.find((name) => name.startsWith("outlined")) ?? kinds[0] ?? "plain";
  return { kind, base: rest };
}

const OWNER_PREFIX = /^(implicit closure|closure|default argument \d+ of|variable initialization expression of|property wrapper backing initializer of|local function|key path [a-z]+ for) /;

/** The function a closure or local body belongs to: "closure #1 in closure #2 in X.f() -> ()" is "X.f() -> ()". */
export function owner(base) {
  let text = base;
  while (OWNER_PREFIX.test(text) && text.includes(" in ")) text = text.slice(text.indexOf(" in ") + 4);
  return text;
}

// ---- Profile and address-taken functions --------------------------------------------------------------------------

/** A wasm-split profile: an 8-byte module hash, then a u32 per defined function (zero: the function never ran). */
export function readProfile(bytes) {
  const data = Buffer.from(bytes);
  if (data.length < 8 || (data.length - 8) % 4 !== 0) {
    throw new Error(`the profile is ${comma(data.length)} bytes: an 8-byte module hash and one u32 per function are expected`);
  }
  const ran = [];
  for (let at = 8; at < data.length; at += 4) ran.push(data.readUInt32LE(at) !== 0);
  return { hash: data.subarray(0, 8).toString("hex"), ran };
}

/** The defined-function indices whose address is taken (the element section); a split needs a stub for each. */
export function addressTaken(wasmBytes) {
  const taken = new Set();
  const element = sectionPayload(wasmBytes, 9);
  if (!element) return taken;
  const importPayload = sectionPayload(wasmBytes, 2);
  const imports = importPayload ? countFunctionImports(importPayload) : 0;
  let [count, at] = leb(element, 0);
  for (let segment = 0; segment < count; segment += 1) {
    let flags;
    [flags, at] = leb(element, at);
    if (flags !== 0) throw new Error(`element segment ${segment} has flags ${flags}; only the plain form (flags 0) is read`);
    at += 1; // i32.const
    while (element[at++] & 0x80);
    at += 1; // end
    let entries;
    [entries, at] = leb(element, at);
    for (let entry = 0; entry < entries; entry += 1) {
      let index;
      [index, at] = leb(element, at);
      if (index >= imports) taken.add(index - imports);
    }
  }
  return taken;
}

// ---- Forwarding stubs of a split ----------------------------------------------------------------------------------

// A forwarding stub: no locals, then only local.get, i32.const, call_indirect or return_call_indirect and end, with at
// least one indirect call. wasm-split writes one for each moved function whose address is taken.
function isForwardingStub(code, start, end) {
  let [groups, j] = leb(code, start);
  if (groups !== 0) return false;
  let indirect = false;
  while (j < end) {
    const op = code[j];
    j += 1;
    if (op === 0x20) [, j] = leb(code, j);
    else if (op === 0x41) while (code[j++] & 0x80);
    else if (op === 0x11 || op === 0x13) {
      [, j] = leb(code, j);
      [, j] = leb(code, j);
      indirect = true;
    } else if (op !== 0x0b) return false;
  }
  return indirect;
}

// The code section entries, each with its size prefix, and whether it is a forwarding stub.
function codeEntries(wasmBytes) {
  const code = sectionPayload(wasmBytes, 10);
  if (!code) return [];
  const [count, first] = leb(code, 0);
  const entries = [];
  let at = first;
  for (let n = 0; n < count; n += 1) {
    const [size, start] = leb(code, at);
    entries.push({ bytes: code.subarray(at, start + size), stub: isForwardingStub(code, start, start + size) });
    at = start + size;
  }
  return entries;
}

/** Forwarding stubs against real functions in a module (raw bytes include each entry's size prefix), and its sections. */
export function splitOverhead(wasmBytes) {
  const stubs = [];
  const real = [];
  for (const { bytes, stub } of codeEntries(wasmBytes)) (stub ? stubs : real).push(bytes);
  const row = (entries) => {
    const blob = Buffer.concat(entries);
    return { count: entries.length, raw: blob.length, brotli: brotli(blob) };
  };
  return { stubs: row(stubs), real: row(real), sections: sectionRows(wasmBytes, SPLIT_SECTIONS) };
}

// ---- The report ---------------------------------------------------------------------------------------------------

// One record per defined function: its demangled name, size, Swift module, kind, the origin and the generic it copies.
function describe(func, index, demangled, scope) {
  const [name, size] = func;
  const text = demangled?.[index] ?? name;
  const { kind, base } = classify(text, /^\$[seS]/.test(name));
  const module = moduleOf(name);
  let origin = "framework and runtime, no application type";
  if (scope.appModules.includes(module)) origin = "application code";
  else if (scope.appPattern?.test(text)) origin = "framework code copied for application types";
  return { name: text, size, module, kind, origin, copyOf: kind === "generic-specialization" ? owner(base) : null };
}

/** Totals per key, largest first. */
function tally(items, keyOf) {
  const totals = new Map();
  for (const item of items) {
    const key = keyOf(item);
    const entry = totals.get(key) ?? { name: key, bytes: 0, count: 0 };
    entry.bytes += item.size;
    entry.count += 1;
    totals.set(key, entry);
  }
  return [...totals.values()].sort((a, b) => b.bytes - a.bytes || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
}

function profileSection(ran, records) {
  const first = records.filter((_, index) => ran[index]);
  return {
    functions: first.length,
    bytes: sum(first.map((record) => record.size)),
    modules: tally(first, (record) => record.module),
    largest: [...first].sort((a, b) => b.size - a.size).slice(0, 25).map((record) => ({ name: record.name, bytes: record.size })),
  };
}

/**
 * The attribution of a module. `parsed` is `parse(path)` with the file's bytes as `data`; `demangled` holds the demangled
 * name of each function (or null without a name section); `options` is { appModules, profile, splitPrimary }, where
 * profile and splitPrimary are file contents (or null). Reads no file and runs no process.
 */
export function buildReport(parsed, demangled, options) {
  const { functions, named, data } = parsed;
  const sizes = functions.map(([, size]) => size);
  const report = { file: parsed.file, bytes: parsed.bytes, functions: functions.length, codeBytes: sum(sizes), named, sections: sectionRows(data) };
  const scope = { appModules: options.appModules, appPattern: options.appModules.length ? new RegExp(`\\b(?:${options.appModules.join("|")})\\.[A-Z]`) : null };
  const records = functions.map((func, index) => describe(func, index, demangled, scope));
  if (named) {
    report.modules = tally(records, (record) => record.module);
    report.kinds = tally(records, (record) => record.kind);
    report.copies = tally(records.filter((record) => record.copyOf), (record) => record.copyOf);
    if (scope.appPattern) report.origins = tally(records, (record) => record.origin);
  }
  const taken = addressTaken(data);
  report.addressTaken = { count: taken.size, bytes: sum([...taken].map((index) => sizes[index] ?? 0)) };
  if (options.profile) {
    const { ran } = readProfile(options.profile);
    if (ran.length !== functions.length) {
      throw new Error(`the profile has ${comma(ran.length)} functions, the module ${comma(functions.length)}: the profile was recorded from another build`);
    }
    report.profile = profileSection(ran, records);
    report.addressTaken.notRun = [...taken].filter((index) => !ran[index]).length;
  }
  if (options.splitPrimary) report.split = splitOverhead(options.splitPrimary);
  return report;
}

export function printReport(report, top, out = (line) => console.log(line)) {
  const pct = (bytes, of = report.codeBytes) => (of ? (100 * bytes / of).toFixed(1) : "0.0");
  const table = (title, rows, n, width = 150) => {
    out(`\n${title}`);
    for (const row of rows.slice(0, n)) out(`  ${right(comma(row.bytes), 10)} ${right(pct(row.bytes), 5)}%  ${right(comma(row.count), 6)}x  ${cut(row.name, width)}`);
  };
  out(report.file);
  out(`  ${comma(report.bytes)} bytes, ${comma(report.functions)} defined functions, ${comma(report.codeBytes)} code bytes`);
  out("\nsections: raw, and brotli alone (quality 11)");
  for (const row of report.sections) out(`  ${row.name.padEnd(22)} ${right(comma(row.raw), 11)} ${right(comma(row.brotli), 10)}`);
  if (!report.named) out("\nno name section: the module has no function names, so the tables by name are left out");
  else {
    table("code bytes by Swift module (mangled prefix: where the generic was written)", report.modules, 25);
    table("code bytes by kind", report.kinds, 25);
    table(`copies of generic functions: top ${top} by total bytes (rows count specializations; closures count in their function)`, report.copies, top, 170);
    if (report.origins) table("application and framework code", report.origins, 10);
  }
  if (report.profile) {
    const p = report.profile;
    out(`\nfirst screen: ran ${comma(p.functions)} of ${comma(report.functions)} functions, ${comma(p.bytes)} code bytes (${pct(p.bytes)}%)`);
    if (report.named) table("first screen code by Swift module", p.modules, 25);
    out("\nlargest functions the first screen ran");
    for (const row of p.largest.slice(0, top)) out(`  ${right(comma(row.bytes), 8)}  ${cut(row.name, 170)}`);
  }
  const a = report.addressTaken;
  out(`\naddress-taken functions (element section): ${comma(a.count)} of ${comma(report.functions)}, ${comma(a.bytes)} code bytes`);
  if (a.notRun !== undefined) out(`  ${comma(a.notRun)} did not run on the first screen: each needs a placeholder import and a forwarding stub in a split`);
  if (report.split) {
    const s = report.split;
    out(`\nsplit primary: forwarding stubs ${comma(s.stubs.count)} functions, ${comma(s.stubs.raw)} B raw, ${comma(s.stubs.brotli)} B brotli alone`);
    out(`  real functions ${comma(s.real.count)} functions, ${comma(s.real.raw)} B raw, ${comma(s.real.brotli)} B brotli alone`);
    for (const row of s.sections) out(`  ${row.name.padEnd(9)} ${right(comma(row.raw), 11)} B raw ${right(comma(row.brotli), 10)} B brotli`);
  }
}

// ---- Command line -------------------------------------------------------------------------------------------------

/** The demangled text of each name, in one `swift demangle` process. Embedded symbols start with $e; the demangler reads $s. */
export function demangleAll(names) {
  if (names.length === 0) return [];
  const input = names.map((name) => (name.startsWith("$e") ? `$s${name.slice(2)}` : name)).join("\n");
  const result = spawnSync("swift", ["demangle"], { input, encoding: "utf8", maxBuffer: 1 << 30 });
  if (result.error?.code === "ENOENT") {
    throw Object.assign(new Error("swift was not found on PATH: the function names are demangled with `swift demangle` (install the Swift toolchain, or read the report of a module without names)"), { exitCode: 2 });
  }
  if (result.error || result.status !== 0) throw new Error(`swift demangle failed: ${result.stderr || result.error?.message}`);
  const lines = result.stdout.split("\n");
  if (lines.length < names.length) throw new Error(`swift demangle printed ${lines.length} lines for ${names.length} names`);
  return names.map((name, index) => lines[index] || name);
}

/**
 * What changed between two reports (`--json` of two builds): the totals, the kinds and the copies of each generic function,
 * largest change first. A generic that is in one report only counts from, or to, zero.
 */
export function diffReports(before, after) {
  const change = (rowsBefore = [], rowsAfter = []) => {
    const was = new Map(rowsBefore.map((row) => [row.name, row]));
    const now = new Map(rowsAfter.map((row) => [row.name, row]));
    const rows = [];
    for (const name of new Set([...was.keys(), ...now.keys()])) {
      const a = was.get(name) ?? { bytes: 0, count: 0 };
      const b = now.get(name) ?? { bytes: 0, count: 0 };
      if (a.bytes !== b.bytes || a.count !== b.count) rows.push({ name, bytes: b.bytes - a.bytes, count: b.count - a.count, bytesBefore: a.bytes, bytesAfter: b.bytes, countBefore: a.count, countAfter: b.count });
    }
    return rows.sort((x, y) => Math.abs(y.bytes) - Math.abs(x.bytes) || (x.name < y.name ? -1 : x.name > y.name ? 1 : 0));
  };
  return {
    bytes: after.bytes - before.bytes,
    functions: after.functions - before.functions,
    codeBytes: after.codeBytes - before.codeBytes,
    before: { bytes: before.bytes, functions: before.functions, codeBytes: before.codeBytes },
    after: { bytes: after.bytes, functions: after.functions, codeBytes: after.codeBytes },
    kinds: change(before.kinds, after.kinds),
    copies: change(before.copies, after.copies),
  };
}

export function printDiff(diff, top, out = (line) => console.log(line)) {
  const signed = (value) => `${value < 0 ? "-" : "+"}${comma(Math.abs(value))}`;
  out(`code bytes ${comma(diff.before.codeBytes)} -> ${comma(diff.after.codeBytes)} (${signed(diff.codeBytes)}); functions ${comma(diff.before.functions)} -> ${comma(diff.after.functions)} (${signed(diff.functions)}); module ${comma(diff.before.bytes)} -> ${comma(diff.after.bytes)} (${signed(diff.bytes)})`);
  const table = (title, rows) => {
    out(`\n${title}`);
    for (const row of rows.slice(0, top)) out(`  ${right(signed(row.bytes), 11)}  ${right(`${comma(row.countBefore)}x -> ${comma(row.countAfter)}x`, 18)}  ${right(`${comma(row.bytesBefore)} -> ${comma(row.bytesAfter)}`, 24)}  ${cut(row.name, 150)}`);
  };
  table("code bytes by kind", diff.kinds);
  table(`copies of generic functions: the ${top} largest changes`, diff.copies);
}

export function main(argv) {
  const args = parseArguments({
    prog: "wasm-size-attribution.mjs",
    description: "Where the code bytes of a named WebAssembly module go: by module, kind, generic copies, application code and split overhead.",
    options: [
      { names: ["--top"], dest: "top", type: "int", default: 40 },
      { names: ["--app-modules"], dest: "appModules", type: "string", default: "" },
      { names: ["--profile"], dest: "profile", type: "string" },
      { names: ["--split-primary"], dest: "splitPrimary", type: "string" },
      { names: ["--json"], dest: "json", type: "string" },
      { names: ["--diff"], dest: "diff", type: "flag" },
    ],
    positionals: [{ name: "paths", nargs: "+" }],
  }, argv);
  const usage = (message) => { throw Object.assign(new Error(message), { exitCode: 2 }); };
  if (args.diff) {
    if (args.paths.length !== 2) usage("--diff takes two reports written with --json: the earlier build, then the later one");
    const [before, after] = args.paths.map((path) => JSON.parse(readFileSync(path, "utf8")));
    printDiff(diffReports(before, after), args.top);
    return;
  }
  if (args.paths.length !== 1) usage("one named module is expected");
  args.wasm = args.paths[0];
  const appModules = args.appModules ? args.appModules.split(",").filter(Boolean) : [];
  for (const module of appModules) if (!/^\w+$/.test(module)) usage(`--app-modules: '${module}' is not a module name`);
  const parsed = { ...parse(args.wasm), data: readFileSync(args.wasm) };
  const demangled = parsed.named ? demangleAll(parsed.functions.map(([name]) => name)) : null;
  const report = buildReport(parsed, demangled, {
    appModules,
    profile: args.profile ? readFileSync(args.profile) : null,
    splitPrimary: args.splitPrimary ? readFileSync(args.splitPrimary) : null,
  });
  printReport(report, args.top);
  if (args.json) writeFileSync(args.json, dumps(report));
}

if (import.meta.main) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(`wasm-size-attribution.mjs: error: ${error.message}`);
    process.exitCode = error.exitCode ?? 1;
  }
}
