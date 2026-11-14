#!/usr/bin/env bun
// Debug development loop only: gives an application's own library targets the framework's linkage model.
//
//   bun Tools/dev-consumer-manifest.mjs <staged Package.swift> [...]
//
// The Embedded SDK's toolset builds every target with `-enable-experimental-feature Embedded -wmo` and nothing else, so
// an application's library target (a `Shared` module next to the browser executable) emits object code for the whole
// transitive closure of what it uses, the framework included, and the executable emits it all again. With
// DeferredCodeGen a library emits only what was marked `@export(interface)` and leaves the rest to the executable, as the
// framework's own libraries do in this loop (Tools/run-browser-embedded.sh, SWIFTUIWEB_LIBRARY_CODEGEN).
//
// The launcher runs this on the STAGED copies of the application's manifests, never on the checkout. It appends one
// loop to the manifest, after its `let package = Package(...)`; a manifest without that declaration, or already
// patched, is left alone. Prints what it did per file.
import { readFileSync, writeFileSync } from "node:fs";

const MARKER = "// SwiftUIWeb development loop: DeferredCodeGen for the application's library targets.";
const SNIPPET = `

${MARKER}
// Added to the staged copy by Tools/dev-consumer-manifest.mjs (debug development loop only).
for target in package.targets where target.type == .regular {
  target.swiftSettings = (target.swiftSettings ?? []) + [.enableExperimentalFeature("DeferredCodeGen")]
}
`;

export function patchManifest(text) {
  if (text.includes(MARKER)) return { text, status: "already patched" };
  if (!/^\s*(public\s+)?let\s+package\s*=\s*Package\s*\(/m.test(text)) return { text, status: "no `let package = Package(`; left alone" };
  return { text: text.replace(/\s*$/, "") + SNIPPET, status: "patched" };
}

if (import.meta.main) {
  const paths = process.argv.slice(2);
  if (paths.length === 0) {
    console.error("usage: bun Tools/dev-consumer-manifest.mjs <staged Package.swift> [...]");
    process.exit(64);
  }
  for (const path of paths) {
    const original = readFileSync(path, "utf8");
    const { text, status } = patchManifest(original);
    if (text !== original) writeFileSync(path, text);
    console.log(`${path}: ${status}`);
  }
}
