#!/usr/bin/env bun
// Splits a release bundle's app.wasm in two by what its first screen runs (the release default; SWIFTUIWEB_WASM_SPLIT=0
// turns it off, Documentation/Architecture/WASM_SPLIT.md).
//
// The page then downloads, before the first screen, only the functions that screen needs (`app.wasm`); the rest
// (`app-rest.wasm`) downloads right after it, in the background. Tools/wasm-split-loader.js loads the second module:
// a call that needs a function of it before it arrived waits for it, it does not fail.
//
//   0. Where the placeholders go. Binaryen puts them in a table of their own when the module has reference types, and then
//      every moved function whose address the module's table holds gets a forwarding stub that stays on its calls. The
//      toolchain's modules list reference-types in their target_features section only because the compiler enables it; when
//      they validate without it, the split runs on a copy without that section (and with the section's other features
//      enabled by flag), so the placeholders sit in the module's own table and the second module's element segments fill
//      them. A module that needs reference types, lists a feature this script has no flag for, or has code that writes its
//      table (a write could replace a placeholder) keeps the two-table layout.
//   1. Binaryen's `wasm-split --instrument` writes a copy of app.wasm that records which functions run.
//   2. A copy of the bundle with that module runs in headless Chromium, in the Worker as a page runs it by default,
//      until its first screen is up: the app is mounted and has stopped committing (400 ms without a commit), at every
//      viewport of --viewports, so that the compact and the regular layout are both counted.
//   3. `wasm-split --split --profile` moves every function no run reached into app-rest.wasm; the profiles of the
//      viewports are merged first. The modules do not go through `wasm-opt` again: on the Board that made both larger
//      over the wire (+0.9 KB brotli) for 5 KB less raw.
//   4. With --link-map, the data only the second module's code uses moves into the second module (Tools/wasm-data-split.mjs):
//      vtables, witness tables, type metadata and string literals of code the first screen does not run.
//   5. Unless --no-verify, the split bundle is loaded once more and must reach a first screen with no page error.
//
// The profile is tied to the exact binary. With --cache-dir, the split of a module is kept under a key of everything it
// depends on (the module, the runtime scripts and the page, this script, Binaryen's version, the route and the viewports),
// so a build whose inputs did not change reuses it and runs no browser. The profile is kept in the build logs
// (`--log-dir`). Run it after every file of the bundle is in place and before Tools/hash-release-bundle.mjs, which
// gives both modules their hashed names and rewrites the loader's reference to app-rest.wasm.
//
// --check exits 0 when this machine can split (a wasm-split that has the options used here, and a Chromium for the
// profile run) and otherwise prints why and exits 1. --fallback turns any failure into a warning that leaves the bundle as
// it was, with one app.wasm, and exits 3 (the launcher then builds the runtime scripts again without the split loader):
// the launcher's default, the way Tools/strip-wasm-release.sh goes on without wasm-opt.
//
// usage: wasm-split-release.mjs <bundle-directory> [--route /] [--viewports 1280x800,390x844] [--log-dir DIR] [--no-verify]
//                               [--cache-dir DIR] [--link-map FILE] [--fallback]
//        wasm-split-release.mjs --check
// Run the tests with: bun test ./Tools/test-wasm-split-release.mjs and bun Tools/test-wasm-split-browser.mjs

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { brotliCompressSync, constants } from "node:zlib";
import { seal } from "./seal-csp.mjs";
import { linkMapKey, splitData } from "./wasm-data-split.mjs";

export const PRIMARY = "app.wasm";
export const SECONDARY = "app-rest.wasm";
// The placeholders' namespace prefix (Tools/wasm-split-loader.js): one short word, as it is repeated for every moved function.
export const PLACEHOLDER_NAMESPACE = "p";
export const PRIMARY_NAMESPACE = "primary";
const MOUNTED = 'html[data-embedded-mounted="true"]';
const SETTLE_LIMIT_MS = 8_000;
const QUIET_MS = 400;

// Keeps the instance of an instrumented module where the evaluation below finds it. Prepended to the copy of the
// worker's and the page's script that the profiling run loads, never to the bundle that ships.
const PROFILE_HOOK = `{const instantiate=WebAssembly.instantiate;WebAssembly.instantiate=function(...args){return instantiate.apply(this,args).then(result=>{const instance=result instanceof WebAssembly.Instance?result:result.instance;if(instance&&instance.exports&&instance.exports.__write_profile)globalThis.__swiftuiwebProfiled=instance;return result;});};}\n`;

