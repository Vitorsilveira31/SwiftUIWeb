#!/usr/bin/env bun
// Lets a test target reuse a browser bundle that an earlier build already produced from the same inputs, instead of
// compiling the same application again (a release build of the Showcase takes about 90 s; most browser suites build it).
//
//   bun Tools/bundle-reuse.mjs key <example>          prints the key of the inputs a build of <example> reads
//   bun Tools/bundle-reuse.mjs check <bundle> <key>   exit 0 when <bundle> was built from <key> and is untouched since,
//                                                     or when a copy built from <key> was kept and is now back in place
//   bun Tools/bundle-reuse.mjs stamp <bundle> <key>   records <key> and the bundle's own digest after a build, and keeps
//                                                     a copy
//
// The key covers every file a build can read (the framework, the host JavaScript and stylesheet, the test apps, the
// examples, the manifests; tracked or not, as they are on disk now), the build settings (CONFIGURATION, the WASM_*
// variables of the WebAssembly SDK and of Binaryen, and every SWIFTUIWEB_* variable that is not about tests) and the
// Swift toolchain. Tests and documents are left out, so editing a
// test does not rebuild its application. The stamp also records a digest of the bundle, so a bundle that a test or a
// person changed after the build is rebuilt rather than reused.
//
// Several targets build the same application in another configuration into the same folder (the lowering app in debug
// and in release, for example), so the last bundle of each key is also kept under .build/bundle-cache/<product>/<key>
// (a few megabytes; the newest KEPT_PER_PRODUCT keys stay) and copied back instead of compiled again.
//
// Tools/run-browser-embedded.sh calls it for `BUILD_ONLY=1` builds of the framework's own apps;
// SWIFTUIWEB_REUSE_BUNDLE=0 always builds.
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { listModules } from "./delta-compress-bundle.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const STAMP = ".bundle-inputs";
const KEPT_PER_PRODUCT = 4;

// What a build reads. Tools/ minus its tests; Tests/ only for the apps the tests build.
const INPUT_PATHS = ["Sources", "Tools", "Tests/Apps", "Examples", "Package.swift", "Package.resolved", "package.json", "bun.lock"];
const IGNORED = (path) =>
  /^Tools\/(test-[^/]*|[a-z-]*test-support\.mjs|run-test-groups\.mjs|run-scripts\.mjs|bundle-reuse\.mjs|audit-[^/]*\.mjs)$/.test(path) ||
  /\.md$/i.test(path) || path.startsWith("Tools/SwiftUIWebLowering/Tests/") || path.startsWith("Tools/LayoutConformance/");
// Variables that select what a test does, not what the build produces.
const TEST_ONLY_VARIABLES = new Set([
  "SWIFTUIWEB_BROWSER_ENGINE",
  "SWIFTUIWEB_REUSE_BUNDLE",
  "SWIFTUIWEB_AUDIT_ROOT",
  "SWIFTUIWEB_PRIVATE_TERMS",
  "SWIFTUIWEB_UPDATE_BINARY_FIXTURES",
  "SWIFTUIWEB_HTML_BENCH",
  // Where the build keeps a cache, and whether it prints a size report: neither changes the bundle.
  "WASM_STRIP_CACHE_DIR",
  "WASM_SIZE_REPORT",
]);

function inputFiles(root) {
  const listed = spawnSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", ...INPUT_PATHS], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  });
  if (listed.status !== 0) throw new Error(`git ls-files failed: ${listed.stderr}`);
  return [...new Set(listed.stdout.split("\0").filter(Boolean))].filter((path) => !IGNORED(path)).sort();
}

