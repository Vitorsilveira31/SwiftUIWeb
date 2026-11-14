#!/usr/bin/env bun
// Exercise the shared Settings app in a real Embedded Chromium runtime.
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { ROOT, freePort, launch, runSuite, serveBundle } from "./browser-test-support.mjs";
import { bundleFilePath } from "./hash-release-bundle.mjs";

const REPORT_DIR = join(ROOT, ".build/universal-app-browser");
const REQUIRED = ["app.wasm", "index.html", "index.js", "styles.css"];
const MANAGE_TEXT =
  "Manage your overall setup and preferences for iPhone and iPad, such as software updates, device language, AirDrop, and more.";

await runSuite(async () => {
  const { values } = parseArgs({ options: { bundle: { type: "string" } } });
  if (values.bundle === undefined) throw new Error("the following arguments are required: --bundle");
  const bundle = resolve(values.bundle);
  for (const filename of REQUIRED) {
    if (!bundleFilePath(bundle, filename)) {
      throw new Error(`${filename} missing from ${bundle}; build the universal app first`);
    }
  }

  mkdirSync(REPORT_DIR, { recursive: true });
  const checks = [];
  const errors = [];
  let status = "FAIL";
  let stop = async () => {};
  try {
    const port = await freePort();
    const served = await serveBundle({ bundle, port, logName: "universal-app-browser/server", required: REQUIRED });
    stop = served.stop;
    const base = served.base;

    const browser = await launch();
    try {
      const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
      page.on("pageerror", (error) => errors.push(error.message));

      async function load(path = "/") {
        const response = await page.goto(base + path, { waitUntil: "domcontentloaded" });
        assert.ok(response !== null && response.status() === 200);
        await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
        await page.waitForSelector('.tab-view[data-tab-style="sidebar-adaptable"]');
      }

      async function assertSelectedTab(label) {
        try {
          await page.waitForFunction(
            (tabLabel) => {
              const view = document.querySelector(".tab-view");
              const tab = [...document.querySelectorAll("[role=tab]")].find(
                (candidate) => candidate.getAttribute("data-tab-label") === tabLabel,
              );
              return (
                !!tab &&
                tab.getAttribute("aria-selected") === "true" &&
                view?.getAttribute("data-selected-tab") === tab.getAttribute("data-tab-value")
              );
            },
            label,
            { timeout: 5_000 },
          );
        } catch (error) {
          const state = await page.locator('[role="tab"]').evaluateAll((tabs) =>
            tabs.map((tab) => ({
              label: tab.getAttribute("data-tab-label"),
              value: tab.getAttribute("data-tab-value"),
              selected: tab.getAttribute("aria-selected"),
            })),
          );
          const semantic = await page.locator(".tab-view").getAttribute("data-selected-tab");
          throw new Error(
            `tab '${label}' was not selected at ${page.url()}: ${JSON.stringify(state)}; semantic=${semantic}`,
            { cause: error },
          );
        }
      }

      async function assertNoHorizontalOverflow() {
        const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
        assert.ok(overflow <= 1, `document overflows viewport by ${overflow}px`);
      }

      await load();
      const tabList = page.locator(".tab-list");
      const navigationPanel = page.locator("[data-tab-sidebar]");
      const mobileToggle = page.locator("[data-tab-mobile-toggle]");
      const phoneGeometry = await mobileToggle.evaluate((e) => ({
        top: e.getBoundingClientRect().top,
        bottom: e.getBoundingClientRect().bottom,
        height: e.getBoundingClientRect().height,
        right: e.getBoundingClientRect().right,
      }));
      assert.ok(await mobileToggle.isVisible());
      assert.equal(await mobileToggle.getAttribute("aria-expanded"), "false");
      assert.ok(Math.abs(844 - phoneGeometry.bottom - 18) <= 2, JSON.stringify(phoneGeometry));
      assert.equal(phoneGeometry.height, 60, JSON.stringify(phoneGeometry));
      assert.ok(Math.abs(390 - phoneGeometry.right - 18) <= 2, JSON.stringify(phoneGeometry));
      assert.equal(
        await page.evaluate(() => document.querySelector(".tab-view")?.getAttribute("data-tab-layout")),
        "mobile",
      );
      assert.ok(await navigationPanel.evaluate((e) => e.inert));
      await mobileToggle.click();
      await page.waitForFunction(
        () => document.querySelector(".tab-view")?.getAttribute("data-tab-mobile-open") === "true",
      );
      assert.equal(await mobileToggle.getAttribute("aria-expanded"), "true");
      await tabList.waitFor({ state: "visible" });
      if (!(await tabList.isVisible())) {
        throw new Error(
          JSON.stringify(
            await tabList.evaluate((e) => ({
              hidden: e.hidden,
              ariaHidden: e.getAttribute("aria-hidden"),
              inert: e.inert,
              open: e.closest(".tab-view")?.outerHTML.slice(0, 1200),
              display: getComputedStyle(e).display,
              visibility: getComputedStyle(e).visibility,
              opacity: getComputedStyle(e).opacity,
              rect: e.getBoundingClientRect().toJSON(),
            })),
          ),
        );
      }
      await page.waitForTimeout(350); // let the 200ms open transition settle
      const panelGeometry = await navigationPanel.evaluate((e) => ({
        left: e.getBoundingClientRect().left,
        right: e.getBoundingClientRect().right,
        radius: getComputedStyle(e).borderRadius,
        role: e.getAttribute("role"),
        modal: e.getAttribute("aria-modal"),
      }));
      assert.ok(
        Math.abs(panelGeometry.left - 12) <= 1 && Math.abs(390 - panelGeometry.right - 12) <= 1,
        JSON.stringify(panelGeometry),
      );
      assert.ok(panelGeometry.radius === "22px" && panelGeometry.role === "dialog", JSON.stringify(panelGeometry));
      assert.ok(panelGeometry.modal === "true", JSON.stringify(panelGeometry));
      const backdrop = page.locator("[data-tab-mobile-backdrop]");
      const backdropFilter = await backdrop.evaluate(
        (e) => getComputedStyle(e).backdropFilter || getComputedStyle(e).webkitBackdropFilter,
      );
      assert.ok(backdropFilter.startsWith("blur(10px)"), "mobile backdrop should blur the page behind it");
      await page.keyboard.press("Escape");
      await page.waitForFunction(
        () => !document.querySelector(".tab-view")?.hasAttribute("data-tab-mobile-open"),
      );
      assert.equal(await mobileToggle.getAttribute("aria-expanded"), "false");
      assert.ok(
        await page.evaluate((element) => document.activeElement === element, await mobileToggle.elementHandle()),
      );
      await assertNoHorizontalOverflow();
      checks.push("phone menu button opens the navigation panel, closes on Escape/selection, and fits the viewport");

      const airplaneSwitch = page.locator('[role="switch"]').first();
      const airplaneTitle = page.getByText("Airplane Mode", { exact: true }).first();
      assert.equal(await airplaneTitle.getAttribute("data-hover-effect"), null);
      assert.equal(
        await airplaneTitle.evaluate((e) => e.closest("[data-hover-effect]")),
        null,
        "a switch-only row must not make its title a highlighted action",
      );
      await airplaneSwitch.check();
      await page.waitForFunction(
        () => document.querySelector("[role=switch]")?.getAttribute("aria-checked") === "true",
      );
      checks.push("state-backed switch updates through the Embedded event path");

      const actionRow = page.getByTestId("settings-tab-4");
      assert.equal(await actionRow.getAttribute("data-hover-effect"), "highlight");
      const initialBackground = await actionRow.evaluate((e) => getComputedStyle(e).backgroundColor);
      await actionRow.hover();
      await page.waitForFunction(
        ([selector, before]) => {
          const e = document.querySelector(selector);
          return e && getComputedStyle(e).backgroundColor !== before;
        },
        ['[data-testid="settings-tab-4"]', initialBackground],
      );
      const hoverState = await actionRow.evaluate((e) => ({
        transform: getComputedStyle(e).transform,
        scale: getComputedStyle(e).scale,
      }));
      assert.equal(hoverState.transform, "none", JSON.stringify(hoverState));
      assert.equal(hoverState.scale, "none", JSON.stringify(hoverState));
      const overview = page.locator('.tab-body [data-tab-panel="true"][data-tab-hidden="false"]');
      assert.equal(
        await overview.getByText("Settings", { exact: true }).first().getAttribute("data-hover-effect"),
        null,
      );
      assert.equal(await page.locator('[role="tab"]').first().getAttribute("data-hover-effect"), null);
      await page.mouse.down();
      const pressedState = await actionRow.evaluate((e) => ({
        transform: getComputedStyle(e).transform,
        scale: getComputedStyle(e).scale,
      }));
      assert.equal(pressedState.transform, "none", JSON.stringify(pressedState));
      assert.equal(pressedState.scale, "none", JSON.stringify(pressedState));
      await page.mouse.up();
      await page.waitForURL("**/*tab-selection=*");
      await page.getByText("Other Networks", { exact: true }).waitFor();
      await assertSelectedTab("Wi-Fi");
      checks.push("only full-row actions highlight; highlight has no hover or press scale");

      await page.reload({ waitUntil: "domcontentloaded" });
      await page.waitForSelector('html[data-embedded-mounted="true"]');
      await page.getByText("Other Networks", { exact: true }).waitFor();
      await assertSelectedTab("Wi-Fi");
      await mobileToggle.click();
      await page.locator('[role="tab"][data-tab-label="Settings"]').click();
      await assertSelectedTab("Settings");
      assert.equal(await mobileToggle.getAttribute("aria-expanded"), "false");
      await page.getByTestId("settings-tab-3").click();
      await page.getByText(MANAGE_TEXT, { exact: true }).waitFor();
      await assertSelectedTab("General");
      await page.goBack();
      await assertSelectedTab("Settings");
      await page.getByText("Airplane Mode", { exact: true }).waitFor();
      await page.goBack();
      await assertSelectedTab("Wi-Fi");
      await page.getByText("Other Networks", { exact: true }).waitFor();
      await page.goForward();
      await assertSelectedTab("Settings");
      await page.goForward();
      await assertSelectedTab("General");
      await page.getByText(MANAGE_TEXT, { exact: true }).waitFor();
      checks.push("tab selection survives reload and browser back/forward");

      await mobileToggle.click();
      await page.waitForFunction(
        () => document.querySelector(".tab-view")?.getAttribute("data-tab-mobile-open") === "true",
      );
      await page.setViewportSize({ width: 820, height: 1180 });
      await page.waitForFunction(
        () => !document.querySelector(".tab-view")?.hasAttribute("data-tab-mobile-open"),
      );
      assert.ok(!(await mobileToggle.isVisible()));
      await page.waitForFunction(
        () => document.querySelector(".tab-view")?.getAttribute("data-tab-sidebar-expanded") === "false",
      );
      const sidebar = navigationPanel;
      const toggle = page.locator("[data-tab-sidebar-toggle]");
      assert.ok(await toggle.isVisible());
      assert.equal(await toggle.getAttribute("aria-label"), "Expand navigation");
      assert.equal(
        await page.evaluate(() => document.querySelector(".tab-view")?.getAttribute("data-tab-layout")),
        "rail",
      );
      const collapsedWidth = await sidebar.evaluate((e) => e.getBoundingClientRect().width);
      assert.ok(collapsedWidth < 120, String(collapsedWidth));
      await toggle.click();
      await page.waitForFunction(
        () => document.querySelector(".tab-view")?.getAttribute("data-tab-sidebar-expanded") === "true",
      );
      assert.equal(await toggle.getAttribute("aria-label"), "Collapse navigation");
      await page.waitForFunction(
        () => document.querySelector("[data-tab-sidebar]")?.getBoundingClientRect().width >= 170,
        undefined,
        { timeout: 3_000 },
      );
      const expandedWidth = await sidebar.evaluate((e) => e.getBoundingClientRect().width);
      assert.ok(expandedWidth >= 170, String(expandedWidth));
      await assertNoHorizontalOverflow();
      await toggle.click();
      await page.waitForFunction(
        () => document.querySelector(".tab-view")?.getAttribute("data-tab-sidebar-expanded") === "false",
      );
      checks.push("tablet sidebar starts icon-only and expands/collapses on demand");

      await page.setViewportSize({ width: 1440, height: 900 });
      await page.waitForFunction(
        () =>
          document.querySelector(".tab-view")?.getAttribute("data-tab-layout") === "sidebar" &&
          document.querySelector(".tab-view")?.getAttribute("data-tab-sidebar-expanded") === "true",
      );
      await page.waitForFunction(
        () => document.querySelector("[data-tab-sidebar]")?.getBoundingClientRect().width >= 200,
        undefined,
        { timeout: 3_000 },
      );
      await assertNoHorizontalOverflow();
      checks.push("desktop uses a labeled side navigation instead of a top tab strip");

      assert.ok(!(await mobileToggle.isVisible()));
      await page.setViewportSize({ width: 390, height: 844 });
      await page.waitForFunction(
        () => document.querySelector(".tab-view")?.getAttribute("data-tab-layout") === "mobile",
      );
      assert.ok(await mobileToggle.isVisible());
      assert.equal(await mobileToggle.getAttribute("aria-expanded"), "false");
      await mobileToggle.click();
      await backdrop.click({ position: { x: 24, y: 24 } });
      await page.waitForFunction(
        () => !document.querySelector(".tab-view")?.hasAttribute("data-tab-mobile-open"),
      );
      assert.equal(await mobileToggle.getAttribute("aria-expanded"), "false");
      checks.push("resizing resets the mobile menu outside phone widths and backdrop dismisses it");

      assert.deepEqual(errors, []);
    } finally {
      await browser.close();
    }
    status = "PASS";
  } finally {
    await stop();
    writeFileSync(
      join(REPORT_DIR, "report.json"),
      JSON.stringify({ status, checks, pageErrors: errors }, null, 2) + "\n",
    );
  }

  for (const check of checks) console.log(`PASS ${check}`);
  console.log(`Universal Settings browser gate: PASS (${checks.length} checks)`);
});
