#!/usr/bin/env bun
// The generated resize rule in a browser: while the layout host holds data-layout-resizing on the document element, every element
// that declares a visible transition computes a zero duration (an armed `.animation` transition, an inline `.transition`, a
// stylesheet transition of the framework and one of the application's own CSS), and the transitions come back once the
// attribute is removed. The rule matches no element without a transition.
//
// The fixture bundle is built with the two steps the bundle script runs (build-styles, then scope-resize-transitions).
//
//   SWIFTUIWEB_BROWSER_ENGINE=chromium bun Tools/test-resize-transition-browser.mjs
//   SWIFTUIWEB_BROWSER_ENGINE=webkit bun Tools/test-resize-transition-browser.mjs
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { engineName, launch, runSuite, serveStatic } from "./browser-test-support.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const BUNDLE = resolve(ROOT, ".build/resize-transition-browser");
const TRANSITIONING = ["armed", "armed-child", "inline", "sheet"];

const APP_CSS = `.fixture-button { transition: background-color 1s ease; }
.fixture-plain { color: rgb(1, 2, 3); }
`;

const INDEX_HTML = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <link rel="stylesheet" href="styles.css">
  <link rel="stylesheet" href="app.css">
</head>
<body>
  <div id="armed" data-animation="ease" style="transition: width 1s ease">armed</div>
  <div id="armed-child" data-layout-animation style="transition: width 1s ease">armed child</div>
  <div id="inline" data-transition="opacity" style="transition: opacity 180ms ease">inline</div>
  <button id="sheet" class="fixture-button">stylesheet</button>
  <div id="plain" class="fixture-plain">plain</div>
</body>
</html>
`;

/** Builds the fixture bundle the way the bundle script does: the framework stylesheet, then the resize rule of every stylesheet. */
function buildBundle() {
  rmSync(BUNDLE, { recursive: true, force: true });
  mkdirSync(BUNDLE, { recursive: true });
  execFileSync("bun", ["Tools/build-styles.mjs", join(BUNDLE, "styles.css")], { cwd: ROOT, stdio: "pipe" });
  writeFileSync(join(BUNDLE, "app.css"), APP_CSS);
  writeFileSync(join(BUNDLE, "index.html"), INDEX_HTML);
  execFileSync("bun", ["Tools/scope-resize-transitions.mjs", BUNDLE], { cwd: ROOT, stdio: "pipe" });
}

/** The ids (or tag names) of the elements that declare a visible transition: a duration of a millisecond or more. */
const visibleTransitions = () => {
  const millis = (text) => text.split(",").map((part) => part.trim()).map((part) => (part.endsWith("ms") ? parseFloat(part) : parseFloat(part) * 1000));
  return [...document.body.querySelectorAll("*")]
    .filter((element) => {
      const style = getComputedStyle(element);
      return style.transitionProperty !== "none" && millis(style.transitionDuration).some((duration) => duration >= 1);
    })
    .map((element) => element.id || element.tagName.toLowerCase());
};

/** The stylesheet rules of the generated resize rule, and the elements each one matches while the attribute is set. */
const resizeRules = () => {
  const rules = [...document.styleSheets]
    .flatMap((sheet) => [...sheet.cssRules])
    .filter((rule) => rule.selectorText?.startsWith("[data-layout-resizing]"));
  document.documentElement.setAttribute("data-layout-resizing", "");
  const matched = rules.flatMap((rule) => [...document.querySelectorAll(rule.selectorText)].map((element) => element.id || element.tagName.toLowerCase()));
  document.documentElement.removeAttribute("data-layout-resizing");
  return { selectors: rules.map((rule) => rule.selectorText), matched: [...new Set(matched)] };
};

/** Sets or removes the attribute the layout host holds while a resize settles. */
const setResizing = (on) => {
  if (on) document.documentElement.setAttribute("data-layout-resizing", "");
  else document.documentElement.removeAttribute("data-layout-resizing");
};

/** Computed transition durations of the given ids, in the page as it is now. */
const durationsOf = (ids) => Object.fromEntries(ids.map((id) => [id, getComputedStyle(document.getElementById(id)).transitionDuration]));

await runSuite(async () => {
  const engine = engineName();
  buildBundle();
  const server = serveStatic(BUNDLE);
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    await page.goto(`${server.base}/index.html`, { waitUntil: "load" });

    const before = await page.evaluate(visibleTransitions);
    for (const id of TRANSITIONING) assert.ok(before.includes(id), `${engine}: ${id} declares a visible transition`);
    assert.ok(!before.includes("plain"), `${engine}: the plain element declares no transition`);

    // The rule names selectors only (no universal one), matches the transitioning elements and not the plain one.
    const rules = await page.evaluate(resizeRules);
    assert.ok(rules.selectors.length >= 2, `${engine}: the generated rule is in the stylesheet`);
    for (const selector of rules.selectors) assert.doesNotMatch(selector, /(^|[\s(,])\*/, `${engine}: no universal selector in ${selector}`);
    for (const id of TRANSITIONING) assert.ok(rules.matched.includes(id), `${engine}: the rule matches ${id}`);
    assert.ok(!rules.matched.includes("plain"), `${engine}: the rule does not match an element without a transition`);
    assert.ok(!rules.matched.includes("body"), `${engine}: the rule does not match the body`);

    // During a resize every transition computes a zero duration.
    await page.evaluate(setResizing, true);
    const resizingVisible = await page.evaluate(visibleTransitions);
    const resizingDurations = await page.evaluate(durationsOf, TRANSITIONING);
    await page.evaluate(setResizing, false);
    assert.deepEqual(resizingVisible, [], `${engine}: no element keeps a visible transition during a resize`);
    for (const id of TRANSITIONING) {
      assert.equal(parseFloat(resizingDurations[id]), 0, `${engine}: ${id} computes a zero duration during a resize (${resizingDurations[id]})`);
    }

    // Once the resize has settled the transitions are back.
    const settled = await page.evaluate(visibleTransitions);
    for (const id of TRANSITIONING) assert.ok(settled.includes(id), `${engine}: ${id} keeps its transition once the resize has settled`);
    console.log(`resize transition rule (${engine}): ok`);
  } finally {
    await browser.close();
    await server.stop();
  }
});
