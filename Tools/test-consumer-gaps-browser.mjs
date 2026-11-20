#!/usr/bin/env bun
// Chromium test of the chrome a view asks of its surroundings (consumer gaps).
//
// Drives Tests/Apps/EmbeddedLoweringConformanceApp/EmbeddedChromeFixture.swift through the real Embedded Swift
// + JavaScript host bundle built by `BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh lowering`:
//
// - a VideoPlayer fills a flexible 430x844 frame, keeps its label, and its <video> element survives a resize;
// - a pushed screen draws no back button on the web (the browser's back pops it); one with toolbar(.hidden, for:
//   .tabBar) shows no tab bar, and one without keeps it; a tab built when its button is pressed shows that screen in
//   the frame the bar goes, not one before;
// - two toolbar(_:for:) modifiers on one screen merge: toolbar(.hidden, for: .navigationBar) and toolbar(.hidden, for:
//   .tabBar) together hide both bars;
// - EmbeddedNavigationBarFixture: an inline title is centred between the back button and a trailing item (its
//   inset clears both), a large title sits below the bar row, a hidden bar reserves no space, and a pushed Text smaller
//   than the screen is centred in it, as SwiftUI centres it.
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

// Reads the navigation bar geometry of the pushed screen, and how far the centre of its `detail` text is from the screen's.
// Every animation of the page has finished (a push's fade and rise), so the boxes are where they land.
const SETTLED = "Promise.all(document.getAnimations().map((animation) => animation.finished.catch(() => null))).then(() => true)";
const MEASURE = `(detail) => {
  const main = document.querySelector('main.navigation-stack');
  const mr = main.getBoundingClientRect();
  const style = getComputedStyle(main, '::before');
  const back = [...document.querySelectorAll('[aria-label="Back"]')].find(e => e.offsetParent !== null);
  const trailing = main.querySelector(':scope > .toolbar-item[data-toolbar-placement="navigation-bar-trailing"]');
  const destination = main.querySelector(':scope > .navigation-destination:not([data-navigation-inactive])');
  return {
    padLeft: parseFloat(style.paddingLeft), padRight: parseFloat(style.paddingRight),
    padTop: parseFloat(style.paddingTop), before: style.display, textAlign: style.textAlign,
    backRight: back ? back.getBoundingClientRect().right - mr.left : null,
    backBottom: back ? back.getBoundingClientRect().bottom - mr.top : null,
    trailingWidth: trailing ? trailing.getBoundingClientRect().width : 0,
    destinationTop: destination ? destination.getBoundingClientRect().top - mr.top : null,
    detailOffset: (() => {
      const text = destination && [...destination.querySelectorAll('*')].find(e => e.children.length === 0 && e.textContent === detail);
      if (!text) return null;
      const d = destination.getBoundingClientRect(), t = text.getBoundingClientRect();
      return { x: t.left + t.width / 2 - (d.left + d.width / 2), y: t.top + t.height / 2 - (d.top + d.height / 2) };
    })(),
  };
}`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    port: { type: "string", default: "0" },
  },
});