/**
 * What the check of the data move prepends to the worker's and the page's script: the first module is instrumented
 * (Binaryen's `--instrument-memory` calls an import for every load and store), and these imports note the accesses that touch
 * the moved ranges `runs` (address pairs, sorted) before the second module is instantiated, which is when the first module must
 * not need that data. They go to `globalThis.__swiftuiwebDataReads`.
 */
/** The wasm-opt passes that make a module report its loads and stores: bulk copies and fills become loops first, which the
 * instrumentation does not otherwise see. `flags` enable the module's features. */
export function instrumentation(flags) {
  return [...flags, "--llvm-memory-copy-fill-lowering", "--instrument-memory"];
}

export function dataHook(runs) {
  return `{const runs=${JSON.stringify(runs)};const reads=globalThis.__swiftuiwebDataReads=[];` +
    `const touches=(a,n)=>{let lo=0,hi=runs.length-1,k=runs.length;while(lo<=hi){const m=(lo+hi)>>1;if(runs[m][1]>a){k=m;hi=m-1;}else lo=m+1;}return k<runs.length&&runs[k][0]<a+n;};` +
    `const loaded=()=>performance.getEntriesByName("swiftuiweb-app-rest").length>0;` +
    `const touch=kind=>(id,bytes,offset,ptr)=>{const a=(ptr+offset)>>>0;if(reads.length<16&&!loaded()&&touches(a,bytes))reads.push(kind+" "+a);return ptr;};` +
    `const keep=(id,value)=>value;` +
    `const imports={load_ptr:touch("read"),store_ptr:touch("write"),load_val_i32:keep,load_val_i64:keep,load_val_f32:keep,load_val_f64:keep,store_val_i32:keep,store_val_i64:keep,store_val_f32:keep,store_val_f64:keep,memory_grow_pre:keep,memory_grow_post:keep};` +
    `const instantiate=WebAssembly.instantiate;WebAssembly.instantiate=function(module,env){if(module instanceof WebAssembly.Module&&env&&WebAssembly.Module.imports(module).some(e=>e.module==="env"&&e.name==="load_ptr"))env.env=Object.assign({},env.env,imports);return instantiate.apply(this,arguments);};}\n`;
}

// Runs in the scope that holds the instrumented instance: the profile is written into fresh pages of its memory.
const READ_PROFILE = () => {
  const instance = globalThis.__swiftuiwebProfiled;
  if (!instance) return null;
  const { memory, __write_profile: write } = instance.exports;
  const pages = 16;
  const at = memory.grow(pages) * 65536;
  const length = write(at, pages * 65536);
  return Array.from(new Uint8Array(memory.buffer, at, length));
};

// The wasm-split options this step uses; an older Binaryen without one of them cannot split (Ubuntu 24.04 ships 108).
const NEEDED_OPTIONS = ["--instrument", "--merge-profiles", "--profile", "--placeholder-namespace", "--import-namespace"];
// The files of the bundle the profile run's code paths depend on, besides the module.
const PAGE_FILES = ["index.html", "index.js", "render-worker.js", "runtime-shared.js", "runtime-deferred.js"];
const SPLIT_SOURCE = fileURLToPath(import.meta.url);
const DATA_SPLIT_SOURCE = fileURLToPath(new URL("./wasm-data-split.mjs", import.meta.url));
/** The exit status of a --fallback run that left the bundle unsplit. */
export const FELL_BACK = 3;

/** Why this machine cannot split, or null when it can. */
export async function unavailable() {
  const help = spawnSync("wasm-split", ["--help"], { encoding: "utf8" });
  if (help.error?.code === "ENOENT") return "Binaryen's wasm-split is not installed (brew install binaryen, or a Binaryen release on Linux)";
  const text = `${help.stdout ?? ""}${help.stderr ?? ""}`;
  const missing = NEEDED_OPTIONS.filter((option) => !text.includes(option));
  if (missing.length) return `this wasm-split (${binaryenVersion()}) has no ${missing.join(", ")}: a newer Binaryen is needed`;
  try {
    const { launch } = await import("./browser-test-support.mjs");
    const browser = await launch({ engine: "chromium" });
    await browser.close();
  } catch (error) {
    return `no headless Chromium for the profile run (bunx playwright install chromium): ${String(error?.message ?? error).split("\n")[0]}`;
  }
  return null;
}

