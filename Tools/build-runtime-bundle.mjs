#!/usr/bin/env bun
// Builds the JavaScript runtime of a browser bundle: `index.js` (the page's runtime, Tools/embedded-runtime.js),
// `render-worker.js` (the Swift worker, Tools/embedded-worker.js), `runtime-shared.js`, the modules both import
// (BrowserIO, the host core, the WASI host, ...), and `runtime-deferred.js` (Tools/deferred-hosts.js), the page's hosts
// the first screen does not run. The entry points are built together with code splitting, so the shared modules are
// downloaded once instead of once per entry point. Both runtime entries import the shared chunk by its relative name;
// index.html announces it with a modulepreload (Tools/rewrite-release-index.js), and a release names every file by its
// content (Tools/hash-release-bundle.mjs).
//
// `runtime-deferred.js` is what embedded-dom.js requests with import(), by URL as the worker is requested, once the first
// publication is on screen: the first screen neither downloads nor parses it, nothing a person does waits for it, and no
// preload announces it. Its modules import nothing. A module both it and index.js imported would be split into a chunk of
// its own, one more file before the first screen: the build refuses any chunk besides the shared one.
//
// With `--manifest` (release), the browser hosts the reachability manifest proves unused leave the build. Each optional
// host is constructed behind a guard on one build-time constant, written inline at the use (bun does not fold a constant
// across a variable), such as `(typeof SWIFTUIWEB_HAS_MOTION === 'undefined' || SWIFTUIWEB_HAS_MOTION)`. Unbundled, and
// in a debug bundle, the constant is undefined and every host is there. A release defines it from the manifest's
// `features` (Tools/release-reachability.js): `false` when the application shows no use of the feature, and dead-code
// elimination drops the host's module. A host that is left out is not loaded later either. A feature the manifest does
// not name (one written before the feature existed) stays on.
//
// The loader of a split module (Tools/wasm-split-loader.js) has its own constant, `globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER`:
// every build the launcher makes defines it, true only with `--wasm-split` (SWIFTUIWEB_WASM_SPLIT=1), so a bundle that is not
// split carries none of it. Unbundled (the tests) it is undefined and the loader stays.
//
// usage: build-runtime-bundle.mjs --outdir <bundle-directory> [--manifest <release-manifest.json>] [--wasm-split]
// Run the tests with: bun Tools/test-build-runtime-bundle.mjs

import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const TOOLS = dirname(fileURLToPath(import.meta.url));

/** The build-time constant of each gated host, and the manifest feature that keeps it. */
export const HOST_FEATURES = Object.freeze({
  // transition-host.js: TransitionHost, ScrollTransitionHost, MatchedGeometryHost.
  SWIFTUIWEB_HAS_MOTION: "motion",
  // media-host.js.
  SWIFTUIWEB_HAS_MEDIA: "media",
  // split-view-host.js.
  SWIFTUIWEB_HAS_SPLIT_VIEWS: "splitViews",
  // lottie-host.js, the player of a MotionView (lottie-loader.js is a lazy helper of its own, release-reachability.js).
  SWIFTUIWEB_HAS_LOTTIE: "lottie",
  // tab-shell.js, the `.sidebarAdaptable` TabView presentation: a TabView is navigation evidence.
  SWIFTUIWEB_HAS_ADAPTIVE_TABS: "navigation",
  // NativeDragDropCoordinator in transfer-host.js, which deferred-hosts.js gathers.
  SWIFTUIWEB_HAS_DRAG_DROP: "dragDrop",
  // BrowserIO/predicate-engine.mjs, in the page and in the worker.
  SWIFTUIWEB_HAS_PREDICATES: "predicates",
});

/** The file index.js loads with import() after the first screen (Tools/deferred-hosts.js). */
export const DEFERRED_CHUNK = "runtime-deferred.js";
/** The entry points and the names they get in the bundle. */
export const ENTRIES = Object.freeze({ "embedded-runtime.js": "index.js", "embedded-worker.js": "render-worker.js", "deferred-hosts.js": DEFERRED_CHUNK });
/** The one chunk the page's runtime and the worker share. */
export const SHARED_CHUNK = "runtime-shared.js";

