#!/usr/bin/env bun
// A mobile tab's floating bar overlays the content, as the iOS tab bar does: the outer vertical scroll view of the shown
// tab ends with room for it, so its last content scrolls clear of the bar ("Para você", the last shelf of a home, sat under
// it). The layout writes the content's bottom padding as `calc(<padding> + var(--scroll-end-clearance))`; this checks
// what the stylesheet gives that variable: room in the outer scroll view of a mobile tab with its bar, none in a scroll
// view inside it, none when the screen hides the bar, none outside the mobile layout.
//   bun Tools/test-tab-scroll-clearance.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const content = id => `<div id="${id}" style="padding-bottom: calc(28px + var(--scroll-end-clearance)) !important; height: 1200px">
  <div class="scroll-view scroll-horizontal"><div id="${id}-shelf" style="padding-bottom: calc(0px + var(--scroll-end-clearance)) !important">shelf</div></div>
  <div class="scroll-view scroll-vertical" style="height: 100px"><div id="${id}-inner" style="padding-bottom: calc(0px + var(--scroll-end-clearance)) !important">inner</div></div>
</div>`;
const tab = (id, attributes) => `<div class="tab-view" ${attributes}><div class="tab-body"><div class="tab-panel">
  <div class="scroll-view scroll-vertical" style="height: 600px">${content(id)}</div>
</div></div></div>`;
const html = tab("bar", 'data-tab-layout="mobile" data-tab-mobile-bar') +
  tab("hidden", 'data-tab-layout="mobile" data-tab-mobile-bar data-tab-bar-hidden="true"') +
  tab("sidebar", 'data-tab-layout="sidebar"');

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 800 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    const padding = id => page.evaluate(name => getComputedStyle(document.getElementById(name)).paddingBottom, id);
    assert.equal(await padding("bar"), "124px", "the outer scroll view of a mobile tab ends with room for the bar");
    assert.equal(await padding("bar-shelf"), "0px", "a horizontal shelf inside it keeps none");
    assert.equal(await padding("bar-inner"), "0px", "a vertical scroll view inside it keeps none");
    assert.equal(await padding("hidden"), "28px", "a screen that hides the bar keeps none");
    assert.equal(await padding("sidebar"), "28px", "the sidebar layout keeps none");
    console.log("PASS a mobile tab's scroll view ends clear of the floating bar");
  } finally {
    await browser.close();
  }
});
