#!/usr/bin/env bun
// Chromium test of Canvas sizing through the real Embedded Swift + CSS layout + JavaScript host bundle.
//
// Drives Tests/Apps/EmbeddedLoweringConformanceApp/EmbeddedCanvasFixture.swift, built by
// `BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh lowering`. A Canvas is greedy like SwiftUI's: a frame
// proposal sets its box, and the backing store follows the resolved box times devicePixelRatio.
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

const MEASURE = `(label) => {
  const canvas = [...document.querySelectorAll('canvas[data-draw-canvas]')]
    .find(c => (c.closest('div') && c.previousElementSibling && c.previousElementSibling.textContent === label));
  if (!canvas) return null;
  const rect = canvas.getBoundingClientRect();
  const ratio = window.devicePixelRatio || 1;
  const ctx = canvas.getContext('2d');
  const cx = Math.floor(canvas.width / 2), cy = Math.floor(canvas.height / 2);
  const pixel = canvas.width && canvas.height ? [...ctx.getImageData(cx, cy, 1, 1).data.slice(0, 4)] : null;
  return {
    box: [rect.width, rect.height],
    backing: [canvas.width, canvas.height],
    expectedBacking: [Math.max(1, Math.round(rect.width * ratio)), Math.max(1, Math.round(rect.height * ratio))],
    pixel,
  };
}`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    port: { type: "string", default: "0" },
    output: { type: "string", default: ".build/embedded-ui/canvas" },
  },
});

