#!/usr/bin/env bun
// A Worker whose call stack the app overflows must not lose the app's state (section 12.11), and must not leave the page blank.
//
// Staged rendering keeps a Worker's stack from bounding the depth of the view trees the framework renders, so this is a
// safety net for what staging cannot reach: application code that recurses by itself. The fixture's `recurse-12000` is a view
// whose body runs a non-tail recursion 12000 calls deep (two functions that call each other and write a global after the
// call, so no optimization turns it into a loop). WebKit's Worker holds the fewest frames and overflows it, while the main thread takes it
// (12000 is measured: 5000 overflowed the Worker only some of the time, because the frame size depends on whether the engine
// has already tiered the two functions up, which is a race with its compile threads; 12000 overflowed it in every run and the
// main thread still renders it)
// (`?render-in-worker=1` forces the Worker past the startup probe). Chromium's Worker has a larger stack, so the check runs on
// WebKit only.
//
// The Worker keeps a snapshot of the instance's memory at the end of every pass. When a pass overflows, the app moves to the
// main thread with that snapshot: the pass that overflowed runs again there, and counters, toggles, text, the navigation
// path, the tab selection, the scroll position and focus all survive. Two triggers are covered: an event (a click) and a task
// a timer resumes (the Worker's task drain). With the migration switched off (`window.__renderWorkerMigration = false`)
// the older recovery stays: the app restarts on the main thread with its state reset.
// Any app can exercise the move: with the performance diagnostics on, `window.__renderWorker.forceOverflow()` makes the
// Worker's next call fail as if its stack had run out. FOODTRUCK_BUNDLE (a FoodTruckWeb bundle) adds a check of that kind on
// Apple's Food Truck sample: its navigation path and a text field survive.
// Bundle: WORKER_OVERFLOW_BUNDLE (.build/browser/ShowcaseApp).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

// The suite always runs against WebKit, whose Worker has the smallest stack. The helper reads the engine when it launches.
process.env.SWIFTUIWEB_BROWSER_ENGINE = "webkit";

