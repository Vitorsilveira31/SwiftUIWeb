#!/usr/bin/env bun
// First paint (Documentation/Architecture/FIRST_PAINT.md): the first screen is in index.html and painted before the wasm is
// requested, the runtime takes it over without a shift, and a capture that differs from the runtime fails the build.
//
// The suite copies a release bundle of the Board benchmark app (FIRST_PAINT_BUNDLE, default .build/browser/BoardBenchmarkApp,
// built with `BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh board`), builds first paint into the copy with
// Tools/first-paint.mjs, and checks, in the Worker (default) and on the main thread (`?render-in-worker=0`):
//   * the markup is there and painted while the wasm request is held back, and nothing asked for it more than once;
//   * the page stays inert to nothing it must answer: a click on the prerendered "Add work" button made before the runtime
//     is up is replayed on the real button after it takes over (the favorites count of the board shows it);
//   * the takeover moves nothing: the boxes of the controls are the same before and after, and (Chromium) the page
//     reports no layout shift for the whole load;
//   * the runtime's state is right after: the prerender and its rules are gone, the board answers typing and a click;
//   * the sealed policy still holds: no violation, and the policy lists the one inline script's hash, no 'unsafe-eval';
//   * a viewport outside the verified width range gets no prerender, and the page works as it did;
//   * the verify mode fails on a capture that was made wrong on purpose (a changed text, a changed rule).
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default).
import assert from "node:assert/strict";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { engineName, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { build, verify, stripFirstPaint } from "./first-paint.mjs";
import { claimPort, compareScreenshots } from "./first-paint-support.mjs";

const SOURCE = resolve(process.env.FIRST_PAINT_BUNDLE ?? join(ROOT, ".build/browser/BoardBenchmarkApp"));
const MOUNTED = 'html[data-embedded-mounted="true"]';
const SEARCH = 'input[aria-label="Search works"]';

const RECORDER = `
(() => {
  window.__fp = { shifts: 0, violations: [] };
  try { new PerformanceObserver((list) => { for (const e of list.getEntries()) if (!e.hadRecentInput) window.__fp.shifts += e.value; }).observe({ type: 'layout-shift', buffered: true }); } catch {}
  document.addEventListener('securitypolicyviolation', (e) => window.__fp.violations.push(e.violatedDirective + ' ' + (e.blockedURI || '')));
})();`;

const boxes = () => Object.fromEntries([...document.querySelectorAll('#embedded-app-root input, #embedded-app-root button')].slice(0, 8).map((e, i) => {
  const r = e.getBoundingClientRect();
  return [i + ':' + (e.getAttribute('aria-label') || e.textContent.trim()), [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 10) / 10)];
}));

async function scenario(base, browser, { query }) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  await page.addInitScript(RECORDER);
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  // Hold every request for the wasm until the test lets it go: whatever is on screen meanwhile came from index.html alone.
  let release;
  const held = new Promise((done) => { release = done; });
  let wasmRequests = 0;
  await page.route(/\.wasm(\?|$)/, async (route) => { wasmRequests++; await held; await route.continue(); });
  await page.goto(`${base}/${query}`, { waitUntil: "domcontentloaded" });

  // 1. The markup is there, and painted, before the wasm.
  await page.waitForSelector(`#embedded-app-root[data-first-paint] ${SEARCH}`);
  assert.equal(await page.locator("#embedded-app-root[data-first-paint]").count(), 1, "the prerender root is present");
  assert.ok((await page.locator("#embedded-app-root[data-first-paint] button").count()) > 10, "the prerendered board has its buttons");
  assert.equal(await page.evaluate(() => document.documentElement.dataset.embeddedMounted ?? null), null, "the runtime is not mounted while the wasm is held");
  assert.ok((await page.screenshot()).length > 20_000, "the page shows the board (not a blank page) before the wasm");

  // 2. A click on the picture, made before the runtime is up, is recorded and replayed on the real control after the takeover.
  await page.locator("#embedded-app-root[data-first-paint] button", { hasText: "☆" }).first().click();
  await page.fill(SEARCH, "Crimson");

  // 3. Let the wasm go: the runtime takes over.
  release();
  await page.waitForSelector(MOUNTED, { timeout: 60_000, state: "attached" });
  await page.waitForTimeout(600);
  assert.equal(await page.locator("[data-first-paint]").count(), 0, "the prerender is gone after the takeover");
  assert.equal(await page.locator("#first-paint-style").count(), 0, "the prerendered rules are gone after the takeover");
  assert.equal(await page.locator("#embedded-app-root").count(), 1, "one app root");
  assert.deepEqual(errors, [], `page errors: ${errors.join("; ")}`);
  assert.equal(wasmRequests, 1, "the wasm was requested exactly once");

  // 4. Nothing shifted at the handover (the boxes themselves are compared in `takeover`, before anything is typed or clicked).
  const recorded = await page.evaluate(() => window.__fp);
  if (engineName() === "chromium") assert.equal(recorded.shifts, 0, `layout shift across the load: ${recorded.shifts}`);
  assert.deepEqual(recorded.violations, [], `Content-Security-Policy violations: ${recorded.violations.join("; ")}`);

  // 5. The runtime's state is right: the early click and the typing were replayed.
  assert.equal(await page.locator(SEARCH).inputValue(), "Crimson", "the text typed before the takeover is in the field");
  const board = await page.locator("#embedded-app-root").innerText();
  assert.ok(!/2000 results/.test(board) && /\d+ results/.test(board), `the typed text filtered the list: ${board.slice(0, 120)}`);
  assert.match(board, /1 favorites/, "the click made before the takeover reached the app");
  await page.fill(SEARCH, "");
  await page.locator("#embedded-app-root button", { hasText: "☆" }).first().click();
  await page.waitForFunction(() => /2 favorites/.test(document.getElementById("embedded-app-root").innerText), null, { timeout: 5000 });
  await context.close();
}

