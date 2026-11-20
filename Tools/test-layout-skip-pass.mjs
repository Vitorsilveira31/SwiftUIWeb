// A commit whose patch wrote nothing the layout reads still scanned the page for semantic roots: 3 to 6 ms on a large app
// screen. SemanticLayoutHost.update returns early when nothing asked for a pass and nothing changed since the last completed
// one. This checks each thing that must make it run anyway.
import assert from "node:assert/strict";
import { SemanticLayoutHost } from "./layout-host.js";

function host() {
  const window = { cancelAnimationFrame() {} };
  const layout = Object.create(SemanticLayoutHost.prototype);
  Object.assign(layout, {
    // The window root.
    root: { querySelector: () => null },
    window, disposed: false, updating: false, updateRequested: false, scheduled: 0,
    metrics: { passes: 0, passesSkipped: 0, unlaid: 0 }, unlaid: new Set(),
    changed: false, windowResized: false, epoch: 2, resizedAt: 10,
    css: { pending: new Set(), layouts: new Set(), released: [], flush() {}, islandOf: () => null },
    mutations: { takeRecords: () => [] },
    // A touch screen's page scroll view (document-scroll.js): no window here hands one over.
    documentScroll: { begin() {}, sync() {} },
  });
  layout.passed = { epoch: 2, resizedAt: 10 };
  return { layout };
}

// Nothing changed since the last pass: the pass is skipped without scanning anything.
{
  const { layout } = host();
  assert.equal(layout.unchangedSincePass(), true);
  layout.roots = () => { throw new Error("a skipped pass must not scan the roots"); };
  layout.update();
  assert.equal(layout.metrics.passesSkipped, 1);
  assert.equal(layout.updating, false, "a skipped pass leaves the host ready for the next one");
}

// Each of these makes the pass run.
const cases = [
  ["no completed pass yet", ({ layout }) => { layout.passed = null; }],
  ["a DOM change was collected", ({ layout }) => { layout.changed = true; }],
  ["a global attribute or fonts changed", ({ layout }) => { layout.epoch++; }],
  ["the window resized", ({ layout }) => { layout.windowResized = true; }],
  ["the window resized since the last pass", ({ layout }) => { layout.resizedAt = 20; }],
  ["a CSS layout island has a change to apply", ({ layout }) => { layout.css.pending.add({}); }],
  ["the page holds a user-defined Layout, whose subview sizes follow their content", ({ layout }) => { layout.css.layouts.add({}); }],
];
for (const [name, change] of cases) {
  const fixture = host();
  change(fixture);
  assert.equal(fixture.layout.unchangedSincePass(), false, name);
}

// A pass something scheduled (a font, an input, a resize) runs even when the DOM did not change.
{
  const { layout } = host();
  layout.scheduled = 7;
  let scanned = false;
  layout.roots = () => { scanned = true; throw new Error("stop after the scan started"); };
  assert.throws(() => layout.update(), /stop after the scan started/);
  assert.ok(scanned, "a scheduled pass is not skipped");
  assert.equal(layout.metrics.passesSkipped, 0);
  assert.equal(layout.passed, null, "a pass that failed is not trusted by the next one");
}

// What a commit writes on every key without changing a box: a text field's value, and the image pipeline's load hints. The
// records reach the host, which collects nothing, so the pass after them is skipped.
{
  const { layout } = host();
  layout.ownAttributes = new Set(["fetchpriority", "loading", "decoding"]);
  const element = (localName, value) => ({ nodeType: 1, localName, parentElement: null, getAttribute: () => value });
  layout.collect([
    { type: "attributes", target: element("input", "ab"), attributeName: "value", oldValue: "a" },
    { type: "attributes", target: element("textarea", "ab"), attributeName: "value", oldValue: "a" },
    { type: "attributes", target: element("img", "high"), attributeName: "fetchpriority", oldValue: "low" },
  ]);
  assert.equal(layout.changed, false, "a text value or a load hint is not a layout change");
  assert.equal(layout.unchangedSincePass(), true);
}

// A change inside a CSS layout island is the mapper's: it reaches `note`, never the host's own flag.
{
  const { layout } = host();
  const island = {}, noted = [];
  layout.css = { pending: new Set(), layouts: new Set(), islandOf: () => island, note: (...args) => noted.push(args) };
  const target = { nodeType: 1, localName: "div", parentElement: null, getAttribute: () => "b" };
  layout.collect([{ type: "attributes", target, attributeName: "class", oldValue: "a" }]);
  assert.equal(noted.length, 1);
  assert.equal(layout.changed, false);
}

// needsSync answers before the call what `update` would: a commit that wrote nothing the layout reads needs no pass, and the
// skip is counted as update counts it.
{
  const { layout } = host();
  layout.ownAttributes = new Set(["fetchpriority"]);
  assert.equal(layout.needsSync(), false, "a commit that wrote nothing the layout reads needs no pass");
  assert.equal(layout.metrics.passesSkipped, 1, "the skipped pass is counted");
}
{
  const cases = [
    ["a pass scheduled by a font, an input or a resize", ({ layout }) => { layout.scheduled = 7; }],
    ["a pass requested while one runs", ({ layout }) => { layout.updateRequested = true; }],
    ["no completed pass yet", ({ layout }) => { layout.passed = null; }],
    ["the window resized", ({ layout }) => { layout.windowResized = true; }],
    ["a global attribute or fonts changed", ({ layout }) => { layout.epoch++; }],
    ["a CSS layout island has a change to apply", ({ layout }) => { layout.css.pending.add({}); }],
    ["a user-defined Layout whose subview sizes follow their content", ({ layout }) => { layout.css.layouts.add({}); }],
  ];
  for (const [name, change] of cases) {
    const fixture = host();
    change(fixture);
    assert.equal(fixture.layout.needsSync(), true, name);
  }
}
// A DOM change the layout reads (here a child added to a view) is collected by needsSync, as the pass would collect it.
{
  const { layout } = host();
  layout.ownAttributes = new Set();
  layout.mutations.takeRecords = () => [{ type: "childList", target: { nodeType: 1, localName: "div", parentElement: null }, addedNodes: [], removedNodes: [] }];
  assert.equal(layout.needsSync(), true, "a child changed");
  assert.equal(layout.changed, true);
}

// A pass something asked for (a sidebar the host toggled, whose attribute the CSS layout does not read) probes the user-defined
// Layouts again, though the pass that runs from the frame finds nothing scheduled any more.
{
  const { layout } = host();
  let frame = null, invalidated = 0;
  layout.window.requestAnimationFrame = (callback) => { frame = callback; return 3; };
  layout.options = {};
  layout.onError = (error) => { throw error; };
  layout.css.invalidateLayouts = () => { invalidated++; };
  layout.css.layouts.add({});
  layout.mutations.disconnect = () => {};
  layout.observeMutations = () => {};
  layout.roots = () => { throw new Error("stop after the scan started"); };
  layout.schedule();
  assert.throws(() => frame(), /stop after the scan started/);
  assert.ok(invalidated > 0, "a scheduled pass probes the Layouts again");
}

console.log("PASS layout pass skipped when nothing changed; every invalidation still runs it");
