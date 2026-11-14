#!/usr/bin/env bun
// The selection tint of Tools/styles.css: the same color on every element as the universal `::selection` it replaced, in
// an engine that inherits highlight styles from the parent (Chromium, WebKit 27; the runtime marks the root) and in one
// that does not (earlier WebKit, where the rule keeps matching every element).
//
// A var() in a universal `::selection` makes Chromium compute a highlight style for every element; on a large production app it
// was about half the style cost of a newly inserted subtree. This test also keeps a new universal `::selection` from bringing it
// back.
//   bun Tools/test-selection-highlight.mjs   (SELECTION_HIGHLIGHT_ENGINES, default "chromium,webkit", picks the engines)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const css = readFileSync(join(ROOT, "Tools/styles.css"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
const runtime = readFileSync(join(ROOT, "Tools/embedded-dom.js"), "utf8");
const probe = /function markHighlightInheritance\(document\) \{[\s\S]*?\n\}\n/.exec(runtime)?.[0];
assert.ok(probe, "embedded-dom.js defines markHighlightInheritance");
assert.match(runtime, /\n  markHighlightInheritance\(document\);\n/, "mountEmbeddedBrowser marks the root");

// The rule, and the universal form it replaced (the reference).
const rule = /([^{}]*::selection[^{}]*)\{([^}]*)\}/g;
const rules = [...css.matchAll(rule)].map((match) => ({ text: match[1], selectors: match[1].split(",").map((s) => s.trim()) }));
assert.equal(rules.length, 1, "styles.css has one ::selection rule");
const [tint] = rules;
const fenced = ":root:not([data-highlight-inheritance]) ::selection";
for (const selector of tint.selectors) {
  assert.ok(selector === fenced || !/(^|[\s>+~])::selection$/.test(selector),
    `'${selector}' would match every element on Chromium too; declare it on the elements that change --color-swu-primary`);
}
const reference = css.replace(tint.text, "\n  ::selection ");

const body = `
  <p id="plain">plain <span id="nested">nested</span></p>
  <div data-tint style="--tint-color: rgb(220 30 30)"><div><span id="tinted">tinted</span></div></div>
  <section data-color-scheme="dark"><div><span id="scheme">dark scheme</span>
    <div data-tint style="--tint-color: rgb(30 160 60)"><b id="tint-in-scheme">tint in dark</b></div></div></section>
  <div class="dark"><i id="dark-class">dark class</i></div>`;
const ids = ["plain", "nested", "tinted", "scheme", "tint-in-scheme", "dark-class"];

await runSuite(async () => {
  for (const engine of (process.env.SELECTION_HIGHLIGHT_ENGINES ?? "chromium,webkit").split(",").filter(Boolean)) {
    const browser = await launch({ engine });
    try {
      const page = await browser.newPage();
      const colors = async (sheet, mark) => {
        await page.setContent(`<style>${sheet}</style>${body}`);
        return page.evaluate(({ probe, ids, mark }) => {
          if (mark) (0, eval)(`(${probe})`)(document);
          return { marked: document.documentElement.hasAttribute("data-highlight-inheritance"),
            colors: ids.map((id) => getComputedStyle(document.getElementById(id), "::selection").backgroundColor) };
        }, { probe, ids, mark });
      };
      const before = await colors(reference, false);
      const after = await colors(css, true);
      const unmarked = await colors(css, false);
      // Chromium inherits highlight styles; WebKit does from version 27. Either way the tint must not change.
      if (engine === "chromium") assert.equal(after.marked, true, "chromium: the probe finds that highlight styles inherit");
      assert.ok(new Set(before.colors).size >= 4, `${engine}: the fixture exercises different tints (${before.colors})`);
      assert.deepEqual(after.colors, before.colors, `${engine}: the selection tint is unchanged on every element`);
      assert.deepEqual(unmarked.colors, before.colors, `${engine}: before the runtime marks the root the tint is unchanged`);
      console.log(`PASS selection highlight ${engine}: ${ids.length} elements keep their tint (inheritance ${after.marked ? "on" : "off"})`);
    } finally {
      await browser.close();
    }
  }
});
