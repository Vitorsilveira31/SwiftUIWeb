#!/usr/bin/env bun
// The grid cell modifiers on a `Grid` (`data-layout-kind="table"`): `gridCellColumns` covers several columns,
// `gridCellAnchor` places a cell in its slot, `gridCellUnsizedAxes` takes the slot instead of sizing it and
// `gridColumnAlignment` aligns a whole column. The CSS layout mapper must lay each out as SwiftUI does.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const css = readFileSync(new URL("./css-layout.js", import.meta.url), "utf8").replace(/^export /gm, "");
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
  await page.setContent("<!doctype html><html><head><style>body{margin:0;font:16px/20px sans-serif}</style></head><body></body></html>");
  await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
  const result = await page.evaluate(() => {
    const leaf = (id, text, extra = "") => `<span id="${id}" data-layout-leaf="text" data-layout-kind="intrinsic" ${extra}>${text}</span>`;
    const row = (...cells) => `<div class="grid-row" data-layout-kind="gridrow">${cells.join("")}</div>`;
    const html = `<div id="root" class="scroll-view scroll-vertical" data-layout-kind="scroll" style="width:400px;height:500px">
      <div class="vstack" data-layout-kind="vstack" data-layout-gap="0" data-align-x="0">
        <div id="grid" class="grid-layout regular-grid" data-layout-kind="table" data-layout-gap="12" data-row-spacing="8" data-align-x="0" data-align-y="0.5">
          ${row(leaf("a", "Alpha beta gamma"), leaf("b", "B"))}
          ${row(leaf("c", "C", 'data-grid-column-alignment="flex-end"'), leaf("d", "D"))}
          ${row(leaf("e", "E", 'data-grid-cell-anchor="1,0.5"'), leaf("f", "F", 'data-grid-cell-anchor="1,1"'))}
          ${row(leaf("span", "Both columns", 'data-grid-cell-columns="2"'))}
          ${row(leaf("g", "A long cell that does not size its column", 'data-grid-unsized-axes="1"'), leaf("h", "H"))}
        </div></div></div>`;
    document.body.innerHTML = html;
    const mapper = new CssLayout(document), root = document.getElementById("root");
    if (!mapper.claim(root)) return { refused: true };
    mapper.flush();
    const rect = (id) => { const r = document.getElementById(id).getBoundingClientRect(); return { x: r.x, right: r.right, y: r.y, bottom: r.bottom, width: r.width }; };
    const grid = document.getElementById("grid");
    return { refused: false, columns: getComputedStyle(grid).gridTemplateColumns.split(" ").map(parseFloat), gap: 12, ...Object.fromEntries(["a", "b", "c", "d", "e", "f", "span", "g", "h"].map((id) => [id, rect(id)])) };
  });
  assert.equal(result.refused, false, "the mapper lays the grid out");
  const near = (a, b, why) => assert.ok(Math.abs(a - b) < 1.5, `${why}: ${a} is not ${b}`);
  assert.equal(result.columns.length, 2, "a cell that covers two columns does not add a column");
  const first = result.a.x, second = result.b.x;
  // gridColumnAlignment(.trailing) on C: the whole first column is trailing-aligned, so C ends where the widest cell does.
  near(result.c.right, result.a.right, "column alignment: C trails its column");
  // gridCellAnchor: E sits at the trailing edge of its slot, F at the trailing edge of its slot too (and at the bottom).
  near(result.e.right, result.a.right, "anchor: E trails its column");
  near(result.f.right, second + result.columns[1], "anchor: F trails its column");
  // gridCellColumns(2): the cell starts at the first column and is as wide as the two columns and their gap at most.
  near(result.span.x, first, "span: starts at the first column");
  assert.ok(result.span.right <= second + result.columns[1] + 1.5, "span: stays inside the two columns");
  // gridCellUnsizedAxes(.horizontal): the long cell does not widen the first column, which keeps A's width.
  near(result.columns[0], result.a.width, "unsized: the first column is as wide as the widest cell that sizes it");
  console.log("css layout grid cells test: OK");
} finally {
  await browser.close();
}
