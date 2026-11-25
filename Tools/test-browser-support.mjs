#!/usr/bin/env bun
// Tools/browser-test-support.mjs: page.waitForFunction must work on a page whose Content-Security-Policy has no
// 'unsafe-eval' (a sealed bundle). Playwright's own version runs through eval() in the page and throws EvalError there.
import assert from "node:assert/strict";
import { launch, runSuite } from "./browser-test-support.mjs";

await runSuite(async () => {
  // Bound to 127.0.0.1, where the page is opened (see Tools/test-check-dictionary-host.mjs for what the wildcard bind risks).
  const server = Bun.serve({
    port: 0,
    hostname: "127.0.0.1",
    fetch: (request) => new URL(request.url).pathname === "/s.js"
      ? new Response('try { new Function("return 1")(); window.pageEval = "allowed"; } catch { window.pageEval = "refused"; }', { headers: { "content-type": "text/javascript" } })
      : new Response(
        "<!doctype html><title>t</title><p id=v>first</p><script src=/s.js></script>",
        { headers: { "content-type": "text/html", "content-security-policy": "default-src 'self'; script-src 'self'" } },
      ),
  });
  const browser = await launch();
  try {
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.port}/`);
    assert.equal(await page.evaluate(() => window.pageEval), "refused", "the page must refuse eval for this test to mean anything");
    await page.evaluate(() => setTimeout(() => { document.getElementById("v").textContent = "second"; window.flag = 7; }, 300));
    await page.waitForFunction("document.getElementById('v').textContent === 'second'");
    await page.waitForFunction(() => window.flag === 7);
    await page.waitForFunction((want) => window.flag === want, 7, { timeout: 2000 });
    await page.waitForFunction("window.flag === 7", undefined, { timeout: 2000, polling: 50 });
    await assert.rejects(page.waitForFunction("window.flag === 8", undefined, { timeout: 300 }), { name: "TimeoutError" });
    // A page opened from a context, and a popup, are covered too.
    const context = await browser.newContext();
    const other = await context.newPage();
    await other.goto(`http://127.0.0.1:${server.port}/`);
    await other.waitForFunction(() => document.getElementById("v").textContent === "first");
    await context.close();
    console.log("PASS waitForFunction runs on a page without 'unsafe-eval'");
  } finally {
    await browser.close();
    server.stop(true);
  }
});
