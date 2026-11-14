#!/usr/bin/env bun
// A run of frame, padding and fixedSize modifiers shares one element (`data-layout-wrap`). CSS has one box for it, so the CSS
// layout mapper folds the chain into that box (`CssLayout.chainPlan`). For every chain of up to four layers, over a one-view
// and a two-view content (a vstack of its own, which is how Swift holds several views, see `_semanticHeld`), inside a vertical
// ScrollView island: the content the mapper lays out in the merged element must have the rectangles it has in the chain of
// wrapper elements, which it always lays out. A chain one box cannot express is refused (the island then stays on the JS host), never laid out differently; Swift does not merge such a chain (`_SemanticLayers.isFoldable`), it keeps its wrapper
// elements, and `SemanticLayerTests` requires the same number of unfoldable chains as is printed here.
// A `containerRelativeFrame` (a frame whose length is a function of its container's) is also tried as the outermost
// layer, with up to three layers inside it.
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

// The chains of one view that `chainPlan` refuses (`SemanticLayerTests.testUnfoldableChainsAreTheOnesCSSRefuses` counts the ones Swift keeps apart).
const UNFOLDABLE = 2919;
const css = readFileSync(new URL("./css-layout.js", import.meta.url), "utf8").replace(/^export /gm, "");
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
await page.setContent("<!doctype html><html><head><style>body{margin:0;font:16px/20px sans-serif}</style></head><body></body></html>");
await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });

