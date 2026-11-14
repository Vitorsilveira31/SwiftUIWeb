#!/usr/bin/env bun
// A view in a cell of a lazy grid keeps state of its own, and a change of that state redraws it as it does in a plain stack
// (Tests/Apps/LazyCellStateApp). Three kinds of cell are pressed in a `LazyVGrid` and in a `VStack`, which is the control: a view
// that holds its state, a generic card that stores the content it was built with, and a state that changes inside `withAnimation`.
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default). Bundle: LAZY_CELL_STATE_BUNDLE (.build/browser/LazyCellStateApp).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.LAZY_CELL_STATE_BUNDLE ?? join(ROOT, ".build/browser/LazyCellStateApp"));

async function main() {
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: null, required: ["index.html"] });
  const browser = await launch();
  try {
    for (const mode of ["", "?render-in-worker=0"]) {
      const context = await browser.newContext({ viewport: { width: 800, height: 900 } });
      const page = await context.newPage();
      const problems = [];
      page.on("pageerror", (error) => problems.push(String(error)));
      page.on("console", (message) => { if (message.type() === "error") problems.push(message.text()); });
      await page.goto(`${server.base}/${mode}`);
      // The app selects the tab with the cells by itself, right after it starts (the cells were drawn while it was hidden).
      await page.waitForSelector('[data-testid="plain-own-add"]', { state: "visible", timeout: 60_000 });
      const read = (id) => page.evaluate((testid) => document.querySelector(`[data-testid="${testid}"]`)?.textContent.trim() ?? null, id);
      const press = async (id) => { await page.locator(`[data-testid="${id}"]`).click(); };
      const settledText = async (id, expected, what) => {
        const deadline = Date.now() + 3000;
        while (Date.now() < deadline) {
          if ((await read(id)) === expected) return;
          await page.waitForTimeout(50);
        }
        assert.equal(await read(id), expected, `${what} (${mode || "worker"})`);
      };
      // While the digits roll the node holds both the old and the new ones; once they settle it holds the number.
      const settledNumber = (id, expected, what) => settledText(id, expected, what);
      for (const where of ["plain", "lazy"]) {
        // A view that holds its own state: a counter and a flag.
        await press(`${where}-own-add`);
        await settledText(`${where}-own-count`, "count 1", `${where}: the counter did not redraw`);
        await press(`${where}-own-add`);
        await settledText(`${where}-own-count`, "count 2", `${where}: the counter did not redraw a second time`);
        await press(`${where}-own-flip`);
        await settledText(`${where}-own-flag`, "on", `${where}: the flag did not redraw`);
        // A generic card that stores the content it was built with.
        await press(`${where}-card-add`);
        await settledText(`${where}-card-count`, "count 1", `${where}: the stored content did not redraw`);
        // State that changes inside withAnimation, with an animation scoped to the value.
        await press(`${where}-animated-add`);
        await settledText(`${where}-animated-count`, "count 1", `${where}: the animated state did not redraw`);
        // The shape that failed on the project site: a content transition with a spring, and buttons styled by their stack.
        await press(`${where}-numeric-add`);
        await settledNumber(`${where}-numeric-count`, "228", `${where}: the number did not roll to its new value`);
        await press(`${where}-symbol-listen`);
        await settledText(`${where}-symbol-listen`, "Stop", `${where}: the Listen button did not become Stop`);
        // A card whose content a switch in a view builder chose.
        await press(`${where}-pa-add`);
        await settledNumber(`${where}-pa-count`, "228", `${where}: the number in a switched card did not roll`);
        await press(`${where}-pb-add`);
        await settledText(`${where}-pb-count`, "count 1", `${where}: the counter in a switched card did not redraw`);
        await press(`${where}-symbol-star`);
        await settledText(`${where}-symbol-starred`, "starred", `${where}: the star did not swap`);
      }
      // A cell that is the root of a row of a keyed ForEach, in four shapes. The page changes tab by itself when it starts, which
      // renders the view above the grid again: the rows it holds must still be answered by their own owners afterwards. Every shape is
      // pressed, and the ones that did not redraw are named together.
      const failed = [];
      const tryText = async (id, expected, name) => { try { await settledText(id, expected, name); } catch { failed.push(name); } };
      await press("v1-a-add"); await tryText("v1-a-count", "count 1", "v1: keyed ForEach, a cell directly");
      await press("v1n-a-add"); await tryText("v1n-a-count", "228", "v1n: keyed ForEach, a numeric cell directly");
      await press("v2-a-add"); await tryText("v2-a-count", "count 1", "v2: keyed ForEach, a card with its content");
      await press("v3-a-pa-add"); await tryText("v3-a-pa-count", "228", "v3: keyed ForEach, a switch (numeric)");
      await press("v3-b-pb-add"); await tryText("v3-b-pb-count", "count 1", "v3: keyed ForEach, a switch (plain counter)");
      assert.deepEqual(failed, [], `cells that did not redraw (${mode || "worker"})`);
      // Rows of a keyed ForEach in a lazy grid, each a card that stores the content a switch built.
      for (const key of ["a", "b", "c"]) {
        const kind = key === "b" ? "pb" : "pa";
        if (kind === "pa") {
          await press(`keyed-${key}-pa-add`);
          await settledNumber(`keyed-${key}-pa-count`, "228", `keyed ${key}: the number did not roll`);
        } else {
          await press(`keyed-${key}-pb-add`);
          await settledText(`keyed-${key}-pb-count`, "count 1", `keyed ${key}: the counter did not redraw`);
        }
      }
      assert.deepEqual(problems, [], `page errors (${mode || "worker"})`);
      await context.close();
    }
    console.log(`PASS ${engineName()}: a view in a lazy grid redraws on a change of its own state, as in a plain stack`);
  } finally {
    await browser.close();
    await server.stop();
  }
}

await runSuite(main);
