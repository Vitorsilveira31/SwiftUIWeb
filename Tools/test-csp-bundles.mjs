#!/usr/bin/env bun
// Every example bundle must load under the Content-Security-Policy it ships with, without one violation.
//
// A bundle's index.html carries the policy (Tools/seal-csp.mjs fills in the hashes of its inline scripts; no bundle allows
// eval, and DOM components are registered functions from the application's own files). A page that breaks its own policy fails quietly: the browser blocks the script and
// writes one console line. This loads each bundle in a real browser and fails on any `securitypolicyviolation` event or
// "Content Security Policy" console message.
//
// usage: bun Tools/test-csp-bundles.mjs              the self-test, then every bundle below .build/browser; it also fails when a
//                                                    product the Makefile builds has no bundle there (the list is not hardcoded)
//        bun Tools/test-csp-bundles.mjs --self-test  only the self-test (no bundle needed)
//        bun Tools/test-csp-bundles.mjs <bundle>...  the self-test, then those bundle directories
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { launch, ROOT, runSuite, serveStatic } from "./browser-test-support.mjs";

/** The violations a bundle's page reports while it loads (and settles), as readable lines. */
export async function violationsOf(browser, bundle) {
  return (await scanBundle(browser, bundle)).violations;
}

/**
 * Loads a bundle's page and returns its violations plus, when `inspect(page)` is given, what it returned once the page
 * settled (a test page reports through it).
 */
export async function scanBundle(browser, bundle, inspect) {
  const server = serveStatic(bundle);
  const page = await browser.newPage();
  const found = [];
  try {
    page.on("console", (message) => {
      if (/content security policy/i.test(message.text())) found.push(`console ${message.type()}: ${message.text().slice(0, 240)}`);
    });
    page.on("pageerror", (error) => {
      if (/content security policy|unsafe-eval/i.test(String(error))) found.push(`page error: ${String(error).slice(0, 240)}`);
    });
    await page.addInitScript(() => {
      window.__cspViolations = [];
      document.addEventListener("securitypolicyviolation", (event) => {
        window.__cspViolations.push(`${event.violatedDirective} blocked ${event.blockedURI || "inline"} (${event.sourceFile || "page"}:${event.lineNumber})`);
      });
    });
    await page.goto(server.base + "/", { waitUntil: "load" });
    // An embedded application announces itself once mounted; a plain page is done at load. Two frames let late scripts run.
    await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 20_000 }).catch(() => {});
    await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
    const result = inspect ? await inspect(page) : undefined;
    found.push(...(await page.evaluate(() => window.__cspViolations)).map((line) => `violation: ${line}`));
    return { violations: found, result };
  } finally {
    await page.close();
    await server.stop();
  }
}

/**
 * A page with the shipped policy (own files only, no eval) that runs the real DOM view host: a component registered before
 * the host starts through the documented queue, one whose factory imports its code on first use, and a mount cancelled
 * before its definition arrives. It reports what each lifecycle phase did.
 */
function domComponentBundle(directory) {
  mkdirSync(directory, { recursive: true });
  copyFileSync(join(ROOT, "Tools/BrowserIO/dom-view-host.mjs"), join(directory, "dom-view-host.mjs"));
  writeFileSync(join(directory, "index.html"), `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'wasm-unsafe-eval'"><title>t</title><script src="./early.js"></script><script type="module" src="./main.js"></script></head><body><div id="host"></div></body></html>`);
  writeFileSync(join(directory, "early.js"), `
    (globalThis.SwiftUIWebDOMComponents ??= { queue: [], define(name, factory) { this.queue.push([name, factory]); } }).define("early", () => ({
      mount(host, root, emit, state) { const log = window.__domLog; log.push("mount:" + state); emit("hello"); const label = document.createElement("span"); label.textContent = state; root.append(label); return { label }; },
      update(instance, state) { window.__domLog.push("update:" + state); instance.label.textContent = state; },
      dispose(instance) { window.__domLog.push("dispose:" + instance.label.textContent); },
    }));`);
  writeFileSync(join(directory, "lazy-component.js"), `
    window.__domLog.push("lazy-code-loaded");
    export default { mount(host, root, emit, state) { window.__domLog.push("lazy-mount:" + state); return {}; }, update() {}, dispose() { window.__domLog.push("lazy-dispose"); } };`);
  writeFileSync(join(directory, "main.js"), `
    import { createDOMViewHost } from "./dom-view-host.mjs";
    const log = (window.__domLog = []);
    const host = createDOMViewHost(window, { report: (element, error) => log.push("report:" + error.message) });
    const element = document.getElementById("host");
    element.addEventListener("dom-view-event", (event) => log.push("emit:" + event.detail.value));
    const wait = (condition) => new Promise((done) => { const tick = () => (condition() ? done() : setTimeout(tick, 10)); tick(); });
    window.SwiftUIWebDOMComponents.define("lazy", () => import("./lazy-component.js").then((module) => module.default));
    host.lifecycle("mount", element, { component: "early", state: "s1" });
    host.lifecycle("update", element, { state: "s2" });
    host.lifecycle("unmount", element);
    log.push("before-lazy");
    host.lifecycle("mount", element, { component: "lazy", state: "a" });
    host.lifecycle("update", element, { state: "b" });
    await wait(() => log.includes("lazy-mount:b"));
    host.lifecycle("unmount", element);
    host.lifecycle("mount", element, { component: "late", state: "x" });
    host.lifecycle("unmount", element);
    window.SwiftUIWebDOMComponents.define("late", () => ({ mount() { log.push("late-mount"); return {}; }, update() {} }));
    await new Promise((done) => setTimeout(done, 50));
    window.__domDone = true;`);
}