const result = await page.evaluate(() => {
  // The layers, as the Swift modifiers write them (names without `data-`): the variants of test-layout-layers.mjs, a
  // frame with a finite maximum only and one with a minimum only.
  const VARIANTS = {
    frame: [
      { "frame-w": "120", "frame-h": "60", "align-x": "0.5", "align-y": "0.5" },
      { "frame-max-w": "inf", "align-x": "0", "align-y": "0.5" },
      { "frame-min-h": "44", "frame-max-h": "inf", "align-x": "1", "align-y": "1" },
      { "frame-max-w": "300", "align-x": "0", "align-y": "0.5" },
      { "frame-min-w": "160", "align-x": "0", "align-y": "0.5" },
    ],
    padding: [
      { "padding-top": "8.0", "padding-leading": "8.0", "padding-bottom": "8.0", "padding-trailing": "8.0" },
      { "padding-leading": "12.0", "padding-trailing": "4.0" },
      { "padding-top": "0.3", "padding-leading": "0.7", "padding-bottom": "0.37", "padding-trailing": "0.1" },
    ],
    fixed: [{ "fixed-x": "true", "fixed-y": "false" }],
  };
  // A `containerRelativeFrame`'s samples, as Swift writes them: half the container, a length that decreases, and the height.
  const RELATIVE = [
    { "relative-w": "0:0;1000:500", "align-x": "0", "align-y": "0.5" },
    { "relative-w": "0:600;320:280;640:280;1280:640", "align-x": "1", "align-y": "0.5" },
    { "relative-h": "0:40;1000:140", "align-x": "0.5", "align-y": "0" },
    { "relative-w": "0:100;1000:100", "relative-h": "0:30;100:30", "align-x": "0.5", "align-y": "0.5" },
  ].map((map) => ({ kind: "container-relative", map }));
  const LAYERS = Object.entries(VARIANTS).flatMap(([kind, maps]) => maps.map((map) => ({ kind, map })));
  const attrs = (kind, map) => [`data-layout-kind="${kind}"`, ...Object.entries(map).map(([k, v]) => `data-${k}="${v}"`)].join(" ");
  const leaf = (id, text) => `<span id="${id}" data-layout-leaf="text" data-layout-kind="intrinsic">${text}</span>`;
  const content = (two) => two ? `<div class="vstack" data-layout-kind="vstack" data-layout-gap="0" data-align-x="0">${leaf("a", "Alpha")}${leaf("b", "Beta longer")}</div>` : leaf("a", "Alpha");
  const chainHTML = (layers, two) => {
    let html = content(two);
    for (let i = layers.length - 1; i >= 0; i--) html = `<div ${attrs(layers[i].kind, layers[i].map)}>${html}</div>`;
    return html;
  };
  const mergedHTML = (layers, two) => {
    const wrap = layers.slice(1).map((l) => [l.kind, ...Object.entries(l.map).map(([k, v]) => `${k}=${v}`)].join(";")).join("|");
    return `<div ${attrs(layers[0].kind, layers[0].map)}${wrap ? ` data-layout-wrap="${wrap}"` : ""}>${content(two)}</div>`;
  };
  // Lays `html` out in an island (a vertical ScrollView 500 wide) and returns the content's rectangles, or null when the
  // mapper refused it.
  const layout = (html) => {
    document.body.innerHTML = `<div id="root" class="scroll-view scroll-vertical" data-layout-kind="scroll" style="width:500px;height:600px"><div class="vstack" data-layout-kind="vstack" data-layout-gap="0">${html}</div></div>`;
    for (const sheet of document.adoptedStyleSheets) sheet.replaceSync("");
    document.adoptedStyleSheets = [];
    const mapper = new CssLayout(document), root = document.getElementById("root");
    if (!mapper.claim(root)) return null;
    mapper.flush();
    const origin = root.getBoundingClientRect();
    // Where a wrapper is larger than what holds it, CSS does not centre it as SwiftUI does (it starts it at the leading
    // edge), so the wrappers are no reference there.
    const overflows = [...root.querySelectorAll("[data-layout-kind]")].some((e) => {
      const p = e.parentElement; if (!p || p === root) return false;
      const a = e.getBoundingClientRect(), b = p.getBoundingClientRect();
      return a.width > b.width + 0.02 || a.height > b.height + 0.02;
    });
    mapper.overflows = overflows;
    const rects = ["a", "b"].map((id) => document.getElementById(id)).filter(Boolean)
      .map((e) => { const r = e.getBoundingClientRect(); return [r.x - origin.x, r.y - origin.y, r.width, r.height]; });
    rects.overflows = overflows;
    return rects;
  };
  const chains = [];
  const extend = (prefix) => { if (prefix.length) chains.push(prefix); if (prefix.length < 4) for (const layer of LAYERS) extend([...prefix, layer]); };
  extend([]);
  // Inside any box that is larger than its content (a fixed frame as well), a frame with a minimum width and no maximum is
  // laid out as the box's track rather than as large as its content: a gap of `chainPlan` that is not the relative frame's
  // (the same chains differ under `frame(width:)`), so they are left out here.
  const floorX = (layer) => layer.map["frame-min-w"] != null && layer.map["frame-max-w"] == null && layer.map["frame-w"] == null;
  const below = (prefix) => { chains.push(prefix); if (prefix.length < 4) for (const layer of LAYERS) if (!floorX(layer)) below([...prefix, layer]); };
  for (const layer of RELATIVE) below([layer]);
  let compared = 0, refused = 0, overflowing = 0, unfoldable = 0, unlaid = 0;
  const failures = [], refusedKinds = {};
  for (const layers of chains) for (const two of [false, true]) {
    const expected = layout(chainHTML(layers, two));
    if (!expected) { unlaid++; continue; } // a wrapper chain CSS cannot lay out
    const actual = layout(mergedHTML(layers, two));
    // Swift never merges layers into a relative frame, so only the other chains are the ones it keeps apart.
    if (!two && !actual && layers[0].kind !== "container-relative") unfoldable++;
    if (expected.overflows) { overflowing++; continue; }
    const name = layers.map((l) => l.kind + "(" + Object.entries(l.map).map(([k, v]) => k + "=" + v).join(",") + ")").join(" > ") + (two ? " [2]" : "");
    if (!actual) { refused++; const key = layers.map((l) => l.kind).join(">"); refusedKinds[key] = (refusedKinds[key] || 0) + 1; continue; }
    compared++;
    const off = expected.some((r, i) => r.some((v, j) => Math.abs(v - actual[i][j]) > 0.02));
    if (off) failures.push({ name, expected, actual });
  }
  return { chains: chains.length, compared, refused, overflowing, unfoldable, unlaid, refusedKinds, failures, failureCount: failures.length };
});
await browser.close();
for (const failure of result.failures.slice(0, process.env.VERBOSE ? Infinity : 6)) console.log("DIFFERS", failure.name, "\n  wrappers", JSON.stringify(failure.expected), "\n  merged  ", JSON.stringify(failure.actual));
const top = Object.entries(result.refusedKinds).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([k, v]) => `${k} ${v}`).join(", ");
console.log(`${result.chains} chains x 2 contents: ${result.compared - result.failureCount} laid out alike, ${result.failureCount} differ, ${result.refused} refused (${top}), ${result.overflowing} skipped (a wrapper overflows what holds it); ${result.unfoldable} chains of one view are unfoldable, ${result.unlaid} wrapper chains not laid out`);
const ok = result.failureCount === 0 && result.unlaid === 0 && result.unfoldable === UNFOLDABLE;
console.log(ok ? "PASS a merged layer chain is laid out like its wrapper elements, or refused; wrapper chains always are laid out" : "FAIL merged layer chains differ from their wrappers, a wrapper chain is not laid out, or the unfoldable chains are not the ones Swift keeps apart");
process.exit(ok ? 0 : 1);
