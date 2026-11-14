#!/usr/bin/env bun
// Reading-order acceptance gate for the real Embedded Showcase.
//
// SwiftUIWeb lays nodes out with CSS (Tools/css-layout.js) and can position them away from their DOM place,
// so DOM order, Tab order, visual geometry and accessibility-tree order are produced
// by separate code paths and can diverge from SwiftUI declaration order. This gate
// drives the linked Showcase fixture at /readingOrder (Tests/Apps/ShowcaseApp/
// ReadingOrderFixture.swift) and compares each of those orders with the declaration
// order written in that fixture.
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { launch, ROOT, runSuite, serveBundle } from "./browser-test-support.mjs";
import { bundleFilePath } from "./hash-release-bundle.mjs";

const BUNDLE = resolve(process.env.READING_ORDER_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
const PORT = Number(process.env.READING_ORDER_PORT ?? "8105");
const ROUTE = "/readingOrder";

// Declaration order, as written in ReadingOrderFixture.swift.
const HORIZONTAL = ["order-h-alpha", "order-h-beta", "order-h-gamma"];
const VERTICAL = ["order-v-first", "order-v-second", "order-v-third"];
const OFFSET = ["order-offset-lead", "order-offset-trail"];
const OVERLAY = ["order-overlay-base", "order-overlay-badge"];
const LAYERS = ["order-z-back", "order-z-front"];
const DECLARATION = [...HORIZONTAL, ...VERTICAL, ...OFFSET, ...OVERLAY, ...LAYERS];

const NAMES = {
  "order-h-alpha": "Alpha", "order-h-beta": "Beta", "order-h-gamma": "Gamma",
  "order-v-first": "First", "order-v-second": "Second", "order-v-third": "Third",
  "order-offset-lead": "Offset leading", "order-offset-trail": "Offset trailing",
  "order-overlay-base": "Primary action", "order-overlay-badge": "Badge",
  "order-z-back": "Back layer", "order-z-front": "Front layer",
};

// Flow layouts: stacks read top-to-bottom (VStack, axis "y") or left-to-right
// (HStack, axis "x"), with the cross axis as the tie-breaker.
const FLOW_GROUPS = [
  ["HStack", HORIZONTAL, "x"],
  ["VStack", VERTICAL, "y"],
  ["VStack with offset", OFFSET, "y"],
];

// Intentional visual divergences inside a flow group. Each entry is left out of
// the geometric comparison. The gate also requires the group to diverge while the
// entry is still included, so a stale entry fails instead of hiding a regression.
const INTENTIONAL_VISUAL_DIVERGENCE = {
  // `.offset(y: 60)` is a post-layout translation, so this control is drawn
  // below its declaration-order sibling by design.
  "order-offset-lead": "`.offset(y: 60)` draws it below its declaration-order sibling",
};

// Controls that are not flow content. Overlay and ZStack children share or overlap
// a box, so top-to-bottom / left-to-right order is not defined for them. They are
// excluded from the flow sort and checked for their layered relation instead; DOM
// and Tab order still cover them through the full declaration list.
const NOT_FLOW_CONTENT = {
  "order-overlay-badge": "`.overlay(alignment: .topTrailing)` layers it over its base",
  "order-z-back": "ZStack layer that overlaps the front layer",
  "order-z-front": "ZStack layer that overlaps the back layer",
};

const RECTS_JS = `() => Object.fromEntries([...document.querySelectorAll('[data-testid^="order-"]')].map(e => {
  const r = e.getBoundingClientRect();
  return [e.getAttribute('data-testid'), {x: r.left, y: r.top, w: r.width, h: r.height}];
}))`;

async function load(page, base, route) {
  const response = await page.goto(base + route, { waitUntil: "domcontentloaded" });
  assert.ok(response && response.status() === 200);
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  await page.waitForSelector(`[data-testid="${DECLARATION[0]}"]`, { timeout: 30_000 });
  await page.waitForTimeout(250);
}

function domOrder(page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('[data-testid^="order-"]')].map((e) => e.getAttribute("data-testid")),
  );
}

async function tabOrder(page) {
  await page.evaluate((id) => document.querySelector(`[data-testid='${id}']`).focus(), DECLARATION[0]);
  const focused = () =>
    page.evaluate(() => (document.activeElement ? document.activeElement.getAttribute("data-testid") : null));
  const seen = [await focused()];
  for (let i = 0; i < DECLARATION.length - 1; i++) {
    await page.keyboard.press("Tab");
    seen.push(await focused());
  }
  return seen;
}

// Rounds to one decimal: exact ties (only .25 and .75 are exact in binary) go to the even tenth,
// every other value rounds correctly, as Number#toFixed does.
function roundHalfEven1(value) {
  const fraction = value - Math.floor(value);
  if (fraction === 0.25 || fraction === 0.75) {
    const tenths = Math.floor(value * 10);
    return (tenths % 2 === 0 ? tenths : tenths + 1) / 10;
  }
  return Number(value.toFixed(1));
}

function visualOrder(rects, ids, axis) {
  const key = (identifier) => {
    const rect = rects[identifier];
    const x = roundHalfEven1(rect.x);
    const y = roundHalfEven1(rect.y);
    return axis === "y" ? [y, x] : [x, y];
  };
  return [...ids].sort((a, b) => {
    const [a0, a1] = key(a);
    const [b0, b1] = key(b);
    return a0 - b0 || a1 - b1;
  });
}

// One-decimal text (same rounding as roundHalfEven1).
const fmt1 = (value) => roundHalfEven1(value).toFixed(1);

function describe(rects, ids) {
  return ids.map((i) => `${i}@x=${fmt1(rects[i].x)},y=${fmt1(rects[i].y)}`).join(", ");
}

