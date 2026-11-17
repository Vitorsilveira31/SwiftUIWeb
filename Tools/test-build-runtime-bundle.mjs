#!/usr/bin/env bun
// The runtime build (Tools/build-runtime-bundle.mjs): index.js and render-worker.js share one chunk, and a release
// manifest leaves out exactly the browser hosts it proves unused.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ENTRIES, HOST_FEATURES, SHARED_CHUNK, buildRuntime, hostDefines } from "./build-runtime-bundle.mjs";

// A string only each gated host's module holds, so its presence in the output says whether the module shipped.
const MARKERS = {
  SWIFTUIWEB_HAS_MOTION: "swu-navigation-cover",
  SWIFTUIWEB_HAS_MEDIA: "media-tracks-report",
  SWIFTUIWEB_HAS_SPLIT_VIEWS: "data-split-min",
  SWIFTUIWEB_HAS_ADAPTIVE_TABS: "tab-labels",
  SWIFTUIWEB_HAS_DRAG_DROP: "dragenter",
  SWIFTUIWEB_HAS_PREDICATES: "BEGINSWITH",
};
assert.deepEqual(Object.keys(MARKERS).sort(), Object.keys(HOST_FEATURES).sort(), "every gated host needs a marker");

const temporary = mkdtempSync(join(tmpdir(), "swui-runtime-build-"));
const build = async (name, manifest) => {
  const outdir = join(temporary, name);
  await Bun.$`mkdir -p ${outdir}`;
  const written = await buildRuntime({ outdir, manifest });
  const files = Object.fromEntries(readdirSync(outdir).map((file) => [file, readFileSync(join(outdir, file), "utf8")]));
  return { written, files, all: Object.values(files).join("\n") };
};

try {
  // 1. Defines: only a feature the manifest names as false leaves; an old manifest without the key keeps the host.
  const none = Object.fromEntries(Object.values(HOST_FEATURES).map((feature) => [feature, false]));
  assert.ok(Object.values(hostDefines({ features: none })).every((value) => value === "false"));
  assert.ok(Object.values(hostDefines({ features: {} })).every((value) => value === "true"), "a feature the manifest does not name was left out");
  assert.ok(Object.values(hostDefines(null)).every((value) => value === "true"));

  // 2. Without a manifest (debug), the three files, every host, and the shared modules in the chunk only.
  const debug = await build("debug", null);
  assert.deepEqual(Object.keys(debug.files).sort(), ["index.js", "render-worker.js", SHARED_CHUNK].sort());
  assert.deepEqual(debug.written.sort(), [...Object.values(ENTRIES), SHARED_CHUNK].sort());
  for (const [name, marker] of Object.entries(MARKERS)) assert.ok(debug.all.includes(marker), `debug build lost the ${name} host (${marker})`);
  for (const entry of Object.values(ENTRIES)) {
    assert.match(debug.files[entry], /from"\.\/runtime-shared\.js"/, `${entry} does not import the shared chunk by its relative name`);
  }
  // The worker is a thin entry: the host core it runs is in the chunk, not copied into it.
  assert.ok(debug.files["render-worker.js"].length < 2048, `render-worker.js holds ${debug.files["render-worker.js"].length} bytes; the host core should be shared`);
  assert.ok(!debug.files["index.js"].includes("BEGINSWITH"), "the predicate engine is in index.js as well as in the shared chunk");

  // 3. A manifest with every gated feature unreachable leaves every host out, and is smaller.
  const release = await build("release", { features: none });
  for (const [name, marker] of Object.entries(MARKERS)) assert.ok(!release.all.includes(marker), `release build kept the ${name} host (${marker})`);
  assert.ok(release.all.length < debug.all.length - 50_000, "leaving the hosts out did not shrink the runtime");

  // 4. One feature on brings back its host alone.
  const media = await build("media", { features: { ...none, media: true } });
  assert.ok(media.all.includes(MARKERS.SWIFTUIWEB_HAS_MEDIA), "media: true did not keep the media host");
  assert.ok(!media.all.includes(MARKERS.SWIFTUIWEB_HAS_MOTION), "media: true brought the transition host back");
  console.log("runtime bundle build: ok");
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
