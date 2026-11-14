// Adaptive media plays from the bundle's own origin: the media helper imports the Shaka build that
// `shaka-loader.js` compiles from the version pinned in package.json, never a CDN.
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = new URL("..", import.meta.url);
const helper = readFileSync(new URL("Tools/avfoundation.js", root), "utf8");
assert.ok(!/import\(\s*["'`]https?:/.test(helper), "the media helper must not import from another origin");
assert.ok(helper.includes('new URL("shaka-loader.js"'), "the media helper loads the bundled Shaka helper");

const manifest = JSON.parse(readFileSync(new URL("package.json", root), "utf8"));
assert.match(manifest.devDependencies["shaka-player"] ?? "", /^\d+\.\d+\.\d+$/, "Shaka is pinned to an exact version");

// The bundler must leave the Shaka import to the browser: inlined, every page using a video would
// download Shaka with the helper, and the helper would no longer stay under a kilobyte.
const out = mkdtempSync(join(tmpdir(), "swiftuiweb-shaka-"));
try {
  const media = await Bun.build({ entrypoints: [new URL("Tools/avfoundation.js", root).pathname], outdir: out, minify: true });
  assert.ok(media.success, "the media helper builds");
  assert.ok(media.outputs[0].size < 4096, `the media helper inlined Shaka (${media.outputs[0].size} bytes)`);
  const shaka = await Bun.build({ entrypoints: [new URL("Tools/shaka-loader.js", root).pathname], outdir: out, minify: true, format: "esm" });
  assert.ok(shaka.success && shaka.outputs[0].size > 100_000, "the Shaka helper bundles the player");
  const source = await shaka.outputs[0].text();
  assert.ok(/export\s*\{[^}]*as default/.test(source), "the Shaka helper has a default export");
} finally {
  rmSync(out, { recursive: true, force: true });
}
console.log("adaptive media is same-origin: ok");
