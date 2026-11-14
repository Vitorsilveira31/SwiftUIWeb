#!/usr/bin/env bun
// A matched swap (Tests/Apps/ViewTransitionApp) runs one browser view transition, and the page ends with the same DOM as a page
// without transitions. A duplicate name, reduced motion and a missing API start none, and the DOM still ends the same.
// The bundle: VIEW_TRANSITION_BUNDLE (.build/browser/ViewTransitionApp, built by `make view-transition-browser-test`).
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.VIEW_TRANSITION_BUNDLE ?? join(ROOT, ".build/browser/ViewTransitionApp"));

/** Records every view transition the page starts, and whether it finished or was skipped. */
const RECORD_TRANSITIONS = `
  window.__transitions = [];
  if (window.__withoutApi) delete Document.prototype.startViewTransition;
  const start = Document.prototype.startViewTransition;
  if (typeof start === 'function') {
    document.startViewTransition = function (callback) {
      const record = { done: false, skipped: false, groups: [] };
      window.__transitions.push(record);
      const transition = start.call(document, callback);
      // The groups' keyframes once the page has adjusted them (its own reaction to ready runs before this one's next).
      transition.ready.then(() => Promise.resolve().then(() => {
        record.groups = document.getAnimations().filter((animation) => (animation.effect?.pseudoElement || '').startsWith('::view-transition-group('))
          .map((animation) => ({ pseudo: animation.effect.pseudoElement, duration: animation.effect.getTiming().duration, frames: animation.effect.getKeyframes().map(({ width, height, transform }) => ({ width, height, transform })) }));
      }), () => {});
      transition.finished.then(() => { record.done = true; }, () => { record.done = true; record.skipped = true; });
      return transition;
    };
  }
`;

/** A page with the fixture: `options` picks reduced motion or a browser without the API. */
async function openFixture(browser, server, { reducedMotion = "no-preference", withoutApi = false } = {}) {
  const context = await browser.newContext({ viewport: { width: 800, height: 600 } });
  const page = await context.newPage();
  await page.emulateMedia({ reducedMotion });
  const problems = [];
  page.on("pageerror", (error) => problems.push(String(error)));
  await page.addInitScript(`window.__withoutApi = ${withoutApi};`);
  await page.addInitScript(RECORD_TRANSITIONS);
  await page.goto(`${server.base}/`);
  await page.waitForSelector('[data-testid="card"]');
  return { page, problems };
}

/** Clicks a control and waits until the page shows the state the click asks for, with every transition it started settled. */
async function click(page, id, expect) {
  await page.click(`[data-testid="${id}"]`);
  await page.waitForSelector(`[data-testid="${expect}"]`);
  await page.waitForFunction(() => window.__transitions.every((record) => record.done));
  await page.waitForTimeout(100);
}

/** The swap's steps, the same on every page: open, close, then a second source with the same name, and removed. `afterOpen` checks the open page. */
async function runSteps(page, afterOpen = async () => {}) {
  await click(page, "toggle", "detail");
  await afterOpen();
  await click(page, "toggle", "card");
  await click(page, "duplicate", "second");
  await click(page, "duplicate", "card");
  return page.evaluate(() => document.body.innerHTML);
}

/** An unrelated change lands while the swap's transition waits for its frame. The page must commit it, and a later click too. */
async function overlappingChange(browser, server, label) {
  const { page, problems } = await openFixture(browser, server);
  // Both clicks in one task: the second change's publication arrives while the first commit's transition waits for its frame.
  await page.evaluate(() => {
    document.querySelector('[data-testid="toggle"]').click();
    document.querySelector('[data-testid="bump"]').click();
  });
  await page.waitForSelector('[data-testid="detail"]');
  await page.waitForFunction(() => document.querySelector('[data-testid="bumps"]')?.textContent.trim() === "bumps 1", null, { timeout: 5000 });
  assert.equal(await page.textContent('[data-testid="state"]'), "open", `${label}: the swap is applied`);
  // A later click still commits: a stalled page would keep the old state.
  await click(page, "duplicate", "second");
  assert.deepEqual(problems, [], `${label}: no page errors with an overlapping change`);
  await page.context().close();
}

/** The view-transition names on the page, in document order. */
function namesOnPage(page) {
  return page.$$eval('[style*="view-transition-name"]', (elements) => elements.map((element) => element.style.getPropertyValue("view-transition-name")));
}

/**
 * One page through a zoom push and back. The push and an unrelated change share one task, so the second publication arrives while
 * the push's transition waits for its frame (the stall class). Returns what the checks need.
 */
