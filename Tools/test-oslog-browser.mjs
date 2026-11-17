#!/usr/bin/env bun
// OSLog's `Logger` in the browser (WebOSLog): the lowering app's "Write log lines" logs one line per level, and each
// must reach the console method of its level, tagged with the logger's subsystem and category. A debug build shows
// private values; a release build writes `<private>` for them, as OSLog does without a debugger attached (see
// Tests/SwiftUIWebTests/WebOSLogTests.swift). The nightly `release-browser-test` runs this on a release bundle, so the
// expected text follows the bundle: a release bundle is the one whose app.wasm has a hashed name.
//
// Bundle: `BUILD_ONLY=1 CONFIGURATION=debug|release Tools/run-browser.sh lowering`. Engine: SWIFTUIWEB_BROWSER_ENGINE.
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { engineName, launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

await runSuite(async () => {
  const bundle = resolve(process.argv[2] ?? ".build/browser/EmbeddedLoweringConformanceApp");
  const module = bundleFilePath(bundle, "app.wasm");
  if (!module) throw new Error(`lowering app bundle is missing: ${bundle}`);
  // The app logs (Tests/Apps/EmbeddedLoweringConformanceApp): `info` and `error` interpolate a String with the default
  // privacy (`.auto`: text is private), `notice` marks it `.public`, `warning` marks a number `.private`, `debug` a number
  // with the default (`.auto`: numbers are public). A release build hides what is private.
  const release = basename(module) !== "app.wasm";
  const hidden = (value) => (release ? "<private>" : value);
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
      ["info", `[conformance:oslog] info ${hidden("Ana")}`],
      ["log", "[conformance:oslog] notice Ana"],
      ["warning", `[conformance:oslog] warning ${hidden("3")}`],
      ["error", `[conformance:oslog] error ${hidden("Ana")}`],
      ["error", "[conformance:oslog] fault"],
    ]);
    console.log(`PASS ${engineName()} OSLog's Logger writes each level to its console method (${release ? "release: private values hidden" : "debug: private values shown"})`);
  } finally {
    await browser?.close();
    server.close?.();
  }
});
