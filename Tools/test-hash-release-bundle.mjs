#!/usr/bin/env bun
// Tests for Tools/hash-release-bundle.mjs: the renamed files, every reference the runtime makes, and the decoys a
// rewrite must leave alone. Run: bun test ./Tools/test-hash-release-bundle.mjs
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { bundleFilePath, hashBundle, hashedName, isHashedFile, logicalName } from "./hash-release-bundle.mjs";

const HASH = /\.([0-9a-f]{8})\.[a-z0-9]+$/;

// A bundle shaped like the release output: the page, its inline bootstrap, the runtime modules and their references.
function writeBundle(root, { font = "font-a" } = {}) {
  const files = {
    "index.html": `<!doctype html>
<link rel="stylesheet" href="./styles.css">
<link rel="modulepreload" href="./index.js">
<link rel="modulepreload" href="./runtime-shared.js">
<script>globalThis.__appModuleFetch={href:new URL("./app.wasm",document.baseURI).href,response:fetch("./app.wasm")};</script>
<link rel="icon" href="./catalog-assets/A.svg">
<meta name="runtime-environment" content="SWIFTUIWEB_IMAGE_ASSETS=A=catalog-assets/A.svg">
<script defer src="./feature-loader.js"></script>
<script type="module">const { instantiate: init } = await import("./index.js");</script>`,
    "index.js": `import{r as core}from"./runtime-shared.js";
const app = new URL("./app.wasm", import.meta.url);
const extra = new URL("extra.wasm", base);
const worker = new Worker(new URL("./render-worker.js", import.meta.url));
const decoys = ["myapp.wasm", "x.index.js", "xextra.wasm", "extra.wasm.map"];`,
    "render-worker.js": `import{r}from"./runtime-shared.js";postMessage("ready");`,
    "runtime-shared.js": `export const r = 1;`,
    "app.wasm": Buffer.from([0, 97, 115, 109, 1, 0, 0, 0, 9, 9, 9]),
    "extra.wasm": Buffer.from([0, 97, 115, 109, 2, 0, 0, 0, 8, 8]),
    "styles.css": `@font-face { font-family: "F"; src: url("./fonts/F.woff2") format("woff2"); }`,
    "fonts/F.woff2": Buffer.from(font),
    "feature-loader.js": `fetch("./features-manifest.json"); import("./avfoundation.js");`,
    "features-manifest.json": `{"features":{"video":{"entry":"./avfoundation.js"}}}`,
    "avfoundation.js": `const shaka = import(new URL("shaka-loader.js", base).href); const mine = "myshaka-loader.js";`,
    "shaka-loader.js": `export default {};`,
    "catalog-assets/A.svg": `<svg xmlns="http://www.w3.org/2000/svg"/>`,
    "catalog-assets.css": `:root { --a: #fff; }`,
    "runtime-environment": `SWIFTUIWEB_IMAGE_ASSETS=A=catalog-assets/A.svg`,
    "staging/Sources/App.swift": `let wasm = "app.wasm"`,
  };
  for (const [name, content] of Object.entries(files)) {
    mkdirSync(dirname(join(root, name)), { recursive: true });
    writeFileSync(join(root, name), content);
  }
  return root;
}

const fresh = () => mkdtempSync(join(tmpdir(), "hash-bundle-"));
const cleanup = (...roots) => roots.forEach((root) => rmSync(root, { recursive: true, force: true }));
const list = (root, prefix = "") =>
  readdirSync(join(root, prefix), { withFileTypes: true })
    .flatMap((entry) => (entry.isDirectory() ? list(root, join(prefix, entry.name)) : [join(prefix, entry.name)]))
    .sort();

