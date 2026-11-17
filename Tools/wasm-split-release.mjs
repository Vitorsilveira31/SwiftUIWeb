#!/usr/bin/env bun
// Splits a release bundle's app.wasm in two by what its first screen runs (the release default; SWIFTUIWEB_WASM_SPLIT=0
// turns it off, Documentation/Architecture/WASM_SPLIT.md).
//
// The page then downloads, before the first screen, only the functions that screen needs (`app.wasm`); the rest
// (`app-rest.wasm`) downloads right after it, in the background. Tools/wasm-split-loader.js loads the second module:
// a call that needs a function of it before it arrived waits for it, it does not fail.
//
//   1. Binaryen's `wasm-split --instrument` writes a copy of app.wasm that records which functions run.
//   2. A copy of the bundle with that module runs in headless Chromium, in the Worker as a page runs it by default,
//      until its first screen is up: the app is mounted and has stopped committing (400 ms without a commit), at every
//      viewport of --viewports, so that the compact and the regular layout are both counted.
//   3. `wasm-split --split --profile` moves every function no run reached into app-rest.wasm; the profiles of the
//      viewports are merged first. The modules do not go through `wasm-opt` again: on the Board that made both larger
//      over the wire (+0.9 KB brotli) for 5 KB less raw.
//   4. Unless --no-verify, the split bundle is loaded once more and must reach a first screen with no page error.
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
//                               [--cache-dir DIR] [--fallback]
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

export const PRIMARY = "app.wasm";
export const SECONDARY = "app-rest.wasm";
// The placeholders' namespace prefix (Tools/wasm-split-loader.js): one short word, as it is repeated for every moved function.
export const PLACEHOLDER_NAMESPACE = "p";
export const PRIMARY_NAMESPACE = "primary";
const MOUNTED = 'html[data-embedded-mounted="true"]';
const QUIET_MS = 400;

// Keeps the instance of an instrumented module where the evaluation below finds it. Prepended to the copy of the
// worker's and the page's script that the profiling run loads, never to the bundle that ships.
const PROFILE_HOOK = `{const instantiate=WebAssembly.instantiate;WebAssembly.instantiate=function(...args){return instantiate.apply(this,args).then(result=>{const instance=result instanceof WebAssembly.Instance?result:result.instance;if(instance&&instance.exports&&instance.exports.__write_profile)globalThis.__swiftuiwebProfiled=instance;return result;});};}\n`;

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

/** The cache key of a split: every input the profile run and the split depend on. */
export function cacheKey(bundle, { route, viewports }) {
  const hash = createHash("sha256");
  const add = (label, bytes) => { hash.update(label); hash.update("\0"); hash.update(createHash("sha256").update(bytes).digest("hex")); hash.update("\n"); };
  add(PRIMARY, readFileSync(join(bundle, PRIMARY)));
  for (const name of PAGE_FILES) if (existsSync(join(bundle, name))) add(name, readFileSync(join(bundle, name)));
  add("script", readFileSync(SPLIT_SOURCE));
  add("binaryen", binaryenVersion());
  add("settings", JSON.stringify({ route, viewports, namespaces: [PLACEHOLDER_NAMESPACE, PRIMARY_NAMESPACE] }));
  return hash.digest("hex").slice(0, 32);
}

