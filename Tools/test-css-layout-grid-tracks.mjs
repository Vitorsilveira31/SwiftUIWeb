#!/usr/bin/env bun
// The tracks a lazy grid's `GridItem`s become in the CSS layout mapper. A fixed item is one track of its size, a flexible one a track
// between its bounds, and an adaptive one as many tracks of its minimum as fit in the space the other items leave (Apple's
// documentation of `GridItem.Size.adaptive`): `[.fixed(90), .adaptive(minimum: 120)]` is the fixed track, then the adaptive ones.
// A LazyHGrid's rows are the tracks the same way.
//   bun Tools/test-css-layout-grid-tracks.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const css = readFileSync(new URL("./css-layout.js", import.meta.url), "utf8").replace(/^export /gm, "");
const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
  await page.setContent("<!doctype html><html><head><style>body{margin:0;font:16px/20px sans-serif}</style></head><body></body></html>");
  await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
  // The grid is 500 along its tracks' axis (a vertical grid's width, a horizontal grid's height) and 300 the other way.
  const lay = ({ tracks, horizontal }) => page.evaluate(({ tracks, horizontal }) => {
    const cells = Array.from({ length: 24 }, (_, i) => `<span data-layout-leaf="text" data-layout-kind="intrinsic" style="width:40px;height:20px">${i}</span>`).join("");
    const stack = horizontal ? "hstack" : "vstack";
    document.body.innerHTML = `<div id="root" data-layout-kind="frame" data-frame-w="${horizontal ? 300 : 500}" data-frame-h="${horizontal ? 500 : 300}" data-align-x="0" data-align-y="0">
      <div class="${stack}" data-layout-kind="${stack}" data-layout-gap="0" data-align-x="0" data-align-y="0">
      <div id="grid" class="grid-layout ${horizontal ? "hgrid" : ""}" data-layout-kind="grid" data-grid-tracks="${tracks}" data-layout-gap="8" data-row-spacing="8" data-align-x="0" data-align-y="0">${cells}</div></div></div>`;
    const mapper = new CssLayout(document), root = document.getElementById("root");
    if (!mapper.claim(root)) return { refused: true };
    mapper.assign(root);
    const style = getComputedStyle(document.getElementById("grid"));
    return { refused: false, tracks: (horizontal ? style.gridTemplateRows : style.gridTemplateColumns).split(/\s+/).map(parseFloat) };
  }, { tracks, horizontal });

  // Items are 8 apart. An adaptive item's tracks stretch to fill the space of their count (`1fr`).
  const fixed = (n) => `fixed:${n}.0:${n}.0:8.0::`, adaptive = (n) => `adaptive:${n}.0:inf:8.0::`, flexible = "flexible:10.0:inf:8.0::";
  const cases = [
    ["fixed items", [fixed(90), fixed(60)], 2, [90, 60]],
    ["flexible items", [flexible, flexible, flexible], 3, null],
    // floor((500 + 8) / (120 + 8)) = 3 tracks.
    ["one adaptive item", [adaptive(120)], 3, null],
    // The fixed item and its gap leave 402: floor((402 + 8) / 128) = 3 adaptive tracks after the fixed one (it was dropped before).
    ["a fixed item, then an adaptive one", [fixed(90), adaptive(120)], 4, [90]],
    ["an adaptive item, then a fixed one", [adaptive(120), fixed(90)], 4, [null, null, null, 90]],
    ["a flexible item beside an adaptive one", [flexible, adaptive(120)], 4, null],
    // CSS repeats one `auto-fill` per grid: a second adaptive item is one track.
    ["two adaptive items", [adaptive(120), adaptive(80)], 4, null],
  ];
  for (const horizontal of [false, true]) {
    for (const [name, tracks, count, sizes] of cases) {
      const result = await lay({ tracks: tracks.join("|"), horizontal });
      assert.equal(result.refused, false, `${name}: the mapper lays the grid out`);
      assert.equal(result.tracks.length, count, `${horizontal ? "rows" : "columns"} of ${name}: ${result.tracks}`);
      if (sizes) sizes.forEach((size, at) => { if (size != null) assert.equal(result.tracks[at], size, `${name}: track ${at} of ${result.tracks}`); });
    }
  }
  console.log("css layout grid tracks test: OK");
} finally {
  await browser.close();
}
