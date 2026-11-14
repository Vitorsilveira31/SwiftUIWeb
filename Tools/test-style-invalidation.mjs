#!/usr/bin/env bun
// What a :has() in Tools/styles.css costs a commit, and that the rewrites made to cut it match the same elements.
//
// A selector whose last compound has nothing to hold on to (`> :only-child`, `> :not(.x)`, `*`) and whose ancestor carries a
// :has() makes the browser invalidate the whole subtree of that ancestor every time the :has() may have changed: any insertion
// below it. In a large production app two such selectors were most of the style recalculation of a commit (about 40% of the
// elements restyled by the DOM patch and by the icon adapter). The :has() belongs on the element the rule styles, or the rule
// is written with sibling combinators; this test keeps new rules from bringing the cost back and proves the two rewritten rules
// equal to the selectors they replaced on random trees.
//   bun Tools/test-style-invalidation.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const css = readFileSync(process.env.STYLES_CSS ?? join(ROOT, "Tools/styles.css"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");

/** Splits a selector list at its top-level commas. */
function splitList(text) {
  const out = []; let depth = 0, current = "", quote = null;
  for (const char of text) {
    if (quote) { current += char; if (char === quote) quote = null; continue; }
    if (char === '"' || char === "'") { quote = char; current += char; continue; }
    if ("([".includes(char)) depth++;
    if (")]".includes(char)) depth--;
    if (char === "," && depth === 0) { out.push(current.trim()); current = ""; } else current += char;
  }
  if (current.trim()) out.push(current.trim());
  return out;
}

/** The compounds of a complex selector, left to right, split at the combinators outside any bracket. */
function compounds(selector) {
  const out = []; let depth = 0, current = "";
  for (const char of selector) {
    if ("([".includes(char)) depth++;
    if (")]".includes(char)) depth--;
    if (depth === 0 && (char === " " || char === ">" || char === "+" || char === "~")) { if (current) out.push(current); current = ""; } else current += char;
  }
  if (current) out.push(current);
  return out;
}

/** Selector lists of the style rules, at any depth of @media, @supports, @container and @layer blocks. */
function styleSelectors(source) {
  const out = []; let i = 0;
  const readBlock = (from) => { let depth = 0; for (let j = from; j < source.length; j++) { if (source[j] === "{") depth++; else if (source[j] === "}" && --depth === 0) return j; } return source.length; };
  const walk = (start, end) => {
    let position = start;
    while (position < end) {
      const open = source.indexOf("{", position);
      if (open < 0 || open >= end) return;
      const prelude = source.slice(position, open).trim();
      const close = readBlock(open);
      if (prelude.startsWith("@")) { if (/^@(media|supports|container|layer)/.test(prelude)) walk(open + 1, close); }
      else out.push(...splitList(prelude));
      position = close + 1;
    }
  };
  walk(0, source.length);
  return out;
}

// An element is held by a class, a tag, an id or an attribute written outside any :not()/:is()/:where() argument.
const holdsOn = (compound) => /^[a-z]|[.#]|\[/i.test(compound.replace(/:[a-z-]+\((?:[^()]|\([^()]*\))*\)/gi, ""));

const selectors = styleSelectors(css);
const offenders = selectors.filter((selector) => {
  const parts = compounds(selector.replace(/::[a-z-]+$/i, ""));
  const subject = parts[parts.length - 1];
  return parts.length > 1 && parts.slice(0, -1).some((part) => part.includes(":has(")) && !holdsOn(subject);
});
assert.ok(selectors.length > 1000 && selectors.some((selector) => selector.includes(":has(")), `the parser found the stylesheet's selectors (${selectors.length})`);
assert.deepEqual(offenders, [], "a :has() on an ancestor of a selector with nothing to hold on to invalidates the whole subtree on every change below it; put the :has() on the element the rule styles");

// The selectors the rewrites replaced and what they are now, in the stylesheet and here.
const PAIRS = [
  { old: '.frame-box:has([data-flexible-width="true"]) > :only-child', now: '.frame-box > :only-child:is([data-flexible-width="true"], :has([data-flexible-width="true"]))' },
  { old: ".navigation-stack > .toolbar-item .icon-label:has(> .symbol-icon) > :not(.symbol-icon)",
    now: ".navigation-stack > .toolbar-item .icon-label > .symbol-icon ~ :not(.symbol-icon), .navigation-stack > .toolbar-item .icon-label > :not(.symbol-icon):has(~ .symbol-icon)" },
];
const compact = css.replace(/\s+/g, " ");
for (const { now } of PAIRS) for (const selector of splitList(now)) assert.ok(compact.includes(selector), `styles.css has the rule ${selector}`);
for (const { old } of PAIRS) assert.ok(!compact.includes(old), `styles.css no longer has ${old}`);

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage();
    await page.setContent("<!doctype html><html><body></body></html>");
    const result = await page.evaluate((pairs) => {
      // Small deterministic generator, so a failure reproduces.
      let seed = 20260716; const random = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32;
      const classes = ["frame-box", "padding-box", "vstack", "hstack", "icon-label", "symbol-icon", "toolbar-item", "navigation-stack", "text"];
      const build = (depth) => {
        const element = document.createElement(random() < 0.2 ? "span" : "div");
        element.className = classes[Math.floor(random() * classes.length)] + (random() < 0.2 ? " " + classes[Math.floor(random() * classes.length)] : "");
        if (random() < 0.18) element.setAttribute("data-flexible-width", "true");
        else if (random() < 0.05) element.setAttribute("data-flexible-width", "false");
        const children = depth > 5 ? 0 : Math.floor(random() * (depth < 2 ? 4 : 3.2));
        for (let child = 0; child < children; child++) { element.append(build(depth + 1)); if (random() < 0.1) element.append(document.createTextNode(" ")); }
        return element;
      };
      let compared = 0, matched = [0, 0], mismatches = [];
      for (let tree = 0; tree < 2000; tree++) {
        const root = build(0);
        // Wrap in a toolbar so the icon-label rule can match too.
        const bar = document.createElement("div"); bar.className = "navigation-stack"; const item = document.createElement("div"); item.className = "toolbar-item"; item.append(root); bar.append(item);
        document.body.replaceChildren(bar);
        for (const [index, { old, now }] of pairs.entries()) {
          const before = new Set(document.querySelectorAll(old)), after = new Set(document.querySelectorAll(now));
          compared++; matched[index] += before.size;
          if (before.size !== after.size || [...before].some((element) => !after.has(element))) mismatches.push({ tree, old, before: before.size, after: after.size });
        }
      }
      return { compared, matched, mismatches: mismatches.slice(0, 3) };
    }, PAIRS);
    assert.deepEqual(result.mismatches, [], "the rewritten selectors match the same elements as the ones they replaced");
    assert.ok(result.matched.every((count) => count > 300), `the random trees exercise both selectors (${result.matched} matches)`);
    console.log(`PASS style invalidation: ${selectors.length} selectors checked, ${result.compared} tree comparisons equal (${result.matched.join(" and ")} matches)`);
  } finally {
    await browser.close();
  }
});
