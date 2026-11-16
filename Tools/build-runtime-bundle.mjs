#!/usr/bin/env bun
// Builds the JavaScript runtime of a browser bundle: `index.js` (the page's runtime, Tools/embedded-runtime.js),
// `render-worker.js` (the Swift worker, Tools/embedded-worker.js) and `runtime-shared.js`, the modules both import
// (BrowserIO, the host core, the WASI host, ...). The two entry points are built together with code splitting, so the
// shared modules are downloaded once instead of once per entry point. Both entries import the chunk by its relative
// name; index.html announces it with a modulepreload (Tools/rewrite-release-index.js), and a release names it by its
// content like the other files (Tools/hash-release-bundle.mjs).
//
// With `--manifest` (release), the browser hosts the reachability manifest proves unused leave the build. Each optional
// host is constructed behind a guard on one build-time constant, written inline at the use (bun does not fold a constant
// across a variable), such as `(typeof SWIFTUIWEB_HAS_MOTION === 'undefined' || SWIFTUIWEB_HAS_MOTION)`. Unbundled, and
// in a debug bundle, the constant is undefined and every host is there. A release defines it from the manifest's
// `features` (Tools/release-reachability.js): `false` when the application shows no use of the feature, and dead-code
// elimination drops the host's module. Nothing is loaded later, so a host that is left out costs no round trip. A feature
// the manifest does not name (one written before the feature existed) stays on.
//
// usage: build-runtime-bundle.mjs --outdir <bundle-directory> [--manifest <release-manifest.json>]
// Run the tests with: bun Tools/test-build-runtime-bundle.mjs

import { mkdtempSync, readFileSync, readdirSync, renameSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
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
  // tab-shell.js, the `.sidebarAdaptable` TabView presentation: a TabView is navigation evidence.
  SWIFTUIWEB_HAS_ADAPTIVE_TABS: "navigation",
  // NativeDragDropCoordinator in host-interactions.js.
  SWIFTUIWEB_HAS_DRAG_DROP: "dragDrop",
  // BrowserIO/predicate-engine.mjs, in the page and in the worker.
  SWIFTUIWEB_HAS_PREDICATES: "predicates",
});

/** The entry points and the names they get in the bundle. */
export const ENTRIES = Object.freeze({ "embedded-runtime.js": "index.js", "embedded-worker.js": "render-worker.js" });
/** The one chunk both entries share. */
export const SHARED_CHUNK = "runtime-shared.js";

/** `{name: "true" | "false"}` for every gated host: false only when the manifest says its feature is unreachable. */
export function hostDefines(manifest) {
  const features = manifest?.features || {};
  return Object.fromEntries(Object.entries(HOST_FEATURES).map(([name, feature]) => [name, String(features[feature] !== false)]));
}

/** Writes `index.js`, `render-worker.js` and `runtime-shared.js` into `outdir`. Returns the names written. */
export async function buildRuntime({ outdir, manifest = null }) {
  const scratch = mkdtempSync(join(resolve(outdir), ".runtime-build-"));
  try {
    const result = await Bun.build({
      entrypoints: Object.keys(ENTRIES).map((entry) => join(TOOLS, entry)),
      outdir: scratch,
      target: "browser",
      format: "esm",
      minify: true,
      splitting: true,
      naming: { entry: "[name].[ext]", chunk: SHARED_CHUNK },
      define: manifest ? hostDefines(manifest) : {},
    });
    if (!result.success) throw new AggregateError(result.logs, "the runtime build failed");
    const written = readdirSync(scratch).sort();
    const expected = [...Object.keys(ENTRIES), SHARED_CHUNK].sort();
    // A second chunk would need its own preload and name: fail instead of shipping a page that requests an unknown file.
    if (written.length !== expected.length || written.some((name, index) => name !== expected[index])) {
      throw new Error(`the runtime build wrote ${written.join(", ")}; expected ${expected.join(", ")}`);
    }
    for (const [entry, name] of Object.entries(ENTRIES)) renameSync(join(scratch, entry), join(outdir, name));
    renameSync(join(scratch, SHARED_CHUNK), join(outdir, SHARED_CHUNK));
    return [...Object.values(ENTRIES), SHARED_CHUNK];
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
    console.error("usage: build-runtime-bundle.mjs --outdir <bundle-directory> [--manifest <release-manifest.json>]");
    return 2;
  }
  const manifest = manifestPath ? JSON.parse(readFileSync(manifestPath, "utf8")) : null;
  await buildRuntime({ outdir, manifest });
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main();
}
