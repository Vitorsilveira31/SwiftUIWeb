#!/usr/bin/env bun
// A bottom safeAreaInset over a vertical ScrollView, as SwiftUI lays it out: the scroll view keeps its full height and
// runs under the inset (a floating bottom bar), the inset paints above it, and the scroll content ends with room for
// the inset (its measured height, `--safe-area-inset-extent`), so the last row scrolls clear of it. Content that is not a
// scroll view keeps the track above the inset.
//   bun Tools/test-css-layout-inset-under.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const css = readFileSync(new URL("./css-layout.js", import.meta.url), "utf8").replace(/^export /gm, "");
const bar = '<div id="BAR" data-layout-kind="size" data-size-w="300" data-size-h="74"></div>';
const fixture = (id, body) => `<div id="${id}" data-layout-kind="frame" data-frame-w="300" data-frame-h="600" data-align-x="0" data-align-y="0">
  <div class="safe-area-inset" data-layout-kind="inset" data-inset-edge="bottom" data-safe-area-edge="bottom" data-layout-gap="0">
    ${body}${bar.replace("BAR", id + "-bar")}
  </div></div>`;
const scroll = id => `<div id="${id}-scroll" class="scroll-view scroll-vertical" data-layout-kind="scroll" data-scroll-axes="vertical">
  <div id="${id}-content" data-layout-kind="padding" data-padding-bottom="16"><div data-layout-kind="size" data-size-w="300" data-size-h="1500"></div></div>
</div>`;

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 400, height: 800 } });
  await page.setContent(`<body style="margin:0">${fixture("under", scroll("under"))}${fixture("plain", '<div id="plain-body" data-layout-kind="size" data-size-w="300" data-size-h="100"></div>')}</body>`);
  await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
  await page.evaluate(() => {
    document.adoptedStyleSheets = [];
    window.layout = new CssLayout(document);
    for (const id of ["under", "plain"]) { const root = document.getElementById(id); window.layout.claim(root); window.layout.assign(root); }
  });
  await page.waitForTimeout(200);
  const box = id => page.evaluate(name => { const r = document.getElementById(name).getBoundingClientRect(); return [Math.round(r.top), Math.round(r.bottom)]; }, id);
  assert.deepEqual(await box("under-scroll"), [0, 600], "the scroll view keeps its full height and runs under the inset");
  assert.deepEqual(await box("under-bar"), [526, 600], "the inset sits at the bottom");
  assert.equal(await page.evaluate(() => getComputedStyle(document.getElementById("under-bar")).zIndex), "1", "the inset paints above the scroll view");
  assert.equal(await page.evaluate(() => getComputedStyle(document.getElementById("under-content")).paddingBottom), "90px", "the content ends with room for the inset");
  assert.ok((await box("plain-body"))[1] <= (await box("plain-bar"))[0], "content that is not a scroll view stays above the inset");
  console.log("PASS a scroll view runs under a bottom safeAreaInset and ends clear of it");
} finally {
  await browser.close();
}
