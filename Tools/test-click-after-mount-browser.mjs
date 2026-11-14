#!/usr/bin/env bun
// Input that arrives right after the page reports `data-embedded-mounted="true"` must never be lost.
//
// A click, a tap or a key press on a control that is on screen the moment the app reports it is mounted must reach
// its handler, in the Worker (the default) and on the main thread (`?render-in-worker=0`), on a machine that is busy: the test
// starts one busy loop per core, so the browser's and the Worker's threads are starved the way a loaded phone starves them.
// The marker comes with the first commit that shows the requested screen (the URL's route is rendered on the first frame),
// so the `/stackDepth` buttons exist the moment it appears; each input still waits for its target and is sent in the same
// breath, which keeps the test valid for a host that mounts earlier.
// The targets are the fixture's first buttons (`depth-20`, `-40`, `-60`), which are inside the viewport.
// Each round opens a fresh page and sends one input as soon as the mount marker appears; every one must change the
// displayed depth without a second attempt. A control button farther along the same horizontal strip is activated by
// a DOM `click`, which has no pointer geometry to get wrong.
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default). Bundle: CLICK_BUNDLE (.build/browser/ShowcaseApp).
// Rounds per input and mode: CLICK_ROUNDS (12).
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { cpus } from "node:os";
import { join, resolve } from "node:path";
import { engineName, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.CLICK_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
const PORT = Number(process.env.CLICK_PORT ?? "8114");
const ROUNDS = Number(process.env.CLICK_ROUNDS ?? "12");
const MOUNTED = 'html[data-embedded-mounted="true"]';
const DEPTH = `document.querySelector('[data-testid="depth-value"]')?.textContent?.trim()`;

async function pointer(page) {
  await page.locator('[data-testid="depth-20"]').click();
  return "depth 20";
}

async function tap(page) {
  await page.locator('[data-testid="depth-20"]').tap();
  return "depth 20";
}

async function enter(page) {
  await page.locator('[data-testid="depth-40"]').focus();
  await page.keyboard.press("Enter");
  return "depth 40";
}

async function space(page) {
  await page.locator('[data-testid="depth-60"]').focus();
  await page.keyboard.press("Space");
  return "depth 60";
}

async function farButton(page) {
  await page.locator('[data-testid="tabview-nested-300"]').dispatchEvent("click");
  return "depth 300";
}

// [name, send, touch]
const INPUTS = [
  ["pointer click", pointer, false],
  ["touch tap", tap, true],
  ["Enter key", enter, false],
  ["Space key", space, false],
  ["click on a far button", farButton, false],
];

await runSuite(async () => {
  const server = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "click-after-mount-server" });
  const base = server.base;
  // One busy loop per core, so the browser's and the Worker's threads are starved.
  const load = Array.from({ length: cpus().length || 4 }, () =>
    spawn(process.execPath, ["-e", "while (true) {}"], { stdio: "ignore" }),
  );
  const lost = [];
  let browser;
  try {
    browser = await launch();
    for (const [mode, query] of [
      ["Worker", ""],
      ["main thread", "?render-in-worker=0"],
    ]) {
      for (const [name, send, touch] of INPUTS) {
        const context = await browser.newContext({ hasTouch: touch });
        for (let round = 0; round < ROUNDS; round++) {
          const page = await context.newPage();
          const errors = [];
          page.on("pageerror", (error) => errors.push(String(error)));
          await page.goto(`${base}/stackDepth${query}`, { waitUntil: "domcontentloaded" });
          await page.waitForSelector(MOUNTED, { timeout: 60_000 });
          const expected = await send(page);
          try {
            await page.waitForFunction(`${DEPTH} === '${expected}'`, undefined, { timeout: 15_000 });
          } catch {
            lost.push(`${name} in the ${mode} (round ${round}): the page stayed at '${await page.evaluate(DEPTH)}'`);
          }
          assert.ok(errors.length === 0, `${name} in the ${mode}: ${JSON.stringify(errors.slice(0, 2))}`);
          await page.close();
        }
        await context.close();
      }
    }
  } finally {
    await browser?.close();
    for (const busy of load) busy.kill();
    await server.stop();
  }
  assert.ok(
    lost.length === 0,
    `${lost.length} inputs were lost in ${engineName()}: ${JSON.stringify(lost.slice(0, 5))}`,
  );
  console.log(
    `PASS ${engineName()} answered every input sent right after the mount ` +
      `(${ROUNDS} rounds x ${INPUTS.length} inputs x 2 modes, under load)`,
  );
});
