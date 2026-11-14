#!/usr/bin/env bun
// Real Embedded Chromium scrolling gate.
//
// This exercises the Showcase ScrollViewReader and modern lazy ScrollView through the linked Swift +
// BrowserIO bundle. The emitted trace is diagnostic only; no expected geometry is hardcoded here.
import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { ROOT, launch, runSuite, serveBundle } from "./browser-test-support.mjs";

await runSuite(async () => {
  const bundle = process.env.SCROLLING_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp");
  const port = Number(process.env.SCROLLING_PORT ?? "8099");
  const tracePath = join(ROOT, ".build/scrolling/trace.json");
  mkdirSync(join(ROOT, ".build/scrolling"), { recursive: true });

  const { base, stop } = await serveBundle({ bundle, port, logName: "scrolling-browser-server" });
  let browser;
  try {
    browser = await launch();
    const context = await browser.newContext({ viewport: { width: 900, height: 900 }, hasTouch: true });
    const page = await context.newPage();
    const response = await page.goto(base + "/collections", { waitUntil: "domcontentloaded" });
    assert.ok(response && response.status() === 200);
    await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
    await page.waitForTimeout(250);

    const hosts = page.locator(".scroll-view");
    assert.ok((await hosts.count()) >= 3, "Showcase did not expose List, reader, and modern scroll surfaces");
    const ids = await page.locator(".scroll-view").evaluateAll((els) => els.map((e) => e.dataset.scrollId));
    assert.ok(
      ids.every(Boolean) && ids.length === new Set(ids).size,
      `scroll IDs are not stable/unique: ${JSON.stringify(ids)}`,
    );

    const readerButton = page.getByRole("button", { name: "Scroll to row 8", exact: true });
    const horizontal = page.locator(".scroll-horizontal").first();
    await readerButton.click();
    await page.waitForTimeout(180);
    const readerTarget = page.locator("[data-view-id='8']").filter({ has: page.locator("text=8") });
    assert.ok((await readerTarget.count()) >= 1, "ScrollViewReader target was not retained");
    const horizontalState = await horizontal.evaluate((e) => ({
      left: e.scrollLeft,
      width: e.clientWidth,
      scrollWidth: e.scrollWidth,
      targets: [...e.querySelectorAll("[data-view-id]")].map((x) => ({
        id: x.getAttribute("data-view-id"),
        left: x.getBoundingClientRect().left,
      })),
    }));
    assert.ok(
      horizontalState.targets.some((target) => target.id === "8"),
      `scoped reader target left its owning surface: ${JSON.stringify(horizontalState)}`,
    );

    const jump = page.getByRole("button", { name: "Jump to item 40", exact: true });
    await jump.click();
    await page.waitForTimeout(220);
    const modern = page.locator(".scroll-view[data-scroll-position='true']:not(.scroll-horizontal)").first();
    const modernState = await page.locator(".scroll-view").evaluateAll((els) =>
      els.map((e) => ({
        position: e.getAttribute("data-scroll-position"),
        top: e.scrollTop,
        max: e.scrollHeight - e.clientHeight,
        id: e.dataset.scrollId,
      })),
    );
    const positionNodes = await page.locator("[data-scroll-position='true']").evaluateAll((els) =>
      els.map((e) => ({
        tag: e.tagName,
        classes: e.className,
        host: Boolean(e.closest(".scroll-view")),
        id: e.dataset.scrollId,
      })),
    );
    assert.ok(
      (await modern.count()) === 1 && (await modern.evaluate((e) => e.scrollTop > 0)),
      `scrollPosition did not move the modern surface: ${JSON.stringify(modernState)}; metadata=${JSON.stringify(positionNodes)}`,
    );

    await modern.evaluate((e) => {
      e.scrollTop = e.scrollHeight;
      e.dispatchEvent(new Event("scroll", { bubbles: true }));
    });
    await page.waitForTimeout(180);
    const bottom = await modern.evaluate((e) => ({ top: e.scrollTop, max: e.scrollHeight - e.clientHeight }));
    // Simulate the real retained-tree edge case where a semantic scroll surface is replaced during a structural
    // commit. The replacement keeps the semantic ID; the coordinator must restore native offset.
    await modern.evaluate((e) => {
      const replacement = e.cloneNode(true);
      e.replaceWith(replacement);
    });
    await page.getByRole("button", { name: "Insert", exact: true }).click();
    await page.waitForTimeout(220);
    await page.evaluate(() => window.__scrollCoordinator?.sync());
    await page.waitForTimeout(40);
    const restored = await page
      .locator(".scroll-view[data-scroll-position='true']:not(.scroll-horizontal)")
      .first()
      .evaluate((e) => ({ top: e.scrollTop, max: e.scrollHeight - e.clientHeight }));
    const restorationTrace = await page.evaluate(() => globalThis.__scrollCoordinatorTrace || {});
    assert.ok(
      (restorationTrace.restored ?? 0) > 0,
      `scroll restoration was not applied across replacement: ${JSON.stringify(restorationTrace)}`,
    );
    assert.ok(
      0 <= restored.top && restored.top <= restored.max + 1,
      `restored scroll position escaped native bounds: ${JSON.stringify(bottom)} -> ${JSON.stringify(restored)}`,
    );

    // SwiftUI ScrollPosition values: edge, point, one-axis targets, animated changes, and the user's scroll
    // answer. Trace counters separate programmatic applications from user reports.
    const coordinatorTrace = () => page.evaluate(() => globalThis.__scrollCoordinatorTrace || {});
    const topState = (locator) => locator.evaluate((e) => ({ top: e.scrollTop, max: e.scrollHeight - e.clientHeight }));
    const beforeEdge = await coordinatorTrace();
    await page.getByRole("button", { name: "Scroll to bottom edge", exact: true }).click();
    await page.waitForTimeout(200);
    const atBottom = await topState(modern);
    assert.ok(
      atBottom.max > 0 && atBottom.max - atBottom.top <= 2,
      `bottom edge did not reach the end: ${JSON.stringify(atBottom)}`,
    );
    const afterEdge = await coordinatorTrace();
    assert.equal(afterEdge.animatedPositions ?? 0, beforeEdge.animatedPositions ?? 0, "a plain edge change animated");
    await page.getByRole("button", { name: "Scroll to offset 300", exact: true }).click();
    await page.waitForTimeout(200);
    const offset300 = await modern.evaluate((e) => e.scrollTop);
    assert.ok(
      Math.abs(offset300 - 300) <= 60,
      `point target y=300 landed at ${offset300} (the view-aligned snap is one item)`,
    );
    const beforeAnimation = await coordinatorTrace();
    // Some engines (headless WebKit) accept smooth scrollTo without moving; the coordinator's dispatch is then the
    // only observable, so the offset check runs only where the engine performs smooth scrolls.
    const smoothMoves = await page.evaluate(async () => {
      const e = document.querySelector(".scroll-view[data-scroll-position='true']:not(.scroll-horizontal)");
      const start = e.scrollTop;
      e.scrollTo({ top: Math.max(0, start - 200), behavior: "smooth" });
      await new Promise((r) => setTimeout(r, 600));
      const moved = e.scrollTop !== start;
      e.scrollTo({ top: start, behavior: "instant" });
      return moved;
    });
    await page.getByRole("button", { name: "Animate to top edge", exact: true }).click();
    if (smoothMoves) {
      await page.waitForFunction(
        () => {
          const e = document.querySelector(".scroll-view[data-scroll-position='true']:not(.scroll-horizontal)");
          return e && e.scrollTop <= 1;
        },
        undefined,
        { timeout: 8000 },
      );
    } else {
      await page.waitForTimeout(300);
    }
    const animatedTop = await topState(modern);
    const afterAnimation = await coordinatorTrace();
    assert.equal(
      afterAnimation.animatedPositions ?? 0,
      (beforeAnimation.animatedPositions ?? 0) + 1,
      `withAnimation edge change was not smooth: ${JSON.stringify(beforeAnimation)} -> ${JSON.stringify(afterAnimation)}`,
    );
    if (smoothMoves) {
      assert.ok(animatedTop.top <= 1, `animated edge target did not reach the top: ${JSON.stringify(animatedTop)}`);
    }
    const rail = page.locator(".scroll-horizontal[data-scroll-position='true']").first();
    await page.getByRole("button", { name: "Scroll rail to trailing edge", exact: true }).click();
    await page.waitForTimeout(200);
    const railEnd = await rail.evaluate((e) => ({ left: e.scrollLeft, max: e.scrollWidth - e.clientWidth }));
    assert.ok(
      railEnd.max > 0 && railEnd.max - railEnd.left <= 2,
      `trailing edge did not reach the end of the rail: ${JSON.stringify(railEnd)}`,
    );
    await page.getByRole("button", { name: "Scroll rail to x 120", exact: true }).click();
    await page.waitForTimeout(200);
    const railX = await rail.evaluate((e) => e.scrollLeft);
    assert.ok(Math.abs(railX - 120) <= 2, `x target 120 landed at ${railX}`);

    // The user's scroll answers the binding (isPositionedByUser) without echoing a position back.
    const beforeUser = await coordinatorTrace();
    await modern.scrollIntoViewIfNeeded();
    await page.waitForTimeout(100);
    let box = await modern.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.wheel(0, 240);
    await page.waitForTimeout(500);
    const scrolledByUser = await topState(modern);
    // The report follows the scroll's settling (140ms after the last scroll event), which engines spread out differently.
    await page.getByText("Positioned by user: true", { exact: true }).waitFor({ timeout: 4000 });
    assert.equal(
      await page.getByText("Positioned by user: true", { exact: true }).count(),
      1,
      "user scroll did not set isPositionedByUser",
    );
    assert.ok(scrolledByUser.top > 0, `wheel did not scroll the modern surface: ${JSON.stringify(scrolledByUser)}`);
    await page.waitForTimeout(400);
    const settledUser = await topState(modern);
    const afterUser = await coordinatorTrace();
    assert.ok(
      Math.abs(settledUser.top - scrolledByUser.top) <= 1,
      `user scroll was echoed back as a programmatic position: ${JSON.stringify(scrolledByUser)} -> ${JSON.stringify(settledUser)}`,
    );
    assert.ok((afterUser.userReports ?? 0) > (beforeUser.userReports ?? 0), "user scroll was not reported to the binding");
    assert.equal(afterUser.positions ?? 0, beforeUser.positions ?? 0, "user scroll re-applied a scroll position");

    // A view-aligned lazy list scrolled to its middle stays there. Its spacers were snap targets: the browser moved
    // the scroller to a spacer's edge whenever the window changed, which moved the window again, forever.
    // A fresh page: rows measured by the steps above hid it.
    const fresh = await context.newPage();
    await fresh.goto(base + "/collections", { waitUntil: "domcontentloaded" });
    await fresh.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
    await fresh.waitForTimeout(400);
    const freshModern = fresh.locator(".scroll-view[data-scroll-position='true']:not(.scroll-horizontal)").first();
    await freshModern.evaluate((e) => { e.scrollTop = 800; });
    await fresh.waitForTimeout(600);
    const drift = await freshModern.evaluate((e) => new Promise((resolve) => {
      const tops = [];
      const tick = () => { tops.push(e.scrollTop); if (tops.length < 30) requestAnimationFrame(tick); else resolve(tops); };
      requestAnimationFrame(tick);
    }));
    assert.ok(Math.max(...drift) - Math.min(...drift) <= 2, `a lazy list scrolled to its middle kept moving: ${JSON.stringify(drift)}`);
    await fresh.close();

    // Every way a user moves a scroll surface sets the binding; a programmatic offset does not.
    const settleProgrammatic = async () => {
      await page.getByRole("button", { name: "Scroll to bottom edge", exact: true }).click();
      await page.getByText("Positioned by user: false", { exact: true }).waitFor({ timeout: 4000 });
      await page.waitForTimeout(400);
    };
    await settleProgrammatic();
    const quiet = await coordinatorTrace();
    assert.equal(
      quiet.userReports ?? 0,
      afterUser.userReports ?? 0,
      `programmatic scroll reported as user: ${JSON.stringify(quiet)}`,
    );

    // Keyboard: a key the coordinator scrolls with (PageUp inside the surface). The surface takes focus the way a
    // keyboard user reaches it; key events then target its subtree. The tabindex is this harness's write, not the page's,
    // so the verification is told the harness owns it.
    await modern.evaluate((e) => {
      window.__binaryVerifyDeclare?.(e, ["tabindex"]);
      e.tabIndex = 0;
      e.focus();
    });
    const beforeKey = await coordinatorTrace();
    await page.keyboard.press("PageUp"); // the surface sits at its bottom edge, so there is room to move up
    await page.getByText("Positioned by user: true", { exact: true }).waitFor({ timeout: 4000 });
    assert.ok(
      ((await coordinatorTrace()).userReports ?? 0) > (beforeKey.userReports ?? 0),
      "keyboard scroll was not reported",
    );
    // The declaration covers that element only: a tabindex nobody declared, on another scroll view, is still reported at the
    // next commit (labelled BINARY-EXPECTED: the verification mode is on, and this difference is the point of the check).
    if (await page.evaluate(() => window.__binaryVerify === true)) {
      page.__binaryExpected = true;
      await page.evaluate(() => document.querySelector(".scroll-view.scroll-horizontal").setAttribute("tabindex", "0"));
      await page.getByRole("button", { name: "Scroll to offset 300", exact: true }).click();
      await page.waitForTimeout(300);
      page.__binaryExpected = false;
      const reported = await page.evaluate(() => (window.__binaryVerifyReport?.differences ?? []).some((d) => d.kind === "attribute-extra" && d.name === "tabindex"));
      assert.ok(reported, "a tabindex no one declared was not reported by the verification mode");
      await page.evaluate(() => document.querySelector(".scroll-view.scroll-horizontal").removeAttribute("tabindex"));
    }

    // Touch: a real touch drag where the engine supports CDP input, otherwise synthetic touch events.
    await settleProgrammatic();
    const beforeTouch = await coordinatorTrace();
    await modern.scrollIntoViewIfNeeded();
    await page.waitForTimeout(100);
    box = await modern.boundingBox();
    const touchX = box.x + box.width / 2;
    const touchY = box.y + box.height * 0.25;
    let touchMode;
    try {
      const cdp = await context.newCDPSession(page);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: touchX, y: touchY }] });
      for (let step = 1; step <= 8; step++) {
        await cdp.send("Input.dispatchTouchEvent", {
          type: "touchMove",
          touchPoints: [{ x: touchX, y: touchY + step * 20 }],
        });
        await page.waitForTimeout(16);
      }
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      touchMode = "cdp";
    } catch {
      // Without CDP input, the touch gesture and the scroll it causes are dispatched in the same order a drag produces them.
      await modern.evaluate(async (e) => {
        e.dispatchEvent(new Event("touchstart", { bubbles: true }));
        e.scrollTop -= 160;
        await new Promise((r) => setTimeout(r, 60));
        e.dispatchEvent(new Event("touchend", { bubbles: true }));
      });
      touchMode = "synthetic";
    }
    await page.getByText("Positioned by user: true", { exact: true }).waitFor({ timeout: 4000 });
    const afterTouch = await coordinatorTrace();
    if (!((afterTouch.userReports ?? 0) > (beforeTouch.userReports ?? 0))) {
      throw new Error(
        `touch scroll (${touchMode}) was not reported: before=${JSON.stringify(beforeTouch)} after=${JSON.stringify(afterTouch)} text=${JSON.stringify(await page.getByText("Positioned by user", { exact: false }).allInnerTexts())} top=${JSON.stringify(await topState(modern))}`,
      );
    }

    // RTL: a right-to-left horizontal surface puts leading at its right edge and trailing at its left.
    const rtl = page.locator(".scroll-horizontal[dir='rtl']").first();
    assert.equal(await rtl.count(), 1, "layoutDirection rightToLeft did not reach the scroll view");
    const rtlBox = await rtl.boundingBox();
    await page.getByRole("button", { name: "RTL trailing edge", exact: true }).click();
    await page.waitForTimeout(250);
    const trailingChip = await page.getByText("RTL 20", { exact: true }).boundingBox();
    assert.ok(
      Math.abs(trailingChip.x - rtlBox.x) <= 12,
      `RTL trailing edge is not on the left: chip=${JSON.stringify(trailingChip)} host=${JSON.stringify(rtlBox)}`,
    );
    await page.getByRole("button", { name: "RTL leading edge", exact: true }).click();
    await page.waitForTimeout(250);
    const leadingChip = await page.getByText("RTL 1", { exact: true }).boundingBox();
    assert.ok(
      Math.abs(leadingChip.x + leadingChip.width - (rtlBox.x + rtlBox.width)) <= 12,
      `RTL leading edge is not on the right: chip=${JSON.stringify(leadingChip)} host=${JSON.stringify(rtlBox)}`,
    );
    writeFileSync(
      tracePath,
      JSON.stringify(
        {
          scrollIds: ids,
          bottom,
          restored,
          coordinator: restorationTrace,
        },
        null,
        2,
      ),
    );
    console.log(`PASS Embedded nested/anchor/position/restoration scrolling; trace=${tracePath}`);
  } finally {
    await browser?.close();
    await stop();
  }
});