function binaryenVersion() {
  const result = spawnSync("wasm-split", ["--version"], { encoding: "utf8" });
  return (result.stdout || result.stderr || "unknown").trim();
}

// Binaryen's flag for each feature name the toolchain writes in the target_features section. Binaryen's reader enables every
// feature of that section after the command-line flags, so a split without reference types needs the section gone and
// every other feature enabled here (--mvp-features turns the defaults off, reference types among them).
export const FEATURE_FLAGS = {
  "mutable-globals": "--enable-mutable-globals",
  "nontrapping-fptoint": "--enable-nontrapping-float-to-int",
  "sign-ext": "--enable-sign-ext",
  "bulk-memory": "--enable-bulk-memory",
  "bulk-memory-opt": "--enable-bulk-memory-opt",
  "multivalue": "--enable-multivalue",
  "call-indirect-overlong": "--enable-call-indirect-overlong",
  "simd128": "--enable-simd",
  "tail-call": "--enable-tail-call",
  "extended-const": "--enable-extended-const",
  "exception-handling": "--enable-exception-handling",
  "atomics": "--enable-threads",
  "multimemory": "--enable-multimemory",
  "relaxed-simd": "--enable-relaxed-simd",
};
const REFERENCE_TYPES = "reference-types";

/**
 * The module's target_features custom section: where it sits (`start` is the section id byte, `end` the byte after its
 * payload) and the features it enables. Null for bytes that are not a module or have no such section.
 */
export function readTargetFeatures(bytes) {
  if (bytes.length < 8 || bytes[0] !== 0 || bytes[1] !== 0x61 || bytes[2] !== 0x73 || bytes[3] !== 0x6d) return null;
  let at = 8;
  const leb = () => { let value = 0, shift = 0, byte; do { if (at >= bytes.length) throw new RangeError("truncated module"); byte = bytes[at++]; value += (byte & 0x7f) * 2 ** shift; shift += 7; } while (byte & 0x80); return value; };
  const text = (length) => { const name = new TextDecoder().decode(bytes.subarray(at, at + length)); at += length; return name; };
  try {
    while (at < bytes.length) {
      const start = at, id = bytes[at++], size = leb(), end = at + size;
      if (end > bytes.length) return null;
      if (id === 0 && text(leb()) === "target_features") {
        const features = [];
        for (let count = leb(); count > 0; count--) {
          const prefix = String.fromCharCode(bytes[at++]);
          features.push({ prefix, name: text(leb()) });
        }
        // Only an enabled feature ('+', or '=' for one the module requires) counts: '-' lists one it avoids.
        return { start, end, features: features.filter(({ prefix }) => prefix !== "-").map(({ name }) => name) };
      }
      at = end;
    }
  } catch (error) {
    if (!(error instanceof RangeError)) throw error;
  }
  return null;
}

/** The module without its target_features section; every other byte is as it was. Bytes without the section are returned as they are. */
export function withoutTargetFeatures(bytes) {
  const section = readTargetFeatures(bytes);
  if (!section) return bytes;
  const copy = new Uint8Array(bytes.length - (section.end - section.start));
  copy.set(bytes.subarray(0, section.start), 0);
  copy.set(bytes.subarray(section.end), section.start);
  return copy;
}

/**
 * Whether a module can be split into its own table, judged from its features alone: `{ flags }` (what to pass to Binaryen
 * for the copy without the section) or `{ reason }` for the two-table layout. Whether the module validates without
 * reference types, and whether its code leaves its table alone, is checked apart, by Binaryen (`whyNotOwnTable`).
 */
export function planLayout(bytes) {
  const section = readTargetFeatures(bytes);
  if (!section) return { reason: "the module has no target_features section" };
  if (!section.features.includes(REFERENCE_TYPES)) return { reason: "the module does not list reference types, so Binaryen keeps its default features" };
  const others = section.features.filter((name) => name !== REFERENCE_TYPES);
  const unknown = others.filter((name) => !Object.hasOwn(FEATURE_FLAGS, name));
  if (unknown.length) return { reason: `no Binaryen flag is known for the feature ${unknown.join(", ")}` };
  return { flags: ["--mvp-features", ...others.map((name) => FEATURE_FLAGS[name])] };
}

// The instructions that write a table, as `wasm-opt --metrics` names them once case and punctuation are dropped.
// `table.set` and `table.fill` need reference types, so validation refuses them first; they are listed all the same.
const TABLE_WRITES = { tablecopy: "table.copy", tableinit: "table.init", tableset: "table.set", tablefill: "table.fill" };

