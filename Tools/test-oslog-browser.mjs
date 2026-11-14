#!/usr/bin/env bun
// OSLog's `Logger` in the browser (WebOSLog): the lowering app's "Write log lines" logs one line per level, and each
// must reach the console method of its level, tagged with the logger's subsystem and category. The bundle is a debug
// build, which shows private values (a release build writes `<private>`, see Tests/SwiftUIWebTests/WebOSLogTests.swift).
//
// Bundle: `BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh lowering`. Engine: SWIFTUIWEB_BROWSER_ENGINE.
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { engineName, launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

await runSuite(async () => {
  const bundle = resolve(process.argv[2] ?? ".build/browser/EmbeddedLoweringConformanceApp");
  if (!bundleFilePath(bundle, "app.wasm")) throw new Error(`lowering app bundle is missing: ${bundle}`);
  const server = await serveDirectory(bundle, 0);
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage();
    const lines = [];
    page.on("console", (message) => { if (message.text().startsWith("[conformance:oslog]")) lines.push([message.type(), message.text()]); });
    await page.goto(`http://127.0.0.1:${server.port}/`, { waitUntil: "networkidle" });
    await page.getByRole("button", { name: "Write log lines", exact: true }).click();
    for (let attempt = 0; attempt < 50 && lines.length < 6; attempt++) await page.waitForTimeout(100);
    assert.deepEqual(lines, [
      ["debug", "[conformance:oslog] debug 3"],
      ["info", "[conformance:oslog] info Ana"],
      ["log", "[conformance:oslog] notice Ana"],
      ["warning", "[conformance:oslog] warning 3"],
      ["error", "[conformance:oslog] error Ana"],
      ["error", "[conformance:oslog] fault"],
    ]);
    console.log(`PASS ${engineName()} OSLog's Logger writes each level to its console method`);
  } finally {
    await browser?.close();
    server.close?.();
  }
});