// Any application built with SWIFTUIWEB_FIRST_PAINT=1: its markup is in index.html and painted before the wasm, and the takeover
// changes nothing the person can see or measure.
async function takeover(base, browser, { query }) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  await page.addInitScript(RECORDER);
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  let release;
  const held = new Promise((done) => { release = done; });
  await page.route(/\.wasm(\?|$)/, async (route) => { await held; await route.continue(); });
  await page.goto(`${base}/${query}`, { waitUntil: "domcontentloaded" });
  await page.waitForSelector("#embedded-app-root[data-first-paint] *");
  assert.ok((await page.locator("#embedded-app-root[data-first-paint]").innerText()).trim().length > 20, "the prerendered root has text");
  assert.equal(await page.evaluate(() => document.documentElement.dataset.embeddedMounted ?? null), null, "not mounted while the wasm is held");
  await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
  const before = await page.evaluate(boxes);
  const text = await page.locator("#embedded-app-root").innerText();
  const shotBefore = await page.screenshot();
  release();
  await page.waitForSelector(MOUNTED, { timeout: 60_000, state: "attached" });
  await page.waitForTimeout(600);
  assert.equal(await page.locator("[data-first-paint], #first-paint-style").count(), 0, "the prerender is gone after the takeover");
  assert.deepEqual(errors, [], `page errors: ${errors.join("; ")}`);
  const after = await page.evaluate(boxes);
  assert.deepEqual(after, before, "the controls did not move at the handover");
  assert.equal(await page.locator("#embedded-app-root").innerText(), text, "the text of the page is what the prerender showed");
  const diff = await compareScreenshots(browser, shotBefore, await page.screenshot());
  assert.ok(diff.sameSize && diff.different === 0, `the runtime's frame differs from the prerendered one: ${JSON.stringify(diff)}`);
  const recorded = await page.evaluate(() => window.__fp);
  if (engineName() === "chromium") assert.equal(recorded.shifts, 0, `layout shift across the load: ${recorded.shifts}`);
  assert.deepEqual(recorded.violations, [], `Content-Security-Policy violations: ${recorded.violations.join("; ")}`);
  await context.close();
}

// Where the page is not the one that was captured, the prerender is taken away before the first paint: a returning visitor (the
// origin holds stored state the app may restore) and, for a capture bound to a language, a browser that speaks another one.
async function guards(base, browser, html) {
  const dropped = async (options, init, why, path = "/") => {
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, ...options });
    const page = await context.newPage();
    if (init) await page.addInitScript(init);
    let rootAtParse = null;
    await page.route(/\.wasm(\?|$)/, async (route) => { rootAtParse = await page.evaluate(() => document.getElementById("embedded-app-root")?.hasAttribute("data-first-paint") ?? null); await route.continue(); });
    await page.goto(`${base}${path}`, { waitUntil: "domcontentloaded" });
    await page.waitForSelector(MOUNTED, { timeout: 60_000, state: "attached" });
    assert.equal(rootAtParse, false, `${why}: the prerender was still there when the wasm was requested`);
    assert.equal(await page.locator("[data-first-paint], #first-paint-style").count(), 0, `${why}: nothing of the prerender is left`);
    assert.ok((await page.locator("#embedded-app-root button, #embedded-app-root a").count()) > 0, `${why}: the runtime rendered the page`);
    await context.close();
  };
  await dropped({}, () => localStorage.setItem("returning-visitor", "1"), "stored state");
  await dropped({}, null, "another address", "/elsewhere");
  await dropped({}, null, "a query the framework does not read", "/?q=1");
  const lang = /data-first-paint-lang="([^"]*)"/.exec(html)?.[1];
  if (lang) await dropped({ locale: "pt-BR" }, null, "another language");
}

