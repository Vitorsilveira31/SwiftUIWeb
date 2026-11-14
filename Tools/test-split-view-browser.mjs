#!/usr/bin/env bun
// Real Embedded browser gate for HSplitView and VSplitView dividers.
//
// Drives the Showcase layout route (/layout) through the linked Swift + BrowserIO bundle, where three split views sit: the IDE
// card (an HSplitView whose second pane holds a VSplitView), the Master/detail card, and the Divider limits card (a leading
// pane of 120 to 240 px). Checks that a pointer drag and the arrow keys move a divider and resize its panes (the content of
// a pane follows its box), that a settled position survives a re-render from a state change and a viewport change, and that
// the limits the panes declare hold for the pointer, the keys, Home and End.
import assert from "node:assert/strict";
import { join } from "node:path";
import { ROOT, launch, runSuite, serveBundle } from "./browser-test-support.mjs";

const ROUTE = "/layout";
const IDE_HORIZONTAL = ["horizontal", "Navigator"];
const IDE_VERTICAL = ["vertical", "Editor"];
const MASTER_DETAIL = ["horizontal", "Selected item"];
const LIMITS = ["horizontal", "Min 120"];

// Page-side helpers. They are passed to Playwright as real functions, so they must not reference module state.
// The index, among every divider on the page, of the divider of `axis` whose layout box holds `marker`.
const INDEX = ([axis, marker]) =>
  [...document.querySelectorAll("[data-split-divider-index]")].findIndex(
    (divider) => divider.getAttribute("data-split-axis") === axis && divider.parentElement.textContent.includes(marker),
  );

// The geometry of one split: its divider, its layout box, each pane (inline extents, limits and box) and the content of each pane.
const SNAPSHOT = (index) => {
  const divider = document.querySelectorAll("[data-split-divider-index]")[index];
  const wrapper = divider.parentElement;
  const rect = (element) => {
    const r = element.getBoundingClientRect();
    return [r.left, r.top, r.width, r.height];
  };
  const panes = [...wrapper.children].filter((child) => child.hasAttribute("data-split-item-index"));
  return {
    index,
    axis: divider.getAttribute("data-split-axis"),
    divider: rect(divider),
    wrapper: rect(wrapper),
    panes: panes.map((pane) => ({
      box: rect(pane),
      min: pane.getAttribute("data-split-min"),
      max: pane.getAttribute("data-split-max"),
      content: pane.firstElementChild ? rect(pane.firstElementChild) : null,
    })),
    positions: wrapper.getAttribute("data-split-positions"),
    ariaNow: divider.getAttribute("aria-valuenow"),
    focused: document.activeElement === divider,
  };
};

const near = (actual, expected, tolerance, what) => {
  assert.ok(
    Math.abs(actual - expected) <= tolerance,
    `${what}: expected ${expected.toFixed(2)} +- ${tolerance}, got ${actual.toFixed(2)}`,
  );
};

// The extent along the split's axis: width for a horizontal split, height for a vertical one.
const extent = (snapshot, pane) => snapshot.panes[pane].box[snapshot.axis === "horizontal" ? 2 : 3];
const along = (snapshot, pane) => snapshot.panes[pane].box[snapshot.axis === "horizontal" ? 0 : 1];
const dividerCenter = (snapshot) => [snapshot.divider[0] + snapshot.divider[2] / 2, snapshot.divider[1] + snapshot.divider[3] / 2];

async function load(page, base) {
  const response = await page.goto(base + ROUTE, { waitUntil: "domcontentloaded" });
  assert.ok(response && response.status() === 200, `${ROUTE} did not load`);
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  await page.waitForFunction(() => document.querySelectorAll("[data-split-divider-index]").length >= 4, undefined, { timeout: 30_000 });
  await page.waitForTimeout(300);
}

async function locate(page, [axis, marker]) {
  const index = await page.evaluate(INDEX, [axis, marker]);
  assert.ok(index >= 0, `no ${axis} divider holds "${marker}"`);
  return index;
}