await runSuite(async () => {
  const bundle = resolve(positionals[0] ?? ".build/browser/EmbeddedLoweringConformanceApp");
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) {
    throw new Error(`Embedded canvas fixture bundle is missing: ${bundle}`);
  }
  const output = resolve(values.output);
  await mkdir(output, { recursive: true });
  const report = { status: "RUNNING", runtime: "Embedded Swift + BrowserIO", checks: [] };

  const server = await serveDirectory(bundle, Number(values.port));
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));

    const check = (name) => {
      if (errors.length) throw new Error("browser runtime errors: " + errors.join("; "));
      report.checks.push({ name, status: "PASS" });
    };

    const measure = async (label) => {
      assert.ok(await page.evaluate("window.__embeddedSession.settled()"), "the app did not settle");
      // A Worker answers the canvas's geometry report a round trip after the first layout.
      await page.waitForFunction(`!!((${MEASURE})(${JSON.stringify(label)}))`, undefined, { timeout: 5000 });
      return page.evaluate(`(${MEASURE})(${JSON.stringify(label)})`);
    };
    const sameList = (a, b) => a.length === b.length && a.every((value, i) => value === b[i]);

    await page.goto(`http://127.0.0.1:${server.port}/`, { waitUntil: "networkidle" });
    await page.getByRole("button", { name: "Open canvas fixture", exact: true }).click();
    await page.waitForFunction(
      "document.querySelectorAll('canvas[data-draw-canvas]').length === 4",
      undefined,
      { timeout: 5000 },
    );

    const framed = await measure("Framed height");
    report.framed_height = framed;
    if (Math.abs(framed.box[1] - 120) > 0.5) {
      throw new Error(`frame(height: 120) canvas measured ${JSON.stringify(framed.box)}, expected height 120: ${JSON.stringify(framed)}`);
    }
    if (framed.box[0] < 100) {
      throw new Error(`greedy canvas should take the offered width, measured ${JSON.stringify(framed.box)}: ${JSON.stringify(framed)}`);
    }
    check("frame(height: 120) gives the canvas its frame height");

    // A Canvas paints only what it draws: an opaque background would hide a canvas stacked beneath it.
    const canvasBackground = await page.evaluate(
      "getComputedStyle(document.querySelector('canvas[data-draw-canvas]')).backgroundColor",
    );
    assert.equal(canvasBackground, "rgba(0, 0, 0, 0)", "a canvas must have no background of its own");
    check("a canvas has no background of its own");

    const sized = await measure("Framed width and height");
    report.framed_width_height = sized;
    if (!sameList(sized.box.map((v) => Math.round(v)), [200, 80])) {
      throw new Error(`frame(width: 200, height: 80) canvas measured ${JSON.stringify(sized.box)}: ${JSON.stringify(sized)}`);
    }
    check("frame(width:height:) gives the canvas its frame size");

    const unframed = await measure("Unframed");
    report.unframed = unframed;
    if (unframed.box[0] <= 0 || unframed.box[1] <= 0) {
      throw new Error(`unframed canvas collapsed: ${JSON.stringify(unframed)}`);
    }
    check("unframed canvas is not collapsed");

    for (const [name, result] of [
      ["framed height", framed],
      ["framed width and height", sized],
      ["unframed", unframed],
    ]) {
      if (!sameList(result.backing, result.expectedBacking)) {
        throw new Error(`${name}: backing store ${JSON.stringify(result.backing)} != box x devicePixelRatio ${JSON.stringify(result.expectedBacking)}`);
      }
    }
    check("backing store equals resolved box times devicePixelRatio");

    // System colors, resolved for light mode (the fixture uses .red, .green and .blue).
    for (const [name, result, color] of [
      ["framed height", framed, [255, 56, 60]],
      ["framed width and height", sized, [52, 199, 89]],
      ["unframed", unframed, [0, 136, 255]],
    ]) {
      const pixel = result.pixel;
      if (pixel === null || pixel.slice(0, 3).some((a, i) => Math.abs(a - color[i]) > 20) || pixel[3] < 250) {
        throw new Error(`${name}: centre pixel ${JSON.stringify(pixel)} is not drawn ${JSON.stringify(color)}`);
      }
    }
    check("canvas paints its drawing into the resolved box");

    // Rectangle, Color and GeometryReader framed to a height are greedy in width like Canvas.
    for (const testId of ["canvas-fixture-rectangle", "canvas-fixture-color", "canvas-fixture-reader"]) {
      const box = await page.evaluate((id) => {
        const r = document.querySelector(`[data-testid="${id}"]`)?.getBoundingClientRect();
        return r ? [r.width, r.height] : null;
      }, testId);
      if (box === null || Math.abs(box[1] - 40) > 0.5 || box[0] < 900) {
        throw new Error(`${testId} framed to height 40 measured ${JSON.stringify(box)}`);
      }
    }
    check("framed Rectangle, Color and GeometryReader take the offered width and frame height");

    // Resizing the window must resize the greedy canvas and repaint its backing store.
    await page.setViewportSize({ width: 700, height: 900 });
    await page.waitForFunction(
      `(() => { const c = [...document.querySelectorAll('canvas[data-draw-canvas]')]
        .find(c => c.previousElementSibling && c.previousElementSibling.textContent === 'Framed height');
        return c && Math.abs(c.getBoundingClientRect().width - 700) < 2 && c.width === Math.round(c.getBoundingClientRect().width * (window.devicePixelRatio || 1)); })()`,
      undefined,
      { timeout: 5000 },
    );
    const resized = await measure("Framed height");
    report.resized_framed_height = resized;
    if (!sameList(resized.backing, resized.expectedBacking)) {
      throw new Error(`after resize backing store ${JSON.stringify(resized.backing)} != ${JSON.stringify(resized.expectedBacking)}`);
    }
    if (resized.pixel === null || resized.pixel[3] < 250) {
      throw new Error(`after resize canvas is not repainted: ${JSON.stringify(resized)}`);
    }
    check("canvas follows a window resize and repaints its backing store");

    // System colors resolve through light-dark(), so the drawing follows the color scheme. Dark system red is #FF4245.
    await page.emulateMedia({ colorScheme: "dark" });
    await page.waitForFunction(
      `(() => { const c = [...document.querySelectorAll('canvas[data-draw-canvas]')]
        .find(c => c.previousElementSibling && c.previousElementSibling.textContent === 'Framed height');
        if (!c) return false; const p = c.getContext('2d').getImageData(c.width >> 1, c.height >> 1, 1, 1).data;
        return Math.abs(p[0] - 255) <= 4 && Math.abs(p[1] - 66) <= 4 && Math.abs(p[2] - 69) <= 4; })()`,
      undefined,
      { timeout: 5000 },
    );
    const dark = await measure("Framed height");
    report.dark_framed_height = dark;
    if (Math.max(...dark.pixel.slice(0, 3).map((a, i) => Math.abs(a - [255, 66, 69][i]))) > 4) {
      throw new Error(`dark scheme did not repaint the canvas to #FF4245: ${JSON.stringify(dark)}`);
    }
    await page.emulateMedia({ colorScheme: "light" });
    await page.waitForFunction(
      `(() => { const c = [...document.querySelectorAll('canvas[data-draw-canvas]')]
        .find(c => c.previousElementSibling && c.previousElementSibling.textContent === 'Framed height');
        if (!c) return false; const p = c.getContext('2d').getImageData(c.width >> 1, c.height >> 1, 1, 1).data;
        return Math.abs(p[0] - 255) <= 4 && Math.abs(p[1] - 56) <= 4 && Math.abs(p[2] - 60) <= 4; })()`,
      undefined,
      { timeout: 5000 },
    ).catch(async (error) => { throw new Error(`light scheme did not repaint the canvas to #FF383C: ${JSON.stringify(await measure("Framed height"))} ${JSON.stringify(await page.evaluate(() => ({ attr: document.documentElement.getAttribute("data-color-scheme"), dark: matchMedia("(prefers-color-scheme: dark)").matches, style: document.documentElement.style.colorScheme })))} (${error.message})`); });
    check("canvas light-dark() colors repaint when the color scheme toggles");

    // A state update that switches a subtree's scheme repaints the canvases below it (and only them): dark system red there,
    // light system red on the canvas outside it.
    const pixelOf = (label) => page.evaluate((label) => {
      const c = [...document.querySelectorAll('canvas[data-draw-canvas]')].find(c => c.previousElementSibling && c.previousElementSibling.textContent === label);
      return c ? [...c.getContext('2d').getImageData(c.width >> 1, c.height >> 1, 1, 1).data.slice(0, 3)] : null;
    }, label);
    const near = (pixel, color) => pixel !== null && pixel.every((a, i) => Math.abs(a - color[i]) <= 4);
    await page.waitForFunction(`(() => { const c = [...document.querySelectorAll('canvas[data-draw-canvas]')].find(c => c.previousElementSibling && c.previousElementSibling.textContent === 'Subtree scheme'); if (!c) return false; const p = c.getContext('2d').getImageData(c.width >> 1, c.height >> 1, 1, 1).data; return Math.abs(p[0] - 255) <= 4 && Math.abs(p[1] - 56) <= 4; })()`, undefined, { timeout: 5000 });
    await page.getByRole("button", { name: "Toggle subtree scheme", exact: true }).click();
    await page.waitForFunction(`(() => { const c = [...document.querySelectorAll('canvas[data-draw-canvas]')].find(c => c.previousElementSibling && c.previousElementSibling.textContent === 'Subtree scheme'); if (!c) return false; const p = c.getContext('2d').getImageData(c.width >> 1, c.height >> 1, 1, 1).data; return Math.abs(p[0] - 255) <= 4 && Math.abs(p[1] - 66) <= 4; })()`, undefined, { timeout: 5000 })
      .catch(async () => { throw new Error(`a subtree switched to dark did not repaint its canvas to #FF4245: ${JSON.stringify(await pixelOf("Subtree scheme"))}`); });
    assert.ok(near(await pixelOf("Framed height"), [255, 56, 60]), "the canvas outside the subtree keeps the page's scheme");
    await page.getByRole("button", { name: "Toggle subtree scheme", exact: true }).click();
    await page.waitForFunction(`(() => { const c = [...document.querySelectorAll('canvas[data-draw-canvas]')].find(c => c.previousElementSibling && c.previousElementSibling.textContent === 'Subtree scheme'); if (!c) return false; const p = c.getContext('2d').getImageData(c.width >> 1, c.height >> 1, 1, 1).data; return Math.abs(p[0] - 255) <= 4 && Math.abs(p[1] - 56) <= 4; })()`, undefined, { timeout: 5000 });
    check("a canvas repaints when its subtree's color scheme switches");

    if (errors.length) throw new Error("browser runtime errors: " + errors.join("; "));
    report.status = "PASS";
  } finally {
    await browser?.close();
    await server.close();
    await writeFile(join(output, "result.json"), JSON.stringify(report, null, 2) + "\n");
  }
  console.log(JSON.stringify(report, null, 2));
});
