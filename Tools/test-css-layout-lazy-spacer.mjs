#!/usr/bin/env bun
// A lazy stack's spacer stands in for the rows outside the window. With none to stand in for (the window reaches that
// end) it takes no room and no spacing: a LazyVStack of two rows with 28 points of spacing is 50 + 28 + 50 tall, as in
// SwiftUI, not 28 more (a home's last shelf ended a gap above the bottom bar). A spacer that stands in for rows keeps
// its height and the spacing before it.
//   bun Tools/test-css-layout-lazy-spacer.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const css = readFileSync(new URL("./css-layout.js", import.meta.url), "utf8").replace(/^export /gm, "");
const row = '<div data-layout-kind="size" data-size-w="100" data-size-h="50"></div>';
const stack = (id, after) => `<div id="${id}" data-layout-kind="frame" data-frame-w="200" data-align-x="0" data-align-y="0">
  <div class="vstack lazy-vstack" data-layout-kind="vstack" data-layout-gap="28">
    <div class="lazy-spacer" data-lazy-spacer="__lazy_before" data-layout-kind="size" data-size-w="0" data-size-h="0" style="height:0px"></div>
    ${row}${row}
    <div class="lazy-spacer" data-lazy-spacer="__lazy_after" data-layout-kind="size" data-size-w="0" data-size-h="${after}" style="height:${after}px"></div>
  </div></div>`;

const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  await page.setContent(`<body style="margin:0">${stack("ends", 0)}${stack("virtualized", 100)}</body>`);
  await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
  const height = id => page.evaluate(name => {
    document.adoptedStyleSheets = [];
    const layout = new CssLayout(document), root = document.getElementById(name);
    layout.claim(root); layout.assign(root);
    return Math.round(root.querySelector(".vstack").getBoundingClientRect().height);
  }, id);
  assert.equal(await height("ends"), 128, "empty spacers take no room and no spacing");
  assert.equal(await height("virtualized"), 128 + 28 + 100, "a spacer for rows outside the window keeps its height and spacing");
  console.log("PASS an empty lazy spacer adds no spacing");
} finally {
  await browser.close();
}