async function outsideRange(base, browser, media) {
  // Narrower than the verified range, the prerender is taken away before the first paint and the page is the page it was.
  const width = Math.max(200, Number(/min-width:(\d+)px/.exec(media)?.[1] ?? 320) - 100);
  const context = await browser.newContext({ viewport: { width, height: 800 } });
  const page = await context.newPage();
  await page.goto(`${base}/`, { waitUntil: "domcontentloaded" });
  await page.waitForSelector(MOUNTED, { timeout: 60_000, state: "attached" });
  assert.equal(await page.locator("[data-first-paint]").count(), 0, `a ${width}px viewport is outside ${media} and gets no prerender`);
  assert.ok((await page.locator("#embedded-app-root button").count()) > 0, "the runtime rendered the board there");
  await context.close();
}

async function main() {
  const siteAt = process.argv.indexOf("--site");
  if (siteAt !== -1) {
    const bundle = resolve(process.argv[siteAt + 1]);
    assert.ok(readFileSync(join(bundle, "index.html"), "utf8").includes("data-first-paint"), `${bundle} was not built with SWIFTUIWEB_FIRST_PAINT=1`);
    const server = await serveBundle({ bundle, port: await claimPort(), logName: null });
    const browser = await launch();
    try {
      await takeover(server.base, browser, { query: "" });
      await takeover(server.base, browser, { query: "?render-in-worker=0" });
      await guards(server.base, browser, readFileSync(join(bundle, "index.html"), "utf8"));
      console.log(`first-paint-browser-test ok (${engineName()}): ${bundle}`);
    } finally { await browser.close(); await server.stop(); }
    return;
  }
  const work = mkdtempSync(join(tmpdir(), "swiftuiweb-first-paint-"));
  let server;
  let browser;
  try {
    const bundle = join(work, "bundle");
    cpSync(SOURCE, bundle, { recursive: true });
    // The page as the build ships it: captured from the bundle itself, then verified.
    const built = await build(bundle, { route: "/", viewport: { width: 1280, height: 1200 } });
    const html = readFileSync(join(bundle, "index.html"), "utf8");
    assert.ok(html.includes("data-first-paint"), "index.html carries the prerender");
    assert.ok(!/'unsafe-eval'/.test(html), "no unsafe-eval in the policy");
    assert.equal((html.match(/<script(?![^>]*\ssrc=)[^>]*>/g) ?? []).length, 4, "the page's own inline scripts are the three it had plus the one first paint adds");

    server = await serveBundle({ bundle, port: await claimPort(), logName: null });
    browser = await launch();
    await takeover(server.base, browser, { query: "" });
    await takeover(server.base, browser, { query: "?render-in-worker=0" });
    await scenario(server.base, browser, { query: "" });
    await scenario(server.base, browser, { query: "?render-in-worker=0" });
    await outsideRange(server.base, browser, built.media);
    await guards(server.base, browser, html);
    await server.stop(); server = undefined;

    // The verify mode fails a capture that is wrong, in either way a capture can be wrong.
    const wrongText = join(work, "wrong-text");
    cpSync(bundle, wrongText, { recursive: true });
    const tampered = readFileSync(join(wrongText, "index.html"), "utf8").replace("Works board", "Works boarx");
    writeFileSync(join(wrongText, "index.html"), tampered);
    // index.html.br/.gz would be served instead of the edited file
    rmSync(join(wrongText, "index.html.br"), { force: true }); rmSync(join(wrongText, "index.html.gz"), { force: true });
    await assert.rejects(() => verify(wrongText, { route: "/", media: built.media }), /pixels differ/, "verify accepted a capture with a wrong text");

    const wrongRule = join(work, "wrong-rule");
    cpSync(bundle, wrongRule, { recursive: true });
    const tamperedRule = readFileSync(join(wrongRule, "index.html"), "utf8").replace(/(<style id="first-paint-style">)/, "$1#embedded-app-root{padding-top:9px}");
    writeFileSync(join(wrongRule, "index.html"), tamperedRule);
    rmSync(join(wrongRule, "index.html.br"), { force: true }); rmSync(join(wrongRule, "index.html.gz"), { force: true });
    await assert.rejects(() => verify(wrongRule, { route: "/", media: built.media }), /pixels differ|sizes differ/, "verify accepted a capture with a wrong rule");

    // The pristine bundle still strips back to what it was.
    assert.equal(stripFirstPaint(html).includes("data-first-paint"), false);
    console.log(`first-paint-browser-test ok (${engineName()}): ${built.bytes} bytes added to index.html, shown when ${built.media}`);
  } finally {
    await browser?.close();
    await server?.stop();
    rmSync(work, { recursive: true, force: true });
  }
}

await runSuite(main);