await runSuite(async () => {
  const bundle = resolve(positionals[0] ?? ".build/browser/EmbeddedLoweringConformanceApp");
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) {
    throw new Error(`Embedded chrome fixture bundle is missing: ${bundle}`);
  }

  const server = await serveDirectory(bundle, Number(values.port));
  const checks = [];
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.port}/`, { waitUntil: "networkidle" });
    await page.getByRole("button", { name: "Open chrome fixture", exact: true }).click();
    await page.setViewportSize({ width: 430, height: 844 });
    const player = page.locator(".avkit-video-player").first();
    await player.waitFor({ timeout: 10_000 });

    const check = (name, condition, detail = "") => {
      if (errors.length) throw new Error("browser runtime errors: " + errors.join("; "));
      if (!condition) throw new Error(`${name} failed ${detail}`);
      checks.push(name);
    };

    const box = await player.boundingBox();
    check(
      "VideoPlayer fills a 430x844 flexible frame instead of its 150pt default",
      box !== null && box.height >= 600 && box.width >= 400,
      `box=${JSON.stringify(box)}`,
    );
    check(
      'VideoPlayer container and <video> carry accessibilityLabel("Trailer")',
      (await page.locator('.avkit-video-player[aria-label="Trailer"]').count()) === 1 &&
        (await page.locator('video[aria-label="Trailer"]').count()) === 1,
    );

    await page.evaluate(() => {
      window.__chromeVideo = document.querySelector(".avkit-video-player video");
    });
    await page.setViewportSize({ width: 500, height: 700 });
    await page.waitForTimeout(200);
    const resized = await player.boundingBox();
    const same = await page.evaluate(
      () =>
        window.__chromeVideo &&
        window.__chromeVideo.isConnected &&
        document.querySelector(".avkit-video-player video") === window.__chromeVideo,
    );
    check(
      "VideoPlayer follows a GeometryReader resize without remounting its <video>",
      Boolean(same),
      `box=${JSON.stringify(resized)}`,
    );
    check(
      "VideoPlayer keeps filling the frame after the resize",
      resized !== null && resized.width >= 450 && resized.height >= 500,
      `box=${JSON.stringify(resized)}`,
    );
    await page.setViewportSize({ width: 430, height: 844 });

    await page.getByRole("tab", { name: "Shown bar", exact: true }).click();
    await page.getByText("Default back and tab bar", { exact: true }).waitFor({ timeout: 10_000 });
    check(
      "a pushed screen draws no back button on the web: the browser's back pops it",
      (await page.locator('[aria-label="Back"]:visible').count()) === 0,
    );
    check("...and the tab bar", (await page.locator(".tab-list:visible").count()) === 1);

    // The tab is built hidden when its button goes down (`tabPrepare`): every frame from the press shows either the
    // tab left behind with the bar, or the pushed screen without it, never the pushed screen with the bar.
    await page.evaluate(() => {
      window.__hiddenBarFrames = [];
      const sample = () => {
        const shown = [...document.querySelectorAll('[data-tab-panel="true"][data-tab-hidden="false"]')]
          .some((panel) => panel.textContent.includes("Own back and tab bar"));
        window.__hiddenBarFrames.push({ shown, bar: document.querySelectorAll(".tab-list").length > 0 });
        if (window.__hiddenBarFrames.length < 30) requestAnimationFrame(sample);
      };
      document.addEventListener("pointerdown", () => requestAnimationFrame(sample), { once: true, capture: true });
    });
    await page.getByRole("tab", { name: "Hidden bar", exact: true }).click();
    await page.getByText("Own back and tab bar", { exact: true }).waitFor({ timeout: 10_000 });
    await page.waitForFunction(() => window.__hiddenBarFrames.length >= 30);
    const hiddenBarFrames = await page.evaluate(() => window.__hiddenBarFrames);
    check(
      "a tab built when its button is pressed never shows its pushed screen together with the tab bar it hides",
      hiddenBarFrames.some((frame) => frame.shown) && !hiddenBarFrames.some((frame) => frame.shown && frame.bar),
      `frames=${JSON.stringify(hiddenBarFrames)}`,
    );
    check(
      "a pushed screen with navigationBarBackButtonHidden(true) has no back button either",
      (await page.locator('[aria-label="Back"]:visible').count()) === 0,
    );
    check(
      "toolbar(.hidden, for: .tabBar) hides the tab bar while the pushed screen is on screen",
      (await page.locator(".tab-list").count()) === 0,
    );

    const openFixture = async (button) => {
      await page.setViewportSize({ width: 1000, height: 900 });
      await page.goto(`http://127.0.0.1:${server.port}/`, { waitUntil: "networkidle" });
      await page.getByRole("button", { name: button, exact: true }).click();
      await page.setViewportSize({ width: 430, height: 844 });
    };

    // Two toolbar(_:for:) modifiers on one screen: the second placement does not erase the first.
    await openFixture("Open chrome fixture");
    await page.getByRole("tab", { name: "Merged bars", exact: true }).click();
    await page.getByText("Merged detail", { exact: true }).waitFor({ timeout: 10_000 });
    check(
      "toolbar(.hidden, for: .navigationBar) and toolbar(.hidden, for: .tabBar) on one screen hide both bars",
      (await page.locator('[aria-label="Back"]:visible').count()) === 0 &&
        (await page.locator(".tab-list").count()) === 0,
    );

    // Navigation bar layout: title inset, large title row, hidden bar.
    await openFixture("Open navigation bar fixture");
    await page.getByRole("link", { name: "Inline title", exact: true }).click();
    await page.getByText("Inline detail", { exact: true }).waitFor({ timeout: 10_000 });
    // Under a mouse a push fades the new page in, rising 12 px over 280 ms (#65): it is measured where it lands.
    await page.evaluate(SETTLED);
    const inline = await page.evaluate(`(${MEASURE})("Inline detail")`);
    check(
      "an inline title is centred and inset clear of the trailing item",
      inline.textAlign === "center" &&
        inline.padLeft >= (inline.backRight ?? 0) &&
        inline.padRight >= inline.trailingWidth && inline.trailingWidth > 0,
      `measure=${JSON.stringify(inline)}`,
    );
    check(
      "a pushed Text smaller than the screen is centred in it",
      inline.detailOffset !== null && Math.abs(inline.detailOffset.x) <= 1 && Math.abs(inline.detailOffset.y) <= 1,
      `measure=${JSON.stringify(inline)}`,
    );
    await openFixture("Open navigation bar fixture");
    await page.getByRole("link", { name: "Large title", exact: true }).click();
    await page.getByText("Large detail", { exact: true }).waitFor({ timeout: 10_000 });
    await page.evaluate(SETTLED);
    const large = await page.evaluate(`(${MEASURE})()`);
    // As iPadOS draws it (#87): the bar's 48-point row on top, even with no items in it, the 34-point title below it in
    // a bar at least 104 points tall, and the screen below the bar.
    check(
      "a large title sits below the bar's row, as on iPadOS, and the screen below it",
      large.backBottom === null && large.padTop === 48 && large.destinationTop >= 104,
      `measure=${JSON.stringify(large)}`,
    );
    await openFixture("Open navigation bar fixture");
    await page.getByRole("link", { name: "Hidden bar", exact: true }).click();
    await page.getByText("Hidden detail", { exact: true }).waitFor({ timeout: 10_000 });
    await page.evaluate(SETTLED);
    const hidden = await page.evaluate(`(${MEASURE})()`);
    check(
      "a hidden navigation bar draws no title and reserves no space",
      hidden.before === "none" && hidden.destinationTop === 0,
      `measure=${JSON.stringify(hidden)}`,
    );
    if (errors.length) throw new Error("browser runtime errors: " + errors.join("; "));
  } finally {
    await browser?.close();
    await server.close();
  }
  for (const name of checks) console.log(`PASS ${name}`);
  console.log(`consumer-gaps browser test: ${checks.length} checks passed`);
});
