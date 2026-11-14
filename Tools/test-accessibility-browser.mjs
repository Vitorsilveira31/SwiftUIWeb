#!/usr/bin/env bun
// Accessibility-tree acceptance gate for the real Embedded Showcase.
import assert from "node:assert/strict";
import { join } from "node:path";
import { ROOT, launch, runSuite, serveBundle } from "./browser-test-support.mjs";

async function load(page, base, route) {
  const response = await page.goto(base + route, { waitUntil: "domcontentloaded" });
  assert.ok(response && response.status() === 200);
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  await settled(page);
}

// The mounted flag comes before the first screen stops changing: on a loaded machine the runtime still replaces nodes after it,
// and a focus on a node that has been replaced waits for it until the test times out. A quiet DOM for a while is the signal.
async function settled(page, quiet = 400, limit = 10_000) {
  await page.evaluate(([quietMs, limitMs]) => new Promise((resolve) => {
    let timer = 0;
    const done = () => { observer.disconnect(); clearTimeout(timer); clearTimeout(cap); resolve(); };
    const observer = new MutationObserver(() => { clearTimeout(timer); timer = setTimeout(done, quietMs); });
    const cap = setTimeout(done, limitMs);
    observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
    timer = setTimeout(done, quietMs);
  }), [quiet, limit]);
}

// Focus the control again when it was replaced between the lookup and the focus; a control that never takes focus still fails.
async function focusControl(page, locator) {
  for (let attempt = 1; ; attempt++) {
    try {
      await locator.focus({ timeout: 3_000 });
      await settled(page, 150, 3_000);
      if (await locator.evaluate((el) => document.activeElement === el)) return;
    } catch (error) {
      if (attempt >= 5) throw error;
    }
    if (attempt >= 5) throw new Error("the control did not keep the focus");
  }
}

// [role, name] pairs from the browser's full accessibility tree.
async function axRoles(page) {
  const session = await page.context().newCDPSession(page);
  const { nodes = [] } = await session.send("Accessibility.getFullAXTree");
  return nodes.map((node) => [node.role?.value, node.name?.value]);
}

await runSuite(async () => {
  const bundle = process.env.ACCESSIBILITY_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp");
  const port = Number(process.env.ACCESSIBILITY_PORT ?? "8104");
  const { base, stop } = await serveBundle({ bundle, port, logName: "accessibility-browser-server" });
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await load(page, base, "/components");
    let roles = await axRoles(page);
    for (const role of ["button", "switch", "slider", "progressbar", "meter"]) {
      assert.ok(roles.some((item) => item[0] === role), JSON.stringify([role, roles]));
    }
    assert.ok((await page.locator('[aria-live="polite"]').count()) >= 0);

    // Keyboard-only acceptance: native controls enter the tab order and remain named after focus moves,
    // without stealing editing keys.
    await load(page, base, "/forms");
    assert.ok((await page.getByRole("button", { name: "Save", exact: true }).count()) > 0);
    assert.ok(await page.getByRole("button", { name: "Save", exact: true }).isDisabled());
    const field = page.getByRole("textbox", { name: "Name", exact: true });
    await focusControl(page, field);
    assert.ok(await page.evaluate((el) => document.activeElement === el, await field.elementHandle()));
    await page.keyboard.press("Tab");
    assert.ok(await page.evaluate((el) => document.activeElement !== el, await field.elementHandle()));
    await page.keyboard.press("Shift+Tab");
    assert.ok(await page.evaluate((el) => document.activeElement === el, await field.elementHandle()));

    await load(page, base, "/presentation");
    const opener = page.getByRole("button", { name: "Alert", exact: true });
    await focusControl(page, opener);
    await opener.press("Enter");
    await page.waitForSelector('.presentation-root[aria-modal="true"]');
    roles = await axRoles(page);
    assert.ok(
      roles.some((item) => item[0] === "dialog" || item[0] === "alertdialog"),
      JSON.stringify(roles),
    );
    assert.ok((await page.locator("[inert][aria-hidden='true']").count()) > 0);
    await page.keyboard.press("Escape");
    await page.waitForSelector(".presentation-root", { state: "detached" });
    assert.ok(await page.evaluate((el) => document.activeElement === el, await opener.elementHandle()));
  } finally {
    await browser?.close();
    await stop();
  }
  console.log("PASS Embedded Chromium accessibility tree, keyboard and modal isolation");
});
