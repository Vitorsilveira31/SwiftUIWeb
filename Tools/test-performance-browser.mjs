#!/usr/bin/env bun
// Low-overhead metrics acceptance gate for the real Embedded Showcase.
//
// `--render-commit` instead runs the opt-in render-commit benchmark
// (Tools/render-commit-benchmark.mjs, `make render-commit-benchmark`).
//
// The page is the linked Swift + BrowserIO runtime. This deliberately
// asserts metric publication and lifecycle cleanup instead of baking in timing
// or DOM counts that would become fixture-specific performance expectations.
//
// Environment: PERF_EMBEDDED_BUNDLE (default .build/browser/ShowcaseApp), PERF_EMBEDDED_PORT (default 8106).
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { main as renderCommitMain } from "./render-commit-benchmark.mjs";

const BUNDLE = resolve(process.env.PERF_EMBEDDED_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
const PORT = Number(process.env.PERF_EMBEDDED_PORT ?? "8106");
const OUTPUT = join(ROOT, ".build", "performance", "embedded-browser.json");
const RENDER_COMMIT = process.argv.includes("--render-commit");

async function load(page, base, route) {
  const response = await page.goto(base + route, { waitUntil: "domcontentloaded" });
  assert.ok(response && response.status() === 200);
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  await page.waitForTimeout(200);
}

async function snapshot(page, name) {
  const value = await page.evaluate(() => globalThis.__performanceMetrics?.snapshot());
  assert.ok(value && value.schemaVersion === 1, `missing metrics snapshot for ${name}: ${JSON.stringify(value)}`);
  assert.equal(value.errors ?? 0, 0, JSON.stringify(value));
  assert.ok((value.commits ?? 0) > 0, JSON.stringify(value));
  const layout = value.layout ?? {};
  // A scenario that changes nothing the layout reads (a local update) has passes skipped and none run.
  assert.ok((layout.passes ?? 0) + (layout.passesSkipped ?? 0) > 0, JSON.stringify(value));
  // The layout host publishes how many passes it skipped (nothing changed since the last) and how many semantic
  // roots CSS could not lay out; the budgets read them per scenario.
  assert.ok("passesSkipped" in layout && layout.unlaid === 0, JSON.stringify(value));
  return value;
}

async function main() {
  for (const name of ["app.wasm", "index.html", "index.js"]) {
    if (!bundleFilePath(BUNDLE, name)) throw new Error(`${name} missing from ${BUNDLE}`);
  }
  const { base, stop } = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "performance-browser-server" });
  const scenarios = {};
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1100, height: 800 } });

    await load(page, base, "/components");
    scenarios.startup = await snapshot(page, "startup");
    // A local update: a view's own @State changes, which writes nothing the layout reads. (The first button of the components
    // page is the shell's, whose click changes nothing at all: the page then commits no publication to count.)
    await load(page, base, "/state");
    await page.evaluate(() => globalThis.__performanceMetrics.reset());
    for (let i = 0; i < 8; i++) {
      await page.getByRole("button", { name: "Change local state" }).first().click();
      await page.waitForTimeout(20);
    }
    scenarios.localUpdate = await snapshot(page, "localUpdate");

    await load(page, base, "/collections");
    await page.evaluate(() => globalThis.__performanceMetrics.reset());
    for (const host of await page.locator(".scroll-view").all()) {
      await host.evaluate((e) => { e.scrollTop = e.scrollHeight; e.dispatchEvent(new Event("scroll", { bubbles: true })); });
    }
    await page.waitForTimeout(120);
    scenarios.scrolling = await snapshot(page, "scrolling");

    await load(page, base, "/presentation");
    await page.evaluate(() => globalThis.__performanceMetrics.reset());
    const opener = page.getByRole("button", { name: "Alert", exact: true });
    for (let i = 0; i < 10; i++) {
      await opener.click();
      await page.waitForSelector(".presentation-root", { timeout: 5_000 });
      await page.keyboard.press("Escape");
      await page.waitForSelector(".presentation-root", { state: "detached", timeout: 5_000 });
    }
    scenarios.presentation = await snapshot(page, "presentation");

    // A 2,000-row Table: row collection and lazy windowing are measured
    // at startup and while the table scrolls to its end.
    await load(page, base, "/tablePerformance");
    scenarios.largeTableStartup = await snapshot(page, "largeTableStartup");
    scenarios.largeTableStartup.renderedRows = await page.locator("tbody tr").count();
    await page.evaluate(() => globalThis.__performanceMetrics.reset());
    const scrolled = await page.evaluate(() => {
      for (let node = document.querySelector("tbody"); node; node = node.parentElement) {
        if (node.scrollHeight > node.clientHeight + 1 && ["auto", "scroll"].includes(getComputedStyle(node).overflowY)) {
          node.scrollTop = node.scrollHeight;
          node.dispatchEvent(new Event("scroll", { bubbles: true }));
          return true;
        }
      }
      // The table windows its rows in the page's own scroll, so the document is the scroll container.
      window.scrollTo(0, document.documentElement.scrollHeight);
      window.dispatchEvent(new Event("scroll"));
      return window.scrollY > 0;
    });
    assert.ok(scrolled, "the large table did not scroll to its end");
    await page.waitForTimeout(120);
    scenarios.largeTableScrolling = await snapshot(page, "largeTableScrolling");
    scenarios.largeTableScrolling.renderedRows = await page.locator("tbody tr").count();
    await browser.close();
    browser = undefined;
  } finally {
    await browser?.close().catch(() => {});
    await stop();
  }
  mkdirSync(dirname(OUTPUT), { recursive: true });
  writeFileSync(OUTPUT, JSON.stringify({ schemaVersion: 1, namespace: "swiftuiweb.embedded-browser", scenarios }, null, 2) + "\n");
  console.log(`PASS Embedded performance metrics and lifecycle scenarios; report=${OUTPUT}`);
}

if (RENDER_COMMIT) {
  // Opt-in render-commit benchmark (`make render-commit-benchmark`); writes
  // .build/performance/render-commit.json and leaves embedded-browser.json alone.
  await renderCommitMain(process.argv.slice(2));
} else {
  await runSuite(main);
}