// Measures the split after bringing its divider into view: a pointer can only reach what the viewport shows.
async function snapshot(page, index) {
  await page.locator("[data-split-divider-index]").nth(index).scrollIntoViewIfNeeded();
  return page.evaluate(SNAPSHOT, index);
}

// Waits until the split's geometry stops changing. The page reports each move to Swift and Swift re-renders the split, which
// can take longer than the key or pointer events that caused it, so a fixed delay would read a split that is still moving.
async function settle(page, index) {
  let last = null;
  let stable = 0;
  for (let attempt = 0; attempt < 150 && stable < 8; attempt++) {
    const panes = await page.evaluate(SNAPSHOT, index);
    const key = JSON.stringify(panes.panes.map((pane) => pane.box));
    stable = key === last ? stable + 1 : 0;
    last = key;
    await page.waitForTimeout(100);
  }
  return snapshot(page, index);
}

// A pointer drag that starts on the divider and ends `dx`, `dy` px away, in as many moves as a person makes.
async function drag(page, before, dx, dy) {
  const [x, y] = dividerCenter(before);
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + dx, y + dy, { steps: 12 });
  await page.mouse.up();
  return settle(page, before.index);
}

async function pressKeys(page, index, keys) {
  await page.locator("[data-split-divider-index]").nth(index).focus();
  for (const key of keys) await page.keyboard.press(key);
  return settle(page, index);
}