async function zoomRun(browser, server, { withoutApi = false, reducedMotion = "no-preference" } = {}) {
  const { page, problems } = await openFixture(browser, server, { withoutApi, reducedMotion });
  const zoomStyle = await page.getAttribute('[data-testid="zoom"]', "style");
  const sourceName = zoomStyle?.match(/view-transition-name:\s*(vt-[-0-9]+)/)?.[1] ?? null;
  await page.evaluate(() => {
    document.querySelector('[data-testid="zoom"]').click();
    document.querySelector('[data-testid="bump"]').click();
  });
  await page.waitForSelector('[data-testid="zoomed"]');
  await page.waitForFunction(() => document.querySelector('[data-testid="bumps"]')?.textContent.trim() === "bumps 1", null, { timeout: 5000 });
  await page.waitForFunction(() => window.__transitions.every((record) => record.done));
  await page.waitForTimeout(100);
  const zoomed = await namesOnPage(page);
  const sourceWhileZoomed = await page.getAttribute('[data-testid="zoom"]', "style");
  await click(page, "back", "zoom");
  const popped = await namesOnPage(page);
  const bumps = await page.textContent('[data-testid="bumps"]');
  const transitions = await page.evaluate(() => window.__transitions.map((record) => ({ done: record.done, skipped: record.skipped })));
  const html = await page.evaluate(() => document.body.innerHTML);
  await page.context().close();
  return { sourceName, zoomed, sourceWhileZoomed, popped, bumps, transitions, html, problems };
}