const BUNDLE = resolve(process.env.WORKER_OVERFLOW_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
const PORT = Number(process.env.WORKER_OVERFLOW_PORT ?? "8114");
const FOODTRUCK = process.env.FOODTRUCK_BUNDLE;

async function openFixture(browser, base, migration = true) {
  const page = await browser.newPage();
  const logs = [];
  page.on("console", (message) => logs.push([message.type(), message.text()]));
  if (!migration) await page.addInitScript("window.__renderWorkerMigration = false");
  await page.goto(base + "/stackDepth?render-in-worker=1", { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  assert.equal(await page.evaluate("window.__embeddedSession.worker"), true, "the Worker was not forced");
  return { page, logs };
}

async function textOf(page, testId) {
  return ((await page.locator(`[data-testid="${testId}"]`).textContent()) ?? "").trim();
}

// Changes everything the fixture's survivors panel keeps, in the Worker.
async function setState(page) {
  await page.locator('[data-testid="survivors-on"]').click();
  await page.waitForSelector('[data-testid="survivor-count"]');
  for (let i = 0; i < 3; i++) await page.locator('[data-testid="survivor-count"]').click();
  // The toggle's label spans the row; its switch is at the right end.
  const box = await page.locator('[data-testid="survivor-flag"]').boundingBox();
  await page.mouse.click(box.x + box.width - 20, box.y + box.height / 2);
  await page.locator('[data-testid="survivor-text"]').click();
  await page.keyboard.type("hello");
  await page.locator('[data-testid="survivor-push"]').click();
  await page.getByText("Beta", { exact: true }).first().click();
  // The scrolled list: its scroller is the element inside the frame that scrolls.
  await page.evaluate(() => {
    const frame = document.querySelector('[data-testid="survivor-scroll"]');
    const scroller = [frame, ...frame.querySelectorAll("*")].find(
      (e) => e.scrollHeight > e.clientHeight + 20 && getComputedStyle(e).overflowY !== "visible",
    );
    scroller.scrollTop = 120;
    window.__survivorScroller = scroller;
  });
  await page.waitForFunction(
    `document.querySelector('[data-testid="survivor-tab-value"]')?.textContent?.trim() === 'tab is beta'`,
  );
  await page.waitForFunction(`document.querySelector('[data-testid="survivor-pushed"]')`);
  assert.equal(await textOf(page, "survivor-count"), "count 3");
  assert.equal(await textOf(page, "survivor-flag-value"), "flag is on");
  assert.equal(await textOf(page, "survivor-text-value"), "text is hello");
  assert.equal(await textOf(page, "survivor-path-value"), "path 1");
  const scroll = await page.evaluate("window.__survivorScroller.scrollTop");
  assert.ok(scroll > 50, String(scroll));
  return scroll;
}

async function trigger(page, how) {
  // `click()` from script leaves the focus (the text field) where it is.
  if (how === "click") {
    await page.evaluate(`document.querySelector('[data-testid="recurse-12000"]').click()`);
  } else {
    await page.evaluate(`document.querySelector('[data-testid="recurse-later"]').click()`);
  }
}

async function checkMigration(browser, base, how) {
  const { page, logs } = await openFixture(browser, base);
  const scroll = await setState(page);
  // The focus sits in the text field when the app overflows.
  await page.locator('[data-testid="survivor-text"]').focus();
  await page.evaluate(`document.querySelector('[data-testid="survivor-text"]').setSelectionRange(5, 5)`);
  await trigger(page, how);
  await page.waitForFunction("window.__embeddedSession.worker === false", undefined, { timeout: 15_000 });
  await page.waitForFunction(
    `document.querySelector('[data-testid="depth-value"]')?.textContent?.trim() === 'depth 12000'`,
    undefined,
    { timeout: 15_000 },
  );
  await page.waitForSelector('[data-testid="depth-leaf"]', { timeout: 15_000 });
  assert.ok(
    logs.some(
      ([kind, text]) =>
        kind === "warning" && text.includes("overflowed the Worker's call stack") && text.includes("with its state"),
    ),
    JSON.stringify(logs),
  );
  assert.equal(
    await page.evaluate("sessionStorage.getItem('swui:worker-overflow')"),
    "1",
    "the overflow was not remembered",
  );
  // The state is what it was in the Worker.
  assert.equal(await textOf(page, "survivor-count"), "count 3");
  assert.equal(await textOf(page, "survivor-flag-value"), "flag is on");
  assert.equal(await textOf(page, "survivor-text-value"), "text is hello");
  assert.equal(await textOf(page, "survivor-tab-value"), "tab is beta");
  assert.equal(await textOf(page, "survivor-path-value"), "path 1");
  assert.equal(await textOf(page, "survivor-pushed"), "pushed 1");
  assert.equal(await page.locator('[data-testid="survivor-text"]').inputValue(), "hello");
  assert.equal(
    await page.evaluate("window.__survivorScroller.isConnected && window.__survivorScroller.scrollTop"),
    scroll,
    "the scroll position moved",
  );
  assert.equal(
    await page.evaluate("document.activeElement?.getAttribute('data-testid')"),
    "survivor-text",
    "the focus moved",
  );
  assert.equal(await page.evaluate("document.activeElement.selectionStart"), 5, "the caret moved");
  // The app is alive on the main thread: it takes input where it left off.
  await page.keyboard.type(" world");
  await page.waitForFunction(
    `document.querySelector('[data-testid="survivor-text-value"]')?.textContent?.trim() === 'text is hello world'`,
    undefined,
    { timeout: 5_000 },
  );
  await page.locator('[data-testid="survivor-count"]').click();
  await page.waitForFunction(
    `document.querySelector('[data-testid="survivor-count"]')?.textContent?.trim() === 'count 4'`,
    undefined,
    { timeout: 5_000 },
  );
  const errors = logs.filter(([kind]) => kind === "error");
  assert.ok(errors.length === 0, JSON.stringify(logs));
  // A reload in the same tab goes straight to the main thread, whatever the startup probe says.
  await page.goto(base + "/", { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  assert.equal(await page.evaluate("window.__embeddedSession.worker"), false, "a reload returned to the Worker");
  await page.close();
  console.log(`PASS a Worker stack overflow (${how}) moves the app to the main thread with its state`);
}

async function checkRestart(browser, base) {
  const { page, logs } = await openFixture(browser, base, false);
  await page.locator('[data-testid="survivors-on"]').click();
  await page.waitForSelector('[data-testid="survivor-count"]');
  await page.locator('[data-testid="survivor-count"]').click();
  await page.evaluate(`document.querySelector('[data-testid="recurse-12000"]').click()`);
  await page.waitForFunction("window.__embeddedSession.worker === false", undefined, { timeout: 15_000 });
  await page.waitForSelector('[data-testid="depth-leaf"]', { timeout: 15_000 });
  assert.ok(
    logs.some(
      ([kind, text]) =>
        kind === "warning" && text.includes("overflowed the Worker's call stack") && !text.includes("with its state"),
    ),
    JSON.stringify(logs),
  );
  assert.equal(await textOf(page, "depth-value"), "depth 0", "the app did not restart");
  assert.equal(await page.locator('[data-testid="survivor-count"]').count(), 0, "a restart keeps no state");
  assert.equal(
    await page.evaluate("sessionStorage.getItem('swui:worker-overflow')"),
    "1",
    "the overflow was not remembered",
  );
  // The restarted app renders the tree that overflowed the Worker.
  await page.locator('[data-testid="recurse-12000"]').click();
  await page.waitForFunction(
    `document.querySelector('[data-testid="depth-value"]')?.textContent?.trim() === 'depth 12000'`,
    undefined,
    { timeout: 15_000 },
  );
  await page.close();
  console.log("PASS without the migration a Worker stack overflow restarts the app on the main thread");
}

async function checkFoodtruck(browser, base) {
  const page = await browser.newPage({ viewport: { width: 430, height: 900 } });
  const logs = [];
  page.on("console", (message) => logs.push([message.type(), message.text()]));
  await page.addInitScript("window.__performanceDiagnostics = true");
  await page.goto(base + "/?render-in-worker=1", { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  assert.equal(await page.evaluate("window.__embeddedSession.worker"), true);
  await page.getByText("Donut Editor", { exact: true }).first().click();
  const name = page.locator('input[aria-label="Name"]');
  await name.waitFor({ timeout: 10_000 });
  await name.fill("Maple Bar");
  await page.waitForFunction(`document.querySelector('input[aria-label="Name"]')?.value === 'Maple Bar'`);
  await page.getByText("Back").first().waitFor();
  const before = await page.evaluate("document.body.innerText");
  await page.evaluate("window.__renderWorker.forceOverflow()");
  // Any call reaches the Worker; a resize is one the page makes by itself.
  await page.setViewportSize({ width: 431, height: 900 });
  await page.waitForFunction("window.__embeddedSession.worker === false", undefined, { timeout: 15_000 });
  await page.waitForTimeout(500);
  assert.ok(
    logs.some(([kind, text]) => kind === "warning" && text.includes("with its state")),
    JSON.stringify(logs),
  );
  assert.equal(await page.locator('input[aria-label="Name"]').inputValue(), "Maple Bar");
  assert.equal(await page.evaluate("document.body.innerText"), before, "the screen changed when the app moved");
  // The app keeps working: back to the list, then into another screen.
  await page.getByText("Back").first().click();
  await page.getByText("Orders", { exact: true }).first().waitFor({ timeout: 10_000 });
  await page.getByText("Orders", { exact: true }).first().click();
  await page.getByText("Back").first().waitFor({ timeout: 10_000 });
  assert.equal(await page.locator('input[aria-label="Name"]').count(), 0, "the sidebar did not navigate");
  const errors = logs.filter(([kind]) => kind === "error");
  assert.ok(errors.length === 0, JSON.stringify(logs));
  await page.close();
  console.log(
    "PASS Food Truck keeps its navigation path and text field when a forced overflow moves it to the main thread",
  );
}

await runSuite(async () => {
  const servers = [];
  let browser;
  try {
    const app = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "worker-overflow-server" });
    servers.push(app);
    if (FOODTRUCK) {
      servers.push(
        await serveBundle({
          bundle: resolve(FOODTRUCK),
          port: PORT + 1,
          logName: "worker-overflow-foodtruck-server",
        }),
      );
    }
    browser = await launch();
    await checkMigration(browser, app.base, "click");
    await checkMigration(browser, app.base, "task");
    await checkRestart(browser, app.base);
    if (FOODTRUCK) await checkFoodtruck(browser, `http://127.0.0.1:${PORT + 1}`);
  } finally {
    await browser?.close();
    for (const server of servers) await server.stop();
  }
});
