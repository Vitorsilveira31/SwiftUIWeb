#!/usr/bin/env bun
// What the Swift publisher sends (real Embedded Showcase bundle, Worker mode).
//
// Publications are binary streams (Documentation/Architecture/BINARY_PATCHES.md): once the page holds the tree, Swift sends
// records of what changed since the publication the page acknowledged. This suite checks that:
//
//   1. Records. A run of re-renders is applied as records, and none fails (a failure makes the page ask for the whole tree).
//   2. Same DOM. The page reached through incremental publications is the page reached when every publication is sent in
//      full (`window.__fullPublish = true` keeps Swift from ever being acknowledged), also for a page that acknowledges
//      late and drops publications.
//
// Environment: PUBLICATION_BUNDLE (default .build/browser/ShowcaseApp), PUBLICATION_PORT (default 8117).
import assert from "node:assert/strict";
import { join } from "node:path";
import { launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = process.env.PUBLICATION_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp");
const PORT = Number(process.env.PUBLICATION_PORT ?? "8117");

/** The mounted DOM without what is allowed to differ between runs. */
function normalizedDOM() {
  const clone = document.getElementById("embedded-app-root").cloneNode(true);
  for (const element of clone.querySelectorAll("*")) {
    element.removeAttribute("data-embedded-event-id");
    // A node id is `slot:generation:type`. The slot is where the arena put the node and the generation counts the nodes that
    // held it before; both follow how many publications were made and dropped on the way (a page that reads only the newest of
    // several), so neither is part of what the page shows.
    // The size of a lazy list's spacer is its rows' measured heights added up, which follows where the window was when it
    // measured: a page that dropped publications measured at other positions.
    if (element.hasAttribute("data-lazy-spacer")) { element.removeAttribute("data-size-h"); element.removeAttribute("data-size-w"); element.removeAttribute("style"); }
    if (element.hasAttribute("data-embedded-node-id")) element.setAttribute("data-embedded-node-id", element.getAttribute("data-embedded-node-id").replace(/^\d+:\d+:/, "*:*:"));
    // The order of attributes and of style declarations depends on which patch wrote them last, not on what the page
    // shows.
    if (element.hasAttribute("style")) {
      const style = element.style;
      element.setAttribute("style", [...style].sort().map((name) => `${name}:${style.getPropertyValue(name)}${style.getPropertyPriority(name) ? "!important" : ""}`).join(";"));
    }
    const attributes = [...element.attributes].map((attribute) => [attribute.name, attribute.value]).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    for (const [name] of attributes) element.removeAttribute(name);
    for (const [name, value] of attributes) element.setAttribute(name, value);
  }
  return clone.innerHTML;
}

/** `rapid`: the page is given its changes faster than it commits them, so that it drops publications it never reads. */
/** Where two serialized pages first differ, with some of the text around it. */
function firstDifference(a, b) {
  let at = 0;
  while (at < a.length && at < b.length && a[at] === b[at]) at += 1;
  return `at ${at}: ...${a.slice(Math.max(0, at - 150), at + 250)}\n  against ...${b.slice(Math.max(0, at - 150), at + 250)}`;
}

async function scenario(page, base, rapid = false) {
  await page.goto(base + "/collections", { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  await page.waitForTimeout(400);
  // Re-renders that change little: the viewport re-runs bodies whose output stays the same.
  for (const width of [1380, 1300, 1220, 1140, 1060, 980, 1060, 1200, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.waitForTimeout(rapid ? 30 : 350);
  }
  if (rapid) {
    await page.waitForTimeout(400);
    // Three clicks in one task: three publications, and the page commits the newest.
    await page.evaluate(() => { const button = [...document.querySelectorAll("button")].find((candidate) => candidate.textContent.trim() === "Insert"); for (let click = 0; click < 3; click += 1) button.click(); });
    await page.waitForTimeout(500);
  } else {
    for (let click = 0; click < 3; click += 1) {
      await page.getByRole("button", { name: "Insert", exact: true }).click();
      await page.waitForTimeout(300);
    }
  }
  for (const width of [1100, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.waitForTimeout(rapid ? 30 : 350);
  }
  // Both runs end at the top: a click by the test's mouse scrolls the button into view and one made by the page does not, and
  // a lazy list shows the window around where it was scrolled to, so the pages would differ by their scroll and not by what
  // was published.
  await page.evaluate(() => {
    document.scrollingElement?.scrollTo(0, 0);
    for (const element of document.querySelectorAll("*")) if (element.scrollTop) element.scrollTop = 0;
  });
  await page.waitForTimeout(500);
}

/**
 * A tab the page shows before Swift publishes its selection. The click's bubble listeners are stopped once the page has applied
 * it, so Swift never hears it and the commit after it still carries Swift's old selection: the page leads Swift. The verification
 * mode must leave the tab's selection out while it leads, and must still report an attribute nobody owns on a tab button.
 * Only meaningful in verify mode (`SWIFTUIWEB_BINARY=verify`).
 */
async function tabSelectionAhead(browser, base) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(base + "/state", { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  await page.waitForTimeout(400);
  if (!(await page.evaluate(() => window.__binaryVerify === true))) {
    console.log("skipped: the tab check needs SWIFTUIWEB_BINARY=verify");
    await page.close();
    return;
  }
  const differences = () => page.evaluate(() => window.__binaryVerifyReport?.differences ?? []);
  await page.locator('.tab-view [role="tab"][data-tab-value="Settings"]').first().click();
  await page.waitForTimeout(400);
  assert.deepEqual(await differences(), [], "a tab click, which Swift answers, reported differences");
  await page.evaluate(() => {
    document.getElementById("embedded-app-root").addEventListener("click", (event) => { if (event.target.closest?.('[role="tab"]')) event.stopPropagation(); }, true);
  });
  await page.locator('.tab-view [role="tab"][data-tab-value="Home"]').first().click();
  await page.waitForTimeout(300);
  // The check is real, and it has to be made in the commit that Swift has not caught up with yet: the page's history sync tells
  // Swift the selection after the commit, and the publication that follows rewrites the tab buttons, which drops the attribute.
  // An attribute nobody owns on a tab button is reported there (labelled BINARY-EXPECTED); nothing else of the selection is.
  page.__binaryExpected = true;
  await page.evaluate(() => document.querySelector('.tab-view [role="tab"][data-tab-value="Settings"]').setAttribute("data-verify-probe", "1"));
  // A commit while Swift still shows the selection before the click.
  await page.setViewportSize({ width: 1300, height: 900 });
  await page.waitForTimeout(800);
  page.__binaryExpected = false;
  const reported = await differences();
  assert.ok(reported.some((d) => d.kind === "attribute-extra" && d.name === "data-verify-probe"), "an attribute nobody owns on a tab button was not reported");
  assert.deepEqual(reported.filter((d) => d.name !== "data-verify-probe"), [], "the page led Swift's tab selection and the verification reported it");
  console.log("PASS a tab selection the page leads is not reported, and an attribute nobody owns still is");
  await page.close();
}

await runSuite(async () => {
  const { base, stop } = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "publication-browser-server" });
  let browser;
  try {
    browser = await launch();

    const incremental = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await incremental.addInitScript(() => { window.__performanceDiagnostics = true; });
    await scenario(incremental, base);
    const diagnostics = await incremental.evaluate(() => window.__performanceMetrics.snapshot().diagnostics);
    console.log(`binary commits=${diagnostics.binaryCommits} records=${diagnostics.binaryRecords} full retries=${diagnostics.fullPublications}`);
    assert.ok(diagnostics.binaryRecords > 5, `the run applied too few records: ${JSON.stringify(diagnostics)}`);
    assert.equal(diagnostics.fullPublications, 0, "a record could not be applied and the page asked for a publication in full");
    const incrementalDOM = await incremental.evaluate(normalizedDOM);
    assert.ok(!(await incremental.evaluate(() => document.getElementById("embedded-app-root").dataset.runtimeError)), "runtime error after the incremental run");

    const full = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await full.addInitScript(() => { window.__fullPublish = true; });
    await scenario(full, base);
    // The two pages are compared once both have settled: a transition that ends a frame later on one of them (a slow runner)
    // is not a difference between publications. A difference that stays is reported where it starts, not as two pages.
    let complete = await full.evaluate(normalizedDOM);
    let latest = incrementalDOM;
    for (const end = Date.now() + 5000; latest !== complete && Date.now() < end; ) {
      await full.waitForTimeout(100);
      [latest, complete] = [await incremental.evaluate(normalizedDOM), await full.evaluate(normalizedDOM)];
    }
    let at = 0;
    while (at < latest.length && latest[at] === complete[at]) at += 1;
    assert.ok(latest === complete, `incremental and full publications left different pages, first different at ${at} of ${latest.length}/${complete.length}:\n  incremental: ${latest.slice(Math.max(0, at - 160), at + 240)}\n  full:        ${complete.slice(Math.max(0, at - 160), at + 240)}`);
    console.log("PASS publications are applied as records, and the page equals the one built from full publications");

    // A page that acknowledges two publications late and reads only the newest of several: Swift has published more than it
    // was told the page holds, and what it publishes next must still leave the page the one built from full publications.
    const lagging = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await lagging.addInitScript(() => { window.__acknowledgeLag = 2; window.__performanceDiagnostics = true; });
    await scenario(lagging, base, true);
    assert.ok(!(await lagging.evaluate(() => document.getElementById("embedded-app-root").dataset.runtimeError)), "runtime error after the lagging run");
    // Compared once both have settled, as the first two pages were.
    let laggingDOM = await lagging.evaluate(normalizedDOM);
    for (const end = Date.now() + 5000; laggingDOM !== complete && Date.now() < end; ) {
      await lagging.waitForTimeout(100);
      [laggingDOM, complete] = [await lagging.evaluate(normalizedDOM), await full.evaluate(normalizedDOM)];
    }
    assert.ok(laggingDOM === complete, `a page that acknowledges late and drops publications left a different page ${firstDifference(laggingDOM, complete)}`);
    const laggingDiagnostics = await lagging.evaluate(() => window.__performanceMetrics.snapshot().diagnostics);
    console.log(`lagging: binary commits=${laggingDiagnostics.binaryCommits} records=${laggingDiagnostics.binaryRecords} full retries=${laggingDiagnostics.fullPublications}`);
    assert.equal(laggingDiagnostics.fullPublications, 0, "the lagging page could not apply a record and asked for a publication in full");
    console.log("PASS a page that acknowledges late and drops publications ends in the same page");

    await tabSelectionAhead(browser, base);
  } finally {
    await browser?.close();
    await stop();
  }
});