/**
 * Why a module cannot take the split's placeholders into its own table under exactly these flags (reference types off);
 * null when it can. Two things rule it out. Binaryen does not accept the module without reference types. Or the module's
 * code writes its function table: `table.copy` and `table.init` need bulk memory only, so validation lets them through,
 * and a placeholder sits in a slot of that table. A call the split routes through the slot would follow such a write,
 * where the unsplit module's direct call does not. One `wasm-opt` run answers both: it validates the module, and
 * `--metrics` counts each kind of instruction.
 */
export function whyNotOwnTable(path, flags) {
  const result = spawnSync("wasm-opt", [path, ...flags, "--metrics"], { encoding: "utf8" });
  if (result.error?.code === "ENOENT") throw new Error("wasm-opt (Binaryen) is not installed: brew install binaryen (or sudo apt-get install binaryen)");
  if (result.status !== 0) return `the module does not validate without reference types (${(result.stderr || result.stdout || "").split("\n").find((line) => line.trim()) ?? "wasm-opt failed"})`;
  const counts = new Map([...(result.stdout ?? "").matchAll(/^\s*(\S+)\s*:\s*(\d+)\s*$/gm)].map(([, name, count]) => [name.toLowerCase().replace(/[._-]/g, ""), Number(count)]));
  // Without the counts nothing says the table is left alone, so the layout that does not depend on it is kept.
  if (!counts.has("[funcs]")) return "wasm-opt --metrics printed no counts, so a write to the module's table cannot be ruled out";
  const writes = Object.keys(TABLE_WRITES).filter((name) => counts.get(name) > 0).map((name) => TABLE_WRITES[name]);
  return writes.length ? `the module's code writes its function table (${writes.join(", ")}), where the placeholders would sit` : null;
}

/** The cache key of a split: every input the profile run and the split depend on. */
export function cacheKey(bundle, { route, viewports, linkMap = null }) {
  const hash = createHash("sha256");
  const add = (label, bytes) => { hash.update(label); hash.update("\0"); hash.update(createHash("sha256").update(bytes).digest("hex")); hash.update("\n"); };
  add(PRIMARY, readFileSync(join(bundle, PRIMARY)));
  for (const name of PAGE_FILES) if (existsSync(join(bundle, name))) add(name, readFileSync(join(bundle, name)));
  add("script", readFileSync(SPLIT_SOURCE));
  add("data-script", readFileSync(DATA_SPLIT_SOURCE));
  add("link-map", linkMap ? linkMapKey(readFileSync(linkMap, "utf8")) : "none");
  add("binaryen", binaryenVersion());
  // The layout follows from the module's bytes and Binaryen's version, both hashed above; its flags are hashed too, so a
  // change in how they are chosen cannot match an entry made under another layout.
  const plan = planLayout(readFileSync(join(bundle, PRIMARY)));
  add("settings", JSON.stringify({ route, viewports, namespaces: [PLACEHOLDER_NAMESPACE, PRIMARY_NAMESPACE], layout: plan.flags ?? null }));
  return hash.digest("hex").slice(0, 32);
}

