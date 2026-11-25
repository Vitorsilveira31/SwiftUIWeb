#!/usr/bin/env bun
// A `TabSection` title in a sidebar keeps its height when the sidebar's tabs do not fit: the list scrolls instead of
// squeezing the titles (they were flexible items with `min-height: 0` and `overflow: hidden`, cut to a few points).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const css = readFileSync(new URL("./styles.css", import.meta.url), "utf8");
const tabs = (count) => Array.from({ length: count }, (_, index) =>
  `<button role="tab" class="tab-item" data-tab="t${index}">Tab ${index}</button>`).join("");
const section = (title, count) =>
  `<span class="tab-section-header" data-tab-section="${title}" data-tab-section-title="${title}">${title}</span>${tabs(count)}`;

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 400 } });
  await page.setContent(`<!doctype html><html><head><style>${css}</style></head><body style="margin:0">
    <div class="tab-view" data-tab-adaptive="sidebar-bottom" style="height:400px">
      <div class="tab-sidebar" data-tab-sidebar="true" style="height:400px">
        <div id="list" class="tab-list tab-sidebar-list" style="height:300px">
          ${tabs(7)}${section("Promotion", 1)}${section("Creative knowledge", 1)}${section("Studio", 2)}${section("Administration", 5)}
        </div>
      </div>
    </div>
  </body></html>`);
  const measure = () => page.evaluate(() => {
    const list = document.getElementById("list");
    const header = list.querySelector(".tab-section-header");
    return {
      overflows: list.scrollHeight > list.clientHeight,
      header: header.getBoundingClientRect().height,
      natural: header.scrollHeight,
    };
  });
  const { overflows, header, natural } = await measure();
  assert.ok(overflows, "the fixture's list is taller than its room, as a long sidebar in a short window");
  assert.ok(natural > 12, `the title has a line of text to show (${natural})`);
  assert.equal(header, natural, `a section title keeps its height in a list that does not fit (${header} of ${natural})`);
  console.log("sidebar section header test: OK");
} finally {
  await browser.close();
}
