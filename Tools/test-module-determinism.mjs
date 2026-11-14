#!/usr/bin/env bun
// Every framework module must compile to the same `.swiftmodule` bytes from the same sources.
//
//   bun Tools/test-module-determinism.mjs [--product ShowcaseApp] [--keep]
//
// SwiftPM rebuilds every module that imports one whose `.swiftmodule` changed. A module that is not deterministic
// changes on every compile, so a comment-only edit in it rebuilt all its dependents. Embedded Swift serializes some
// functions at a different place on some compiles: specializations of closures defined in generic functions (a closure
// passed to `withUnsafePointer(to:)` from a generic function in SwiftUIWebCore, the standard library's
// `String(decoding:as:)` in SwiftUIWebHTML) and the expansion of an `isolation: = #isolation` default argument in
// SwiftUIWebNetworking (Documentation/Performance/BUILD_TIME.md, "The development loop"). The order only changes on some
// compiles, so one pass is not proof: run it several times after touching such code.
//
// The test builds the product in debug with its own development cache, records the bytes of every module, touches every
// lowered source (same bytes, newer modification time, so SwiftPM recompiles every module), builds again and compares.
// It runs the default linkage model (SWIFTUIWEB_EXPORT_INTERFACE=0), where every function body is serialized: the
// strictest case.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const { values } = parseArgs({ options: { product: { type: "string", default: "ShowcaseApp" }, keep: { type: "boolean", default: false } } });
const cache = join(ROOT, ".build", "module-determinism", values.product);

function walk(dir, visit) {
  let names;
  try { names = readdirSync(dir); } catch { return; }
  for (const name of names) {
    const path = join(dir, name);
    const info = statSync(path, { throwIfNoEntry: false });
    if (!info) continue;
    if (info.isDirectory()) walk(path, visit);
    else visit(path);
  }
}

function build(label) {
  const env = {
    ...process.env, CONFIGURATION: "debug", BUILD_ONLY: "1", SWIFTUIWEB_PRODUCT: values.product, SWIFTUIWEB_DEV_CACHE: cache,
    SWIFTUIWEB_EXPORT_INTERFACE: "0", SWIFTUIWEB_BUNDLE_ROOT: join(cache, "bundle"),
    // Touching the sources changes no byte, which the launcher would otherwise skip as a build with nothing to do.
    SWIFTUIWEB_SKIP_UNCHANGED_BUILD: "0",
  };
  const started = performance.now();
  const run = spawnSync("/bin/bash", [join(ROOT, "Tools/run-browser.sh"), values.product], { cwd: ROOT, env, encoding: "utf8", maxBuffer: 1 << 28 });
  if (run.status !== 0) {
    console.error((run.stdout + run.stderr).split("\n").slice(-40).join("\n"));
    throw new Error(`${label} build failed (exit ${run.status})`);
  }
  console.log(`${label} build: ${((performance.now() - started) / 1000).toFixed(1)} s`);
}

/** The library modules (the product's own executable module imports nothing that depends on it, so it never rebuilds
 * anything) by name: their hash, and with --keep a copy of the first build's bytes for `bcwalk`-style diagnosis. */
function moduleHashes(copyTo) {
  const hashes = new Map();
  walk(join(cache, "scratch"), (path) => {
    if (!path.endsWith(".swiftmodule") || !/\/Objects-normal\/[^/]+\/Modules\//.test(path)) return;
    const name = path.split("/").pop().replace(/\.swiftmodule$/, "");
    if (name === values.product) return;
    const bytes = readFileSync(path);
    hashes.set(name, createHash("sha256").update(bytes).digest("hex"));
    if (copyTo) { mkdirSync(copyTo, { recursive: true }); writeFileSync(join(copyTo, `${name}.swiftmodule`), bytes); }
  });
  return hashes;
}

build("first");
const before = moduleHashes(values.keep ? join(cache, "first-build-modules") : null);
if (before.size === 0) throw new Error(`no module found under ${join(cache, "scratch")}`);
// A new modification time with the same bytes: SwiftPM recompiles every module, and the lowering (which writes only
// files whose bytes change) leaves the times alone.
const later = new Date(Date.now() + 2000);
let touched = 0;
walk(join(cache, "tree", "Sources"), (path) => { if (path.endsWith(".swift")) { utimesSync(path, later, later); touched++; } });
build("second");
const after = moduleHashes();

const changed = [...before].filter(([name, hash]) => after.has(name) && after.get(name) !== hash).map(([name]) => name).sort();
console.log(`${before.size} library modules, ${touched} sources touched`);
if (!values.keep) rmSync(cache, { recursive: true, force: true });
if (changed.length) {
  console.error(`FAIL module determinism: ${changed.join(", ")} compiled to different bytes from the same sources`);
  process.exit(1);
}
console.log("PASS module determinism: every library module compiled to the same bytes twice");
