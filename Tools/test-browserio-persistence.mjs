#!/usr/bin/env bun
// BrowserIO persistence in a real browser: localStorage and IndexedDB must survive a page reload.
//
// Tools/BrowserIO/browser-smoke.html drives the host (browser-io.mjs) through its packet ABI. The first load writes a
// localStorage value and an IndexedDB record; the reload reads both back, then removes them. The fake IndexedDB in
// BrowserIO/test-host.mjs cannot show that the data really outlives the page, so this suite does.
// SWIFTUIWEB_BROWSER_ENGINE selects chromium (default), webkit or firefox.
import assert from "node:assert/strict";
import { join } from "node:path";
import { engineName, launch, ROOT, runSuite, serveStatic } from "./browser-test-support.mjs";

const RESULT = "document.documentElement.dataset.result";

async function settle(page) {
  await page.waitForFunction(`${RESULT} !== undefined || document.querySelector('#result').textContent.startsWith('First write')`, undefined, {
    timeout: 30_000,
  });
}

await runSuite(async () => {
  const server = serveStatic(join(ROOT, "Tools/BrowserIO"));
  let browser;
  try {
    browser = await launch();
    const page = await (await browser.newContext()).newPage();
    await page.goto(`${server.base}/browser-smoke.html`);
    await settle(page);
    assert.match(await page.textContent("#result"), /^First write committed/, "first load must write, not verify");

    await page.reload();
    await settle(page);
    const result = await page.evaluate(RESULT);
    assert.equal(result, "pass", await page.textContent("#result"));
    assert.match(await page.textContent("#result"), /^PASS/);

    // The second load removed its records, so a third load starts from nothing and writes again.
    await page.reload();
    await settle(page);
    assert.match(await page.textContent("#result"), /^First write committed/, "records were not cleaned up");
  } finally {
    await browser?.close();
    await server.stop();
  }
  console.log(`PASS BrowserIO persistence: localStorage and IndexedDB survive a reload and are cleaned up (${engineName()})`);
});
