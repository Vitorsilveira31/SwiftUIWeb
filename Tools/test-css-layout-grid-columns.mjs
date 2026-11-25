#!/usr/bin/env bun
// Which item of a lazy grid a cell is aligned by. A cell takes the alignment of the `GridItem` of the column it is rendered in. An
// adaptive item makes as many columns as the width allows, so the column of a cell is not its index modulo the items, and only the
// browser knows it once it laid the grid out: the mapper writes the alignment the cell has until then, and `alignGridColumns` sets the
// column's (`--cl-col-x`, `--cl-col-y`) after every pass and when the grid's size changes. Grids whose items align the same way keep
// the alignment in the block, as before.
//   bun Tools/test-css-layout-grid-columns.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chromium } from "playwright";
import { alignsByColumn, trackOfColumn } from "./css-layout.js";

// The mapping from a rendered column to its item. A track is `{ type, ax, ay }`; `ax` and `ay` are null where the item names no alignment.
const fixed = (ax = null, ay = null) => ({ type: "fixed", ax, ay }), flexible = (ax = null, ay = null) => ({ type: "flexible", ax, ay });
const adaptive = (ax = null, ay = null) => ({ type: "adaptive", ax, ay });
const columnsOf = (tracks, columns) => Array.from({ length: columns }, (_, column) => trackOfColumn(tracks, columns, column));
// [fixed, adaptive]: the fixed item's column, then the adaptive item's, as many times as the columns that are left.
assert.deepEqual(columnsOf([fixed(), adaptive()], 2), [0, 1]);
assert.deepEqual(columnsOf([fixed(), adaptive()], 3), [0, 1, 1]);
assert.deepEqual(columnsOf([fixed(), adaptive()], 5), [0, 1, 1, 1, 1]);
// [adaptive, fixed]: the adaptive item's columns, then the fixed item's.
assert.deepEqual(columnsOf([adaptive(), fixed()], 4), [0, 0, 0, 1]);
// [flexible, adaptive, fixed]: one of each around the repetition.
assert.deepEqual(columnsOf([flexible(), adaptive(), fixed()], 5), [0, 1, 1, 1, 2]);
// Only the first adaptive item repeats; the second is one column (CSS repeats one `auto-fill` per grid).
assert.deepEqual(columnsOf([adaptive(), adaptive()], 4), [0, 0, 0, 1]);
assert.deepEqual(columnsOf([fixed(), adaptive(), adaptive()], 4), [0, 1, 1, 2]);
// Without an adaptive item the items repeat in order; so do they when the count is one the template cannot make.
assert.deepEqual(columnsOf([fixed(), flexible(), flexible()], 3), [0, 1, 2]);
assert.deepEqual(columnsOf([fixed(), adaptive(), fixed()], 1), [0]);
// Which grids need the browser: an adaptive item beside items that align the cell differently, in either axis.
const aligned = (tracks, ax = 0.5, ay = 0.5) => alignsByColumn(tracks, ax, ay);
assert.equal(aligned([fixed(0), adaptive(1)]), true, "a leading fixed item and a trailing adaptive one");
assert.equal(aligned([fixed(0.5, 0), adaptive(0.5, 1)]), true, "items that differ vertically");
assert.equal(aligned([fixed(0), adaptive()], 0.5), true, "an item that names an alignment beside one that takes the grid's");
assert.equal(aligned([fixed(), adaptive()]), false, "no item names an alignment");
assert.equal(aligned([fixed(1), adaptive(1)]), false, "every item aligns the same way");
assert.equal(aligned([fixed(1), adaptive()], 1), false, "an item that names the grid's alignment beside one that takes it");
assert.equal(aligned([fixed(0), flexible(1)]), false, "no adaptive item: the column is the item's index");
assert.equal(aligned([adaptive(0), adaptive(1)]), true, "two adaptive items");

