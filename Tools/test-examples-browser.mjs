#!/usr/bin/env bun
// Chromium test of the small apps (Examples/<Name>) through their real Embedded Swift + JavaScript host bundles
// (`make example-browser-test` builds them all). The apps are ordinary iOS SwiftUI that exists to find what the
// browser host cannot do, so the test is deliberately broad and shallow: every app mounts, draws something of its
// own and raises no page error.
//
// Usage: bun Tools/test-examples-browser.mjs <bundles directory> <Example>...
// EXAMPLE_SHOTS=<directory> also saves a screenshot of each app.
import assert from "node:assert/strict";
import { existsSync, mkdirSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

// An element only that app draws, by its accessibility identifier (`data-testid` in the browser). An app with no
// entry is checked for any content at all.
const MARKERS = {
  MonthCalendar: '[data-testid="calendar-title"]',
  Sparkline: '[data-testid="tick"]',
  Carousel: '[data-testid="strip"]',
  ShapeGallery: '[data-testid="fx-shapes"]',
  CanvasGallery: '[data-testid="fx-arc"]',
  MarkdownReader: '[data-testid="markdown-contents"]',
  WrapAround: '[data-testid="scene-drag"]',
  StoreMap: '[data-testid="map"]',
};

// What an app's own behaviour must do in the browser beyond mounting, after the first screen is checked.
const CHECKS = {
  // The feed page has a bottom bar (ToolbarItemPlacement.bottomBar): it takes a row of its own at the foot of the screen
  // instead of floating over the content.
  Carousel: async (page, problems) => {
    await page.locator('[data-testid="feed-page"]').click();
    await page.waitForSelector(".navigation-bottom-bar", { timeout: 8_000 }).catch(() => {});
    await page.waitForTimeout(1_000);
    const g = await page.evaluate(() => {
      const bar = document.querySelector(".navigation-bottom-bar"), root = document.querySelector(".navigation-root");
      return bar && root ? { barTop: bar.getBoundingClientRect().top, barBottom: bar.getBoundingClientRect().bottom, rootBottom: root.getBoundingClientRect().bottom, height: innerHeight } : null;
    });
    if (!g) problems.push("the feed page has no bottom bar");
    else if (g.barTop < g.rootBottom - 1) problems.push(`the bottom bar overlaps the screen (bar top ${g.barTop}, screen bottom ${g.rootBottom})`);
    else if (Math.abs(g.barBottom - g.height) > 1) problems.push(`the bottom bar is not at the foot of the screen (bar bottom ${g.barBottom}, window ${g.height})`);
  },
};

await runSuite(async () => {
  const { positionals } = parseArgs({ allowPositionals: true });
  const [bundles = ".build/browser/Examples", ...examples] = positionals;
  assert.ok(examples.length > 0, "name at least one example");
  const shots = process.env.EXAMPLE_SHOTS ? resolve(process.env.EXAMPLE_SHOTS) : null;
  if (shots) mkdirSync(shots, { recursive: true });
  const browser = await launch();
  const failures = [];
  try {
    for (const name of examples) {
      const bundle = resolve(bundles, name, `${name}Web`);
      const problems = [];
      if (!existsSync(join(bundle, "index.html"))) {
        problems.push(`no bundle at ${bundle}`);
      } else {
        const server = await serveDirectory(bundle);
        const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
        const errors = [];
        page.on("pageerror", (error) => errors.push(error.message));
        page.on("console", (message) => { if (message.type() === "error") errors.push(`console: ${message.text()}`); });
        try {
          await page.goto(server.base + "/", { waitUntil: "domcontentloaded" });
          await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
          const marker = MARKERS[name];
          if (marker) await page.waitForSelector(marker, { timeout: 8_000 }).catch(() => problems.push(`its own content (${marker}) never appeared`));
          await page.waitForTimeout(1_500);
          const drawn = await page.evaluate(() => document.body.innerText.trim().length + document.querySelectorAll("canvas, svg, video, img").length);
          if (drawn === 0) problems.push("the page is empty");
          if (shots) await page.screenshot({ path: join(shots, `${name}.png`) });
          await CHECKS[name]?.(page, problems);
        } catch (error) {
          problems.push(`did not open: ${error.message.split("\n")[0]}`);
        }
        // A network failure of a sample resource is the network's, not the framework's.
        const real = errors.filter((text) => !/Failed to load resource|net::ERR/.test(text));
        if (real.length) problems.push(`page errors: ${[...new Set(real)].slice(0, 3).join(" | ")}`);
        await page.close();
        await server.stop?.();
      }
      console.log(`${problems.length ? "FAIL" : "ok  "} ${name}${problems.length ? ": " + problems.join("; ") : ""}`);
      if (problems.length) failures.push(name);
    }
    assert.deepEqual(failures, [], "every example mounts, draws and raises no page error");
    console.log("examples browser test: OK");
  } finally {
    await browser.close();
  }
});
