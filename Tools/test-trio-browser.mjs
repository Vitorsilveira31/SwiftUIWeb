#!/usr/bin/env bun
// Chromium test of Examples/Trio, the iOS/Android/Web example, through the real Embedded Swift + JavaScript host bundle
// (`make trio-browser-test` builds it):
//
// - the default TabView draws iOS 26's floating tab bar: a capsule narrower than the row it sits in, at every width;
// - a `.tabItem { Label("Counter", systemImage: "plus") }` is titled "Counter", without the icon's fallback glyph;
// - `@AppStorage` written through a binding in a child view renders the parent that declared it: the About screen's
//   "Dark mode" switch flips the page's color scheme both ways, every time, also on a dark system;
// - the shared view models answer: the counter counts and a task can be added.
import assert from "node:assert/strict";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

await runSuite(async () => {
  const { positionals } = parseArgs({ allowPositionals: true });
  const bundle = resolve(positionals[0] ?? ".build/browser/TrioWeb/TrioWeb");
  const server = await serveDirectory(bundle);
  const browser = await launch();
  const errors = [];
  try {
    // A dark system: the switch must still give a light page when it is off, so it cannot fall back to the system.
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, colorScheme: "dark" });
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(server.base + "/", { waitUntil: "domcontentloaded" });
    await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
    await page.waitForSelector(".tab-bar .tab-list [role=tab]");

    const labels = await page.locator(".tab-list [role=tab]").evaluateAll((tabs) => tabs.map((tab) => tab.getAttribute("data-tab-label")));
    assert.deepEqual(labels, ["Counter", "Tasks", "About"], "tab titles carry no icon glyph");

    const capsule = () => page.evaluate(() => {
      const row = document.querySelector(".tab-bar").getBoundingClientRect();
      const bar = document.querySelector(".tab-bar .tab-list");
      const box = bar.getBoundingClientRect();
      return { row: row.width, bar: box.width, left: box.left - row.left, right: row.right - box.right,
        radius: parseFloat(getComputedStyle(bar).borderTopLeftRadius), height: box.height };
    });
    for (const width of [390, 1280]) {
      await page.setViewportSize({ width, height: 844 });
      await page.waitForTimeout(150);
      const shape = await capsule();
      assert.ok(shape.bar < shape.row && shape.left >= 12 && shape.right >= 12, `the bar floats inside its row at ${width}px: ${JSON.stringify(shape)}`);
      assert.ok(shape.radius >= shape.height / 2, `the bar is a capsule at ${width}px: ${JSON.stringify(shape)}`);
    }
    await page.setViewportSize({ width: 390, height: 844 });

    // Counter: the shared view model.
    await page.locator("[role=tab]", { hasText: "Counter" }).click();
    // `accessibilityIdentifier` is `data-testid` in the browser.
    await page.locator('[data-testid="counter-increment"]').click();
    await page.waitForFunction(() => document.querySelector('[data-testid="counter-value"]')?.textContent.trim() === "1");

    // Tasks: add one.
    await page.locator("[role=tab]", { hasText: "Tasks" }).click();
    await page.getByPlaceholder("New task").fill("Ship it");
    await page.getByRole("button", { name: "Add" }).click();
    await page.getByText("Ship it").waitFor();

    // About: the dark mode switch, through @AppStorage owned by ContentView.
    await page.locator("[role=tab]", { hasText: "About" }).click();
    const toggle = page.getByRole("switch", { name: "Dark mode" });
    await toggle.waitFor();

    // A LabeledContent whose value does not fit a phone row: the label keeps its width and the value wraps beside it.
    const engine = await page.evaluate(() => {
      const row = [...document.querySelectorAll(".labeled-content")].find((e) => e.textContent.startsWith("Engine"));
      const [label, value] = [...row.children].map((cell) => cell.getBoundingClientRect());
      return { label: label.width, gap: value.left - label.right, valueHeight: value.height, labelHeight: label.height };
    });
    assert.ok(engine.label > 30 && engine.gap >= 8, `the label keeps its width beside the value: ${JSON.stringify(engine)}`);
    assert.ok(engine.valueHeight > engine.labelHeight, `the long value wraps: ${JSON.stringify(engine)}`);
    const scheme = () => page.evaluate(() => document.documentElement.getAttribute("data-color-scheme"));
    assert.equal(await scheme(), "light", "the switch is off, so the page is light on a dark system");
    for (const expected of ["dark", "light", "dark", "light"]) {
      await toggle.click();
      await page.waitForFunction((want) => document.documentElement.getAttribute("data-color-scheme") === want, expected, { timeout: 3_000 })
        .catch(async () => assert.fail(`the switch should make the page ${expected}, it is ${await scheme()}`));
    }

    assert.deepEqual(errors, [], "no page errors");
    console.log("trio browser test: OK");
  } finally {
    await browser.close();
    await server.stop?.();
  }
});
