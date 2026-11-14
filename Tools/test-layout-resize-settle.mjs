// A window resize must not be animated. An element can carry an inline CSS transition (the page holds one while an `.animation` value change runs), so
// the width a resize step gives it would animate for the modifier's duration, and every frame of that
// animation reports new sizes to Swift, which renders and runs a layout pass again (measured on a large production app:
// 34 to 56 commits for one 20 px step). SemanticLayoutHost marks the document element while a resize settles and
// styles.css turns transitions off under that mark.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { RESIZE_SETTLE_MS, RESIZING_ATTRIBUTE, SemanticLayoutHost } from "./layout-host.js";
import { bundleResizeTransitionRule, collectTransitionSelectors, resizeTransitionRule } from "./scope-resize-transitions.mjs";

function host() {
  const attributes = new Set();
  const timers = new Map();
  let nextTimer = 1;
  const documentElement = {
    hasAttribute: (name) => attributes.has(name),
    setAttribute: (name) => attributes.add(name),
    removeAttribute: (name) => attributes.delete(name),
  };
  const window = {
    setTimeout: (callback, delay) => { timers.set(nextTimer, { callback, delay }); return nextTimer++; },
    clearTimeout: (id) => timers.delete(id),
  };
  const instance = Object.create(SemanticLayoutHost.prototype);
  Object.assign(instance, { window, document: { documentElement }, disposed: false });
  return { layout: instance, attributes, timers };
}

// markResize marks the document element, remembers when, and removes the mark once the settle time has passed.
{
  const { layout, attributes, timers } = host();
  layout.markResize();
  assert.ok(attributes.has(RESIZING_ATTRIBUTE), "a resize marks the document element");
  assert.equal(typeof layout.resizedAt, "number");
  assert.equal(timers.size, 1);
  const [timer] = timers.values();
  assert.equal(timer.delay, RESIZE_SETTLE_MS);
  timer.callback();
  assert.ok(!attributes.has(RESIZING_ATTRIBUTE), "the mark is removed when the resize has settled");
}

// Further resize steps keep one pending timer, so the mark lasts until RESIZE_SETTLE_MS after the last step.
{
  const { layout, attributes, timers } = host();
  layout.markResize();
  layout.markResize();
  layout.markResize();
  assert.equal(timers.size, 1, "each step replaces the pending timer instead of stacking another");
  assert.ok(attributes.has(RESIZING_ATTRIBUTE));
}

// A host disposed before the timer fires leaves the document element alone.
{
  const { layout, attributes, timers } = host();
  layout.markResize();
  layout.disposed = true;
  attributes.add(RESIZING_ATTRIBUTE);
  [...timers.values()][0].callback();
  assert.ok(attributes.has(RESIZING_ATTRIBUTE), "the timer of a disposed host does nothing");
}

// The settle time is short enough not to be noticed and long enough to cover the frames of a resize step.
assert.ok(RESIZE_SETTLE_MS >= 100 && RESIZE_SETTLE_MS <= 500, `RESIZE_SETTLE_MS is ${RESIZE_SETTLE_MS}`);

// The resize rule is generated for the bundle from the stylesheets it ships (Tools/scope-resize-transitions.mjs): the source
// stylesheet has no universal rule any more, and the generated one names the transitions it declares, never every element.

{
  const css = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "styles.css"), "utf8");
  const compact = css.replace(/\s+/g, " ");
  assert.ok(!compact.includes(`[${RESIZING_ATTRIBUTE}] *`), "styles.css has no universal resize rule: the bundle generates a scoped one");
  const { rule, fallback, selectors } = bundleResizeTransitionRule([css]);
  assert.equal(fallback, false, "the framework stylesheet can be read");
  assert.ok(selectors > 0, "the framework stylesheet declares transitions");
  assert.ok(rule.includes(`[${RESIZING_ATTRIBUTE}] :where([data-animation], [data-layout-animation], [style*="transition"], `), "the scoped rule names the armed and inline transitions");
  assert.match(rule, new RegExp(`\\[${RESIZING_ATTRIBUTE}\\] :where\\(.progress-bar\\)::-webkit-progress-value \\{ transition: none !important; \\}`), "pseudo-element transitions are held off too");
  assert.doesNotMatch(rule, /:where\(\*|, \*[,)]/, "the scoped rule names no bare universal selector");
  assert.match(rule, /\{ transition: none !important; \}/, "the rule removes transitions and wins over an inline one");
}

// Selectors come from style rules that declare a transition (also inside @media), with pseudo-elements and attribute values kept whole.
{
  const css = `a{transition:none} .btn:hover, .x::before {transition: color 1s} @media (x){ input::-webkit-slider-thumb{transition-duration:1s} } @keyframes k { from{transition:none} } [data-q="a,b"] { transition-property: opacity } .plain { color: red }`;
  assert.deepEqual(collectTransitionSelectors(css), [".btn:hover", ".x::before", "input::-webkit-slider-thumb", '[data-q="a,b"]']);
  // A transition that is none, or under a millisecond (the reduced-motion rules), starts nothing visible and names no element.
  assert.deepEqual(collectTransitionSelectors("a{transition:none} b{transition-duration:0.01ms} c{transition:color 0s} *{transition-duration:0.01ms !important}"), []);
  const rule = resizeTransitionRule(collectTransitionSelectors(css));
  assert.ok(!rule.includes(".plain"), "an element without a transition is not matched");
  assert.ok(rule.includes(`[${RESIZING_ATTRIBUTE}] :where(.x)::before`));
  assert.ok(rule.includes(`[${RESIZING_ATTRIBUTE}] :where(input)::-webkit-slider-thumb`));
}

// A stylesheet that cannot be read falls back to the universal rule rather than leaving transitions running.
{
  const broken = bundleResizeTransitionRule(["a { transition: none; } b { transition: color 1s; "]);
  assert.equal(broken.fallback, true);
  assert.ok(broken.rule.includes(`[${RESIZING_ATTRIBUTE}] *, `));
}

// Nothing declared, nothing to scope beyond the runtime markers: the rule still names them, so it is never empty for a bundle.
{
  const { rule, selectors } = bundleResizeTransitionRule([".a { color: red }"]);
  assert.equal(selectors, 0);
  assert.ok(rule.includes("[data-animation]"));
}

console.log("layout resize settle: ok");
