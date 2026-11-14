#!/usr/bin/env bun
// A player without a view does not stop the page's buttons from working.
//
// Drives Tests/Apps/EmbeddedLoweringConformanceApp: each cycle opens the network/media fixture (it creates an AVPlayer in a
// @State initializer and shows a VideoPlayer), returns to the main page (the player stays registered as a headless player),
// and then clicks the sibling buttons of the main page. Every click must show its new count within LATENCY_MS.
//
// Before the fix, the player's own render-revision bump subscribed the render that created it, so each publication created a
// new player and published again: the page was busy for seconds after the return, and clicks showed late or not at all.
//
// Each cycle runs on Chromium and WebKit, with the Worker (the default) and on the main thread (`?render-in-worker=0`). Bundle:
// EMBEDDED_LOWERING_BUNDLE (.build/browser/EmbeddedLoweringConformanceApp). Engines: HEADLESS_PLAYER_ENGINES (chromium,webkit).
import { existsSync } from "node:fs";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

// HEADLESS_PLAYER_LATENCY_MS raises the budget on a slow shared runner. Before the fix a click answered after seconds or never.
const LATENCY_MS = Number(process.env.HEADLESS_PLAYER_LATENCY_MS ?? "1000");
// After a miss the check waits this much longer, so the failure says whether the page was slow or stopped answering.
const LATE_MS = 10_000;
const CYCLES = 4;
const CLICKS = 5;
const MODES = [
  ["worker", ""],
  ["main-thread", "?render-in-worker=0"],
];

async function clickAndExpect(page, button, label, count) {
  // The page must answer within LATENCY_MS.
  await page.getByRole("button", { name: button, exact: true }).click();
  const clicked = Date.now();
  const expected = page.getByText(`${label}: ${count}`, { exact: true });
  try {
    await expected.waitFor({ timeout: LATENCY_MS });
  } catch (error) {
    const shown = await page.getByText(`${label}:`).allInnerTexts();
    const late = await expected.waitFor({ timeout: LATE_MS }).then(() => `it showed after ${Date.now() - clicked} ms`, () => `nor within ${LATE_MS} ms more`);
    throw new Error(`'${button}' did not show ${label}: ${count} within ${LATENCY_MS} ms, ${late} (page showed ${JSON.stringify(shown)})`, {
      cause: error,
    });
  }
}

async function run(engine, mode, query, base, checks) {
  process.env.SWIFTUIWEB_BROWSER_ENGINE = engine;
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1000, height: 800 } });
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    page.on("console", (message) => {
      if (message.type() === "error" && !message.text().includes("Failed to load resource")) errors.push(message.text());
    });
    await page.goto(base + "/" + query, { waitUntil: "networkidle" });
    let observed = 0;
    // InitAssignedViewModel starts at 4 (EmbeddedLoweringConformanceApp/main.swift).
    let initAssigned = 4;
    for (let cycle = 0; cycle < CYCLES; cycle++) {
      console.log(`${engine}/${mode} cycle ${cycle + 1}: opening the fixture`);
      await page.getByRole("button", { name: "Open network media fixture", exact: true }).click();
      await page.getByText("Network: fixture", { exact: true }).waitFor({ timeout: 10_000 });
      await page.getByRole("button", { name: "Return to conformance app", exact: true }).click();
      await page.getByRole("button", { name: "Update observer", exact: true }).waitFor({ timeout: 10_000 });
      for (let click = 0; click < CLICKS; click++) {
        observed += 1;
        await clickAndExpect(page, "Update observer", "Observed", observed);
      }
      for (let click = 0; click < CLICKS; click++) {
        initAssigned += 1;
        await clickAndExpect(page, "Update init-assigned", "Init-assigned", initAssigned);
      }
      checks.push(`${engine}/${mode} cycle ${cycle + 1}: ${CLICKS} + ${CLICKS} sibling clicks answer within ${LATENCY_MS} ms`);
    }
    if (errors.length) throw new Error(`${engine}/${mode} browser errors: ` + errors.join("; "));
  } finally {
    await browser.close();
  }
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    port: { type: "string", default: "0" }, // HTTP port (0 selects a free port)
  },
});

await runSuite(async () => {
  const bundle = resolve(positionals[0] ?? process.env.EMBEDDED_LOWERING_BUNDLE ?? ".build/browser/EmbeddedLoweringConformanceApp");
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) {
    throw new Error(`Embedded lowering bundle is missing: ${bundle}`);
  }
  const engines = (process.env.HEADLESS_PLAYER_ENGINES ?? "chromium,webkit").split(",").filter(Boolean);
  const server = await serveDirectory(bundle, Number(values.port));
  const base = server.base;
  const checks = [];
  try {
    for (const engine of engines) {
      for (const [mode, query] of MODES) {
        await run(engine, mode, query, base, checks);
      }
    }
  } finally {
    await server.close();
  }
  for (const name of checks) console.log(`PASS ${name}`);
  console.log(`headless-player siblings browser test: ${checks.length} runs passed`);
});
