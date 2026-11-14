#!/usr/bin/env bun
// Embedded presentation and focus lifecycle gate.
//
// The page is the linked Showcase Swift + BrowserIO application. The
// checks inspect semantic lifecycle/focus state, not presentation pixels.
//
// Usage: bun Tools/test-presentation-browser.mjs --mode presentation|focus
// Environment: PRESENTATION_BUNDLE (default .build/browser/ShowcaseApp), PRESENTATION_PORT (default 8101).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const MODES = ["presentation", "focus"];
let mode;
try {
  mode = parseArgs({ options: { mode: { type: "string" } }, strict: true }).values.mode;
} catch (error) {
  console.error(`test-presentation-browser.mjs: error: ${error.message}`);
  process.exit(2);
}
if (!MODES.includes(mode)) {
  console.error("test-presentation-browser.mjs: error: argument --mode: required, one of presentation, focus");
  process.exit(2);
}

const BUNDLE = resolve(process.env.PRESENTATION_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
const PORT = Number(process.env.PRESENTATION_PORT ?? "8101");

await runSuite(async () => {
  const { base, stop } = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "presentation-browser-server" });
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1000, height: 800 } });

    async function load(route) {
      const response = await page.goto(base + route, { waitUntil: "domcontentloaded" });
      assert.ok(response && response.status() === 200);
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
      await page.waitForTimeout(220);
    }

    if (mode === "presentation") {
      await load("/presentation");
      const opener = page.getByRole("button", { name: "Alert", exact: true });
      for (let cycle = 0; cycle < 100; cycle++) {
        await opener.click();
        await page.waitForSelector(".presentation-root[data-presentation-id]", { timeout: 5_000 });
        const dialog = page.locator(".presentation-root").last();
        assert.ok(await dialog.getAttribute("data-presentation-owner-id"));
        assert.ok(["presenting", "presented"].includes(await dialog.getAttribute("data-presentation-phase")));
        await page.keyboard.press("Escape");
        await page.waitForSelector(".presentation-root", { state: "detached", timeout: 5_000 });
      }
      const trace = (await page.evaluate("globalThis.__presentationTrace || {}")) ?? {};
      assert.ok((trace.dismissals ?? 0) >= 100, JSON.stringify(trace));
      assert.ok((trace.presenting ?? 0) >= 100 && (trace.dismissing ?? 0) >= 100, JSON.stringify(trace));
      assert.equal(await page.locator(".presentation-root").count(), 0);
      await page.getByRole("button", { name: "Sheet", exact: true }).click();
      await page.waitForSelector(".sheet-panel[data-presentation-id]");
      await page.getByRole("button", { name: "Dismiss", exact: true }).click();
      await page.waitForSelector(".sheet-panel", { state: "detached" });
      // onDismiss, cancel/default shortcuts, modal shortcut scope,
      // presenting alerts and detents (Showcase "Keyboard and controls").
      const state = () => page.locator('[data-testid="lab-presentation-state"]').innerText();
      const count = () => page.locator('[data-testid="lab-shortcut-count"]').innerText();
      const modifier = (await page.evaluate("/Mac|iPhone|iPad/.test(navigator.platform)")) ? "Meta" : "Control";
      const detentButton = page.getByRole("button", { name: "Detent sheet" });
      await detentButton.scrollIntoViewIfNeeded();
      await detentButton.click();
      await page.waitForSelector(".sheet-panel[data-presentation-detents]");
      const before = await count();
      await page.keyboard.press(`${modifier}+k`); // the button is behind the modal sheet
      await page.waitForTimeout(100);
      assert.equal(await count(), before);
      await page.keyboard.press("Escape"); // .keyboardShortcut(.cancelAction)
      await page.waitForSelector(".sheet-panel", { state: "detached" });
      await page.waitForTimeout(100);
      assert.equal(await state(), "Sheet dismissals: 1 · action: cancel · alert: none");
      await detentButton.click();
      await page.waitForSelector(".sheet-panel[data-presentation-detents]");
      await page.locator(".sheet-panel").focus();
      await page.keyboard.press("Enter"); // .keyboardShortcut(.defaultAction)
      await page.waitForSelector(".sheet-panel", { state: "detached" });
      await page.waitForTimeout(100);
      assert.equal(await state(), "Sheet dismissals: 2 · action: confirm · alert: none");
      await detentButton.click();
      await page.waitForSelector(".sheet-panel[data-presentation-detents]");
      await page.keyboard.press("Escape"); // focus is on the auto-focused cancel button
      await page.waitForSelector(".sheet-panel", { state: "detached" });
      await page.waitForTimeout(100);
      assert.ok((await state()).startsWith("Sheet dismissals: 3 · action: cancel"), await state());
      await page.getByRole("button", { name: "Presenting alert" }).click();
      await page.waitForSelector(".alert-panel");
      assert.ok((await page.locator(".alert-panel").innerText()).includes("Report.pdf will be removed."));
      await page.keyboard.press("Escape"); // alerts map Escape to the cancel-role button
      await page.waitForSelector(".alert-panel", { state: "detached" });
      await page.waitForTimeout(100);
      assert.ok((await state()).endsWith("alert: kept"), await state());
      // Compact width: the bottom sheet takes its detent height; the
      // grabber snaps to the nearest detent and a click cycles detents.
      await page.setViewportSize({ width: 390, height: 800 });
      await load("/presentation");
      const compactDetentButton = page.getByRole("button", { name: "Detent sheet" });
      await compactDetentButton.scrollIntoViewIfNeeded();
      await compactDetentButton.click();
      // The sheet rises for half a second (styles.css, swu-sheet-in): its box is measured once it has arrived.
      await page.waitForSelector('.sheet-panel[data-presentation-resizable="true"]:not([data-enter-animation])');
      await page.waitForTimeout(100);
      const sheet = page.locator(".sheet-panel");
      let box = await sheet.boundingBox();
      assert.ok(Math.abs(box.height - 400) <= 2, JSON.stringify(box)); // .medium = half of 800
      await page.mouse.move(box.x + box.width / 2, box.y + 10);
      await page.mouse.down();
      await page.mouse.move(box.x + box.width / 2, box.y - 250, { steps: 8 });
      await page.mouse.up();
      await page.waitForTimeout(250);
      assert.equal(await sheet.getAttribute("data-presentation-detent-selection"), "large");
      const large = await sheet.boundingBox();
      assert.ok(Math.abs(large.height - 776) <= 2, JSON.stringify(large));
      box = large;
      await page.mouse.click(box.x + box.width / 2, box.y + 10);
      await page.waitForTimeout(250);
      assert.equal(await sheet.getAttribute("data-presentation-detent-selection"), "medium");
      await page.keyboard.press("Escape");
      await page.waitForSelector(".sheet-panel", { state: "detached" });
      await page.setViewportSize({ width: 1000, height: 800 });
      console.log("PASS Embedded presentation lifecycle, Escape/backdrop dismissal and 100 cycles");
      console.log("PASS Embedded sheet onDismiss, cancel/default shortcuts, modal shortcut scope, presenting alert and detents");
    } else {
      await load("/forms");
      const field = page.getByRole("textbox", { name: "Name", exact: true });
      await field.focus();
      assert.ok(await page.evaluate((el) => document.activeElement === el, await field.elementHandle()));
      await page.keyboard.press("Tab");
      assert.ok(await page.evaluate((el) => document.activeElement !== el, await field.elementHandle()));
      await page.keyboard.press("Shift+Tab");
      assert.ok(await page.evaluate((el) => document.activeElement === el, await field.elementHandle()));
      await load("/presentation");
      const opener = page.getByRole("button", { name: "Alert", exact: true });
      await opener.click();
      await page.waitForSelector('.presentation-root[aria-modal="true"]');
      // Role queries intentionally exclude inert content; inspect the
      // retained background node directly to prove it is isolated.
      const outside = page.locator("button").filter({ hasText: "Sheet" }).first();
      assert.ok(await outside.evaluate((e) => e.closest("[inert]") !== null || e.inert));
      await page.keyboard.press("Escape");
      await page.waitForSelector(".presentation-root", { state: "detached" });
      assert.ok(await page.evaluate((el) => document.activeElement === el, await opener.elementHandle()));
      const trace = (await page.evaluate("globalThis.__presentationTrace || {}")) ?? {};
      assert.ok((trace.focusMoves ?? 0) > 0 && (trace.dismissals ?? 0) > 0, JSON.stringify(trace));
      console.log("PASS Embedded FocusState-compatible focus restoration, Tab loop and modal keyboard isolation");
    }
  } finally {
    await browser?.close();
    await stop();
  }
});
