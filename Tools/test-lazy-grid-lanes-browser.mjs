#!/usr/bin/env bun
// A lazy grid is as large as its rows along the scrolling axis, and its size holds while it loads, while the page scrolls to its end and
// while it grows. The page counts a grid's rows from the tracks the browser laid out, not from the columns Swift declared (an adaptive
// column is one however many fit), and Swift sizes the cells it has not shown from what the page measured of one cell. Counting every
// cell as a row made the space for the cells outside the window several times too tall, so the height jumped when the window formed
// and the content moved under a tap. Fixtures: Tests/Apps/LazyCellStateApp, one tab for each kind of grid, 120 cells of 100 along the
// scrolling axis and 8 apart, then a text:
//   adaptive  one adaptive column;           mixed     a fixed column beside an adaptive one (the fixed track, then the adaptive ones that fit);
//   flexible  three flexible columns;        across    adaptive rows of a horizontal grid in a horizontal scroll view;
//   growing   an adaptive grid of 12 cells that gets 300 more when "Append" is pressed;
//   aligned   [.fixed(90) leading, .adaptive(minimum: 120) trailing] of cells 60 wide: each cell sits at the edge its column's item names,
//             whatever number of adaptive columns the window makes (a cell's column is only known once the browser laid the grid out).
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default). Bundle: LAZY_CELL_STATE_BUNDLE (.build/browser/LazyCellStateApp).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.LAZY_CELL_STATE_BUNDLE ?? join(ROOT, ".build/browser/LazyCellStateApp"));
const MIXED_FIXED = 90, MIXED_MINIMUM = 120; // the Mixed tab's columns (LazyCellStateRootView.swift)
const CELL = 100, GAP = 8, CELLS = 120, GROW_START = 12, GROW_STEP = 300;
const ALIGNED_CELL = 60, NARROW_WIDTH = 520; // the Aligned tab's cells (LazyGridFixtures.swift), and a window that makes fewer columns than 1000
const KINDS = [
  { kind: "adaptive", tab: "Adaptive", axis: "y" },
  { kind: "mixed", tab: "Mixed", axis: "y" },
  { kind: "aligned", tab: "Aligned", axis: "y" },
  { kind: "flexible", tab: "Flexible", axis: "y" },
  { kind: "across", tab: "Across", axis: "x" },
];

/** In the page: how long the grid of `kind` is along its scrolling axis (from its start to the text after it), how long its rows need,
 * and how many cells and columns (rows, across) it has. */
const measureGrid = ({ kind, axis, cells, cell, gap }) => {
  const end = document.querySelector(`[data-testid="${kind}-end"]`);
  const view = end?.closest(".scroll-view");
  const grid = view?.querySelector("[data-keep-lazy-index]");
  if (!view || !grid || !view.getClientRects().length) return null;
  const style = getComputedStyle(grid);
  const tracks = (axis === "y" ? style.gridTemplateColumns : style.gridTemplateRows).split(/\s+/).filter((track) => /^[\d.]/.test(track)).length;
  const lines = Math.ceil(cells / tracks);
  const from = grid.getBoundingClientRect(), to = end.getBoundingClientRect();
  return {
    tracks,
    firstTrack: parseFloat((axis === "y" ? style.gridTemplateColumns : style.gridTemplateRows).split(/\s+/)[0]),
    viewWidth: grid.clientWidth,
    extent: Math.round(axis === "y" ? to.top - from.top : to.left - from.left),
    expected: lines * cell + (lines - 1) * gap,
    shown: grid.querySelectorAll("[data-lazy-index]").length,
  };
};

/** In the page: where each cell of the grid of `kind` that is shown sits in its column. The cell `index` is in column `index % columns`
 * (a row holds a cell for each column), which is `cellWidth` wide, flush with its column's leading edge in the first (the fixed item
 * aligns leading) and with its trailing edge in the others (the adaptive item aligns trailing). Returns the columns' widths, how many
 * cells were checked and the ones that are not where their column puts them. */