const css = readFileSync(new URL("./css-layout.js", import.meta.url), "utf8").replace(/^export /gm, "");
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
  await page.setContent("<!doctype html><html><head><style>body{margin:0;font:16px/20px sans-serif}</style></head><body></body></html>");
  await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout; window.mapper = null;" });
  // A grid of 24 cells 40 wide and 20 tall (`tracks` is the grid's `data-grid-tracks`), 500 wide (a LazyHGrid's rows: 500 tall), in a page
  // the mapper styled. Returns what the grid is made of, and `where` reads where each cell is in its column afterwards.
  const lay = ({ tracks, horizontal = false, width = 500 }) => page.evaluate(({ tracks, horizontal, width }) => {
    const cells = Array.from({ length: 24 }, (_, i) => `<span data-layout-leaf="text" data-layout-kind="intrinsic" style="display:block;width:40px;height:20px">${i}</span>`).join("");
    const stack = horizontal ? "hstack" : "vstack";
    document.body.innerHTML = `<div id="root" data-layout-kind="frame" data-frame-w="${horizontal ? 300 : width}" data-frame-h="${horizontal ? width : 300}" data-align-x="0" data-align-y="0">
      <div class="${stack}" data-layout-kind="${stack}" data-layout-gap="0" data-align-x="0" data-align-y="0">
      <div id="grid" class="grid-layout ${horizontal ? "hgrid" : ""}" data-layout-kind="grid" data-grid-tracks="${tracks}" data-layout-gap="8" data-row-spacing="8" data-align-x="0.5" data-align-y="0.5">${cells}</div></div></div>`;
    window.mapper = new CssLayout(document);
    const root = document.getElementById("root");
    if (!window.mapper.claim(root)) return { refused: true };
    window.mapper.assign(root);
    window.mapper.alignGridColumns();
    return { refused: false, byColumn: window.mapper.columned.size === 1, blocks: window.mapper.blocks.filter(Boolean).some((block) => block.includes("--cl-col-")) };
  }, { tracks, horizontal, width });
  // For each cell: its column (its index modulo the columns the browser made), where it sits in the column on the axis the grid's tracks
  // run along (0: at the leading edge, 1: at the trailing edge) and the free room it has there; across the tracks the same on the other axis.
  const where = ({ horizontal = false } = {}) => page.evaluate((horizontal) => {
    const grid = document.getElementById("grid"), style = getComputedStyle(grid);
    const tracks = (horizontal ? style.gridTemplateRows : style.gridTemplateColumns).split(/\s+/).map(parseFloat);
    const gap = parseFloat(horizontal ? style.rowGap : style.columnGap) || 0, box = grid.getBoundingClientRect();
    const starts = tracks.map((_, at) => (horizontal ? box.top : box.left) + tracks.slice(0, at).reduce((sum, size) => sum + size + gap, 0));
    return { columns: tracks.length, cells: [...grid.children].map((cell, index) => {
      const r = cell.getBoundingClientRect(), column = index % tracks.length, start = starts[column], size = tracks[column];
      const room = size - (horizontal ? r.height : r.width), at = (horizontal ? r.top : r.left) - start;
      return { index, column, along: room > 0.5 ? at / room : null };
    }) };
  }, horizontal);

  const fix = (n, ax, ay) => `fixed:${n}.0:${n}.0:8.0:${ax}:${ay}`, adapt = (n, ax, ay) => `adaptive:${n}.0:inf:8.0:${ax}:${ay}`;
  const flex = (ax, ay) => `flexible:10.0:inf:8.0:${ax}:${ay}`;
  const near = (a, b) => Math.abs(a - b) < 0.02;

  // The alignment of an item along its tracks' axis: a LazyVGrid's columns are aligned horizontally (0 leading, 1 trailing), a
  // LazyHGrid's rows vertically (0 top, 1 bottom); the other axis is centred.
  const item = (horizontal, along) => horizontal ? [0.5, along] : [along, 0.5];
  const track = (horizontal, make, along, ...args) => make(...args, ...item(horizontal, along));
  const grid = (horizontal, ...items) => items.join("|");

  // [fixed(90, leading), adaptive(120, trailing)] at 500: the fixed track, then three adaptive ones. Each cell is at the edge of its column's item.
  for (const horizontal of [false, true]) {
    const axis = horizontal ? "rows" : "columns";
    const mixed = await lay({ tracks: grid(horizontal, track(horizontal, fix, 0, 90), track(horizontal, adapt, 1, 120)), horizontal });
    assert.equal(mixed.refused, false, "the mapper lays the grid out");
    assert.equal(mixed.byColumn, true, "a grid whose items align differently is aligned by column");
    assert.equal(mixed.blocks, true, "its cells read the column's alignment, with their own as the fallback");
    const result = await where({ horizontal });
    assert.equal(result.columns, 4, `the fixed ${axis} and three adaptive ones`);
    for (const cell of result.cells) {
      const edge = cell.column === 0 ? 0 : 1;
      assert.ok(cell.along == null || near(cell.along, edge), `cell ${cell.index} of ${axis}: column ${cell.column} at ${cell.along}, the item aligns it ${edge === 0 ? "leading" : "trailing"}`);
    }
    assert.ok(result.cells.filter((cell) => cell.along != null).length >= 20, "the cells are narrower than their tracks, so their alignment shows");
  }

  // A grid that is narrower has fewer adaptive columns, and a wider one more: the cells that were in the fixed column are in an adaptive
  // one, and the other way. (330 is room for one adaptive column, 400 for two, 500 for three, 700 for four.)
  for (const [width, columns] of [[500, 4], [330, 2], [400, 3], [700, 5]]) {
    await lay({ tracks: grid(false, track(false, fix, 0, 90), track(false, adapt, 1, 120)), width });
    const result = await where();
    assert.equal(result.columns, columns, `columns at ${width}`);
    for (const cell of result.cells) {
      const edge = cell.column === 0 ? 0 : 1;
      assert.ok(cell.along == null || near(cell.along, edge), `at ${width}: cell ${cell.index} of ${result.columns} columns is in column ${cell.column} at ${cell.along}, the item aligns it ${edge === 0 ? "leading" : "trailing"}`);
    }
  }

  // [adaptive(leading), fixed(trailing)]: the repetition comes first, and the cells of the last column are the fixed item's.
  await lay({ tracks: [adapt(120, 0, 0.5), fix(90, 1, 0.5)].join("|") });
  const reversed = await where();
  assert.equal(reversed.columns, 4);
  for (const cell of reversed.cells) assert.ok(cell.along == null || near(cell.along, cell.column === 3 ? 1 : 0), `reversed: cell ${cell.index} in column ${cell.column} at ${cell.along}`);

  // The grid changes size with no pass of the mapper (a pane that moves): the cells follow the columns the browser makes now.
  await lay({ tracks: [fix(90, 0, 0.5), adapt(120, 1, 0.5)].join("|") });
  await page.evaluate(() => { document.getElementById("root").style.setProperty("width", "400px", "important"); });
  await page.waitForFunction(() => getComputedStyle(document.getElementById("grid")).gridTemplateColumns.split(" ").length === 3);
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const moved = await where();
  assert.equal(moved.columns, 3);
  for (const cell of moved.cells) assert.ok(cell.along == null || near(cell.along, cell.column === 0 ? 0 : 1), `a grid that changed size: cell ${cell.index} in column ${cell.column} at ${cell.along}`);

  // The host is disposed while its DOM stays mounted: the grid's observer is disconnected, so a later resize leaves the cells as they are
  // (cell 3 is in the last of four columns, trailing, and would be in the first of three, leading) and the mapper holds no grid.
  await lay({ tracks: [fix(90, 0, 0.5), adapt(120, 1, 0.5)].join("|") });
  const disposed = await page.evaluate(async () => {
    const cell = document.getElementById("grid").children[3], before = cell.style.getPropertyValue("--cl-col-x");
    // The observer `lay` made (the first `alignGridColumns` creates it): `dispose` must disconnect it, not only stop reacting to it.
    const observer = window.mapper.columnObserver;
    let disconnected = 0;
    if (observer) { const disconnect = observer.disconnect; observer.disconnect = function () { disconnected++; return disconnect.call(this); }; }
    window.mapper.dispose();
    document.getElementById("root").style.setProperty("width", "400px", "important");
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    window.mapper.alignGridColumns();
    return { before, after: cell.style.getPropertyValue("--cl-col-x"), columns: getComputedStyle(document.getElementById("grid")).gridTemplateColumns.split(" ").length, held: window.mapper.columned.size, observed: !!observer, disconnected, kept: window.mapper.columnObserver };
  });
  assert.deepEqual(disposed, { before: "flex-end", after: "flex-end", columns: 3, held: 0, observed: true, disconnected: 1, kept: null }, `a disposed mapper leaves the cells alone and disconnects the observer: ${JSON.stringify(disposed)}`);

  // Items that align the same way, or none that is adaptive: the alignment stays in the block, and nothing is observed or written.
  for (const tracks of [[fix(90, 1, 0.5), adapt(120, 1, 0.5)], [fix(90, "", ""), adapt(120, "", "")], [fix(90, 0, 0.5), flex(1, 0.5), flex(1, 0.5)]]) {
    const result = await lay({ tracks: tracks.join("|") });
    assert.equal(result.byColumn, false, `${tracks.join("|")}: aligned by the block`);
    assert.equal(result.blocks, false, `${tracks.join("|")}: no cell reads a column's alignment`);
    const written = await page.evaluate(() => [...document.getElementById("grid").children].some((cell) => cell.style.getPropertyValue("--cl-col-x") || cell.style.getPropertyValue("--cl-col-y")));
    assert.equal(written, false, `${tracks.join("|")}: no cell carries a column's alignment`);
  }
  console.log("css layout grid columns test: OK");
} finally {
  await browser.close();
}
