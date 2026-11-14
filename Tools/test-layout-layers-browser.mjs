#!/usr/bin/env bun
// A run of frame, padding and fixedSize modifiers shares one element (`data-layout-wrap`, `_SemanticLayers`) that CSS layout styles
// as the chain of wrapper elements it replaces. A shared element nothing styles would lose the layers: every visible one must
// carry the block of the CSS layout mapper (`data-cl`, the folded chain, see Documentation/Architecture/CSS_LAYOUT.md) or a
// class of the CSS Swift emitted (`slN`), in every Showcase topic, at a phone, a tablet and a desktop width.
// Bundle: LAYERS_BUNDLE (.build/browser/ShowcaseApp). Port: LAYERS_PORT.
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { launch, ROOT, runSuite, serveBundle } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.LAYERS_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
const PORT = Number(process.env.LAYERS_PORT ?? "8118");

await runSuite(async () => {
  const { base, stop } = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "layers-browser-server" });
  let browser;
  try {
    browser = await launch();
    let merged = 0, topics = 0;
    for (const width of [375, 900, 1280]) {
      const page = await browser.newPage({ viewport: { width, height: 800 } });
      await page.goto(base + "/");
      await page.waitForSelector("[data-docs-part=topic]", { state: "attached", timeout: 60_000 });
      await page.waitForTimeout(500);
      const routes = await page.evaluate(() => [...document.querySelectorAll('[data-docs-part="topic"]')].map((b) => b.getAttribute("data-docs-route")));
      for (const route of routes) {
        await page.locator(`[data-docs-part="topic"][data-docs-route="${route}"]`).first().evaluate((b) => b.click());
        await page.waitForTimeout(1200);
        const result = await page.evaluate(() => {
          const lost = [];
          let count = 0;
          for (const element of document.querySelectorAll("[data-layout-wrap]")) {
            if (element.closest("[data-layout-hidden],[hidden],[data-tab-hidden=true],[data-navigation-inactive=true]") || !element.getClientRects().length) continue;
            count++;
            if (!element.hasAttribute("data-cl") && ![...element.classList].some((c) => /^sl\d+$/.test(c))) lost.push(element.className + " in " + element.parentElement?.className);
          }
          return { count, lost };
        });
        assert.deepEqual(result.lost, [], `${route} at ${width}px: shared layout elements CSS layout did not style`);
        merged += result.count; topics++;
      }
      await page.close();
    }
    assert.ok(merged > 0, "no topic has a shared layout element: the test checks nothing");
    console.log(`PASS every shared layout element is styled by CSS layout (${merged} in ${topics} topic views)`);
  } finally {
    await browser?.close();
    await stop();
  }
});
