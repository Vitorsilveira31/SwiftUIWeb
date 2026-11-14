#!/usr/bin/env bun
// The rows of a lazy list show what a click changed in the publication that answers the click, not 20 to 35 ms later and not only after
// the list scrolls. The Board benchmark app (Tests/Apps/BoardBenchmarkApp): selecting a work highlights its row, marking a favorite
// turns the star of its row. When the count or the title the click also changes is on the page, the row must already show it, in the
// same task and one frame later; and a scroll that brings the window to another range keeps it.
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default). Bundle: LAZY_ROWS_BUNDLE (.build/browser/BoardBenchmarkApp).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.LAZY_ROWS_BUNDLE ?? join(ROOT, ".build/browser/BoardBenchmarkApp"));

/** Runs in the page: clicks, and when `done` holds reads the row twice, in the task the change landed in and one frame later. */
function clickAndRead({ click, done, row }) {
  return new Promise((resolve, reject) => {
    const holds = () => done.type === "text"
      ? document.querySelector(`[data-testid="${done.id}"]`)?.textContent.trim() === done.text
      : false;
    const read = () => {
      const element = document.querySelector(`[data-testid="${row}"]`);
      const holder = element.closest('[data-testid="row"]') ?? element;
      return { background: holder.getAttribute("data-background-style"), star: document.querySelector(`[data-testid="${click.replace("title-", "fav-")}"]`)?.textContent.trim() ?? null, text: element.textContent.trim() };
    };
    const observer = new MutationObserver(() => {
      if (!holds()) return;
      observer.disconnect();
      const sameTask = read();
      requestAnimationFrame(() => requestAnimationFrame(() => resolve({ sameTask, nextFrame: read() })));
    });
    observer.observe(document, { subtree: true, childList: true, characterData: true, attributes: true });
    setTimeout(() => { observer.disconnect(); reject(new Error("the change never reached the page")); }, 10000);
    document.querySelector(`[data-testid="${click}"]`).click();
  });
}

async function main() {
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: null, required: ["index.html"] });
  const browser = await launch();
  try {
    for (const mode of ["", "?render-in-worker=0"]) {
      const page = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();
      const problems = [];
      page.on("pageerror", (error) => problems.push(String(error)));
      await page.goto(`${server.base}/${mode}`);
      await page.waitForSelector('[data-testid="title-5"]');
      await page.waitForTimeout(800);
      const label = `${engineName()}${mode ? " main thread" : " worker"}`;

      // A selection: the row is highlighted when the detail shows its title.
      const title = await page.evaluate(() => document.querySelector('[data-testid="title-5"]').textContent.trim());
      const selected = await page.evaluate(clickAndRead, { click: "title-5", done: { type: "text", id: "detail-title", text: title }, row: "title-5" });
      assert.notEqual(selected.nextFrame.background, "transparent", `${label}: the selected row is highlighted one frame after the detail shows`);
      assert.notEqual(selected.sameTask.background, "transparent", `${label}: the selected row is highlighted in the task that shows the detail`);

      // Selecting another: the first row loses it.
      const other = await page.evaluate(() => document.querySelector('[data-testid="title-6"]').textContent.trim());
      const moved = await page.evaluate(clickAndRead, { click: "title-6", done: { type: "text", id: "detail-title", text: other }, row: "title-6" });
      assert.notEqual(moved.nextFrame.background, "transparent", `${label}: the newly selected row is highlighted`);
      const first = await page.evaluate(() => document.querySelector('[data-testid="title-5"]').closest('[data-testid="row"]').getAttribute("data-background-style"));
      assert.equal(first, "transparent", `${label}: the row that was selected is plain again`);

      // Favorites, twice (the second used to wait for a second pass): the star turns when the count changes.
      for (const [count, id] of [[1, 10], [2, 20]]) {
        const starred = await page.evaluate(clickAndRead, { click: `fav-${id}`, done: { type: "text", id: "fav-count", text: `${count} favorites` }, row: `fav-${id}` });
        if (process.env.LAZY_ROWS_DEBUG) console.log(label, id, JSON.stringify(starred));
        assert.equal(starred.sameTask.text, "★", `${label}: the star of work ${id} turned in the task that shows the count`);
        assert.equal(starred.nextFrame.text, "★", `${label}: and a frame later`);
      }

      // The scroll brings other rows in and keeps what the click changed.
      await page.mouse.move(400, 400);
      await page.mouse.wheel(0, 150);
      await page.waitForTimeout(700);
      const after = await page.evaluate(() => ({
        selected: document.querySelector('[data-testid="title-6"]')?.closest('[data-testid="row"]')?.getAttribute("data-background-style"),
        star: document.querySelector('[data-testid="fav-10"]')?.textContent.trim(),
        plain: document.querySelector('[data-testid="title-5"]')?.closest('[data-testid="row"]')?.getAttribute("data-background-style"),
      }));
      assert.notEqual(after.selected, "transparent", `${label}: the selection survives a scroll`);
      assert.equal(after.star, "★", `${label}: the star survives a scroll`);
      assert.equal(after.plain, "transparent", `${label}: a row that was not selected stays plain after the scroll`);
      assert.deepEqual(problems, [], `${label}: no page errors`);
      console.log(`PASS ${label}: a selection and a favorite show in the publication that answers the click, and after a scroll`);
    }
  } finally {
    await browser.close();
    await server.stop();
  }
}

await runSuite(main);
