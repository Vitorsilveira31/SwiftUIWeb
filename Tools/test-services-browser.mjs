#!/usr/bin/env bun
// Page services end to end: Swift (Examples/ServicesInterop, built for Embedded WebAssembly) calls the page's `echo`
// service, gets its answer and its failure, and observes its events, with Swift in a worker (the default) and on the
// main thread. Build the bundle first:
//   cd Examples/ServicesInterop && SWIFTUIWEB_PACKAGE_ROOT="$PWD" SWIFTUIWEB_PRODUCT=ServicesInteropApp \
//     SWIFTUIWEB_BUNDLE_ROOT="$PWD/.build/browser" BUILD_ONLY=1 ../../Tools/run-browser-embedded.sh ServicesInteropApp
// then: bun Tools/test-services-browser.mjs [bundle]. SWIFTUIWEB_BROWSER_ENGINE selects chromium (default), webkit or firefox.
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { engineName, launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

const bundle = resolve(process.argv[2] ?? "Examples/ServicesInterop/.build/browser/ServicesInteropApp");

await runSuite(async () => {
  if (!existsSync(join(bundle, "index.html"))) throw new Error(`ServicesInterop bundle is missing: ${bundle}`);
  const server = await serveDirectory(bundle, 0);
  let browser;
  const passed = [];
  try {
    browser = await launch();
    for (const [mode, query] of [["worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const page = await browser.newPage();
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(`http://127.0.0.1:${server.port}/${query}`, { waitUntil: "networkidle" });
      const shows = (text) => page.getByText(text, { exact: true }).first().waitFor({ timeout: 15_000 });
      await shows("greeting: Hello, Swift");
      await shows("failure: code -6");
      await page.getByRole("button", { name: "Start ticks", exact: true }).click();
      await shows("ticks: 1,2,3");
      if (errors.length) throw new Error(`${mode}: page errors: ${errors.join(" | ")}`);
      passed.push(mode);
      await page.close();
    }
  } finally {
    await browser?.close();
    server.close?.();
    server.stop?.();
  }
  console.log(`PASS page services (${engineName()}): call, failure and events, ${passed.join(" and ")}`);
});
