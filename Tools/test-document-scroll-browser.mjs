#!/usr/bin/env bun
// The page's scroll view hands its scrolling to the document on a touch screen (Tools/document-scroll.js), shown on the project
// site (Examples/ShowcaseSite): a header above a TabView whose pages are ScrollViews.
//
//   * on a phone with a touch screen the document scrolls, not the page's scroll view: the page runs to the bottom of the
//     screen, where a phone's browser draws its bars over it, and the bars can shrink;
//   * the header sticks where it was, on the window's background, and the page scrolls under it;
//   * the scroll view answers for the document: its `scrollTop` is the document's and moves it, its `scroll` events follow the
//     document's, its `clientHeight` is the screen under the header and its box starts under the header;
//   * the last content can be scrolled to the bottom of the screen, and the page's scroll view reaches it;
//   * each page keeps its offset: another page opens at its own, and the first comes back where it was left;
//   * with a mouse (no touch screen) nothing changes: the scroll view scrolls and the document does not.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: SHOWCASE_SITE_BUNDLE (default .build/browser/ShowcaseSite).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.SHOWCASE_SITE_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseSite"));
const PHONE = { width: 390, height: 844 };

async function open(browser, base, path, { touch = true, query = "" } = {}) {
  // `isMobile` is Chromium's; WebKit takes the touch screen alone (`pointer: coarse` follows `hasTouch` in both).
  const mobile = engineName() === "chromium" ? { isMobile: true } : {};
  const context = await browser.newContext({ viewport: PHONE, hasTouch: touch, ...(touch ? mobile : {}), locale: "en-US" });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(`${base}${path}${query}`, { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
  await page.waitForSelector("h1, [role=heading]", { state: "attached", timeout: 60_000 });
  // The layout pass that hands the scroll over follows the first commit (a touch screen), and the page answers taps once the
  // prerendered first screen has given way to it.
  if (touch) await page.waitForSelector("[data-document-scroller]", { state: "attached", timeout: 30_000 });
  await page.waitForFunction(() => !document.querySelector("[data-first-paint]"));
  await page.waitForFunction(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(() => done(true)))));
  return { context, page, errors };
}

// What the page shows of its scroll: the document's, the page's scroll view's and the header's.
const state = (page) => page.evaluate(() => {
  const scroller = document.querySelector("[data-document-scroller]");
  const header = document.querySelector('[data-document-sticky="top"]');
  const box = scroller?.getBoundingClientRect();
  return {
    coarse: matchMedia("(pointer: coarse)").matches,
    documentScrolls: document.scrollingElement.scrollHeight > innerHeight + 1,
    viewport: document.documentElement.clientHeight,
    scrollY: Math.round(scrollY),
    handed: !!scroller,
    scrollTop: scroller ? Math.round(scroller.scrollTop) : null,
    clientHeight: scroller?.clientHeight ?? null,
    scrollHeight: scroller?.scrollHeight ?? null,
    boxTop: box ? Math.round(box.top) : null,
    boxBottom: box ? Math.round(box.bottom) : null,
    headerTop: header ? Math.round(header.getBoundingClientRect().top) : null,
    headerBottom: header ? Math.round(header.getBoundingClientRect().bottom) : null,
    headerBackground: header ? getComputedStyle(header).backgroundColor : null,
    // Everything that sticks at the top (the header and the Divider under it) ends here.
    band: Math.round(Math.max(0, ...[...document.querySelectorAll('[data-document-sticky="top"]')].map((e) => e.getBoundingClientRect().bottom))),
    page: document.body.getBoundingClientRect().height,
  };
});

async function checkHandsOver(browser, base, query) {
  const { context, page, errors } = await open(browser, base, "/en/benefits", { query });
  const before = await state(page);
  assert.ok(before.coarse, "a touch screen reports a coarse pointer");
  assert.ok(before.handed, "on a touch screen the page's scroll view hands its scrolling to the document");
  assert.ok(before.documentScrolls, `the document scrolls (it is ${before.page}px tall in a ${before.viewport}px screen)`);
  assert.ok(before.headerBottom > 0 && before.headerTop === 0, `the header is at the top of the screen (${before.headerTop}..${before.headerBottom})`);
  assert.equal(before.boxTop, before.band, "the scroll view's box starts under what sticks at the top");
  assert.equal(before.boxBottom, before.viewport, "the scroll view's box ends at the bottom of the screen");
  assert.equal(before.clientHeight, before.viewport - before.band, "the scroll view's clientHeight is the screen under what sticks at the top");
  assert.notEqual(before.headerBackground, "rgba(0, 0, 0, 0)", "the header sticks on the window's background");

  // The scroll view's scrollTop is the document's: setting it scrolls the document and fires the scroll view's own event.
  const moved = await page.evaluate(async () => {
    const scroller = document.querySelector("[data-document-scroller]");
    let events = 0;
    scroller.addEventListener("scroll", () => events++);
    scroller.scrollTop = 300;
    await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
    return { y: Math.round(scrollY), top: Math.round(scroller.scrollTop), events };
  });
  assert.equal(moved.y, 300, "setting the scroll view's scrollTop scrolls the document");
  assert.equal(moved.top, 300, "the scroll view's scrollTop is the document's");
  assert.ok(moved.events > 0, "the scroll view fires scroll events when the document scrolls");
  const scrolled = await state(page);
  assert.equal(scrolled.headerTop, 0, "the header stays at the top while the page scrolls under it");

  // The end of the page reaches the bottom of the screen.
  await page.evaluate(() => window.scrollTo({ top: document.scrollingElement.scrollHeight, behavior: "instant" }));
  const end = await page.evaluate(() => {
    const scroller = document.querySelector("[data-document-scroller]");
    const last = [...scroller.querySelectorAll("*")].filter((e) => e.getClientRects().length && e.textContent.trim()).pop();
    return { bottom: Math.round(last.getBoundingClientRect().bottom), viewport: document.documentElement.clientHeight, max: scroller.scrollHeight - scroller.clientHeight, top: Math.round(scroller.scrollTop) };
  });
  assert.ok(end.bottom <= end.viewport, `the last content ends on screen (${end.bottom} in ${end.viewport})`);
  assert.ok(Math.abs(end.top - end.max) <= 1, `the scroll view's range is the document's (${end.top} of ${end.max})`);
  assert.deepEqual(errors, [], "page errors");
  await context.close();
  return "hands over";
}

