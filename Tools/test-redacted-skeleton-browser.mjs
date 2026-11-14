#!/usr/bin/env bun
// `.redacted(reason: .placeholder)` paints a skeleton: text is transparent over a neutral bar, shapes and pictures are neutral
// blocks, controls stay inert, and the bar pulses unless the user prefers reduced motion. `.unredacted()` ends the rules, and
// `.redacted(reason: .privacy)` blurs. The page is a fixture with the markup the renderer emits for those modifiers (the Swift
// side is checked by CoreRuntimeFeatureContractTests); the stylesheet is Tools/styles.css itself.
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default).
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { engineName, launch, ROOT, runSuite } from "./browser-test-support.mjs";

const STYLES = await readFile(join(ROOT, "Tools/styles.css"), "utf8");
const TINY_GIF = "data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==";
const TRANSPARENT = "rgba(0, 0, 0, 0)";

const PAGE = `<!doctype html>
<html><head><meta charset="utf-8"><style>${STYLES}</style></head>
<body>
  <p><span id="control">Control text</span></p>
  <main id="skeleton" class="redacted redacted-placeholder" data-redaction-reasons="1" aria-busy="true">
    <h2 id="title">Quarterly revenue</h2>
    <p><span id="body">Confidential figures for the board</span></p>
    <div id="shape" data-shape="rectangle" style="width: 120px; height: 24px; background-color: rgb(255, 0, 0)"></div>
    <img id="picture" alt="" src="${TINY_GIF}" width="48" height="48">
    <button id="pay" type="button">Pay now</button>
    <div id="public" class="unredacted"><span id="public-text">Public note</span></div>
  </main>
  <main id="private" class="redacted redacted-privacy" data-redaction-reasons="2"><span id="private-text">Card 4242</span></main>
</body></html>`;

/** Computed style and box of one fixture element, read in the page. */
function inspect(page, id) {
  return page.evaluate((id) => {
    const element = document.getElementById(id);
    const style = getComputedStyle(element);
    const box = element.getBoundingClientRect();
    return {
      color: style.color,
      background: style.backgroundColor,
      radius: style.borderRadius,
      animation: style.animationName,
      filter: style.filter,
      pointerEvents: style.pointerEvents,
      width: box.width,
      height: box.height,
    };
  }, id);
}

async function openFixture(browser, { reducedMotion = "no-preference" } = {}) {
  const page = await (await browser.newContext({ viewport: { width: 800, height: 600 } })).newPage();
  await page.emulateMedia({ reducedMotion });
  const problems = [];
  page.on("pageerror", (error) => problems.push(String(error)));
  await page.setContent(PAGE, { waitUntil: "load" });
  await page.waitForFunction(() => document.getElementById("picture").complete);
  return { page, problems };
}

async function main() {
  const label = engineName();
  const browser = await launch();
  try {
    const { page, problems } = await openFixture(browser);

    // The text is not readable: transparent, and it keeps a box with a neutral background behind it.
    const title = await inspect(page, "title");
    assert.equal(title.color, TRANSPARENT, `${label}: the title text is transparent`);
    assert.ok(title.width > 0 && title.height > 0, `${label}: the title bar has a box (${title.width}x${title.height})`);
    assert.notEqual(title.background, TRANSPARENT, `${label}: the title sits on a neutral bar`);
    assert.notEqual(title.radius, "0px", `${label}: the bar is rounded`);
    const body = await inspect(page, "body");
    assert.equal(body.color, TRANSPARENT, `${label}: text inside a paragraph is transparent too`);
    assert.ok(body.width > 0 && body.height > 0, `${label}: that bar has a box`);

    // Shapes and pictures become flat neutral blocks; the picture keeps its box.
    const shape = await inspect(page, "shape");
    assert.ok(shape.width > 0 && shape.height > 0, `${label}: the shape keeps its size`);
    assert.notEqual(shape.filter, "none", `${label}: the shape is flattened to a neutral block`);
    const picture = await inspect(page, "picture");
    assert.notEqual(picture.filter, "none", `${label}: the picture is flattened to a neutral block`);

    // Controls stay inert under the skeleton.
    assert.equal((await inspect(page, "pay")).pointerEvents, "none", `${label}: a button under the skeleton does not take pointer events`);

    // The bar pulses on the compositor (opacity) and stops for reduced motion.
    assert.equal(title.animation, "swu-redaction-pulse", `${label}: the bar pulses`);
    assert.equal(shape.animation, "swu-redaction-pulse", `${label}: a block pulses`);

    // `.unredacted()` subtree: its text is the same as the same text outside any redaction.
    const publicText = await inspect(page, "public-text");
    const control = await inspect(page, "control");
    assert.equal(publicText.color, control.color, `${label}: the unredacted text keeps its colour`);
    assert.notEqual(publicText.color, TRANSPARENT, `${label}: the unredacted text is not transparent`);
    assert.equal(publicText.animation, "none", `${label}: the unredacted text does not pulse`);
    assert.equal(publicText.pointerEvents, "auto", `${label}: the unredacted text takes pointer events`);

    // Privacy blurs its subtree and keeps the text.
    const privateText = await inspect(page, "private-text");
    assert.notEqual(privateText.color, TRANSPARENT, `${label}: privacy alone keeps the text`);
    assert.equal((await inspect(page, "private")).filter, "blur(5px)", `${label}: privacy blurs`);

    // Accessibility: the subtree stays busy and its text stays in the DOM for assistive technology.
    assert.equal(await page.getAttribute("#skeleton", "aria-busy"), "true", `${label}: the skeleton is announced as busy`);
    assert.equal(await page.textContent("#title"), "Quarterly revenue", `${label}: the text stays in the DOM`);

    assert.deepEqual(problems, [], `${label}: no page errors`);
    console.log(`PASS ${label}: placeholder text is a bar, blocks pulse, unredacted text is normal, privacy blurs`);

    const quiet = await openFixture(browser, { reducedMotion: "reduce" });
    const stillTitle = await inspect(quiet.page, "title");
    assert.equal(stillTitle.animation, "none", `${label}: reduced motion stops the pulse`);
    assert.equal(stillTitle.color, TRANSPARENT, `${label}: reduced motion keeps the skeleton`);
    assert.equal((await inspect(quiet.page, "shape")).animation, "none", `${label}: reduced motion stops the block pulse`);
    assert.deepEqual(quiet.problems, [], `${label}: no page errors with reduced motion`);
    console.log(`PASS ${label} reduced motion: the skeleton is still drawn and does not pulse`);
  } finally {
    await browser.close();
  }
}

await runSuite(main);