async function domComponentTest(browser, work) {
  domComponentBundle(join(work, "dom-component"));
  const { violations, result } = await scanBundle(browser, join(work, "dom-component"), async (page) => {
    await page.waitForFunction("window.__domDone === true", undefined, { timeout: 10_000 });
    return page.evaluate(() => window.__domLog);
  });
  assert.deepEqual(violations, [], "a registered component must run under the sealed policy");
  assert.deepEqual(result, [
    "mount:s1", "emit:hello", "update:s2", "dispose:s2",
    "before-lazy", "lazy-code-loaded", "lazy-mount:b", "lazy-dispose",
  ], "mount, emit, update and dispose, then a lazy component mounted with the latest state, and a cancelled mount that never runs");
  console.log("PASS a registered component (queued, lazy and cancelled) mounts, updates, emits and disposes under the sealed policy");
}

/** A page with the shipped shape: a policy that allows its inline script by hash and no eval, then the script. */
function syntheticBundle(directory, script) {
  mkdirSync(directory, { recursive: true });
  const hash = createHash("sha256").update(script).digest("base64");
  writeFileSync(
    join(directory, "index.html"),
    `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'sha256-${hash}'"><title>t</title></head><body><script>${script}</script><p id="ok">loaded</p></body></html>`,
  );
}

async function selfTest(browser) {
  const work = mkdtempSync(join(tmpdir(), "csp-bundles-"));
  try {
    syntheticBundle(join(work, "clean"), "window.ran = 1;");
    assert.deepEqual(await violationsOf(browser, join(work, "clean")), [], "a page that stays inside its policy has no violation");
    syntheticBundle(join(work, "evals"), "try { new Function('return 1')(); } catch (error) { console.error(String(error)); }");
    const evalViolations = await violationsOf(browser, join(work, "evals"));
    assert.ok(evalViolations.some((line) => /unsafe-eval|script-src/.test(line)), `eval under the policy must be reported: ${JSON.stringify(evalViolations)}`);
    // An inline script the policy does not list.
    mkdirSync(join(work, "unlisted"), { recursive: true });
    writeFileSync(
      join(work, "unlisted/index.html"),
      `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'"></head><body><script>window.ran = 1;</script></body></html>`,
    );
    assert.ok((await violationsOf(browser, join(work, "unlisted"))).length > 0, "an inline script the policy does not list must be reported");
    await domComponentTest(browser, work);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  console.log("PASS the CSP scan reports an eval and an unlisted inline script and passes a clean page");
}

/**
 * The browser products the Makefile builds: `SWIFTUIWEB_PRODUCT=<name>` and the example names it passes to
 * Tools/run-browser.sh (mapped to products by that script's own case table). A product added to the Makefile joins
 * this list by itself.
 */
export function productsBuiltByTheMakefile() {
  const makefile = readFileSync(join(ROOT, "Makefile"), "utf8");
  const script = readFileSync(join(ROOT, "Tools/run-browser-embedded.sh"), "utf8");
  const aliases = new Map();
  for (const match of script.matchAll(/([a-z0-9|-]+)\) product=(\w+)/g)) for (const name of match[1].split("|")) aliases.set(name, match[2]);
  const products = new Set();
  // Per recipe line: SWIFTUIWEB_PRODUCT=<name> overrides the product the example name would build.
  for (const line of makefile.split("\n")) {
    const run = line.match(/Tools\/run-browser\.sh\s+"?([a-z][a-z0-9-]*)"?/);
    if (!run) continue;
    const override = line.match(/SWIFTUIWEB_PRODUCT=(\w+)/);
    const product = override ? override[1] : aliases.get(run[1]);
    if (product) products.add(product);
  }
  return [...products].sort();
}

function bundlesBelow(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(join(directory, entry.name, "index.html")))
    .map((entry) => join(directory, entry.name))
    .sort();
}

await runSuite(async () => {
  const args = process.argv.slice(2);
  const browser = await launch();
  try {
    await selfTest(browser);
    if (args.includes("--self-test")) return;
    const bundles = args.length ? args.map((path) => resolve(path)) : bundlesBelow(join(ROOT, ".build/browser"));
    if (!args.length) {
      const missing = productsBuiltByTheMakefile().filter((product) => !bundles.some((bundle) => bundle.endsWith(`/${product}`)));
      assert.deepEqual(missing, [], `the Makefile builds these products but no bundle of them was scanned: ${missing.join(", ")} (build them: make csp-bundles-test)`);
    }
    assert.ok(bundles.length > 0, "no bundle to scan: build one first (for example `make csp-bundles-test`)");
    const failures = [];
    for (const bundle of bundles) {
      const violations = await violationsOf(browser, bundle);
      console.log(`${violations.length ? "FAIL" : "ok  "} ${bundle.split("/").pop()}${violations.length ? `\n  ${violations.join("\n  ")}` : ""}`);
      if (violations.length) failures.push(bundle);
    }
    assert.deepEqual(failures, [], `${failures.length} bundle(s) break their own Content-Security-Policy`);
    console.log(`PASS ${bundles.length} bundle(s) load under their shipped Content-Security-Policy without a violation`);
  } finally {
    await browser.close();
  }
});
