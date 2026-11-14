#!/usr/bin/env bun
// Browser test of owners that render again on their own, and of focus that follows the person.
//
// Drives Tests/Apps/EmbeddedLoweringConformanceApp/EmbeddedRetainedOwnerFixture.swift through the real Embedded Swift +
// JavaScript host bundle built by `BUILD_ONLY=1 Tools/run-browser.sh lowering`, with Swift in a Worker and on
// the main thread (`?render-in-worker=0`):
//
// - a `TabView` whose tabs come from a `ForEach` shows screens that read a shared model with `@Environment(Model.self)`.
//   Writing the model re-renders each tab's owner outside any enclosing view's render. The screen must resolve the
//   model there (it used to trap, and the runtime was unusable afterwards), keep its `@State`, and show the new value;
//   every tab keeps working after a trap-free run of writes and tab switches;
// - a trap (a button that calls fatalError) is reported once: the page stops calling into the instance, which a trap
//   leaves half-updated, instead of trapping again on every later call and task tick;
// - a person who moves from one field to the next types into the field they moved to: a publication that still
//   reflects the previous focus must not pull focus back (a password landed in the e-mail field).
//
// The engine comes from SWIFTUIWEB_BROWSER_ENGINE (chromium by default, or webkit).
//
// Usage: bun Tools/test-retained-owner-browser.mjs [bundle] [--port N]   (port 0 selects a free port)
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

const EMAIL = "reader@example.test";
const PASSWORD = "swordfish";
let parsed;
try {
  parsed = parseArgs({ allowPositionals: true, options: { port: { type: "string", default: "0" } }, strict: true });
} catch (error) {
  console.error(`test-retained-owner-browser.mjs: error: ${error.message}`);
  process.exit(2);
}
const bundle = resolve(parsed.positionals[0] ?? ".build/browser/EmbeddedLoweringConformanceApp");
const port = Number(parsed.values.port);

await runSuite(async () => {
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) {
    throw new Error(`Embedded lowering bundle is missing: ${bundle}`);
  }
  const server = await serveDirectory(bundle, port);
  const serverPort = server.port;
  const checks = [];
  let browser;
  try {
    browser = await launch();
    for (const [mode, query] of [["worker", ""], ["main-thread", "?render-in-worker=0"]]) {
      let page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
      await page.goto(`http://127.0.0.1:${serverPort}/${query}`, { waitUntil: "networkidle" });
      await page.getByRole("button", { name: "Open retained owner fixture", exact: true }).click();

      const text = async (value, timeout = 10_000) => {
        await page.getByText(value, { exact: true }).first().waitFor({ timeout });
      };

      await text("Screen catalog: detail 0");
      for (const taps of [1, 2]) {
        await page.getByRole("button", { name: "Tap catalog", exact: true }).click();
        await text(`Taps catalog: ${taps}`);
      }
      for (const detail of [1, 2, 3]) {
        await page.getByRole("button", { name: "Write the model", exact: true }).click();
        await text(`Screen catalog: detail ${detail}`);
      }
      await text("Taps catalog: 2");
      checks.push(`${mode}: the model write re-renders a tab's screen, which keeps its state`);

      await page.getByRole("tab", { name: "queue", exact: true }).click();
      await text("Screen queue: detail 3");
      await page.getByRole("button", { name: "Tap queue", exact: true }).click();
      await text("Taps queue: 1");
      await page.getByRole("button", { name: "Write the model", exact: true }).click();
      await text("Screen queue: detail 4");
      await text("Taps queue: 1");
      await page.getByRole("tab", { name: "settings", exact: true }).click();
      await page.getByRole("button", { name: "Write the model", exact: true }).click();
      await text("Screen settings: detail 5");
      await page.getByRole("tab", { name: "catalog", exact: true }).click();
      await text("Screen catalog: detail 5");
      await text("Taps catalog: 2");
      checks.push(`${mode}: every tab resolves the model and renders the new value after switches`);

      const email = page.getByPlaceholder("Retained e-mail");
      const password = page.getByPlaceholder("Retained password");
      for (let attempt = 0; attempt < 6; attempt++) {
        await email.fill(EMAIL);
        await password.fill(PASSWORD);
        await page.waitForTimeout(150);
        assert.equal(await email.inputValue(), EMAIL, `${mode}: password landed in the e-mail field (${attempt})`);
        assert.equal(await password.inputValue(), PASSWORD, `${mode}: password field lost its text (${attempt})`);
        await email.fill("");
        await password.fill("");
      }
      await text("Typed: 0/0");
      checks.push(`${mode}: moving from one field to the next keeps the keystrokes in the new field`);

      const failures = await page.evaluate("document.getElementById('embedded-app-root')?.dataset.runtimeError ?? ''");
      assert.ok(!failures, `${mode}: runtime error reported: ${failures}`);
      assert.deepEqual(errors, [], `${mode}: errors: ${JSON.stringify(errors)}`);
      await page.close();

      // A trap is reported once and the instance is left alone afterwards.
      page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
      const reports = [];
      const uncaught = [];
      page.on("pageerror", (error) => uncaught.push(error.message));
      page.on("console", (message) => { if (message.type() === "error") reports.push(message.text()); });
      await page.addInitScript("window.__swuiErrors = []; window.addEventListener('runtime-error', e => window.__swuiErrors.push(e.detail.message));");
      await page.goto(`http://127.0.0.1:${serverPort}/${query}`, { waitUntil: "networkidle" });
      await page.getByRole("button", { name: "Open retained owner fixture", exact: true }).click();
      await text("Screen catalog: detail 0");
      await page.getByRole("button", { name: "Trap on purpose", exact: true }).click();
      await page.waitForFunction("window.__swuiErrors.length >= 1", undefined, { timeout: 10_000 });
      await page.getByRole("button", { name: "Write the model", exact: true }).click();
      await page.getByRole("tab", { name: "queue", exact: true }).click();
      await page.waitForTimeout(1500); // several of the 250 ms task ticks
      const events = await page.evaluate("window.__swuiErrors");
      assert.equal(events.length, 1, `${mode}: a trap was reported ${events.length} times: ${JSON.stringify(events)}`);
      const swift = reports.filter((line) => line.startsWith("[SwiftUIWeb]"));
      assert.equal(swift.length, 1, `${mode}: a trap logged ${swift.length} errors: ${JSON.stringify(swift)}`);
      assert.deepEqual(uncaught, [], `${mode}: uncaught errors after a trap: ${JSON.stringify(uncaught)}`);
      checks.push(`${mode}: a trap is reported once and the instance is left alone afterwards`);
      await page.close();
    }
    await browser.close();
    browser = undefined;
  } finally {
    await browser?.close().catch(() => {});
    await server.close();
  }
  for (const line of checks) console.log(`  - ${line}`);
  console.log("Retained owner browser test passed.");
});
