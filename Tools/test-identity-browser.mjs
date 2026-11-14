#!/usr/bin/env bun
// Small real-Embedded browser identity gate.
//
// The bundle is produced by `make identity-browser-test`. This deliberately uses the linked Showcase WASM and
// BrowserIO runtime rather than a mock DOM ABI.
import assert from "node:assert/strict";
import { join } from "node:path";
import { launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

await runSuite(async () => {
  const bundle = process.env.IDENTITY_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp");
  const port = Number(process.env.IDENTITY_PORT ?? "8098");
  const { base, stop } = await serveBundle({ bundle, port, logName: "identity-browser-server" });
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

    async function load(route) {
      const response = await page.goto(base + route, { waitUntil: "domcontentloaded" });
      assert.ok(response && response.status() === 200);
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
      await page.waitForTimeout(150);
    }

    await load("/collections");
    const row = page.locator('[data-view-id="1"]').first();
    assert.equal(await row.count(), 1, "initial keyed row missing");
    await page.evaluate(() => { document.querySelector('[data-view-id="1"]').__identityProbe = "stable"; });
    await page.getByRole("button", { name: "Insert", exact: true }).click();
    await page.waitForTimeout(150);
    assert.equal(await page.evaluate(() => document.querySelector('[data-view-id="1"]')?.__identityProbe), "stable");

    await load("/forms");
    const field = page.getByPlaceholder("Name").first();
    await field.focus();
    const handle = await field.elementHandle();
    await field.fill("Identity");
    await page.waitForTimeout(150);
    assert.ok(await page.evaluate((el) => document.activeElement === el, handle), "focused TextField was replaced");

    await load("/presentation");
    await page.getByRole("button", { name: "Alert", exact: true }).click();
    await page.waitForSelector(".presentation-root");
    await page.keyboard.press("Escape");
    await page.waitForSelector(".presentation-root", { state: "detached" });
    console.log("PASS real Embedded keyed DOM, focused field and presentation identity");
  } finally {
    await browser?.close();
    await stop();
  }
});
