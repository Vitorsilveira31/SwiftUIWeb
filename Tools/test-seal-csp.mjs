#!/usr/bin/env bun
// Tests for Tools/seal-csp.mjs and the policy in Tools/browser-index.html.
// Run: bun test ./Tools/test-seal-csp.mjs
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { PLACEHOLDER, inlineScriptHashes, main, seal } from "./seal-csp.mjs";
import { ROOT } from "./browser-test-support.mjs";

const hash = (body) => `'sha256-${createHash("sha256").update(body).digest("base64")}'`;
const page = (policy) => `<head><meta http-equiv="Content-Security-Policy" content="script-src 'self' ${policy}"></head>
<script>var a = 1;</script>
<script src="./x.js"></script>
<script defer src="./y.js"></script>
<script type="module">await import("./index.js");</script>
<script>var a = 1;</script>
<script>   </script>`;

describe("seal-csp", () => {
  test("hashes every distinct inline script and skips external and empty ones", () => {
    assert.deepEqual(inlineScriptHashes(page("")), [hash("var a = 1;"), hash('await import("./index.js");')]);
  });

  test("fills the placeholder and never adds 'unsafe-eval'", () => {
    const sealed = seal(page(PLACEHOLDER));
    assert.ok(sealed.includes(`script-src 'self' ${hash("var a = 1;")} ${hash('await import("./index.js");')}`), sealed);
    assert.ok(!sealed.includes("__"));
    assert.ok(!sealed.includes("unsafe-eval"), "no sealed page may allow eval");
  });

  test("leaves a page with its own policy alone", () => {
    const own = page("'unsafe-inline'");
    assert.equal(seal(own), own);
  });

  test("the command line step rewrites index.html in place and rejects bad usage", () => {
    const dir = mkdtempSync(join(tmpdir(), "seal-csp-"));
    try {
      writeFileSync(join(dir, "index.html"), page(PLACEHOLDER));
      assert.equal(main([dir]), 0);
      assert.ok(readFileSync(join(dir, "index.html"), "utf8").includes(hash("var a = 1;")));
      assert.equal(main([]), 2);
      assert.equal(main(["--allow-eval", dir]), 2, "the removed --allow-eval flag is a usage error, not a silent no-op");
      assert.equal(main([join(dir, "missing")]), 1);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("the template's policy allows no script beyond its own files, WebAssembly and sealed inline scripts", () => {
    const template = readFileSync(join(ROOT, "Tools/browser-index.html"), "utf8");
    const policy = /<meta http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(template)?.[1];
    assert.ok(policy, "browser-index.html needs a Content-Security-Policy meta");
    const directives = Object.fromEntries(policy.split(";").map((part) => part.trim()).filter(Boolean).map((part) => {
      const [name, ...sources] = part.split(/\s+/);
      return [name, sources];
    }));
    assert.deepEqual(directives["script-src"], ["'self'", "'wasm-unsafe-eval'", PLACEHOLDER]);
    assert.deepEqual(directives["object-src"], ["'none'"]);
    assert.deepEqual(directives["base-uri"], ["'self'"]);
    assert.ok(!policy.includes("'unsafe-inline'") || /style-src[^;]*'unsafe-inline'/.test(policy), "'unsafe-inline' only for styles");
    // The meta comes before every script, or the script would run before the policy applies.
    assert.ok(template.indexOf("Content-Security-Policy") < template.indexOf("<script"));
  });

  // Nothing that sends text to the JavaScript engine may sit on the DOM component path. The shipped runtime files are
  // scanned as text, so a regression fails here before a browser has to refuse it (Tools/test-csp-bundles.mjs does
  // that in a real page).
  test("the DOM view path and the runtime files never compile or evaluate strings", () => {
    const files = [
      "Tools/BrowserIO/dom-view-host.mjs", "Tools/BrowserIO/browser-io.mjs", "Tools/remote-dom-host.js",
      "Tools/embedded-dom.js", "Tools/embedded-worker-client.js", "Tools/embedded-host-core.js", "Tools/embedded-runtime.js",
      ...readdirSync(join(ROOT, "Tools/BrowserIO")).filter((name) => name.endsWith(".mjs") && !name.startsWith("test-")).map((name) => `Tools/BrowserIO/${name}`),
    ];
    const forbidden = /(?<![\w.$])(?:new\s+)?(?:Function|AsyncFunction)\s*\(|(?<![\w.$])eval\s*\(|\b(?:setTimeout|setInterval)\s*\(\s*["'`]|\bimport\s*\(\s*["'`]data:/;
    const hits = [...new Set(files)].flatMap((file) => {
      const text = readFileSync(join(ROOT, file), "utf8").split("\n");
      return text.flatMap((line, index) => (forbidden.test(line.replace(/\/\/.*$/, "")) ? [`${file}:${index + 1}: ${line.trim().slice(0, 120)}`] : []));
    });
    assert.deepEqual(hits, []);
  });
});