export function inputsKey(example, env = process.env, root = ROOT) {
  const hash = createHash("sha256");
  hash.update(`example ${example}\n`);
  for (const name of Object.keys(env).sort()) {
    if ((name === "CONFIGURATION" || name.startsWith("WASM_") || name.startsWith("SWIFTUIWEB_")) && !TEST_ONLY_VARIABLES.has(name)) {
      hash.update(`env ${name}=${env[name]}\n`);
    }
  }
  const swift = spawnSync(env.SWIFTUIWEB_SWIFT || "swift", ["--version"], { encoding: "utf8" });
  hash.update(`swift ${swift.stdout ?? ""}${swift.stderr ?? ""}\n`);
  // The earlier modules of SWIFTUIWEB_PREVIOUS_BUNDLES (their directories are in the variable above) decide the difference
  // files the build writes (Tools/delta-compress-bundle.mjs), so their bytes are inputs too.
  for (const directory of String(env.SWIFTUIWEB_PREVIOUS_BUNDLES ?? "").split(":").filter(Boolean)) {
    for (const module of listModules(directory)) {
      hash.update(`previous ${module}\n`);
      hash.update(readFileSync(join(resolve(directory), module)));
    }
  }
  for (const path of inputFiles(root)) {
    let bytes;
    try {
      bytes = readFileSync(join(root, path));
    } catch {
      continue; // listed but deleted from the working tree
    }
    hash.update(`file ${path} ${bytes.length}\n`);
    hash.update(bytes);
  }
  return hash.digest("hex");
}

/** Digest of every file of a bundle except the stamp, so a bundle edited after its build does not count as built. */
export function bundleDigest(bundle) {
  const hash = createHash("sha256");
  const walk = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stat = statSync(path);
      if (stat.isDirectory()) walk(path);
      else if (relative(bundle, path) !== STAMP) {
        hash.update(`${relative(bundle, path)} ${stat.size}\n`);
        hash.update(readFileSync(path));
      }
    }
  };
  walk(bundle);
  return hash.digest("hex");
}

export function isReusable(bundle, key) {
  const stamp = join(bundle, STAMP);
  // A release bundle names its module by content (app.3f9a1c2e.wasm), a debug one app.wasm.
  if (!existsSync(stamp) || !readdirSync(bundle).some((name) => /^app(\.[0-9a-f]+)?\.wasm$/.test(name))) return false;
  const [recordedKey, recordedDigest] = readFileSync(stamp, "utf8").trim().split(/\s+/);
  return recordedKey === key && recordedDigest === bundleDigest(bundle);
}

/** Where the copy of `bundle` built from `key` is kept: .build/bundle-cache/<product>/<key>, next to .build/browser. */
function cacheEntry(bundle, key, cacheRoot) {
  return join(cacheRoot ?? join(dirname(dirname(resolve(bundle))), "bundle-cache"), basename(bundle), key);
}

export function stamp(bundle, key, { cacheRoot } = {}) {
  writeFileSync(join(bundle, STAMP), `${key} ${bundleDigest(bundle)}\n`);
  const entry = cacheEntry(bundle, key, cacheRoot);
  rmSync(entry, { recursive: true, force: true });
  mkdirSync(dirname(entry), { recursive: true });
  cpSync(bundle, entry, { recursive: true });
  // Keep the newest few keys of this product.
  const product = dirname(entry);
  const entries = readdirSync(product).map((name) => ({ name, time: statSync(join(product, name)).mtimeMs }));
  entries.sort((a, b) => b.time - a.time).slice(KEPT_PER_PRODUCT).forEach(({ name }) => rmSync(join(product, name), { recursive: true, force: true }));
}

/** Puts the kept copy built from `key` back in place of `bundle`, when there is one and it is intact. */
export function restore(bundle, key, { cacheRoot } = {}) {
  const entry = cacheEntry(bundle, key, cacheRoot);
  if (!isReusable(entry, key)) return false;
  const next = `${resolve(bundle)}.restoring`;
  rmSync(next, { recursive: true, force: true });
  cpSync(entry, next, { recursive: true });
  rmSync(bundle, { recursive: true, force: true });
  renameSync(next, bundle);
  const now = new Date();
  utimesSync(entry, now, now); // the newest use keeps it in the cache
  return true;
}

if (import.meta.main) {
  const [command, first, second] = process.argv.slice(2);
  if (command === "key" && first) console.log(inputsKey(first));
  else if (command === "check" && first && second) {
    if (isReusable(first, second)) process.exit(0);
    if (restore(first, second)) {
      console.log(`Restored the bundle kept from an earlier build with the same inputs: ${first}`);
      process.exit(0);
    }
    process.exit(1);
  }
  else if (command === "stamp" && first && second) stamp(first, second);
  else {
    console.error("usage: bundle-reuse.mjs key <example> | check <bundle> <key> | stamp <bundle> <key>");
    process.exit(2);
  }
}
