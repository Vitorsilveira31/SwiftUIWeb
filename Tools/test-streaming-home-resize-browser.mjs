#!/usr/bin/env bun
// A window resize on a streaming app's home screen stays cheap in work, not just in time. Fixture: the "Streaming" tab of
// Tests/Apps/LazyCellStateApp (StreamingHomeFixture.swift): a hero of three slides (a poster over a blurred, scaled copy of itself,
// a second poster with a shadow and a rotation, a gradient, a rounded clip, a height that follows the width), six rails of twelve
// poster tiles, each with a `Canvas` placeholder (16 by 16 colored rectangles, 256 fills) under a blur and under the poster's image,
// and a navigation bar over a material. Every box follows the window's width, so a resize changes the size of every canvas.
//
// What is counted (a count, not a time, so a slow or busy machine does not decide it):
//   - the bytes of drawing commands the page is sent for each fill of a canvas (`data-canvas-commands`): they are what Swift writes, the
//     publication hashes and sends, and the page parses, so the size of a canvas of 256 fills is paid by every canvas at every step
//     of every resize (44 canvases are on screen here);
//   - the Path2D objects the page builds while it paints those canvases: a rectangle is filled as one, with none (a Path2D is parsed from
//     text and allocated for each of the 256 cells of each drawing);
//   - the drawing closures that ran (the fixture counts them and shows the number, `streaming-draws`): a canvas is drawn at most twice
//     for each size the window gives it (the render of the page at the size it knew, the report of the new size), and does not pile up;
//   - after the resize settles (the host's mark of it cleared, two frames later), every canvas on screen is drawn for its own box
//     (`data-canvas-size` is the box's size): a canvas whose last report did not reach a redraw stays drawn for an earlier step.
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default). Bundle: LAZY_CELL_STATE_BUNDLE (.build/browser/LazyCellStateApp).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.LAZY_CELL_STATE_BUNDLE ?? join(ROOT, ".build/browser/LazyCellStateApp"));
const FROM = 1400, STEP = 20, STEPS = 20;
// A fill of a colored rectangle is sent as about 80 bytes (it was about 130 with the rectangle written out as a polygon).
const MAX_COMMAND_BYTES_PER_FILL = 100;

/** In the page, before it loads: counts what painting a canvas allocates and calls (a Path2D built for each path, a fill of a rectangle
 * or of a path). */
const countPaintWork = () => {
  const work = (window.__paintWork = { path2d: 0, rect: 0, fill: 0 });
  const Native = window.Path2D;
  window.Path2D = class extends Native { constructor(...args) { super(...args); work.path2d++; } };
  const proto = CanvasRenderingContext2D.prototype, closePath = proto.closePath, fill = proto.fill;
  proto.closePath = function (...args) { work.rect++; return closePath.apply(this, args); };
  proto.fill = function (...args) { work.fill++; return fill.apply(this, args); };
};

/** In the page: the canvases that are on screen, with the bytes of their drawing and how they are drawn against their box. */
const readCanvases = () => {
  const out = [];
  for (const canvas of document.querySelectorAll("canvas[data-draw-canvas]")) {
    const placed = canvas.getBoundingClientRect();
    if (placed.width <= 0 || placed.height <= 0 || placed.right <= 0 || placed.left >= innerWidth) continue;
    // The layout box, not the placed one: the hero's blurred copy is scaled up by an effect that does not change its layout.
    const style = getComputedStyle(canvas), box = { width: parseFloat(style.width), height: parseFloat(style.height) };
    const [drawnWidth, drawnHeight] = (canvas.getAttribute("data-canvas-size") ?? "0,0").split(",").map(Number);
    out.push({
      fills: Number(canvas.getAttribute("data-canvas-command-count") ?? 0),
      bytes: (canvas.getAttribute("data-canvas-commands") ?? "").length,
      boxWidth: box.width, boxHeight: box.height, drawnWidth, drawnHeight,
    });
  }
  return out;
};