/** Keeps the eight most recent splits of a cache folder. */
function pruneCache(cacheDir) {
  const entries = readdirSync(cacheDir).filter((name) => name.endsWith(".rest.wasm")).map((name) => name.slice(0, -".rest.wasm".length));
  const byAge = entries.map((key) => ({ key, time: statSync(join(cacheDir, `${key}.rest.wasm`)).mtimeMs })).sort((a, b) => b.time - a.time);
  for (const { key } of byAge.slice(8)) for (const suffix of [".app.wasm", ".rest.wasm", ".prof", ".layout", ".data"]) rmSync(join(cacheDir, key + suffix), { force: true });
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error?.code === "ENOENT") throw new Error(`${command} (Binaryen) is not installed: brew install binaryen (or sudo apt-get install binaryen)`);
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed:\n${result.stderr || result.stdout}`);
  return result.stdout;
}

export function parseViewports(text) {
  return text.split(",").map((entry) => {
    const match = /^(\d+)x(\d+)$/.exec(entry.trim());
    if (!match) throw new Error(`--viewports is a list of WIDTHxHEIGHT, not ${entry}`);
    return { width: Number(match[1]), height: Number(match[2]) };
  });
}

/**
 * The mutable globals a module defines itself (not imports). A move from the Worker to the main thread carries linear
 * memory only; a global the first module owns is, in a Swift module, the stack pointer, which is back at its start between
 * passes, but a mutable global that wasm-split moved into the second module would start over there. Returns their count.
 */
export function ownMutableGlobals(bytes) {
  let at = 8;
  const leb = () => { let value = 0, shift = 0, byte; do { byte = bytes[at++]; value += (byte & 0x7f) * 2 ** shift; shift += 7; } while (byte & 0x80); return value; };
  while (at < bytes.length) {
    const id = bytes[at++], size = leb(), end = at + size;
    if (id !== 6) { at = end; continue; }
    let mutable = 0;
    for (let count = leb(), index = 0; index < count; index++) {
      at++; // value type
      if (bytes[at++] === 1) mutable++;
      // The constant expression: the opcodes a global's initializer can hold, up to its end (0x0b).
      for (let op = bytes[at++]; op !== 0x0b; op = bytes[at++]) {
        if (op === 0x41 || op === 0x42 || op === 0x23 || op === 0xd2) { while (bytes[at++] & 0x80); }
        else if (op === 0x43) at += 4;
        else if (op === 0x44) at += 8;
        else if (op === 0xd0) at++;
        else if (![0x6a, 0x6b, 0x6c, 0x7c, 0x7d, 0x7e].includes(op)) throw new Error(`unexpected opcode 0x${op.toString(16)} in a global initializer`);
      }
    }
    return mutable;
  }
  return 0;
}

/** Waits until the app is mounted and has stopped committing: its first screen. */
export async function settle(page, timeout = 60_000) {
  try {
    await page.waitForSelector(MOUNTED, { timeout, state: "attached" });
  } catch (error) {
    throw new Error(`the app did not mount within ${timeout / 1000} s (${error.message.split("\n")[0]}): the first screen cannot be profiled`);
  }
  // The first screen is ready once commits stop for `QUIET_MS`, or after `SETTLE_LIMIT_MS` for an app that never stops
  // (a TimelineView, data that keeps arriving: Food Truck's animated header and its new orders), which made the release
  // build wait forever.
  await page.evaluate(([quietMs, limitMs]) => new Promise((done) => {
    let timer = 0, finished = false;
    const finish = async () => { if (finished) return; finished = true; clearTimeout(timer); clearTimeout(limit); window.removeEventListener("commit-phase", quiet); await document.fonts.ready; done(); };
    const quiet = () => { clearTimeout(timer); timer = setTimeout(finish, quietMs); };
    const limit = setTimeout(finish, limitMs);
    window.addEventListener("commit-phase", quiet);
    quiet();
  }), [QUIET_MS, SETTLE_LIMIT_MS]);
}

/** Loads the bundle at `base` and returns the profile its first screen wrote, read from the Worker (or the page). */
async function profileOnce(browser, base, route, viewport) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: 1 });
  try {
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await page.goto(`${base}${route}`, { waitUntil: "domcontentloaded" });
    await settle(page);
    if (errors.length) throw new Error(`the instrumented bundle reported page errors: ${errors.join("; ")}`);
    for (const worker of page.workers()) {
      const profile = await worker.evaluate(READ_PROFILE).catch(() => null);
      if (profile) return { bytes: Uint8Array.from(profile), where: "worker" };
    }
    const profile = await page.evaluate(READ_PROFILE);
    if (!profile) throw new Error("no instrumented instance was found in the worker or the page");
    return { bytes: Uint8Array.from(profile), where: "page" };
  } finally {
    await context.close();
  }
}

/**
 * Runs the first screen of the bundle `checked` (a copy whose first module is instrumented and carries `dataHook` in its scripts) at
 * one viewport and returns the accesses to the moved data that happened before the second module was instantiated.
 */
async function dataReadsOnce(browser, base, route, viewport) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: 1 });
  try {
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await page.goto(`${base}${route}`, { waitUntil: "domcontentloaded" });
    await settle(page);
    // The second module arrives behind the first screen; what the first module touches until then is what counts.
    for (let tries = 0; tries < 100; tries++) {
      const loaded = [];
      for (const scope of [...page.workers(), page]) loaded.push(await scope.evaluate(() => performance.getEntriesByName("swiftuiweb-app-rest").length).catch(() => 0));
      if (loaded.some((count) => count > 0)) break;
      await new Promise((done) => setTimeout(done, 100));
    }
    if (errors.length) throw new Error(`the instrumented bundle reported page errors: ${errors.join("; ")}`);
    const reads = [];
    for (const scope of [...page.workers(), page]) reads.push(...(await scope.evaluate(() => globalThis.__swiftuiwebDataReads ?? []).catch(() => [])));
    return reads;
  } finally {
    await context.close();
  }
}

/** Loads the split bundle and checks it reaches a first screen with no page error; returns whether a call had to wait
 * for app-rest.wasm on the way (a function the profile missed, loaded synchronously). */
async function verifyOnce(browser, base, route, viewport) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: 1 });
  try {
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await page.goto(`${base}${route}`, { waitUntil: "domcontentloaded" });
    await settle(page);
    if (errors.length) throw new Error(`the split bundle reported page errors: ${errors.join("; ")}`);
    const marks = [];
    for (const scope of [...page.workers(), page]) marks.push(...await scope.evaluate(() => performance.getEntriesByName("swiftuiweb-app-rest").map((mark) => mark.detail)).catch(() => []));
    return { waited: marks.some((detail) => detail?.waited === true) };
  } finally {
    await context.close();
  }
}

/**
 * Runs the first screen with the moved data watched and returns why the move must not be shipped, or null. The first module (the
 * one that leaves the data out) is instrumented with Binaryen's `--instrument-memory`, and the hook `dataHook` notes every load
 * and store that touches the moved ranges before the second module is instantiated: the analysis in Tools/wasm-data-split.mjs
 * says there are none, and this run, over the first screen at each viewport, says whether it was right.
 */
async function checkDataMove({ browser, serveBundle, bundle, work, route, viewports, primary, secondary, runs, flags, log }) {
  try {
    const checked = servableCopy(bundle, join(work, "data-check"));
    const first = join(work, "first-with-data-moved.wasm");
    writeFileSync(first, primary);
    run("wasm-opt", [...instrumentation(flags), first, "-o", join(checked, PRIMARY)]);
    writeFileSync(join(checked, SECONDARY), secondary);
    for (const script of ["render-worker.js", "index.js"]) {
      const path = join(checked, script);
      if (existsSync(path)) writeFileSync(path, dataHook(runs) + readFileSync(path, "utf8"));
    }
    const server = await serveBundle({ bundle: checked, logName: null });
    try {
      for (const viewport of viewports) {
        const reads = await dataReadsOnce(browser, server.base, route, viewport);
        if (reads.length > 0) return `the first screen at ${viewport.width}x${viewport.height} touched moved data before ${SECONDARY} arrived (${reads.slice(0, 3).join(", ")})`;
      }
    } finally {
      await server.stop();
    }
    return null;
  } catch (error) {
    log(`warning: the data move could not be checked (${String(error?.message ?? error).split("\n")[0]})`);
    return "the check of the moved data did not run";
  }
}

/** A copy of the bundle the browser can run before the build seals it: the policy of index.html still holds the placeholder of
 * its inline-script hashes, which would block the bootstrap, so the copy's policy is sealed now. */
function servableCopy(bundle, to) {
  cpSync(bundle, to, { recursive: true });
  const index = join(to, "index.html");
  writeFileSync(index, seal(readFileSync(index, "utf8")));
  return to;
}

const brotliSize = (path) => brotliCompressSync(readFileSync(path), { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_LGWIN]: 24 } }).length;

const kb = (bytes) => `${(bytes / 1024).toFixed(1)} KB`;
const sizes = (input, primary, secondary) => ({
  before: { raw: statSync(input).size, br: brotliSize(input) },
  first: { raw: statSync(primary).size, br: brotliSize(primary) },
  rest: { raw: statSync(secondary).size, br: brotliSize(secondary) },
});
const report = ({ before, first, rest, layout }, log, how = "") =>
  log(`wasm split${how}: ${PRIMARY} ${kb(first.raw)} (${kb(first.br)} br) before the first screen, ${SECONDARY} ${kb(rest.raw)} (${kb(rest.br)} br) after it; unsplit ${kb(before.raw)} (${kb(before.br)} br)${layout ? `; ${layout}` : ""}`);

const SINGLE_TABLE = "placeholders in the module's own table";
const twoTables = (reason) => `two-table layout (${reason})`;

export async function splitBundle(bundle, { route = "/", viewports = parseViewports("1280x800,390x844"), logDir = null, verify = true, cacheDir = null, linkMap = null, log = console.log } = {}) {
  const input = join(bundle, PRIMARY);
  if (!existsSync(input)) throw new Error(`no ${PRIMARY} in ${bundle}`);
  if (existsSync(join(bundle, SECONDARY))) throw new Error(`${bundle} is split already`);
  // A build whose inputs did not change takes the split an earlier build made, and runs no browser.
  const key = cacheDir ? cacheKey(bundle, { route, viewports, linkMap }) : null;
  const cached = key ? { primary: join(cacheDir, `${key}.app.wasm`), secondary: join(cacheDir, `${key}.rest.wasm`), profile: join(cacheDir, `${key}.prof`), layout: join(cacheDir, `${key}.layout`), data: join(cacheDir, `${key}.data`) } : null;
  if (cached && existsSync(cached.primary) && existsSync(cached.secondary)) {
    const layout = existsSync(cached.layout) ? readFileSync(cached.layout, "utf8") : null;
    const data = existsSync(cached.data) ? readFileSync(cached.data, "utf8") : null;
    const measured = { ...sizes(input, cached.primary, cached.secondary), layout, data };
    cpSync(cached.primary, input);
    cpSync(cached.secondary, join(bundle, SECONDARY));
    const now = new Date();
    utimesSync(cached.secondary, now, now);
    if (logDir && existsSync(cached.profile)) { mkdirSync(logDir, { recursive: true }); cpSync(cached.profile, join(logDir, "first-screen.prof")); }
    report(measured, log, " (the split of an earlier build from the same inputs)");
    if (data) log(data);
    return measured;
  }
  const { launch, serveBundle } = await import("./browser-test-support.mjs");
  const work = mkdtempSync(join(tmpdir(), "swiftuiweb-wasm-split-"));
  try {
    // 0. The layout, decided before profiling. The copy that is instrumented is the copy that is split, with the same flags:
    // the profile carries the checksum of the module it was made for.
    let source = input, flags = [], why = null;
    const plan = planLayout(readFileSync(input));
    if (plan.flags) {
      const stripped = join(work, "without-reference-types.wasm");
      writeFileSync(stripped, withoutTargetFeatures(readFileSync(input)));
      why = whyNotOwnTable(stripped, plan.flags);
      if (!why) { source = stripped; flags = plan.flags; }
    } else why = plan.reason;
    const layout = source === input ? twoTables(why) : SINGLE_TABLE;
    // 1. The instrumented module, in a copy of the bundle whose scripts keep its instance reachable.
    const profiled = servableCopy(bundle, join(work, "profiled"));
    run("wasm-split", ["--instrument", source, "-o", join(profiled, PRIMARY), ...flags]);
    for (const script of ["render-worker.js", "index.js"]) {
      const path = join(profiled, script);
      if (existsSync(path)) writeFileSync(path, PROFILE_HOOK + readFileSync(path, "utf8"));
    }
    // 2. Its first screen, at every viewport.
    const browser = await launch({ engine: "chromium" });
    const profiles = [];
    try {
      const server = await serveBundle({ bundle: profiled, logName: null });
      try {
        for (const viewport of viewports) {
          const { bytes, where } = await profileOnce(browser, server.base, route, viewport);
          const path = join(work, `profile-${viewport.width}x${viewport.height}.prof`);
          writeFileSync(path, bytes);
          profiles.push(path);
          log(`wasm split: profiled the first screen at ${viewport.width}x${viewport.height} (${where})`);
        }
      } finally {
        await server.stop();
      }
      // 3. The split, from the merged profile.
      const profile = join(work, "first-screen.prof");
      if (profiles.length === 1) cpSync(profiles[0], profile);
      else run("wasm-split", ["--merge-profiles", ...profiles, "-o", profile]);
      const primary = join(work, PRIMARY), secondary = join(work, SECONDARY);
      run("wasm-split", ["--split", source, "--profile", profile, "-o1", primary, "-o2", secondary,
        "--placeholder-namespace", PLACEHOLDER_NAMESPACE, "--import-namespace", PRIMARY_NAMESPACE, "--strip-debug", ...flags]);
      if (logDir) {
        mkdirSync(logDir, { recursive: true });
        cpSync(profile, join(logDir, "first-screen.prof"));
      }
      const moved = ownMutableGlobals(readFileSync(secondary));
      if (moved > 0) throw new Error(`wasm-split moved ${moved} mutable global(s) into ${SECONDARY}; a move from the Worker to the main thread would start them over, so this module cannot be split`);
      // 3b. The data only the second module uses goes with it. A map that does not fit, or any doubt, leaves the data where it was.
      let data = null;
      if (linkMap) {
        let result;
        try {
          result = splitData({ primary: readFileSync(primary), secondary: readFileSync(secondary), linkMap: readFileSync(linkMap, "utf8") });
        } catch (error) {
          result = { reason: `the move failed (${String(error?.message ?? error).split("\n")[0]})` };
        }
        const problem = result.moved && !verify ? "--no-verify skips the check of the move" : result.moved ? await checkDataMove({ browser, serveBundle, bundle, work, route, viewports, primary: result.primary, secondary: result.secondary, runs: result.moved.ranges, flags: source === input ? [] : flags, log }) : null;
        if (result.moved && !problem) {
          writeFileSync(primary, result.primary);
          writeFileSync(secondary, result.secondary);
          data = `wasm split: ${kb(result.moved.bytes)} of data (${result.moved.objects} objects: vtables, metadata and strings only ${SECONDARY} uses) moved from ${PRIMARY} to ${SECONDARY}`;
        } else data = `wasm split: the data stays in ${PRIMARY} (${problem ?? result.reason})`;
      }
      const measured = { ...sizes(input, primary, secondary), layout, data };
      // 4. The split bundle still starts. It is checked in a copy, so the bundle itself only ever holds a split that passed.
      if (verify) {
        const checked = servableCopy(bundle, join(work, "split"));
        cpSync(primary, join(checked, PRIMARY));
        cpSync(secondary, join(checked, SECONDARY));
        const server = await serveBundle({ bundle: checked, logName: null });
        try {
          for (const viewport of viewports) {
            const { waited } = await verifyOnce(browser, server.base, route, viewport);
            if (waited) log(`warning: at ${viewport.width}x${viewport.height} the first screen waited for a function of ${SECONDARY} (the profile missed it)`);
          }
        } finally {
          await server.stop();
        }
      }
      cpSync(primary, input);
      cpSync(secondary, join(bundle, SECONDARY));
      if (cached) {
        mkdirSync(cacheDir, { recursive: true });
        writeFileSync(join(work, "layout.txt"), layout);
        writeFileSync(join(work, "data.txt"), data ?? "");
        for (const [from, to] of [[join(work, "layout.txt"), cached.layout], [join(work, "data.txt"), cached.data], [profile, cached.profile], [primary, cached.primary], [secondary, cached.secondary]]) {
          cpSync(from, `${to}.${process.pid}`);
          // The rest goes last: a split is in the cache once its second module is.
          cpSync(`${to}.${process.pid}`, to);
          rmSync(`${to}.${process.pid}`, { force: true });
        }
        pruneCache(cacheDir);
      }
      report(measured, log);
      if (data) log(data);
      return measured;
    } finally {
      await browser.close();
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

export async function main(argv) {
  const { values, positionals } = parseArgs({
    args: argv, allowPositionals: true,
    options: {
      route: { type: "string", default: "/" }, viewports: { type: "string", default: "1280x800,390x844" }, "log-dir": { type: "string" },
      "no-verify": { type: "boolean", default: false }, "cache-dir": { type: "string" }, "link-map": { type: "string" }, fallback: { type: "boolean", default: false },
      check: { type: "boolean", default: false },
    },
  });
  if (values.check) {
    const reason = await unavailable();
    if (reason) console.error(reason);
    return reason ? 1 : 0;
  }
  if (positionals.length !== 1) {
    console.error("usage: wasm-split-release.mjs <bundle-directory> [--route /] [--viewports 1280x800,390x844] [--log-dir DIR] [--no-verify] [--cache-dir DIR] [--link-map FILE] [--fallback]\n       wasm-split-release.mjs --check");
    return 2;
  }
  const bundle = resolve(positionals[0]);
  try {
    await splitBundle(bundle, { route: values.route, viewports: parseViewports(values.viewports), logDir: values["log-dir"] ?? null, verify: !values["no-verify"], cacheDir: values["cache-dir"] ?? null, linkMap: values["link-map"] ?? null });
  } catch (error) {
    if (!values.fallback) throw error;
    // The bundle is only written once a split passed, so it still holds the one module it had. Its runtime scripts were
    // built for a split module, though; exit 3 tells the launcher to build them again without the loader.
    console.error(`warning: this release app.wasm is NOT split (one module, downloaded whole before the first screen): ${String(error?.message ?? error).split("\n")[0]}. SWIFTUIWEB_WASM_SPLIT=0 builds without the split on purpose; SWIFTUIWEB_WASM_SPLIT=1 makes this an error.`);
    return FELL_BACK;
  }
  return 0;
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