/** `{name: "true" | "false"}` for every gated host: false only when the manifest says its feature is unreachable. */
export function hostDefines(manifest) {
  const features = manifest?.features || {};
  return Object.fromEntries(Object.entries(HOST_FEATURES).map(([name, feature]) => [name, String(features[feature] !== false)]));
}

/**
 * The bundle name of each file the build wrote (`{written: name}`), from the outputs Bun reports: the entries by their
 * names and the one chunk as the shared one. Throws on any other output. A second chunk is what a module imported both
 * by deferred-hosts.js and by the first screen (or the worker) becomes: a file no page announces, and one more request
 * before the first screen.
 */
export function bundleNames(outputs) {
  const names = {};
  const chunks = [];
  for (const output of outputs) {
    const written = basename(output.path);
    if (output.kind === "entry-point" && ENTRIES[written]) names[written] = ENTRIES[written];
    else if (output.kind === "chunk") chunks.push(written);
    else throw new Error(`the runtime build wrote ${written} (${output.kind}), which is neither an entry nor a chunk it names`);
  }
  if (chunks.length !== 1 || Object.keys(names).length !== Object.keys(ENTRIES).length) {
    throw new Error(`the runtime build wrote the chunks ${chunks.join(", ") || "(none)"}; expected the one index.js and the `
      + `worker share. A module that deferred-hosts.js imports and the first screen imports too becomes a chunk of its own: `
      + `hand the deferred host what it needs instead of importing it.`);
  }
  names[chunks[0]] = SHARED_CHUNK;
  return names;
}

/** `text` with every quoted relative reference to a written file (`"./embedded-runtime-1a2b.js"`, `'./deferred-hosts.js'`)
 * given its bundle name. */
export function renameReferences(text, names) {
  for (const [written, name] of Object.entries(names)) {
    for (const quote of ['"', "'", "`"]) text = text.split(`${quote}./${written}${quote}`).join(`${quote}./${name}${quote}`);
  }
  return text;
}

/** Writes `index.js`, `render-worker.js`, `runtime-shared.js` and `runtime-deferred.js` into `outdir`. Returns the names written. */
export async function buildRuntime({ outdir, manifest = null, wasmSplit = false }) {
  const scratch = mkdtempSync(join(resolve(outdir), ".runtime-build-"));
  try {
    const result = await Bun.build({
      entrypoints: Object.keys(ENTRIES).map((entry) => join(TOOLS, entry)),
      outdir: scratch,
      target: "browser",
      format: "esm",
      minify: true,
      splitting: true,
      naming: { entry: "[name].[ext]", chunk: "[name]-[hash].[ext]" },
      define: { ...(manifest ? hostDefines(manifest) : {}), "globalThis.SWIFTUIWEB_WASM_SPLIT_LOADER": String(wasmSplit) },
    });
    if (!result.success) throw new AggregateError(result.logs, "the runtime build failed");
    const names = bundleNames(result.outputs);
    const written = readdirSync(scratch).sort();
    const reported = Object.keys(names).sort();
    if (written.length !== reported.length || written.some((name, index) => name !== reported[index])) {
      throw new Error(`the runtime build wrote ${written.join(", ")}; Bun reported ${reported.join(", ")}`);
    }
    // The imports between the files (and Bun's table of them for import()) name the files as the build wrote them.
    for (const [file, name] of Object.entries(names)) writeFileSync(join(outdir, name), renameReferences(readFileSync(join(scratch, file), "utf8"), names));
    return Object.values(names).sort();
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

function argument(argv, name) {
  const index = argv.indexOf(name);
  return index >= 0 && index + 1 < argv.length ? argv[index + 1] : null;
}

export async function main(argv = process.argv.slice(2)) {
  const outdir = argument(argv, "--outdir");
  const manifestPath = argument(argv, "--manifest");
  if (!outdir) {
    console.error("usage: build-runtime-bundle.mjs --outdir <bundle-directory> [--manifest <release-manifest.json>] [--wasm-split]");
    return 2;
  }
  const manifest = manifestPath ? JSON.parse(readFileSync(manifestPath, "utf8")) : null;
  await buildRuntime({ outdir, manifest, wasmSplit: argv.includes("--wasm-split") });
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main();
}