async function main() {
  const label = engineName();
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: null, required: ["index.html"] });
  const browser = await launch();
  try {
    // The page with transitions: the matched pair names one element, the transition runs, and nothing is left named after.
    const { page, problems } = await openFixture(browser, server);
    const cardName = await page.getAttribute('[data-testid="card"]', "style");
    assert.match(cardName ?? "", /view-transition-name:\s*vt-/, `${label}: the card names its element`);
    const withTransitions = await runSteps(page, async () => {
      const names = await page.$$eval('[style*="view-transition-name"]', (elements) => elements.map((element) => element.style.getPropertyValue("view-transition-name")));
      // The detail, the pinned pair and the root's zoom source: three names, each on one element.
      assert.equal(names.length, 3, `${label}: the detail, the pin and the zoom source are named while open, got ${names.length}`);
      assert.equal(new Set(names).size, names.length, `${label}: no name on two elements`);
      assert.match(names[0], /^vt-/, `${label}: the detail carries the pair's name`);
      const transitions = await page.evaluate(() => window.__transitions.filter((record) => record.done).length);
      const started = await page.evaluate(() => window.__transitions.length);
      assert.ok(started >= 1, `${label}: the swap starts a view transition (the first paint starts none)`);
      assert.equal(transitions, started, `${label}: every transition finishes`);
    });
    // `properties: .position` with a top-leading anchor: the group takes the new size at once, and moves its top-leading
    // corner from the old view's to the new one's.
    const small = await page.evaluate(() => { const rect = document.querySelector('[data-testid="unpinned"]').getBoundingClientRect(); return { left: rect.left, top: rect.top }; });
    await click(page, "pin", "pinned");
    const pin = await page.evaluate(() => {
      const name = document.querySelector('[data-testid="pinned"]').style.getPropertyValue("view-transition-name");
      const record = window.__transitions[window.__transitions.length - 1];
      return record.groups.find((group) => group.pseudo === `::view-transition-group(${name})`)?.frames ?? null;
    });
    assert.ok(pin && pin.length >= 2, `${label}: the pinned pair morphs in a group of its own`);
    const [first, last] = [pin[0], pin[pin.length - 1]];
    assert.equal(first.width, last.width, `${label}: matching only the position, the group takes the new width at once`);
    assert.equal(first.height, last.height, `${label}: and the new height`);
    const corner = /matrix\(([^)]*)\)/.exec(first.transform)?.[1].split(",").map(Number).slice(4) ?? [];
    assert.ok(Math.abs(corner[0] - small.left) < 1.5 && Math.abs(corner[1] - small.top) < 1.5, `${label}: from the old view's top-leading corner (${corner} against ${small.left},${small.top})`);
    // The morph lasts as long as the commit's animation, or as the value animation the commit armed above the pair; a plain
    // commit keeps the browser's own timing.
    const morph = () => page.evaluate(() => window.__transitions[window.__transitions.length - 1].groups.find((group) => group.pseudo !== "::view-transition-group(root)")?.duration ?? null);
    const plainMorph = await morph();
    await click(page, "slow-pin", "unpinned");
    assert.equal(await morph(), 600, `${label}: inside withAnimation the morph takes the commit's 0.6 s (a plain commit: ${plainMorph})`);
    await click(page, "value-pin", "pinned");
    assert.equal(await morph(), 900, `${label}: and the 0.9 s of the value animation armed above the pair, without withAnimation`);
    assert.notEqual(plainMorph, 600, `${label}: a plain commit keeps the browser's timing`);
    assert.notEqual(plainMorph, 900, `${label}: whatever animations other commits had`);
    assert.deepEqual(problems, [], `${label}: no page errors with transitions`);
    await page.context().close();

    // The same steps without the API: the DOM must end the same, and no transition starts.
    const plain = await openFixture(browser, server, { withoutApi: true });
    const withoutTransitions = await runSteps(plain.page);
    // The names are per document (Swift hashes them with a per-process seed), so two pages name the same pair differently.
    const opaque = (html) => html.replace(/view-transition-name: vt-[-0-9]+;/g, "view-transition-name: vt;").replace(/data-matched-(source|target)="vt-[-0-9]+"/g, "data-matched-$1=\"vt\"");
    assert.equal(opaque(withTransitions), opaque(withoutTransitions), `${label}: the final DOM equals the page without transitions`);
    assert.deepEqual(await plain.page.evaluate(() => window.__transitions.length), 0, `${label}: no transition without the API`);
    assert.deepEqual(plain.problems, [], `${label}: no page errors without the API`);
    await plain.page.context().close();

    // Reduced motion: the swap still happens, with no transition.
    const quiet = await openFixture(browser, server, { reducedMotion: "reduce" });
    await click(quiet.page, "toggle", "detail");
    assert.equal(await quiet.page.evaluate(() => window.__transitions.length), 0, `${label}: no transition with reduced motion`);
    assert.equal(await quiet.page.textContent('[data-testid="state"]'), "open", `${label}: the swap happens with reduced motion`);
    assert.deepEqual(quiet.problems, [], `${label}: no page errors with reduced motion`);
    await quiet.page.context().close();

    // Duplicate names: the second source is present, the DOM is right, and nothing is left waiting for an aborted transition.
    const dup = await openFixture(browser, server);
    await click(dup.page, "duplicate", "second");
    assert.equal(await dup.page.textContent('[data-testid="state"]'), "closed", `${label}: the duplicate source does not change the state`);
    assert.deepEqual(dup.problems, [], `${label}: a duplicate name is not a page error`);
    await dup.page.context().close();

    await overlappingChange(browser, server, label);
    const zoom = await zoomRun(browser, server);
    assert.ok(zoom.sourceName, `${label}: the zoom source is named`);
    assert.equal(new Set(zoom.zoomed).size, zoom.zoomed.length, `${label}: one element per name while zoomed`);
    assert.ok(zoom.zoomed.includes(zoom.sourceName), `${label}: the zoom destination carries the source's name`);
    assert.ok(!(zoom.sourceWhileZoomed ?? "").includes("view-transition-name"), `${label}: the source gives its name up while zoomed`);
    assert.ok(zoom.transitions.length >= 1 && zoom.transitions.every((record) => record.done && !record.skipped), `${label}: the zoom runs a transition`);
    assert.equal(new Set(zoom.popped).size, zoom.popped.length, `${label}: one element per name after back`);
    assert.ok(zoom.popped.includes(zoom.sourceName), `${label}: back gives the name to the source`);
    assert.equal(zoom.bumps, "bumps 1", `${label}: the unrelated change in the same task is applied`);
    assert.deepEqual(zoom.problems, [], `${label}: no page errors across the zoom`);
    const zoomPlain = await zoomRun(browser, server, { withoutApi: true });
    assert.equal(opaque(zoom.html), opaque(zoomPlain.html), `${label}: the zoom ends with the same DOM as without transitions`);
    assert.equal(zoomPlain.transitions.length, 0, `${label}: no zoom transition without the API`);
    const zoomQuiet = await zoomRun(browser, server, { reducedMotion: "reduce" });
    assert.equal(zoomQuiet.transitions.length, 0, `${label}: no zoom transition with reduced motion`);
    assert.equal(zoomQuiet.bumps, "bumps 1", `${label}: reduced motion still applies the zoom`);
    console.log(`PASS ${label}: one transition for a matched swap, the same final DOM as without transitions, none with reduced motion or without the API`);
  } finally {
    await browser.close();
    await server.stop();
  }
}

await runSuite(main);
