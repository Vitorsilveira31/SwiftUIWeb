#!/usr/bin/env bun
// Real Chromium control behavior and accessibility matrix for Embedded Showcase.
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, ROOT, runSuite, serveBundle } from "./browser-test-support.mjs";

const REQUIRED = ["app.wasm", "index.html", "index.js", "styles.css", "showcase-host.js"];

const { values } = parseArgs({
  options: {
    mode: { type: "string", default: "controls" },
    bundle: { type: "string", default: join(ROOT, ".build/browser/ShowcaseApp") },
    port: { type: "string", default: "8098" },
  },
});

await runSuite(async () => {
  if (values.mode !== "controls" && values.mode !== "accessibility") {
    throw new Error(`argument --mode: invalid choice: '${values.mode}' (choose from 'controls', 'accessibility')`);
  }
  const bundle = resolve(values.bundle);
  const missing = REQUIRED.filter((name) => !bundleFilePath(bundle, name));
  if (missing.length) throw new Error(`Missing ${missing.join(", ")}. Build the Embedded Showcase first.`);

  // serveBundle writes its log to .build/controls-server.log.
  const { base, stop } = await serveBundle({ bundle, port: Number(values.port), logName: "controls-server", required: REQUIRED });
  let browser;
  let message;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));

    async function load(route) {
      const response = await page.goto(base + route, { waitUntil: "domcontentloaded" });
      assert.ok(response && response.status() === 200);
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30000 });
      await page.waitForTimeout(250);
    }

    const labText = (name) => page.locator(`[data-testid="${name}"]`).innerText();
    // A lab label once it shows `expected`, or what it shows after five seconds: a debug bundle, WebKit and a busy
    // machine all take longer than a fixed pause to apply a key press.
    const labTextWhen = async (name, expected) => {
      let shown;
      for (const end = Date.now() + 5000; Date.now() < end; await page.waitForTimeout(50)) {
        shown = await labText(name);
        if (shown === expected) break;
      }
      return shown;
    };

    await load("/components");
    const controls = page.locator("[data-control-kind]");
    const controlCount = await controls.count();
    assert.ok(controlCount >= 10, String(controlCount));

    const toggle = page.locator('[data-control-kind="toggle"] input').first();
    const before = await toggle.isChecked();
    await toggle.click();
    await page.waitForTimeout(100);
    assert.notEqual(await toggle.isChecked(), before);

    const slider = page.locator('[data-control-kind="slider"]').first();
    await slider.evaluate((el) => {
      el.value = "0.8";
      el.dispatchEvent(new InputEvent("input", { bubbles: true }));
    });
    await page.waitForTimeout(100);
    assert.equal(Number(await slider.inputValue()), 0.8);
    assert.equal(await slider.getAttribute("aria-valuenow"), "0.8");
    const labeledSlider = page.getByRole("slider", { name: "Progress" });
    assert.equal(await labeledSlider.evaluate((e) => e.parentElement.className), "slider-group");
    const minimumLabel = page.locator(".slider-minimum-label");
    const maximumLabel = page.locator(".slider-maximum-label");
    const minimumText = await minimumLabel.innerText();
    assert.equal(minimumText.trim(), "0%", minimumText);
    const maximumText = await maximumLabel.innerText();
    assert.equal(maximumText.trim(), "100%", maximumText);
    const minimumBox = await minimumLabel.boundingBox();
    const trackBox = await labeledSlider.boundingBox();
    const maximumBox = await maximumLabel.boundingBox();
    assert.ok(minimumBox.x + minimumBox.width <= trackBox.x + 1, JSON.stringify([minimumBox, trackBox]));
    assert.ok(trackBox.x + trackBox.width <= maximumBox.x + 1, JSON.stringify([trackBox, maximumBox]));
    assert.ok(Math.abs(minimumBox.y + minimumBox.height / 2 - (trackBox.y + trackBox.height / 2)) < 4);
    assert.equal(await labeledSlider.getAttribute("aria-valuemax"), "1");

    const picker = page.locator('[data-control-kind="picker"] select').first();
    await picker.selectOption("WebAssembly");
    await page.waitForTimeout(100);
    assert.equal(await picker.inputValue(), "WebAssembly");

    const stepper = page.locator('[data-control-kind="stepper"]').first();
    const oldValue = await stepper.locator('[role="spinbutton"]').getAttribute("aria-valuenow");
    await stepper.getByRole("button", { name: "Increase" }).click();
    await page.waitForTimeout(100);
    assert.notEqual(await stepper.locator('[role="spinbutton"]').getAttribute("aria-valuenow"), oldValue);

    const menu = page.locator('[data-control-kind="menu"]').first();
    const summary = menu.locator(":scope > summary");
    assert.equal(await summary.getAttribute("aria-haspopup"), "menu");
    await summary.click();
    await page.waitForTimeout(50);
    assert.equal(await summary.getAttribute("aria-expanded"), "true");
    await summary.click();
    await page.waitForTimeout(50);
    assert.equal(await summary.getAttribute("aria-expanded"), "false");

    await load("/forms");
    const text = page.locator('[data-control-kind="text-field"]').first();
    await text.fill("Olá 日本語");
    await text.focus();
    await text.evaluate((el) => el.setSelectionRange(2, 5));
    await page.waitForTimeout(50);
    await text.evaluate((el) => el.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true })));
    await text.evaluate((el) =>
      el.dispatchEvent(new CompositionEvent("compositionupdate", { bubbles: true, data: "日本" })),
    );
    assert.equal(await text.getAttribute("data-ime-composing"), "true");
    await text.evaluate((el) => {
      el.value = "編集中";
      el.dispatchEvent(new InputEvent("input", { bubbles: true, isComposing: true }));
    });
    await page.waitForTimeout(50);
    assert.equal(await text.inputValue(), "編集中");
    await text.evaluate((el) =>
      el.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true, data: "編集中" })),
    );
    await page.waitForTimeout(100);
    assert.equal(await text.getAttribute("data-ime-composing"), null);
    assert.ok(await text.evaluate((el) => el === document.activeElement));

    // Disabled Save is a native disabled button, not merely a visual state.
    const save = page.getByRole("button", { name: "Save", exact: true });
    assert.ok(await save.isDisabled());

    // Keyboard and control-style parity (Showcase "Keyboard and controls").
    await load("/presentation");
    const modifier = (await page.evaluate("/Mac|iPhone|iPad/.test(navigator.platform)")) ? "Meta" : "Control";
    await page.locator("body").click({ position: { x: 5, y: 5 } });
    await page.keyboard.press(`${modifier}+k`);
    await page.keyboard.press(`${modifier}+j`); // bound to a disabled button
    await page.keyboard.press("k"); // missing modifier
    assert.equal(await labTextWhen("lab-shortcut-count", "Shortcut count: 1"), "Shortcut count: 1");
    const keyList = page.locator('[data-testid="lab-key-list"]');
    await keyList.focus();
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("ArrowDown"); // clamped; still handled
    await page.keyboard.press("q"); // ignored by the list, handled by the ancestor
    assert.equal(await labTextWhen("lab-key-state", "Highlighted: Archive · container keys: 1"), "Highlighted: Archive · container keys: 1");
    const segmented = page.locator('[data-picker-style="segmented"]');
    assert.equal(await segmented.getAttribute("role"), "radiogroup");
    assert.equal(await segmented.locator("select").count(), 0);
    const segments = segmented.locator('[role="radio"]');
    assert.deepEqual(
      await Promise.all([0, 1, 2].map((i) => segments.nth(i).getAttribute("aria-checked"))),
      ["false", "true", "false"],
    );
    await segments.nth(2).click();
    assert.equal(await labTextWhen("lab-period", "Period: month"), "Period: month");
    await page.keyboard.press("ArrowLeft");
    assert.equal(await labTextWhen("lab-period", "Period: week"), "Period: week");
    assert.equal(await page.evaluate("document.activeElement.getAttribute('aria-checked')"), "true");
    const box = await segmented.boundingBox();
    assert.ok(box.width > 300 && box.height < 48, JSON.stringify(box));
    const checkbox = page.getByRole("checkbox", { name: "Checkbox option" });
    assert.equal(await checkbox.getAttribute("role"), null);
    await checkbox.click();
    const bold = page.getByRole("button", { name: "Bold" });
    assert.equal(await bold.getAttribute("aria-pressed"), "false");
    await bold.click();
    await page.waitForTimeout(100);
    assert.equal(await bold.getAttribute("aria-pressed"), "true");
    const quiet = page.getByRole("switch", { name: "Quiet hours" });
    assert.equal(await quiet.evaluate((e) => e.closest("label").textContent.trim()), "");
    assert.equal(await labText("lab-toggles"), "Toggles: checked bold quiet");
    const hold = page.locator("button", { hasText: "Hold me" });
    await hold.scrollIntoViewIfNeeded();
    const holdBox = await hold.boundingBox();
    await page.mouse.move(holdBox.x + 5, holdBox.y + 5);
    await page.mouse.down();
    await page.waitForTimeout(150);
    const pressedText = await hold.innerText();
    assert.ok(pressedText.includes("Pressed"), pressedText);
    await page.mouse.up();
    await page.waitForTimeout(150);
    const idleText = await hold.innerText();
    assert.ok(idleText.includes("Idle"), idleText);

    if (values.mode === "accessibility") {
      await load("/components");
      const toggleInput = page.locator('[data-control-kind="toggle"] input').first();
      assert.equal(await toggleInput.getAttribute("role"), "switch");
      assert.ok(["true", "false"].includes(await toggleInput.getAttribute("aria-checked")));
      const sliderControl = page.locator('[data-control-kind="slider"]').first();
      assert.equal(await sliderControl.getAttribute("aria-valuemin"), "0");
      assert.equal(await sliderControl.getAttribute("aria-valuemax"), "1");
      assert.equal(await page.locator('[data-control-kind="progress-view"]').first().getAttribute("max"), "1");
      assert.equal(await page.locator('[data-control-kind="gauge"]').first().getAttribute("role"), "meter");
      await page.emulateMedia({ colorScheme: "dark" });
      assert.ok(await page.evaluate("getComputedStyle(document.body).color"));
    }

    assert.deepEqual(errors, [], "page errors: " + JSON.stringify(errors));
    message =
      values.mode === "controls"
        ? "PASS Embedded SwiftUI control behavior and IME matrix"
        : "PASS Embedded control accessibility, disabled, focus and dark-mode matrix";
  } finally {
    await browser?.close();
    await stop();
  }
  console.log(message);
});