const measureAlignment = ({ kind, cellWidth }) => {
  const grid = document.querySelector(`[data-testid="${kind}-end"]`)?.closest(".scroll-view")?.querySelector("[data-keep-lazy-index]");
  if (!grid || !grid.getClientRects().length) return null;
  const style = getComputedStyle(grid);
  const widths = style.gridTemplateColumns.split(/\s+/).filter((track) => /^[\d.]/.test(track)).map(parseFloat);
  const gap = parseFloat(style.columnGap) || 0;
  const origin = grid.getBoundingClientRect().left + grid.clientLeft;
  const starts = widths.map((_, at) => origin + widths.slice(0, at).reduce((sum, width) => sum + width + gap, 0));
  const wrong = [];
  let checked = 0;
  for (const cell of grid.querySelectorAll(":scope > [data-lazy-index]")) {
    const index = Number(cell.getAttribute("data-lazy-index")), column = index % widths.length, r = cell.getBoundingClientRect();
    const start = starts[column], end = start + widths[column];
    const edge = column === 0 ? Math.abs(r.left - start) : Math.abs(r.right - end);
    checked++;
    if (edge > 1 || Math.abs(r.width - cellWidth) > 1) wrong.push({ index, column, left: Math.round(r.left), right: Math.round(r.right), start: Math.round(start), end: Math.round(end) });
  }
  return { columns: widths.length, widths, checked, wrong: wrong.slice(0, 6), wrongCount: wrong.length };
};

/** In the page: the scroll extent of the view of `kind` at every animation frame for `ms` milliseconds, and after every task that changed
 * the document (a commit that is corrected before the next frame is still a page that was the wrong size for the task's end). */
const sample = ({ kind, axis, ms, untilStopped = false }) => new Promise((resolve) => {
  const sizes = [];
  const start = performance.now();
  // With `untilStopped` the sampler runs until the test sets `window.__stopLazySampling` (or `ms` passes, the cap), and
  // `window.__lazySamplingStarted` tells the test the first frame has been reached.
  // `window.__lazySamplingCapped` says the cap ended it first, so the test knows the samples do not reach its stop.
  if (untilStopped) { window.__stopLazySampling = false; window.__lazySamplingCapped = false; window.__lazySamplingStarted = true; }
  const read = () => {
    const view = document.querySelector(`[data-testid="${kind}-end"]`)?.closest(".scroll-view");
    if (view) sizes.push(axis === "y" ? view.scrollHeight : view.scrollWidth);
  };
  const observer = new MutationObserver(read);
  observer.observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
  const frame = () => {
    read();
    const running = untilStopped ? !window.__stopLazySampling && performance.now() - start < ms : performance.now() - start < ms;
    if (untilStopped && !running && !window.__stopLazySampling) window.__lazySamplingCapped = true;
    if (running) requestAnimationFrame(frame);
    else {
      observer.disconnect();
      if (untilStopped) { window.__lazySamplingStarted = false; window.__stopLazySampling = false; }
      resolve(sizes);
    }
  };
  requestAnimationFrame(frame);
});

/** In the page: scrolls the view of `kind` to its end. */
const scrollToEnd = ({ kind, axis }) => {
  const view = document.querySelector(`[data-testid="${kind}-end"]`).closest(".scroll-view");
  if (axis === "y") view.scrollTop = view.scrollHeight; else view.scrollLeft = view.scrollWidth;
};

/** In the page: whether the cell `index` of `kind` ends inside its view: its end lies between the view's start and its end. */
const endsInside = ({ kind, axis, index }) => {
  const cell = document.querySelector(`[data-testid="${kind}-cell-${index}"]`);
  const view = cell?.closest(".scroll-view");
  if (!cell || !view) return null;
  const a = cell.getBoundingClientRect(), b = view.getBoundingClientRect();
  return axis === "y"
    ? a.bottom >= b.top && a.bottom <= b.bottom + 1
    : a.right >= b.left && a.right <= b.right + 1;
};

const spread = (sizes) => Math.max(...sizes) - Math.min(...sizes);

