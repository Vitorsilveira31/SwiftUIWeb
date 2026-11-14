#!/usr/bin/env bun
// State kept across a reload of the development loop, in a real browser (Tests/Apps/MotionApp, a debug build with the
// development exports): the page saves its states before the reload the watcher asks for, and the module that replaces it
// starts from them. A reload nobody asked the page to prepare starts from the initial values. On the main thread and in
// the worker.
// The bundle: the first argument (built by `make state-reload-browser-test`). Engine: SWIFTUIWEB_BROWSER_ENGINE.
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { CLIENT_SCRIPT } from "./live-reload.mjs";

const BUNDLE = resolve(process.argv[2] ?? join(ROOT, ".build/state-reload/embedded/MotionApp"));
const KEY = "swui:14:swiftuiweb.dev:state";

await runSuite(async () => {
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort() });
  const browser = await launch();
  try {
    for (const query of ["?render-in-worker=0", ""]) {
      const where = query ? "main thread" : "worker";
      const page = await (await browser.newContext({ viewport: { width: 800, height: 900 } })).newPage();
      const problems = [];
      page.on("pageerror", (error) => problems.push(String(error)));
      page.on("console", (message) => { if (message.type() === "error") problems.push(message.text()); });
      const open = async () => { await page.waitForSelector('[data-testid="row-1"]'); };
      const rows = () => page.evaluate(() => [...document.querySelectorAll('[data-testid^="row-"]')].map((row) => row.getAttribute("data-testid")));
      await page.goto(`${server.base}/${query}`);
      await open();
      const initial = await rows();

      // State the next page must start from: three more rows, the newest first.
      for (let i = 0; i < 3; i++) await page.click('[data-testid="add"]');
      await page.waitForFunction((count) => document.querySelectorAll('[data-testid^="row-"]').length === count, initial.length + 3);
      const before = await rows();
      assert.notDeepEqual(before, initial);

      // What the page script does on the watcher's "reload": ask the module to save, wait for the key, reload.
      assert.equal(await page.evaluate(() => globalThis.__swiftuiwebSaveState()), true, `${where}: a debug module saves its state`);
      await page.waitForFunction((key) => sessionStorage.getItem(key) !== null, KEY);
      const saved = await page.evaluate((key) => sessionStorage.getItem(key), KEY);
      assert.match(saved, /\t\[i\t/, `${where}: the rows are a state of integers`);
      await page.reload();
      await open();
      assert.deepEqual(await rows(), before, `${where}: the page is back with the rows it had`);
      // The state is live, not a picture: the next row continues the count.
      await page.click('[data-testid="add"]');
      await page.waitForFunction((count) => document.querySelectorAll('[data-testid^="row-"]').length === count, before.length + 1);
      assert.equal((await rows()).length, before.length + 1, where);

      // The saved values were taken: a reload the page did not prepare starts over.
      await page.waitForFunction((key) => sessionStorage.getItem(key) === null, KEY);
      await page.reload();
      await open();
      assert.deepEqual(await rows(), initial, `${where}: an ordinary reload starts from the initial values`);
      assert.deepEqual(problems, [], where);
      await page.close();
    }

    // The page script itself: its reload handler saves before it reloads (a page with a stand-in event source).
    {
      const page = await (await browser.newContext({ viewport: { width: 800, height: 900 } })).newPage();
      await page.addInitScript(() => {
        window.__sources = [];
        window.EventSource = class { constructor() { this.handlers = {}; window.__sources.push(this); } addEventListener(type, handler) { this.handlers[type] = handler; } close() {} };
      });
      await page.goto(`${server.base}/`);
      await page.waitForSelector('[data-testid="row-1"]');
      await page.evaluate(CLIENT_SCRIPT);
      const initial = await page.evaluate(() => document.querySelectorAll('[data-testid^="row-"]').length);
      await page.click('[data-testid="add"]');
      await page.waitForFunction((count) => document.querySelectorAll('[data-testid^="row-"]').length === count, initial + 1);
      await Promise.all([page.waitForEvent("load"), page.evaluate(() => { window.__sources.at(-1).handlers.reload(); })]);
      await page.waitForSelector('[data-testid="row-1"]');
      assert.equal(await page.evaluate(() => document.querySelectorAll('[data-testid^="row-"]').length), initial + 1, "the watcher's reload keeps the state");
      await page.close();
    }
  } finally {
    await browser.close();
    await server.stop();
  }
  console.log(`PASS ${engineName()}: a reload of the development loop keeps the page's state, and an ordinary reload starts over`);
});