/** Keeps the eight most recent splits of a cache folder. */
function pruneCache(cacheDir) {
  const entries = readdirSync(cacheDir).filter((name) => name.endsWith(".rest.wasm")).map((name) => name.slice(0, -".rest.wasm".length));
  const byAge = entries.map((key) => ({ key, time: statSync(join(cacheDir, `${key}.rest.wasm`)).mtimeMs })).sort((a, b) => b.time - a.time);
  for (const { key } of byAge.slice(8)) for (const suffix of [".app.wasm", ".rest.wasm", ".prof"]) rmSync(join(cacheDir, key + suffix), { force: true });
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
  await page.evaluate((quietMs) => new Promise((done) => {
    let timer = 0;
    const quiet = () => { clearTimeout(timer); timer = setTimeout(async () => { await document.fonts.ready; done(); }, quietMs); };
    window.addEventListener("commit-phase", quiet);
    quiet();
  }), QUIET_MS);
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
const report = ({ before, first, rest }, log, how = "") =>
  log(`wasm split${how}: ${PRIMARY} ${kb(first.raw)} (${kb(first.br)} br) before the first screen, ${SECONDARY} ${kb(rest.raw)} (${kb(rest.br)} br) after it; unsplit ${kb(before.raw)} (${kb(before.br)} br)`);

export async function splitBundle(bundle, { route = "/", viewports = parseViewports("1280x800,390x844"), logDir = null, verify = true, cacheDir = null, log = console.log } = {}) {
  const input = join(bundle, PRIMARY);
  if (!existsSync(input)) throw new Error(`no ${PRIMARY} in ${bundle}`);
  if (existsSync(join(bundle, SECONDARY))) throw new Error(`${bundle} is split already`);
  // A build whose inputs did not change takes the split an earlier build made, and runs no browser.
  const key = cacheDir ? cacheKey(bundle, { route, viewports }) : null;
  const cached = key ? { primary: join(cacheDir, `${key}.app.wasm`), secondary: join(cacheDir, `${key}.rest.wasm`), profile: join(cacheDir, `${key}.prof`) } : null;
  if (cached && existsSync(cached.primary) && existsSync(cached.secondary)) {
    const measured = sizes(input, cached.primary, cached.secondary);
    cpSync(cached.primary, input);
    cpSync(cached.secondary, join(bundle, SECONDARY));
    const now = new Date();
    utimesSync(cached.secondary, now, now);
    if (logDir && existsSync(cached.profile)) { mkdirSync(logDir, { recursive: true }); cpSync(cached.profile, join(logDir, "first-screen.prof")); }
    report(measured, log, " (the split of an earlier build from the same inputs)");
    return measured;
  }
  const { launch, serveBundle } = await import("./browser-test-support.mjs");
  const work = mkdtempSync(join(tmpdir(), "swiftuiweb-wasm-split-"));
  try {
    // 1. The instrumented module, in a copy of the bundle whose scripts keep its instance reachable.
    const profiled = servableCopy(bundle, join(work, "profiled"));
    run("wasm-split", ["--instrument", input, "-o", join(profiled, PRIMARY)]);
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
      run("wasm-split", ["--split", input, "--profile", profile, "-o1", primary, "-o2", secondary,
        "--placeholder-namespace", PLACEHOLDER_NAMESPACE, "--import-namespace", PRIMARY_NAMESPACE, "--strip-debug"]);
      if (logDir) {
        mkdirSync(logDir, { recursive: true });
        cpSync(profile, join(logDir, "first-screen.prof"));
      }
      const moved = ownMutableGlobals(readFileSync(secondary));
      if (moved > 0) throw new Error(`wasm-split moved ${moved} mutable global(s) into ${SECONDARY}; a move from the Worker to the main thread would start them over, so this module cannot be split`);
      const measured = sizes(input, primary, secondary);
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
        for (const [from, to] of [[profile, cached.profile], [primary, cached.primary], [secondary, cached.secondary]]) {
          cpSync(from, `${to}.${process.pid}`);
          // The rest goes last: a split is in the cache once its second module is.
          cpSync(`${to}.${process.pid}`, to);
          rmSync(`${to}.${process.pid}`, { force: true });
        }
        pruneCache(cacheDir);
      }
      report(measured, log);
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
      "no-verify": { type: "boolean", default: false }, "cache-dir": { type: "string" }, fallback: { type: "boolean", default: false },
      check: { type: "boolean", default: false },
    },
  });
  if (values.check) {
    const reason = await unavailable();
    if (reason) console.error(reason);
    return reason ? 1 : 0;
  }
  if (positionals.length !== 1) {
    console.error("usage: wasm-split-release.mjs <bundle-directory> [--route /] [--viewports 1280x800,390x844] [--log-dir DIR] [--no-verify] [--cache-dir DIR] [--fallback]\n       wasm-split-release.mjs --check");
    return 2;
  }
  const bundle = resolve(positionals[0]);
  try {
    await splitBundle(bundle, { route: values.route, viewports: parseViewports(values.viewports), logDir: values["log-dir"] ?? null, verify: !values["no-verify"], cacheDir: values["cache-dir"] ?? null });
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
