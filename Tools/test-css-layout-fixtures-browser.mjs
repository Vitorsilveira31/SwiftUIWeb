#!/usr/bin/env bun
// CSS layout of the lowering app's fixtures.
//
// Each fixture below is opened in the lowering app and every element under the app root is measured: after the fixture opens
// and, where it has them, after a click (a publication patches the page), after the root's `aria-hidden` is removed and after
// the window narrows. CSS layout must lay the fixture out (blocks of Swift's or of the page's mapper), no semantic root may
// be left without a layout (`layoutMetrics.unlaid`), the boxes Apple's SwiftUI measures (`apart`, `apple`) must be as it
// gives them, and the page may report no error or mismatch (with `window.__layoutVerify` it also compares every block Swift
// sent with its own analysis). The boxes themselves are not recorded: what a fixture must satisfy is asserted.
//
//   bun Tools/test-css-layout-fixtures-browser.mjs [bundle] [--only <fixture>]
//
// - EmbeddedInsetFixture: safeAreaInset on each edge, and a TabView with its bottom tab bar.
// - EmbeddedGridCellsFixture: a Grid whose cells span columns, anchor, take their slot and align their column, and a screen with a
//   bottom bar in a row of its own.
// - EmbeddedPlacementFixture: `.position(x:y:)` of a text, of a framed shape and of a long text that wraps.
// - EmbeddedLabeledFixture: LabeledContent rows with long labels and long values, and one in an HStack.
// - EmbeddedFitFixture: `ViewThatFits(in: .horizontal)` in frames that select each candidate, and one that follows the
//   window, measured again after a publication patches the candidates (`click`) and after the window narrows (`resize`);
//   with no candidate, with one, in a candidate, with candidates from a `ForEach` and an `if`, in a ZStack, in a horizontal
//   ScrollView and over both axes.
// - EmbeddedPresentedFixture: a NavigationStack's root, then a destination presented over it (`click`), then the root's
//   `aria-hidden` removed, as a presentation's focus isolation restores it (`reveal`): a pushed screen replaces its root, shown
//   or not.
// - EmbeddedRelativeFixture: `containerRelativeFrame` of a horizontal ScrollView, of the window and of a vertical
//   ScrollView, measured again after the window narrows; `count:span:spacing:` on either axis, closures that decrease, bend,
//   rise again and go negative, and frames with a frame, a padding and a background around and inside them.
// - EmbeddedSplitFixture: HSplitView and VSplitView of two and three panes, panes that hug and panes that fill, frames with a
//   minimum, an ideal and a maximum, panes that wrap a text or hold a ScrollView or a split view, measured again after a
//   publication changes the texts (`click`) and after the window narrows. Each pane is a root of the mapper. The split view has
//   no divider drag in the browser to drive: Swift places the panes from the persisted positions (`LayoutTests`), and the page
//   lays out the slots it is given.
//
// The mapper must refuse nothing (`stats.unsupported`, `window.__cssLayoutInstance`, which the diagnostics flag publishes) in
// the fixtures marked `onlyCss`, and Swift emits the CSS of the ones marked `swift` (a `data-sl-root` on the page).
// - EmbeddedScrollFixture: a horizontal shelf in a VStack and vertical ScrollViews of a short text and of full-width rows.
// - EmbeddedScrollRootFixture: a vertical ScrollView as the root view (the verifier compares its block with Swift's).
// - EmbeddedTextFixture: TextFields in HStacks (default and plain styles) and texts with `lineLimit(2)` and `lineLimit(3)`.
// - EmbeddedPrincipalFixture: two principal toolbar items between a leading and a trailing item, with and without a title; and
//   several items on a side: between blocks as wide as each other (the mapper centres the principal group on the bar only
//   then: between blocks of unequal width it centres the group between them, which `test-css-layout-roots.mjs` checks), with
//   no principal item and with one.
// - EmbeddedNavigationViewFixture: a legacy NavigationView at its root, then after a push (`click`).
// - EmbeddedLayerFixture: overlays as tall as their content, aligned at an edge or a corner (WebKit sizes and aligns such
//   a box from its containing block), and a menu Picker beside a flexible field (without field-sizing, the page measures
//   its selected label).
// - EmbeddedLazyShelfFixture: a horizontal ScrollView of an HStack of chips wider than the window, in a LazyVStack. The
//   shelf is a row of the lazy stack, not a lazy collection windowed on its axis: every chip is rendered, and stays so
//   (windowed by height, the window swung between 3 and 12 chips at every publication).
// - EmbeddedCanvasFixture: Canvases framed to a height, to a size and not framed (a framed Canvas keeps its element).
// - EmbeddedLayoutFixture: user-defined Layouts (a wrapping flow that asks for ideal sizes, a radial layout anchored at centres, a
//   layout that proposes the widest ideal width, custom layouts inside one another and in a ScrollView), measured again after a
//   publication changes the chips (`click`) and after the window narrows. The page reports each Layout's proposal and its
//   subviews' sizes to Swift (`reportLayouts`), so CSS lays all of it out.
// - EmbeddedAspectFixture: aspect boxes capped by the height of the frame around them (and a padding in between): the boxes
//   are the ones Apple's SwiftUI gives (`apple`), and Swift must emit the page's blocks.
// - EmbeddedControlsFixture: Divider, linear ProgressView, Slider, menu Picker, linear Gauge, TextEditor and Canvas in stacks, in rows,
//   framed and not. Every group has a frame of its own, and the test checks its boxes against what Apple's SwiftUI gives for the
//   same tree (`apart`, a `data-testid`; `Tests/LayoutConformance/apple-macos-css-extra.json`, the `x-divider-*` and the other
//   `x-` fixtures of `Tools/css-layout-oracle.mjs`).
// - EmbeddedShapesFixture: a Section whose header and footer hold two views (a padding around a vstack of its own) and chains
//   of frames one CSS box cannot hold (they keep an element each).
// - EmbeddedHostRootsFixture: the layout trees a browser-owned widget hosts, each a semantic root of its own: an alert with a
//   message and actions and a confirmation dialog (`click`: the presentation), the cells of a Table, the views a Chart draws in
//   its foreignObjects (annotations, custom axis labels) and Grids inside a Form row and a disclosure.
// - The start page holds every fixture's button and a Table.
//
// The fit and relative fixtures are taller than the default 800 px window (a root taller than its window is centred), so they
// open in a window of 1400 px.
//
// Bundle: `BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh lowering` (the boxes were recorded on the release bundle; the debug
// one differs by a pixel in WebKit's table). Engine: SWIFTUIWEB_BROWSER_ENGINE.
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { engineName, launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

const FIXTURES = [{ button: null, name: "start", onlyCss: true }, { button: "Open inset fixture", name: "inset" }, { button: "Open grid cells fixture", name: "grid-cells", onlyCss: true, swift: true }, { button: "Open placement fixture", name: "placement" }, { button: "Open labeled fixture", name: "labeled" },
  { button: "Open fit fixture", name: "fit", click: "Count", resize: 300, onlyCss: true, height: 1400 }, { button: "Open presented fixture", name: "presented", click: "Present", reveal: true, onlyCss: true, swift: true },
  { button: "Open relative fixture", name: "relative", resize: 640, onlyCss: true, height: 1400 }, { button: "Open scroll fixture", name: "scroll" }, { button: "Open scroll root fixture", name: "scroll-root" },
  { button: "Open text fixture", name: "text" }, { button: "Open principal fixture", name: "principal", onlyCss: true, swift: true },
  { button: "Open navigation view fixture", name: "navigation-view", click: "Open detail", clickRole: "link", onlyCss: true, swift: true },
  { button: "Open layer fixture", name: "layer" }, { button: "Open lazy shelf fixture", name: "lazy-shelf", texts: /^Format chip \d+$/, count: 12 },
  { button: "Open canvas fixture", name: "canvas" }, { button: "Open shapes fixture", name: "shapes" },
  { button: "Open aspect fixture", name: "aspect", apple: [/^div\.aspect-box \S+ \S+ 160 80$/, /^div\.aspect-box \S+ \S+ 50 100$/, /^div\.aspect-box \S+ \S+ 320 160$/], swift: true },
  { button: "Open layout fixture", name: "layout", click: "Count", resize: 360, onlyCss: true, height: 1400 },
  { button: "Open alert fixture", name: "alert", click: "Show alert", onlyCss: true },
  { button: "Open confirmation fixture", name: "confirmation", click: "Show dialog", onlyCss: true },
  { button: "Open table fixture", name: "table", onlyCss: true },
  { button: "Open chart fixture", name: "chart", onlyCss: true },
  { button: "Open form fixture", name: "form", onlyCss: true },
  { button: "Open split fixture", name: "split", click: "Count", resize: 520, onlyCss: true, height: 1400 },
  { button: "Open controls fixture", name: "controls", onlyCss: true, swift: true, still: true, height: 1700, apart: [
    { id: "controls-divider-row", select: "hr", w: 1, h: 40,
      reason: "A Divider in an HStack is a vertical rule as tall as the row (Apple: x-divider-hstack, 1 x 40)" },
    { id: "controls-slider-row", select: ".hstack", w: 320,
      reason: "A Slider takes what its neighbours leave (Apple: x-slider-row, 191.5 of 260), so its row is as wide as its frame" },
    { id: "controls-progress-row", select: ".hstack", w: 320,
      reason: "A progress bar takes what its neighbour leaves (Apple: x-progress-hstack, 210.5 of 260), so its row is as wide as its frame" },
    { id: "controls-canvas-ideal", select: "canvas", h: 10,
      reason: "A Canvas offered no height is 10 pt tall (Apple: x-canvas-ideal), the stylesheet's 1 px border included" },
    { id: "controls-editor-stack", select: "textarea", h: 118,
      reason: "A TextEditor in a stack of a fixed height takes the height the stack leaves (Apple: x-editor-vstack, 122 of 150 beside a text of 20)" },
    { id: "controls-gauge", select: ".gauge-meter", h: 40,
      reason: "A Gauge's label is above its track, 8 px apart (the stylesheet's gap; Apple: x-gauge-vstack has the label above the bar too)" },
    { id: "controls-picker", select: "select", wMax: 120,
      reason: "A menu Picker is as wide as its selected label (Apple: x-menu-picker-alone 156 of 320, x-menu-picker-wide-frame 156 of 250)" },
    { id: "controls-picker-framed", select: "select", wMax: 120,
      reason: "A menu Picker in a frame wider than its label stays as wide as its label (Apple: x-menu-picker-wide-frame)" },
  ] }];

// What `apart` checks: the box of the first element `select` matches in the group, relative to the group's top left. `w`/`h`: its size
// (1.5 px off at most), `wMax`: at most that wide.
const APART = `(parts) => parts.map(part => {
  const group = document.querySelector('[data-testid="' + part.id + '"]'), base = group.getBoundingClientRect();
  const box = e => { const r = e.getBoundingClientRect(); return { x: r.x - base.x, y: r.y - base.y, w: r.width, h: r.height }; };
  const found = group.querySelector(part.select);
  return { id: part.id, box: found && box(found) };
})`;
const matches = (part, got) => {
  if (!got.box) return false;
  if (part.w !== undefined && Math.abs(got.box.w - part.w) > 1.5) return false;
  if (part.h !== undefined && Math.abs(got.box.h - part.h) > 1.5) return false;
  if (part.wMax !== undefined && got.box.w > part.wMax) return false;
  return true;
};

const BOXES = `() => {
  const out = [];
  for (const e of document.querySelectorAll('#embedded-app-root *')) {
    if (!e.getClientRects().length) continue;
    const r = e.getBoundingClientRect();
    const name = String(e.className?.baseVal ?? e.className).split(' ').filter(c => c && !/^s[lr]\\d+$/.test(c))[0] || '';
    out.push([e.localName + '.' + name, ...[r.x, r.y, r.width, r.height].map(v => Math.round(v * 2) / 2)].join(' '));
  }
  return {
    boxes: out,
    unlaid: window.__embeddedSession?.layoutMetrics?.unlaid ?? null,
    css: document.querySelectorAll('#embedded-app-root [data-cl], #embedded-app-root [data-sl-root]').length,
    swift: document.querySelectorAll('#embedded-app-root [data-sl-root]').length,
    roots: [...document.querySelectorAll('#embedded-app-root .navigation-root')].filter(e => e.getClientRects().length).length,
    unsupported: window.__cssLayoutInstance ? window.__cssLayoutInstance.stats.unsupported : null,
    mismatches: (window.__layoutMismatch || []).map(m => JSON.stringify(m).slice(0, 300)),
  };
}`;

const { values, positionals } = parseArgs({ allowPositionals: true, options: { port: { type: "string", default: "0" }, only: { type: "string" } } });

await runSuite(async () => {
  const bundle = resolve(positionals[0] ?? ".build/browser/EmbeddedLoweringConformanceApp");
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) throw new Error(`lowering app bundle is missing: ${bundle}`);
  const server = await serveDirectory(bundle, Number(values.port));
  let browser;
  try {
    browser = await launch();
    const open = async (fixture) => {
      const page = await browser.newPage({ viewport: { width: 1000, height: fixture.height ?? 800 }, deviceScaleFactor: 1 });
      const errors = [];
      page.on("pageerror", (error) => errors.push(error.message));
      page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
      await page.addInitScript(() => { window.__layoutVerify = true; window.__performanceDiagnostics = true; });
      await page.goto(`http://127.0.0.1:${server.port}/`, { waitUntil: "networkidle" });
      await page.evaluate(() => window.__performanceMetrics?.reset());
      if (fixture.button) await page.getByRole("button", { name: fixture.button, exact: true }).click();
      await page.waitForTimeout(1500);
      // The layout runs once the app has drawn, which a runner with few cores takes more than a fixed pause to do.
      await page.waitForFunction(() => document.querySelectorAll("#embedded-app-root [data-cl], #embedded-app-root [data-sl-root]").length > 0, null, { timeout: 30_000 }).catch(() => {});
      // (`still`: a spinner turns, and the box of a turned square is the bounding box of its turn; every animation is held at its start.)
      if (fixture.still) await page.evaluate(() => document.getAnimations().forEach((animation) => { animation.pause(); animation.currentTime = 0; }));
      const result = await page.evaluate(`(${BOXES})()`);
      if (fixture.apart) result.apart = await page.evaluate(`(${APART})(${JSON.stringify(fixture.apart)})`);
      if (fixture.texts) {
        result.texts = [];
        for (let i = 0; i < 8; i++) { result.texts.push(await page.getByText(fixture.texts).count()); await page.waitForTimeout(100); }
      }
      let clicked = null, resized = null, revealed = null;
      if (fixture.click) {
        await page.getByRole(fixture.clickRole ?? "button", { name: fixture.click, exact: true }).click();
        await page.waitForTimeout(1000);
        clicked = await page.evaluate(`(${BOXES})()`);
      }
      if (fixture.reveal) {
        // The stylesheet hides a pushed stack's root by its `aria-hidden`, which a presentation's focus isolation can restore
        // (removing it): the depth hides it all the same.
        await page.evaluate(() => document.querySelectorAll('.navigation-root').forEach((e) => e.removeAttribute('aria-hidden')));
        await page.waitForTimeout(500);
        revealed = await page.evaluate(`(${BOXES})()`);
      }
      if (fixture.resize) {
        await page.setViewportSize({ width: fixture.resize, height: fixture.height ?? 800 });
        await page.waitForTimeout(1000);
        resized = await page.evaluate(`(${BOXES})()`);
      }
      await page.close();
      return { ...result, clicked, resized, revealed, errors };
    };
    for (const fixture of FIXTURES.filter((f) => !values.only || f.name === values.only)) {
      const css = await open(fixture);
      if (fixture.texts) assert.deepEqual(css.texts, Array(css.texts.length).fill(fixture.count), `${fixture.name}: every item is rendered`);
      assert.deepEqual(css.errors, [], `${fixture.name}: errors`);
      assert.deepEqual(css.mismatches, [], `${fixture.name}: blocks Swift sent differ from the page's analysis`);
      assert.ok(css.css > 0, `${fixture.name}: CSS layout lays the fixture out`);
      if (fixture.swift) assert.ok(css.swift > 0, `${fixture.name}: Swift emits the fixture's CSS`);
      const steps = { opened: css, clicked: css.clicked, revealed: css.revealed, resized: css.resized };
      if (fixture.onlyCss) {
        assert.deepEqual(css.unsupported, {}, `${fixture.name}: the mapper refuses nothing, CSS lays the whole fixture out`);
        for (const later of [css.clicked, css.revealed, css.resized]) if (later) assert.deepEqual(later.unsupported, {}, `${fixture.name}: the mapper refuses nothing after the change`);
      }
      for (const [step, page] of Object.entries(steps)) if (page) assert.equal(page.unlaid, 0, `${fixture.name}: semantic roots left without a layout after the fixture is ${step}`);
      for (const [i, part] of (fixture.apart ?? []).entries()) {
        assert.ok(matches(part, css.apart[i]), `${fixture.name}: ${part.id} has Apple's boxes (${JSON.stringify(css.apart[i])}): ${part.reason}`);
      }
      // (`apple`: the boxes of an aspect box capped by its frame are Apple's.)
      for (const box of fixture.apple ?? []) assert.ok(css.boxes.some((line) => box.test(line)), `${fixture.name}: CSS layout has an aspect box that matches ${box}`);
      if (fixture.reveal) assert.equal(css.revealed.roots, 0, `${fixture.name}: the pushed screen replaces its root, shown or not`);
    }
    console.log(`PASS ${engineName()} CSS layout of ${FIXTURES.map(f => f.name).join(", ")}`);
  } finally {
    await browser?.close();
    server.close?.();
  }
});