async function main() {
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: null, required: ["index.html"] });
  try {
    const browser = await launch();
    try {
      for (const mode of ["", "?render-in-worker=0"]) {
        const label = `${engineName()}${mode ? " main thread" : " worker"}`;
        const context = await browser.newContext({ viewport: { width: 1000, height: 700 } });
        const page = await context.newPage();
        const problems = [];
        page.on("pageerror", (error) => problems.push(String(error)));
        await page.goto(`${server.base}/${mode}`);
        // The app selects its second tab by itself right after it starts; the grids are on the tabs after it.
        await page.waitForSelector('[data-testid="plain-own-add"]', { state: "visible", timeout: 60_000 });

        // What is waited for: the page has measured the cells and sized the space around the window, which the extent reaches in a frame
        // or two; the wait ends when it holds the rows' extent, and the assertion names what it was when it never did.
        const settle = async (spec, cells) => {
          const deadline = Date.now() + 10_000;
          let found = null;
          while (Date.now() < deadline) {
            found = await page.evaluate(measureGrid, { ...spec, cells, cell: CELL, gap: GAP });
            if (found && found.shown > 0 && Math.abs(found.extent - found.expected) <= 2) break;
            await page.waitForTimeout(50);
          }
          assert.ok(found && found.shown > 0, `${label} ${spec.kind}: the grid shows no cells`);
          assert.ok(Math.abs(found.extent - found.expected) <= 2,
            `${label} ${spec.kind}: the grid is ${found.extent} long, its ${cells} cells in ${found.tracks} tracks need ${found.expected}`);
          return found;
        };

        // What is waited for: every cell the grid shows is in its column's edge. The wait ends when they all are, and the assertion names
        // the cells that were not when they never were. `distinctFrom` is a column count the grid must not have (the other window's).
        const settleAlignment = async (spec, when, distinctFrom = null) => {
          const deadline = Date.now() + 10_000;
          let found = null;
          while (Date.now() < deadline) {
            found = await page.evaluate(measureAlignment, { kind: spec.kind, cellWidth: ALIGNED_CELL });
            if (found && found.checked > 0 && found.wrongCount === 0 && found.columns !== distinctFrom) break;
            await page.waitForTimeout(50);
          }
          assert.ok(found && found.checked > 0, `${label} ${spec.kind} ${when}: the grid shows no cells`);
          assert.notEqual(found.columns, distinctFrom, `${label} ${spec.kind} ${when}: the grid still has ${found.columns} columns after the window changed width`);
          // Two columns would not tell a cell's column from its index modulo the items: the first column is the fixed item, the rest are the adaptive one.
          assert.ok(found.columns > 2, `${label} ${spec.kind} ${when}: the grid has ${found.columns} columns; the test needs the adaptive item to repeat`);
          assert.ok(found.checked >= found.columns, `${label} ${spec.kind} ${when}: ${found.checked} cells shown, fewer than the ${found.columns} columns`);
          assert.equal(found.wrongCount, 0, `${label} ${spec.kind} ${when}: ${found.wrongCount} of ${found.checked} cells are not at the edge their column's item names (columns ${found.widths}): ${JSON.stringify(found.wrong)}`);
          return found;
        };

        for (const spec of KINDS) {
          await page.getByRole("tab", { name: spec.tab }).click();
          const found = await settle(spec, CELLS);
          const aligned = spec.kind === "aligned" ? await settleAlignment(spec, "at 1000") : null;
          // A grid of one track would not tell a cell from a row.
          assert.ok(found.tracks > 1, `${label} ${spec.kind}: the grid has ${found.tracks} track(s); the test needs several`);
          if (spec.kind === "across") assert.equal(found.tracks, 4, `${label} ${spec.kind}: the grid has ${found.tracks} rows, the 300 tall view holds four`);
          // What SwiftUI lays out for [.fixed(90), .adaptive(minimum: 120)] with 8 between: the fixed track, then as many adaptive
          // tracks as fit in the width it leaves (Apple: "as many items as fit in the space left by the other items").
          if (spec.kind === "mixed") {
            const adaptive = Math.floor((found.viewWidth - MIXED_FIXED - GAP + GAP) / (MIXED_MINIMUM + GAP));
            assert.equal(found.firstTrack, MIXED_FIXED, `${label} mixed: the first track is ${found.firstTrack} wide, the fixed item is ${MIXED_FIXED}`);
            assert.equal(found.tracks, 1 + adaptive, `${label} mixed: ${found.tracks} tracks in ${found.viewWidth}, SwiftUI lays out the fixed one and ${adaptive} adaptive ones`);
          }
          // Once it holds that extent, nothing changes it: not time, and not a scroll to the end (the window moves to the last rows).
          const idle = await page.evaluate(sample, { kind: spec.kind, axis: spec.axis, ms: 1000 });
          assert.equal(spread(idle), 0, `${label} ${spec.kind}: the extent changed while the page was idle: ${[...new Set(idle)]}`);
          const sampling = page.evaluate(sample, { kind: spec.kind, axis: spec.axis, ms: 1500 });
          await page.evaluate(scrollToEnd, spec);
          const scrolled = await sampling;
          assert.equal(spread(scrolled), 0, `${label} ${spec.kind}: the extent changed while scrolling to the end: ${[...new Set(scrolled)]}`);
          assert.equal(await page.evaluate(endsInside, { ...spec, index: CELLS - 1 }), true, `${label} ${spec.kind}: the last cell is not inside the view after scrolling to the end`);
          console.log(`[${label}] ${spec.kind}: ${found.tracks} tracks, ${found.extent} long, held while idle and scrolled to the end`);
          if (aligned) {
            // The rows at the end of the grid were mounted by the scroll, and their cells are aligned as the first rows' were.
            await settleAlignment(spec, "at 1000, scrolled to the end");
            // A narrower window makes fewer adaptive columns: the cells that were in the fixed column are in an adaptive one now (and the
            // other way after the window grows back), and each takes the alignment of the column it is rendered in.
            const height = page.viewportSize().height;
            await page.setViewportSize({ width: NARROW_WIDTH, height });
            await settle(spec, CELLS);
            const narrow = await settleAlignment(spec, `at ${NARROW_WIDTH}`, aligned.columns);
            await page.setViewportSize({ width: 1000, height });
            await settle(spec, CELLS);
            await settleAlignment(spec, "back at 1000", narrow.columns);
            console.log(`[${label}] ${spec.kind}: cells at the edge of their column with ${aligned.columns} columns, then ${narrow.columns}, then ${aligned.columns} again`);
          }
        }

        // A grid that grows: from the press to a second later the extent never goes down, and it ends at the rows' extent. What is
        // compared is the first frames after the new cells arrive, which are laid out from Swift's estimate of the cells not shown
        // until the page's window answers.
        const growing = { kind: "growing", axis: "y" };
        await page.getByRole("tab", { name: "Growing" }).click();
        await settle(growing, GROW_START);
        // Sampling starts before the append and stops only once the grid has settled at its new size (capped at 15 s).
        const sampling = page.evaluate(sample, { ...growing, ms: 15000, untilStopped: true });
        await page.waitForFunction(() => window.__lazySamplingStarted === true);
        await page.locator('[data-testid="growing-append"]').click();
        const grown = await settle(growing, GROW_START + GROW_STEP);
        await page.evaluate(() => { window.__stopLazySampling = true; });
        const sizes = await sampling;
        assert.equal(await page.evaluate(() => window.__lazySamplingCapped), false, `${label} growing: sampling hit its 15 s cap before the grid settled, so a later drop would go unseen`);
        const drops = sizes.flatMap((size, at) => (at > 0 && size < sizes[at - 1] ? [`${sizes[at - 1]} -> ${size}`] : []));
        assert.deepEqual(drops, [], `${label} growing: the extent went down after cells were appended (${[...new Set(sizes)]})`);
        assert.ok(grown.shown < GROW_START + GROW_STEP, `${label} growing: the grid shows all ${grown.shown} cells; the test needs cells outside the window`);
        const steps = sizes.filter((size, at) => at === 0 || size !== sizes[at - 1]);
        console.log(`[${label}] growing: ${GROW_START} cells, then ${GROW_START + GROW_STEP}: never shorter (${steps.join(" -> ")}), ${grown.extent} long`);

        assert.deepEqual(problems, [], `${label}: page errors`);
        await context.close();
      }
    } finally {
      await browser.close();
    }
    console.log("Lazy grid lanes browser test passed.");
  } finally {
    await server.stop();
  }
}

await runSuite(main);