// A page's offset is its own: another page opens at its own offset, and the first comes back where it was left.
async function checkTabsKeepOffsets(browser, base, query) {
  const { context, page, errors } = await open(browser, base, "/en/benefits", { query });
  await page.evaluate(() => window.scrollTo({ top: 400, behavior: "instant" }));
  // A tap within 150 ms of a scroll ends the scroll and is not a tap (embedded-dom.js, `scrolling`).
  await page.waitForTimeout(250);
  // A finger taps where the control is. (A locator's click first scrolls its element into view, and a view stuck at the top is
  // scrolled to where it sits in the flow, the top of the document: no tap does that.)
  const tap = async (locator) => {
    const box = await locator.boundingBox();
    await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
  };
  const go = async (label) => {
    await page.evaluate(() => { window.__handedBefore = document.querySelector("[data-document-scroller]"); });
    await tap(page.locator('button[aria-label="Menu"]:visible').first());
    const link = page.getByRole("link", { name: new RegExp(`${label}$`) }).locator("visible=true").first();
    await link.waitFor({ state: "visible" });
    await tap(link);
    await page.waitForFunction((name) => location.pathname.endsWith(name), label === "Benefits" ? "benefits" : "performance");
    // The pass that hands the shown page's scroll view over follows the commit that shows it, which can come after the address
    // changed (the Worker): until then the page left behind is still the one handed over.
    await page.waitForFunction(() => { const s = document.querySelector("[data-document-scroller]"); return !!s && s !== window.__handedBefore && s.checkVisibility(); });
    await page.waitForFunction(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(() => done(true)))));
  };
  await go("Performance");
  const other = await state(page);
  assert.ok(other.handed, "the other page's scroll view hands its scrolling over");
  assert.equal(other.scrollY, 0, "another page opens at its own offset (the top)");
  await go("Benefits");
  const back = await state(page);
  assert.equal(back.scrollY, 400, "the first page comes back where it was left");
  assert.deepEqual(errors, [], "page errors");
  await context.close();
  return "tabs keep offsets";
}

// The page's scroll view, grown with the page, reaches the bottom of the screen.
async function checkReachesBottom(browser, base, query) {
  const { context, page, errors } = await open(browser, base, "/en/benefits", { query });
  const filled = await page.evaluate(() => {
    const scroller = document.querySelector("[data-document-scroller]");
    const real = Element.prototype.getBoundingClientRect.call(scroller);
    return { bottom: Math.round(real.bottom), viewport: document.documentElement.clientHeight };
  });
  assert.ok(filled.bottom >= filled.viewport, `the page's scroll view reaches the bottom of the screen (${filled.bottom} of ${filled.viewport})`);
  assert.deepEqual(errors, [], "page errors");
  await context.close();
  return "reaches the bottom";
}

// With a mouse the page's scroll view keeps its own scrolling.
async function checkMouseKeepsScrollView(browser, base, query) {
  const { context, page, errors } = await open(browser, base, "/en/benefits", { touch: false, query });
  const s = await state(page);
  assert.ok(!s.coarse, "a mouse reports a fine pointer");
  assert.ok(!s.handed, "with a mouse the scroll view keeps its scrolling");
  assert.ok(!s.documentScrolls, "with a mouse the document does not scroll");
  assert.deepEqual(errors, [], "page errors");
  await context.close();
  return "mouse";
}

runSuite(async () => {
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "document-scroll-server" });
  const browser = await launch();
  try {
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const done = [];
      for (const check of [checkHandsOver, checkTabsKeepOffsets, checkReachesBottom, checkMouseKeepsScrollView]) done.push(await check(browser, server.base, query));
      console.log(`[${engineName()}/${mode}] ${done.join(", ")}`);
    }
    console.log("Document scroll browser test passed.");
  } finally {
    await browser.close();
    await server.stop();
  }
});
