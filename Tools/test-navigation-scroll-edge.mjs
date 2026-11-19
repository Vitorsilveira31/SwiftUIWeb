#!/usr/bin/env bun
// A navigation bar is transparent while the screen on top of the stack sits at its scroll edge and takes its material and
// hairline once its content scrolls under it, as iOS draws it. The host marks a scrolled vertical scroll view
// (`data-scrolled`); a screen under the top one (a scrolled root behind a pushed screen) does not count.
//   bun Tools/test-navigation-scroll-edge.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const scroll = (id) => `<div id="${id}" class="scroll-view scroll-vertical" style="height:200px;overflow-y:auto"><div style="height:900px"></div></div>`;
const html = `<main class="navigation-stack" data-navigation-title="Detail" data-navigation-depth="1" data-navigation-title-display-mode="inline">
  <div class="navigation-root">${scroll("root-scroll")}</div>
  <div class="navigation-destination">${scroll("top-scroll")}</div>
</main>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 700 } });
    await page.setContent(`<style>${styles}</style><body>${html}</body>`);
    const bar = () => page.evaluate(() => {
      const style = getComputedStyle(document.querySelector("main"), "::before");
      return { background: style.backgroundColor, border: style.borderBottomColor };
    });
    const clear = { background: "rgba(0, 0, 0, 0)", border: "rgba(0, 0, 0, 0)" };
    const mark = (id, on) => page.evaluate(([id, on]) => document.getElementById(id).toggleAttribute("data-scrolled", on), [id, on]);
    assert.deepEqual(await bar(), clear, "at the scroll edge the bar is transparent");
    await mark("root-scroll", true);
    assert.deepEqual(await bar(), clear, "a scrolled screen under the pushed one does not tint the bar");
    await mark("top-scroll", true);
    const scrolled = await bar();
    assert.notEqual(scrolled.background, clear.background, "content under the bar gives it its material");
    assert.notEqual(scrolled.border, clear.border, "and its hairline");
    await mark("top-scroll", false);
    assert.deepEqual(await bar(), clear, "back at the top the bar is transparent again");
    console.log("PASS the navigation bar follows the scroll edge of the screen on top");
  } finally {
    await browser.close();
  }
});