function intersects(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

async function focusableAxNodes(page) {
  const session = await page.context().newCDPSession(page);
  const { nodes = [] } = await session.send("Accessibility.getFullAXTree");
  // The reply is a flat list in no particular tree order (a shallower node can precede a deeper one declared
  // before it). Reading order is the tree's pre-order, so walk it through `childIds` from the root.
  const byId = new Map(nodes.map((node) => [node.nodeId, node]));
  const roots = nodes.filter((node) => !byId.has(node.parentId));
  const result = [];
  const stack = [...roots].reverse();
  while (stack.length) {
    const node = stack.pop();
    if (!node.ignored) {
      const props = Object.fromEntries((node.properties ?? []).map((p) => [p.name, p.value?.value]));
      if (props.focusable === true) result.push([node.role?.value ?? "", node.name?.value ?? ""]);
    }
    for (const child of [...(node.childIds ?? [])].reverse()) {
      if (byId.has(child)) stack.push(byId.get(child));
    }
  }
  return result;
}

await runSuite(async () => {
  for (const name of ["app.wasm", "index.html", "index.js"]) {
    if (!bundleFilePath(BUNDLE, name)) throw new Error(`${name} missing from ${BUNDLE}`);
  }

  // The allowlists must describe real controls in the flow groups they change.
  const flowIds = new Set(FLOW_GROUPS.flatMap(([, ids]) => ids));
  const divergent = Object.keys(INTENTIONAL_VISUAL_DIVERGENCE);
  const notFlow = Object.keys(NOT_FLOW_CONTENT);
  assert.ok(divergent.every((id) => flowIds.has(id)), JSON.stringify(INTENTIONAL_VISUAL_DIVERGENCE));
  assert.ok(notFlow.every((id) => !flowIds.has(id)), JSON.stringify(NOT_FLOW_CONTENT));
  assert.ok(divergent.every((id) => !Object.hasOwn(NOT_FLOW_CONTENT, id)));

  const { base, stop } = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "reading-order-browser-server" });
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    await load(page, base, ROUTE);

    // (b) DOM order of the fixture controls equals declaration order.
    const dom = await domOrder(page);
    assert.deepEqual(dom, DECLARATION, `DOM order ${JSON.stringify(dom)} != declaration ${JSON.stringify(DECLARATION)}`);

    // (a) Tab from the first control visits every control in declaration order.
    const tabbed = await tabOrder(page);
    assert.deepEqual(tabbed, DECLARATION, `Tab order ${JSON.stringify(tabbed)} != declaration ${JSON.stringify(DECLARATION)}`);

    // (c) Flow layouts read in declaration order by geometry.
    const rects = await page.evaluate(`(${RECTS_JS})()`);
    for (const [label, ids, axis] of FLOW_GROUPS) {
      const missing = ids.filter((i) => !Object.hasOwn(rects, i));
      assert.equal(missing.length, 0, `${label} controls not laid out: ${JSON.stringify(missing)}`);
      const compared = ids.filter((i) => !Object.hasOwn(INTENTIONAL_VISUAL_DIVERGENCE, i));
      const visual = visualOrder(rects, ids, axis).filter((i) => !Object.hasOwn(INTENTIONAL_VISUAL_DIVERGENCE, i));
      assert.deepEqual(
        visual,
        compared,
        `${label} visual order ${JSON.stringify(visual)} != declaration ${JSON.stringify(compared)}; positions: ${describe(rects, ids)}`,
      );
      if (ids.some((i) => Object.hasOwn(INTENTIONAL_VISUAL_DIVERGENCE, i))) {
        assert.notDeepEqual(
          visualOrder(rects, ids, axis),
          ids,
          `${label} allowlist is stale: the group reads in declaration order; positions: ${describe(rects, ids)}`,
        );
      }
    }

    // Overlay and ZStack children are not flow content: check their layered
    // relation directly instead of a reading order.
    const baseRect = rects["order-overlay-base"];
    const badgeRect = rects["order-overlay-badge"];
    assert.ok(intersects(baseRect, badgeRect), `overlay badge is not layered on its base: ${describe(rects, OVERLAY)}`);
    const backRect = rects["order-z-back"];
    const frontRect = rects["order-z-front"];
    assert.ok(intersects(backRect, frontRect), `ZStack layers do not overlap: ${describe(rects, LAYERS)}`);

    // (d) Every focusable element has a name and a role, and the named
    // fixture controls appear in the accessibility tree in declaration order.
    const focusable = await focusableAxNodes(page);
    const unnamed = focusable.filter((node) => !node[1].trim());
    const roleless = focusable.filter((node) => !node[0] || node[0] === "none" || node[0] === "generic");
    assert.equal(unnamed.length, 0, `focusable nodes without a name: ${JSON.stringify(unnamed)}`);
    assert.equal(roleless.length, 0, `focusable nodes without a role: ${JSON.stringify(roleless)}`);
    const fixtureNames = new Set(DECLARATION.map((i) => NAMES[i]));
    const axFixture = focusable.filter((node) => fixtureNames.has(node[1]));
    const axOrder = axFixture.map((node) => node[1]);
    const expectedNames = DECLARATION.map((i) => NAMES[i]);
    assert.deepEqual(axOrder, expectedNames, `accessibility order ${JSON.stringify(axOrder)} != declaration ${JSON.stringify(expectedNames)}`);
    assert.ok(axFixture.every((node) => node[0] === "button"), JSON.stringify(axFixture));
  } finally {
    await browser?.close();
    await stop();
  }
  console.log("PASS Embedded Chromium reading order: DOM, Tab, flow geometry, accessibility tree");
});