await runSuite(async () => {
  const bundle = process.env.SPLIT_VIEW_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp");
  const port = Number(process.env.SPLIT_VIEW_PORT ?? "8150");
  const { base, stop } = await serveBundle({ bundle, port, logName: "split-view-browser-server" });
  let browser;
  try {
    browser = await launch();
    const context = await browser.newContext({ viewport: { width: 1200, height: 900 } });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await load(page, base);

    // 1. A pointer drag moves the divider, resizes both panes and the content of the leading pane follows its box.
    const master = await locate(page, MASTER_DETAIL);
    const start = await snapshot(page, master);
    const total = extent(start, 0) + extent(start, 1);
    await drag(page, start, 60, 0);
    const dragged = await snapshot(page, master);
    near(extent(dragged, 0), extent(start, 0) + 60, 1.5, "leading pane after a 60 px drag");
    near(extent(dragged, 1), extent(start, 1) - 60, 1.5, "trailing pane after a 60 px drag");
    near(dragged.divider[0], start.divider[0] + 60, 1.5, "divider after a 60 px drag");
    near(extent(dragged, 0) + extent(dragged, 1), total, 1, "the panes keep the split's extent");
    near(dragged.panes[0].content[2], start.panes[0].content[2] + 60, 3, "leading content width after a drag");
    near(parseFloat(dragged.ariaNow), (extent(dragged, 0) / total) * 100, 0.5, "divider aria-valuenow after a drag");
    const fractions = dragged.positions.split(",").map(Number);
    near(fractions[0] + fractions[1], 1, 1e-6, "reported positions sum to 1");
    near(fractions[0], extent(dragged, 0) / total, 1e-3, "reported leading fraction");

    // 2. The position survives a re-render caused by a state change (a row chosen in the detail's list).
    const row = page.locator("[data-split-divider-index]").nth(master).locator("xpath=..").getByRole("button", { name: "WASM browser runtime", exact: true });
    await row.click();
    await page.waitForTimeout(300);
    const rerendered = await snapshot(page, master);
    near(extent(rerendered, 0), extent(dragged, 0), 1.5, "leading pane after a state-change re-render");

    // 3. The position is Swift's, not the page's: a viewport change re-lays the split from the settled fraction.
    await page.setViewportSize({ width: 900, height: 900 });
    await page.waitForTimeout(400);
    const resized = await snapshot(page, master);
    const resizedTotal = extent(resized, 0) + extent(resized, 1);
    assert.ok(Math.abs(resizedTotal - total) > 50, "the split did not follow the viewport");
    near(extent(resized, 0), (extent(rerendered, 0) / total) * resizedTotal, 1.5, "leading pane keeps its fraction after a resize");
    await page.setViewportSize({ width: 1200, height: 900 });
    await page.waitForTimeout(300);

    // 4. The arrow keys move the focused divider: 2% of the split per press, 10% with Shift.
    const keyed = await snapshot(page, master);
    const keyedTotal = extent(keyed, 0) + extent(keyed, 1);
    await pressKeys(page, master, ["ArrowRight", "ArrowRight", "ArrowRight"]);
    const afterKeys = await snapshot(page, master);
    assert.ok(afterKeys.focused, "the divider does not take focus");
    near(extent(afterKeys, 0), extent(keyed, 0) + 3 * 0.02 * keyedTotal, 1.5, "leading pane after three ArrowRight");
    await pressKeys(page, master, ["Shift+ArrowLeft"]);
    const afterShift = await snapshot(page, master);
    near(extent(afterShift, 0), extent(afterKeys, 0) - 0.1 * keyedTotal, 1.5, "leading pane after Shift+ArrowLeft");

    // 5. A vertical split: a pointer drag and ArrowUp move its divider along the y axis.
    const editor = await locate(page, IDE_VERTICAL);
    const vertical = await snapshot(page, editor);
    const verticalTotal = extent(vertical, 0) + extent(vertical, 1);
    await drag(page, vertical, 0, 30);
    const verticalDragged = await snapshot(page, editor);
    near(extent(verticalDragged, 0), extent(vertical, 0) + 30, 1.5, "top pane after a 30 px vertical drag");
    near(extent(verticalDragged, 1), extent(vertical, 1) - 30, 1.5, "bottom pane after a 30 px vertical drag");
    await pressKeys(page, editor, ["ArrowUp", "ArrowUp"]);
    const verticalKeyed = await snapshot(page, editor);
    near(extent(verticalKeyed, 0), extent(verticalDragged, 0) - 2 * 0.02 * verticalTotal, 1.5, "top pane after two ArrowUp");

    // 6. The IDE horizontal split still moves (its second pane holds the vertical split).
    const ide = await locate(page, IDE_HORIZONTAL);
    const ideStart = await snapshot(page, ide);
    await drag(page, ideStart, -40, 0);
    const ideDragged = await snapshot(page, ide);
    near(extent(ideDragged, 0), extent(ideStart, 0) - 40, 1.5, "IDE navigator after a -40 px drag");

    // 7. The limits: the leading pane stays between its 120 px minimum and 240 px maximum for the pointer, Home and End.
    const limits = await locate(page, LIMITS);
    const bounded = await snapshot(page, limits);
    assert.equal(bounded.panes[0].min, "120", "leading pane minimum");
    assert.equal(bounded.panes[0].max, "240", "leading pane maximum");
    assert.equal(bounded.panes[1].max, null, "trailing pane has no maximum");
    await drag(page, bounded, -100, 0);
    near(extent(await snapshot(page, limits), 0), 120, 1, "leading pane dragged past its minimum");
    await drag(page, await snapshot(page, limits), 250, 0);
    near(extent(await snapshot(page, limits), 0), 240, 1, "leading pane dragged past its maximum");
    await pressKeys(page, limits, ["Home"]);
    near(extent(await snapshot(page, limits), 0), 120, 1, "Home stops at the minimum");
    await pressKeys(page, limits, ["End"]);
    near(extent(await snapshot(page, limits), 0), 240, 1, "End stops at the maximum");
    await pressKeys(page, limits, ["ArrowRight"]);
    near(extent(await snapshot(page, limits), 0), 240, 1, "ArrowRight stays at the maximum");

    assert.deepEqual(errors, [], "the page reported errors");
    console.log("PASS split views: pointer, keys, re-render, resize, vertical, limits");
  } finally {
    await browser?.close();
    await stop();
  }
});