async function main() {
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: null, required: ["index.html"] });
  try {
    const browser = await launch();
    try {
      for (const mode of ["", "?render-in-worker=0"]) {
        const label = `${engineName()}${mode ? " main thread" : " worker"}`;
        // The tab is laid out and its canvases drawn: dozens of them are on screen (a slower engine takes longer).
        const open = async (context) => {
          const page = await context.newPage();
          await page.goto(`${server.base}/${mode}`);
          await page.waitForSelector('[data-testid="plain-own-add"]', { state: "visible", timeout: 60_000 });
          await page.getByRole("tab", { name: "Streaming", exact: true }).click();
          await page.waitForFunction(() => [...document.querySelectorAll("canvas[data-draw-canvas]")].filter((canvas) => { const box = canvas.getBoundingClientRect(); return box.width > 0 && box.left < innerWidth && box.right > 0; }).length >= 30, undefined, { timeout: 60_000 });
          await page.waitForTimeout(1500);
          return page;
        };
        // The resize steps, then the settle: the host's mark of the resize is gone and two frames have passed (Swift answers the
        // last report in the second; the wait that follows is for a busy machine, and a canvas that was left stale stays so).
        const resizeAndSettle = async (page) => {
          for (let step = 1; step <= STEPS; step++) {
            await page.setViewportSize({ width: FROM - STEP * step, height: 800 });
            await page.waitForTimeout(80);
          }
          await page.waitForFunction(() => !document.documentElement.hasAttribute("data-layout-resizing"), undefined, { timeout: 10_000 });
          await page.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))));
          await page.waitForTimeout(500);
        };
        const assertDrawnForTheirBoxes = (canvases, what) => {
          const stale = canvases.filter((canvas) => Math.abs(canvas.drawnWidth - canvas.boxWidth) > 0.5 || Math.abs(canvas.drawnHeight - canvas.boxHeight) > 0.5);
          assert.equal(stale.length, 0, `${label}: ${what}: ${stale.length} of ${canvases.length} canvases are drawn for another size than their box, e.g. ${stale[0]?.drawnWidth}x${stale[0]?.drawnHeight} in ${stale[0]?.boxWidth}x${stale[0]?.boxHeight}`);
        };

        // At rest every canvas is drawn for the box it is in. A report of a canvas's last size reached Swift and invalidated it, but the
        // views that remember their render gave the old drawing back: in a Worker about one resize in two left every tile drawn for
        // the size of the step before. It depends on timing, so several fresh pages resize (a page that has only resized, with nothing
        // pressed before it, as a person's would).
        for (let run = 1; run <= (mode ? 2 : 6); run++) {
          const fresh = await browser.newContext({ viewport: { width: FROM, height: 800 }, deviceScaleFactor: 1 });
          const freshPage = await open(fresh);
          await resizeAndSettle(freshPage);
          assertDrawnForTheirBoxes(await freshPage.evaluate(readCanvases), `resize ${run}`);
          await fresh.close();
        }

        const context = await browser.newContext({ viewport: { width: FROM, height: 800 }, deviceScaleFactor: 1 });
        const problems = [];
        await context.addInitScript(countPaintWork);
        const page = await open(context);
        page.on("pageerror", (error) => problems.push(String(error)));

        // The fixture shows how many drawings it ran as of its last render; a press of a slide button renders it again.
        let slide = 0;
        const draws = async () => {
          slide = 1 - slide;
          await page.locator(`[data-testid="streaming-slide-${slide}"]`).first().click();
          await page.waitForTimeout(700);
          return Number((await page.locator('[data-testid="streaming-draws"]').first().textContent()).replace(/\D/g, ""));
        };

        const before = await page.evaluate(readCanvases);
        assert.ok(before.length >= 30, `${label}: ${before.length} canvases on screen, the fixture should show dozens`);
        assert.equal(Math.max(...before.map((canvas) => canvas.fills)), 256, `${label}: a placeholder should draw 16 by 16 rectangles`);
        for (const canvas of before) {
          assert.ok(canvas.bytes <= canvas.fills * MAX_COMMAND_BYTES_PER_FILL + 200,
            `${label}: a canvas of ${canvas.fills} fills is sent ${canvas.bytes} bytes of commands (${(canvas.bytes / canvas.fills).toFixed(0)} a fill, at most ${MAX_COMMAND_BYTES_PER_FILL})`);
        }

        const drawsBefore = await draws();
        await page.evaluate(() => Object.assign(window.__paintWork, { path2d: 0, rect: 0, fill: 0 }));
        await resizeAndSettle(page);
        const after = await page.evaluate(readCanvases);
        const drawsAfter = await draws();
        const work = await page.evaluate(() => ({ ...window.__paintWork }));
        const perCanvasPerStep = (drawsAfter - drawsBefore) / STEPS / after.length;
        console.log(`[${label}] ${after.length} canvases, ${STEPS} resize steps: ${drawsAfter - drawsBefore} drawings (${perCanvasPerStep.toFixed(2)} for each canvas at each step), `
          + `${work.rect} rectangles closed, ${work.fill} path fills, ${work.path2d} Path2D built, `
          + `${before[0].bytes && Math.round(Math.max(...before.map((canvas) => canvas.bytes)) / 256)} bytes of commands for each fill`);
        assert.ok(drawsAfter > drawsBefore, `${label}: no canvas was drawn again while the window changed size, so the test counts nothing`);
        // Each canvas is drawn for the size a step gives it, at most twice (about 1 to 1.7 measured, by engine and load); a drawing for each
        // report of every size it passes through, or one for every commit, would be several times that.
        assert.ok(perCanvasPerStep <= 2.2, `${label}: ${perCanvasPerStep.toFixed(2)} drawings of each canvas at each resize step, at most two are expected`);
        // A canvas of colored cells fills rectangles: each is one call, with no Path2D built for it.
        assert.ok(work.rect >= 256 * (drawsAfter - drawsBefore) * 0.5, `${label}: ${work.rect} rectangles closed for ${drawsAfter - drawsBefore} drawings of 256 cells`);
        assert.ok(work.path2d <= work.fill * 0.05, `${label}: ${work.path2d} Path2D built to paint ${work.fill} fills: a rectangle needs none`);
        assertDrawnForTheirBoxes(after, "the counted resize");
        assert.deepEqual(problems, [], `${label}: page errors`);
        await context.close();
      }
      console.log("streaming home resize: the canvases are sent and painted as rectangles, and drawn at most twice for each size, and every one ends drawn for its box");
    } finally {
      await browser.close();
    }
  } finally {
    await server.stop();
  }
}

await runSuite(main);