describe("hash-release-bundle", () => {
  test("names every framework file by the hash of its final bytes and keeps the page's name", () => {
    const root = writeBundle(fresh());
    try {
      const { renamed } = hashBundle(root);
      assert.deepEqual(
        [...renamed.keys()].sort(),
        ["app.wasm", "avfoundation.js", "catalog-assets.css", "catalog-assets/A.svg", "extra.wasm", "feature-loader.js", "features-manifest.json", "fonts/F.woff2", "index.js", "render-worker.js", "runtime-shared.js", "shaka-loader.js", "styles.css"],
      );
      for (const [from, to] of renamed) {
        assert.equal(to, hashedName(from, to.match(HASH)[1]), `${to} keeps the extension of ${from}`);
        const digest = createHash("sha256").update(readFileSync(join(root, to))).digest("hex").slice(0, 8);
        assert.equal(to.match(HASH)[1], digest, `${to} is named by the hash of its final bytes`);
        assert.equal(logicalName(to), from);
      }
      const names = list(root);
      assert.ok(names.includes("index.html") && names.includes("runtime-environment"), "the page and the environment keep their names");
      assert.ok(!names.includes("app.wasm") && !names.includes("index.js"), "no plain framework name survives");
      assert.equal(readFileSync(join(root, "staging/Sources/App.swift"), "utf8"), `let wasm = "app.wasm"`, "files outside the set are untouched");
    } finally {
      cleanup(root);
    }
  });

  test("rewrites every reference the page, the runtime, the stylesheets and the feature manifest make", () => {
    const root = writeBundle(fresh());
    try {
      const { renamed } = hashBundle(root);
      const name = (file) => renamed.get(file);

      const html = readFileSync(join(root, "index.html"), "utf8");
      assert.ok(html.includes(`href="./${name("styles.css")}"`));
      assert.ok(html.includes(`href="./${name("index.js")}"`));
      assert.ok(html.includes(`new URL("./${name("app.wasm")}",document.baseURI)`) && html.includes(`fetch("./${name("app.wasm")}")`), "the page's own wasm fetch");
      assert.ok(html.includes(`href="./${name("catalog-assets/A.svg")}"`), "the catalog image is hashed in the page");
      assert.ok(!html.includes("./catalog-assets/A.svg"), "no plain catalog reference survives in the page");
      assert.ok(html.includes(`import("./${name("index.js")}")`), "the inline bootstrap imports the hashed module");
      assert.ok(html.includes(`src="./${name("feature-loader.js")}"`));
      assert.ok(html.includes(`SWIFTUIWEB_IMAGE_ASSETS=A=${name("catalog-assets/A.svg")}`), "the runtime environment names the hashed image");

      const js = readFileSync(join(root, name("index.js")), "utf8");
      assert.ok(js.includes(`new URL("./${name("app.wasm")}", import.meta.url)`), "the wasm fetch");
      assert.ok(js.includes(`new URL("${name("extra.wasm")}", base)`), "the second wasm fetch");
      assert.ok(js.includes(`new URL("./${name("render-worker.js")}", import.meta.url)`), "the worker URL");
      // The chunk the runtime and the worker share (Tools/build-runtime-bundle.mjs), as the minified import names it.
      assert.ok(js.includes(`from"./${name("runtime-shared.js")}"`), "the runtime's import of the shared chunk");
      assert.ok(readFileSync(join(root, name("render-worker.js")), "utf8").includes(`from"./${name("runtime-shared.js")}"`), "the worker's import of the shared chunk");
      assert.ok(html.includes(`href="./${name("runtime-shared.js")}"`), "the shared chunk's preload");
      assert.ok(js.includes(`["myapp.wasm", "x.index.js", "xextra.wasm", "extra.wasm.map"]`), "decoy names are untouched");

      const css = readFileSync(join(root, name("styles.css")), "utf8");
      assert.ok(css.includes(`url("./${name("fonts/F.woff2")}")`), "the font url() in the stylesheet");

      const feature = readFileSync(join(root, name("feature-loader.js")), "utf8");
      assert.ok(feature.includes(`fetch("./${name("features-manifest.json")}")`));
      assert.ok(feature.includes(`import("./${name("avfoundation.js")}")`));

      const manifest = readFileSync(join(root, name("features-manifest.json")), "utf8");
      assert.ok(manifest.includes(`"./${name("avfoundation.js")}"`), "the feature manifest names the hashed entry");

      const avfoundation = readFileSync(join(root, name("avfoundation.js")), "utf8");
      assert.ok(avfoundation.includes(`new URL("${name("shaka-loader.js")}", base)`));
      assert.ok(avfoundation.includes(`"myshaka-loader.js"`), "a longer name ending in the same letters is untouched");
    } finally {
      cleanup(root);
    }
  });

  test("a stylesheet gets a new name when a font it loads changes, although its own text does not", () => {
    const first = writeBundle(fresh(), { font: "font-a" });
    const second = writeBundle(fresh(), { font: "font-b" });
    try {
      const a = hashBundle(first).renamed.get("styles.css");
      const b = hashBundle(second).renamed.get("styles.css");
      assert.notEqual(a, b, "the stylesheet's cached copy cannot outlive the font it points to");
    } finally {
      cleanup(first, second);
    }
  });

  test("the same bytes always get the same names", () => {
    const first = writeBundle(fresh());
    const second = writeBundle(fresh());
    try {
      assert.deepEqual([...hashBundle(first).renamed], [...hashBundle(second).renamed]);
    } finally {
      cleanup(first, second);
    }
  });

  test("refuses to hash a bundle that is already hashed", () => {
    const root = writeBundle(fresh());
    try {
      hashBundle(root);
      assert.throws(() => hashBundle(root), /already has a content-hashed name/);
    } finally {
      cleanup(root);
    }
  });

  test("refuses references that form a cycle", () => {
    const root = fresh();
    try {
      writeFileSync(join(root, "index.html"), `<script src="./a.js"></script>`);
      writeFileSync(join(root, "a.js"), `import "./b.js";`);
      writeFileSync(join(root, "b.js"), `import "./a.js";`);
      assert.throws(() => hashBundle(root), /cycle/);
    } finally {
      cleanup(root);
    }
  });

  test("finds a bundle file by its logical name, plain or hashed", () => {
    const root = writeBundle(fresh());
    try {
      assert.equal(bundleFilePath(root, "index.html"), join(root, "index.html"));
      assert.equal(bundleFilePath(root, "app.wasm"), join(root, "app.wasm"));
      const { renamed } = hashBundle(root);
      assert.equal(bundleFilePath(root, "app.wasm"), join(root, renamed.get("app.wasm")));
      assert.equal(bundleFilePath(root, "missing.wasm"), null);
      assert.equal(bundleFilePath(join(root, "absent"), "app.wasm"), null);
    } finally {
      cleanup(root);
    }
  });

  test("names and the set of hashed files", () => {
    assert.equal(hashedName("app.wasm", "3f9a1c2e"), "app.3f9a1c2e.wasm");
    assert.equal(hashedName("catalog-assets/A.svg", "00000001"), "catalog-assets/A.00000001.svg");
    assert.equal(logicalName("app.3f9a1c2e.wasm"), "app.wasm");
    assert.equal(logicalName("index.html"), "index.html");
    assert.equal(isHashedFile("index.html"), false);
    assert.equal(isHashedFile("catalog-assets/x.png"), true);
    assert.equal(isHashedFile("fonts/F.woff2"), true);
    assert.equal(isHashedFile("runtime-environment"), false);
    assert.equal(isHashedFile("swift-build.log"), false);
  });
});
