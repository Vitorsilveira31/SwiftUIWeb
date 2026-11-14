#!/usr/bin/env bun
// Oracle for CSS layout (Tools/css-layout.js): the SwiftUI trees of the layout conformance suite are rendered with the
// data-* vocabulary the Swift side emits, laid out by CSS only, and compared with
//   * Apple SwiftUI's frames (Tests/LayoutConformance/apple-macos-css.json, tolerances of Tools/LayoutConformance/fixtures.json),
//   * the frames of extra fixtures (Tests/LayoutConformance/apple-macos-css-extra.json, Tools/LayoutConformance/run-css-apple.sh), and
//   * the frames an earlier layout engine's conformance tests asserted, captured from Apple and translated here (the engine and its tests are removed).
// --check exits 1 when a node outside KNOWN_MISSES misses (or a known miss passes, so the list is kept current).
// usage: bun Tools/css-layout-oracle.mjs [--check] [--verbose] [--browser chromium|webkit|firefox] [--apple f] [--apple-extra f]
import { readFileSync } from "node:fs";
import { chromium, webkit, firefox } from "playwright";

const args = process.argv.slice(2);
const verbose = args.includes("--verbose");
const browserName = args.includes("--browser") ? args[args.indexOf("--browser") + 1] : "chromium";
const root = new URL("..", import.meta.url).pathname;
const appleArg = args.includes("--apple") ? args[args.indexOf("--apple") + 1] : root + "Tests/LayoutConformance/apple-macos-css.json";
const apple = JSON.parse(readFileSync(appleArg, "utf8")).nodes;
const spec = JSON.parse(readFileSync(root + "Tools/LayoutConformance/fixtures.json", "utf8"));

// ---- a tiny DSL for the trees --------------------------------------------------------------------------------------
const attr = (o) => Object.entries(o).filter(([, v]) => v !== undefined && v !== null).map(([k, v]) => ` ${k}="${String(v).replace(/"/g, "&quot;")}"`).join("");
const node = (cls, kind, a, kids = [], style = "", tag = "div") => `<${tag} class="${cls}" data-layout-kind="${kind}"${attr(a)}${style ? ` style="${style}"` : ""}>${kids.join("")}</${tag}>`;
const L = (alignment) => ({ leading: [0, .5], trailing: [1, .5], top: [.5, 0], bottom: [.5, 1], center: [.5, .5], topLeading: [0, 0], topTrailing: [1, 0], bottomLeading: [0, 1], bottomTrailing: [1, 1] })[alignment ?? "center"];
const probe = (name) => name ? { "data-probe": name } : {};
const num = (v) => v === Infinity ? "inf" : v;
export const F = ({ w, h, minW, maxW, minH, maxH, align, p } = {}, ...kids) => {
  const [ax, ay] = L(align);
  return node("frame-box", "frame", { "data-frame-w": w, "data-frame-h": h, "data-frame-min-w": minW, "data-frame-max-w": num(maxW), "data-frame-min-h": minH, "data-frame-max-h": num(maxH), "data-align-x": ax, "data-align-y": ay, ...probe(p) }, kids);
};
const Pad = ({ top = 0, leading = 0, bottom = 0, trailing = 0, p } = {}, ...kids) => node("padding", "padding", { "data-padding-top": top, "data-padding-leading": leading, "data-padding-bottom": bottom, "data-padding-trailing": trailing, ...probe(p) }, kids);
const V = ({ spacing = 8, align = "center", priority, p } = {}, ...kids) => node("vstack", "vstack", { "data-layout-gap": spacing, "data-align-x": L(align)[0], "data-layout-priority": priority, ...probe(p) }, kids);
const H = ({ spacing = 8, align = "center", p } = {}, ...kids) => node("hstack", "hstack", { "data-layout-gap": spacing, "data-align-y": align === "baseline" ? undefined : L(align)[1], "data-layout-alignment": align === "baseline" ? "baseline" : undefined, ...probe(p) }, kids);
const Overlay = ({ align = "center", p } = {}, base, ...layers) => node("overlay-layer", "overlay", { "data-align-x": L(align)[0], "data-align-y": L(align)[1], ...probe(p) }, [base, ...layers]);
const Background = ({ align = "center", p } = {}, base, ...layers) => node("backdrop-layer", "background", { "data-align-x": L(align)[0], "data-align-y": L(align)[1], ...probe(p) }, [...layers, base]);
const Aspect = ({ ratio, fill = false, p } = {}, ...kids) => node("aspect-box", "aspect", { "data-aspect-ratio": ratio, "data-aspect-fill": fill, ...probe(p) }, kids);
const Table = ({ spacing = 8, rowSpacing = 8, align = "center", p } = {}, ...rows) => node("table-view", "table", { "data-layout-gap": spacing, "data-row-spacing": rowSpacing, "data-align-x": L(align)[0], "data-align-y": L(align)[1], ...probe(p) }, rows);
const GridRow = ({ align, p } = {}, ...cells) => node("grid-row", "gridrow", { "data-row-align-y": align ? L(align)[1] : undefined, ...probe(p) }, cells);
const Geo = ({ p } = {}, ...kids) => node("geometry-reader passthrough", "geometry", { "data-geometry-reader": "true", ...probe(p) }, kids);
const ShapeP = (color, p) => `<div class="shape-layer" style="background:${color}" data-probe="${p}"></div>`;
const Z = ({ align = "center", p } = {}, ...kids) => node("zstack", "zstack", { "data-align-x": L(align)[0], "data-align-y": L(align)[1], ...probe(p) }, kids);
const Spacer = ({ min = 8, priority, p } = {}) => node("flex-spacer", "spacer", { "data-spacer-min": min, "data-layout-priority": priority, ...probe(p) });
// A user-defined Layout's wrapper (Swift sizes it for the proposal the page reports; `sizers` below answer as the Layout does).
const Lay = (layout, p) => node("layout-box", "size", { "data-layout-proposal": "true", "data-layout-content-width": 0, "data-layout-content-height": 0, "data-emulate": layout, ...probe(p) });
const Fixed = ({ x = true, y = true, p } = {}, ...kids) => node("fixed", "fixed", { "data-fixed-x": x, "data-fixed-y": y, ...probe(p) }, kids);
const Shape = (color = "red") => `<div class="shape-layer" style="background:${color}"></div>`;
const Color = (w, h, color, p) => F({ w, h, p }, Shape(color));
const FONT = "font:17px/20px -apple-system,system-ui,sans-serif;";
const T = (text, { line1, priority, p } = {}) => node("", "intrinsic", { "data-layout-leaf": "text", "data-layout-priority": priority, ...probe(p) }, [text], FONT + (line1 ? "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" : ""), "span");
// A browser text leaf with an ideal width (the `Leaves` of the earlier engine's tests): wraps to nothing, reports min(proposal, ideal), 20 tall.
const Leaf = (ideal, p, extra = {}) => node("", "intrinsic", { "data-layout-leaf": "text", ...extra, ...probe(p) }, [`<span style="display:block;width:${ideal}px;height:20px"></span>`], "overflow:hidden;height:20px;", "span");
// A menu Picker's <select>, as wide as its selected label (`--sl-select-w`, which the page measures) when it has room.
const Select = (ideal, p) => `<select data-probe="${p}" style="--sl-select-w:${ideal}px"><option>Chocolate Glaze</option><option>Sour Candy Glaze</option></select>`;
const Grid = ({ tracks, rowSpacing = 8, spacing = 8, p, horizontal } = {}, ...kids) => node("grid-layout" + (horizontal ? " hgrid" : ""), "grid", { "data-grid-tracks": tracks, "data-row-spacing": rowSpacing, "data-layout-gap": spacing, ...probe(p) }, kids);
const LONG = "SwiftUI proposes a width and this sentence should wrap into multiple lines because it is long enough to need them, and then some more words to be safe. ".repeat(3);

// ---- Apple fixtures --------------------------------------------------------------------------------------------------
const host = (id, ...kids) => F({ w: 320, h: 240, p: id + ".host" }, ...kids);
const fixtures = {
  "root-text": () => host("root-text", T("Hello world", { p: "root-text.text" })),
  "proposal-probe": null, // a user-defined Layout: Swift decides, no CSS equivalent
  "vstack-center": () => host("vstack-center", V({ spacing: 10 }, Color(40, 20, "red", "vstack-center.a"), Color(80, 30, "blue", "vstack-center.b"))),
  "vstack-leading": () => host("vstack-leading", V({ spacing: 10, align: "leading" }, Color(40, 20, "red", "vstack-leading.a"), Color(80, 30, "blue", "vstack-leading.b"))),
  "hstack-spacer": () => host("hstack-spacer", F({ w: 260, h: 60 }, H({ spacing: 0 }, Color(40, 20, "red", "hstack-spacer.left"), Spacer(), Color(60, 20, "blue", "hstack-spacer.right")))),
  "spacer-min": () => host("spacer-min", F({ w: 100, h: 120 }, V({ spacing: 0 }, Color(30, 20, "red", "spacer-min.top"), Spacer({ min: 44 }), Color(30, 20, "blue", "spacer-min.bottom")))),
  "frame-strict": () => host("frame-strict", F({ w: 180, h: 90, p: "frame-strict.child" }, Color(40, 20, "red"))),
  "frame-infinity-leading": () => host("frame-infinity-leading", F({ maxW: Infinity, align: "leading" }, T("Leading", { p: "frame-infinity-leading.child" }))),
  "layout-priority": () => host("layout-priority", F({ w: 190, h: 50 }, H({ spacing: 0 }, T("HIGH PRIORITY CONTENT", { line1: 1, priority: 1, p: "layout-priority.high" }), T("lower priority content", { line1: 1, p: "layout-priority.low" })))),
  "layout-priority-reversed": () => host("layout-priority-reversed", F({ w: 190, h: 50 }, H({ spacing: 0 }, T("lower priority content", { line1: 1, p: "layout-priority-reversed.low" }), T("HIGH PRIORITY CONTENT", { line1: 1, priority: 1, p: "layout-priority-reversed.high" })))),
  "layout-priority-three-levels": () => host("layout-priority-three-levels", F({ w: 190, h: 50 }, H({ spacing: 0 }, T("HIGH PRIORITY CONTENT", { line1: 1, priority: 2, p: "layout-priority-three-levels.high" }), T("lower priority content", { line1: 1, priority: 1, p: "layout-priority-three-levels.middle" }), T("lower priority content", { line1: 1, p: "layout-priority-three-levels.low" })))),
  "fixed-size": () => host("fixed-size", F({ w: 120 }, Fixed({ x: true, y: false }, T("This text has an intentionally long intrinsic width", { p: "fixed-size.text" })))),
  "zstack-bottom-trailing": () => host("zstack-bottom-trailing", Z({ align: "bottomTrailing" }, F({ w: 200, h: 120 }, Shape("transparent")), Color(40, 30, "red", "zstack-bottom-trailing.child"))),
  "text-wrapping": () => host("text-wrapping", F({ w: 130, p: "text-wrapping.text" }, T("SwiftUI proposes a width and this sentence should wrap into multiple lines."))),
  "nested-frames": () => host("nested-frames", F({ w: 200, h: 140, align: "topLeading" }, F({ w: 90, h: 70, align: "bottomTrailing", p: "nested-frames.inner" }, Color(30, 20, "red")))),
  "hstack-text-spacer": () => host("hstack-text-spacer", F({ w: 190, h: 50 }, H({ spacing: 0 }, T("A medium length title", { p: "hstack-text-spacer.text" }), Spacer({ min: 0 })))),
  "fixed-column-text": () => host("fixed-column-text", F({ w: 240, h: 80 }, H({ spacing: 12 }, Color(44, 60, "red", "fixed-column-text.poster"), V({ spacing: 0, align: "leading" }, T("A medium length title", { p: "fixed-column-text.title" })), Spacer({ min: 0 })))),
  "lazy-grid-top": () => host("lazy-grid-top", F({ w: 300 }, Grid({ tracks: "flexible:10:inf::0.5:0|flexible:10:inf::0.5:0", rowSpacing: 10 }, Color(50, 40, "red", "lazy-grid-top.a"), Color(50, 80, "blue", "lazy-grid-top.b")))),
  "lazy-grid-fill": () => host("lazy-grid-fill", F({ w: 300 }, Grid({ tracks: "flexible:10:inf:30|flexible:10:inf", rowSpacing: 10 }, F({ maxH: Infinity, p: "lazy-grid-fill.a" }, F({ w: 50 }, Shape("red"))), Color(50, 80, "blue", "lazy-grid-fill.b")))),
  "grid-row-alignment": () => host("grid-row-alignment", Table({ spacing: 10, rowSpacing: 10, align: "topLeading" }, GridRow({}, Color(50, 40, "red", "grid-row-alignment.a"), Color(80, 80, "blue", "grid-row-alignment.b")), GridRow({ align: "bottom" }, Color(30, 20, "red", "grid-row-alignment.c"), Color(50, 60, "blue", "grid-row-alignment.d")))),
};


// ---- extra fixtures (Tools/LayoutConformance/CssLayoutOracle.swift) -------------------------------------------------------
const T17 = (text, p) => T(text, { p });
const extras = {
  "x-two-texts": () => host("x-two-texts", F({ w: 260 }, H({ spacing: 8 }, T17("A fairly long first text that needs room", "x-two-texts.a"), T17("Another quite long second text here", "x-two-texts.b")))),
  "x-three-texts": () => host("x-three-texts", F({ w: 280 }, H({ spacing: 6 }, T17("Short", "x-three-texts.a"), T17("A medium sized text", "x-three-texts.b"), T17("A rather long closing text, longer", "x-three-texts.c")))),
  "x-frame-cap": () => host("x-frame-cap", F({ w: 300 }, V({ spacing: 0, align: "leading" }, F({ maxW: 120, align: "leading", p: "x-frame-cap.cap" }, T17("Capped"))))),
  "x-frame-cap-hug": () => host("x-frame-cap-hug", V({ spacing: 4, align: "leading", p: "x-frame-cap-hug.stack" }, F({ maxW: 120, p: "x-frame-cap-hug.cap" }, T17("Capped text wraps at its maximum width of one hundred and twenty")), T17("Next", "x-frame-cap-hug.next"))),
  "x-frame-min": () => host("x-frame-min", F({ minW: 150, minH: 60, p: "x-frame-min.f" }, T17("Hi"))),
  "x-frame-minmax": () => host("x-frame-minmax", F({ w: 300 }, V({ spacing: 4 }, F({ minW: 100, maxW: 200, p: "x-frame-minmax.a" }, T17("a")), F({ minW: 100, maxW: 200, p: "x-frame-minmax.b" }, T17("A longer text inside"))))),
  "x-padding": () => host("x-padding", Pad({ top: 8, leading: 20, trailing: 20, p: "x-padding.p" }, T17("Padded"))),
  "x-padding-fill": () => host("x-padding-fill", Pad({ top: 16, leading: 16, bottom: 16, trailing: 16, p: "x-padding-fill.p" }, F({ maxW: Infinity, align: "leading" }, T17("Pad")))),
  "x-overlay": () => host("x-overlay", Overlay({ align: "bottomTrailing", p: "x-overlay.base" }, Color(120, 60, "blue"), Color(30, 20, "red", "x-overlay.o"))),
  "x-overlay-fill": () => host("x-overlay-fill", Overlay({ p: "x-overlay-fill.base" }, T17("Label"), ShapeP("green", "x-overlay-fill.o"))),
  "x-grid-fill-row": () => host("x-grid-fill-row", Fixed({ x: false, p: "x-grid-fill-row.grid" }, Table({ spacing: 12, rowSpacing: 12 }, GridRow({}, V({ p: "x-grid-fill-row.a" }, T17("Orders"), F({ maxW: Infinity, maxH: 100, p: "x-grid-fill-row.tiles" }, Aspect({ ratio: 2 }, Shape("green")))), V({ p: "x-grid-fill-row.b" }, T17("Weather"), F({ minH: 60, p: "x-grid-fill-row.chart" }, Geo({}, Shape("orange")))))))),
  "x-frame-min-geo": () => host("x-frame-min-geo", Fixed({ x: false, p: "x-frame-min-geo.stack" }, V({ spacing: 8 }, T17("Total"), F({ minH: 120, p: "x-frame-min-geo.frame" }, Geo({ p: "x-frame-min-geo.reader" }, Shape("red")))))),
  "x-frame-max-hug": () => host("x-frame-max-hug", Fixed({ x: false, p: "x-frame-max-hug.stack" }, V({ spacing: 8 }, T17("Tiles"), F({ maxW: Infinity, maxH: 80, p: "x-frame-max-hug.frame" }, Aspect({ ratio: 2, p: "x-frame-max-hug.aspect" }, Shape("green")))))),
  "x-frame-min-fill": () => host("x-frame-min-fill", Fixed({ x: false }, F({ maxW: Infinity, minH: 120, p: "x-frame-min-fill.gallery" }, H({ spacing: 4 }, F({ maxW: Infinity, maxH: Infinity, align: "bottomLeading", p: "x-frame-min-fill.a" }, V({ spacing: 6, align: "leading" }, Spacer(), T17("Bora"))), F({ maxW: Infinity, maxH: Infinity, align: "bottomLeading", p: "x-frame-min-fill.b" }, V({ spacing: 6, align: "leading" }, Spacer(), T17("Lagoon"))))))),
  "x-background": () => host("x-background", Background({ p: "x-background.base" }, Pad({ top: 10, leading: 10, bottom: 10, trailing: 10 }, T17("Background")), ShapeP("orange", "x-background.bg"))),
  "x-aspect-fit": () => host("x-aspect-fit", F({ w: 100, h: 100 }, Aspect({ ratio: 2, p: "x-aspect-fit.a" }, Shape("red")))),
  "x-aspect-width": () => host("x-aspect-width", F({ w: 150 }, V({ spacing: 0 }, Aspect({ ratio: 0.75, p: "x-aspect-width.a" }, Shape("red"))))),
  "x-geometry": () => host("x-geometry", F({ w: 200, h: 100, p: "x-geometry.g" }, Geo({}, F({ w: 100 }, T17("Top leading", "x-geometry.t"))))),
  "x-fixed-vertical": () => host("x-fixed-vertical", F({ w: 110, p: "x-fixed-vertical.f" }, Fixed({ x: false, y: true }, T("A long sentence that has to wrap into several lines inside this narrow frame.")))),
  "x-zstack-topleading": () => host("x-zstack-topleading", Z({ align: "topLeading", p: "x-zstack-topleading.z" }, Color(160, 100, "blue"), Color(50, 40, "red", "x-zstack-topleading.r"), T17("Text", "x-zstack-topleading.t"))),
  "x-vstack-spacer": () => host("x-vstack-spacer", F({ w: 150, h: 200 }, V({ spacing: 0 }, T17("Top", "x-vstack-spacer.t"), Spacer({ min: 8 }), T17("Bottom", "x-vstack-spacer.b")))),
  "x-flex-vs-text": () => host("x-flex-vs-text", F({ w: 260, h: 40 }, H({ spacing: 10 }, ShapeP("red", "x-flex-vs-text.c"), T17("A text beside a color", "x-flex-vs-text.t")))),
  "x-trailing-stack": () => host("x-trailing-stack", V({ spacing: 4, align: "trailing", p: "x-trailing-stack.v" }, T17("Short", "x-trailing-stack.a"), T17("A much longer line", "x-trailing-stack.b"))),
  "x-baseline": () => host("x-baseline", H({ spacing: 8, align: "baseline", p: "x-baseline.h" }, node("", "intrinsic", { "data-layout-leaf": "text", ...probe("x-baseline.a") }, ["Big"], "font:28px/33px -apple-system,system-ui,sans-serif", "span"), node("", "intrinsic", { "data-layout-leaf": "text", ...probe("x-baseline.b") }, ["small"], "font:12px/15px -apple-system,system-ui,sans-serif", "span"))),
  "x-nested-flex": () => host("x-nested-flex", F({ w: 240, p: "x-nested-flex.h" }, H({ spacing: 8 }, V({ spacing: 2, align: "leading", p: "x-nested-flex.v" }, T17("Title that is long enough to wrap around"), node("", "intrinsic", { "data-layout-leaf": "text" }, ["Subtitle"], "font:13px/16px -apple-system,system-ui,sans-serif", "span")), Spacer({ min: 0 }), node("", "intrinsic", { "data-layout-leaf": "text", ...probe("x-nested-flex.g") }, ["Go"], "font:15px/19px -apple-system,system-ui,sans-serif", "span")))),
  "x-text-in-frame-height": () => host("x-text-in-frame-height", F({ h: 40, p: "x-text-in-frame-height.v" }, V({ spacing: 0 }, F({ w: 120, p: "x-text-in-frame-height.t" }, T17("Line one line two line three line four line five"))))),
  // A finite maximum height caps the aspect box inside it; a Layout is proposed no height down a chain of hugging views (see the Apple
  // fixtures of the same names in CssLayoutOracle.swift).
  "x-aspect-cap-tall": () => host("x-aspect-cap-tall", Fixed({ x: false, p: "x-aspect-cap-tall.stack" }, V({ spacing: 8 }, T17("Tiles"), F({ maxW: Infinity, maxH: 80, p: "x-aspect-cap-tall.frame" }, Aspect({ ratio: 0.5, p: "x-aspect-cap-tall.aspect" }, Shape("green")))))),
  "x-aspect-cap-padded": () => host("x-aspect-cap-padded", Fixed({ x: false, p: "x-aspect-cap-padded.stack" }, V({ spacing: 8 }, T17("Tiles"), node("frame-box", "frame", { "data-frame-max-w": "inf", "data-frame-max-h": 80, "data-align-x": .5, "data-align-y": .5, "data-layout-wrap": "padding;padding-top=10;padding-leading=10;padding-bottom=10;padding-trailing=10", "data-probe": "x-aspect-cap-padded.frame" }, [Aspect({ ratio: 2, p: "x-aspect-cap-padded.aspect" }, Shape("green"))])))),
  "x-aspect-cap-narrow": () => host("x-aspect-cap-narrow", F({ w: 100, p: "x-aspect-cap-narrow.stack" }, Fixed({ x: false }, V({ spacing: 8 }, T17("Tiles"), F({ maxW: Infinity, maxH: 80, p: "x-aspect-cap-narrow.frame" }, Aspect({ ratio: 2, p: "x-aspect-cap-narrow.aspect" }, Shape("green"))))))),
  "x-aspect-hero": () => host("x-aspect-hero", Fixed({ x: false, p: "x-aspect-hero.stack" }, V({ spacing: 8 }, T17("Tiles"), F({ maxW: Infinity, maxH: 100, p: "x-aspect-hero.frame" }, Aspect({ ratio: 2, p: "x-aspect-hero.aspect" }, Lay("hero", "x-aspect-hero.layout")))))),
  "x-layout-stack-hug": () => host("x-layout-stack-hug", Fixed({ x: false, p: "x-layout-stack-hug.stack" }, V({ spacing: 8 }, H({ spacing: 8 }, T17("Donuts"), Spacer()), F({ minH: 60, maxH: Infinity, p: "x-layout-stack-hug.frame" }, Lay("donut", "x-layout-stack-hug.lattice"))))),
  "x-layout-grid-hug": () => host("x-layout-grid-hug", Fixed({ x: false, p: "x-layout-grid-hug.grid" }, Table({ spacing: 12, rowSpacing: 12 }, GridRow({}, V({ spacing: 8, p: "x-layout-grid-hug.card" }, H({ spacing: 8 }, T17("Donuts"), Spacer()), F({ minH: 60, maxH: Infinity, p: "x-layout-grid-hug.frame" }, Lay("donut", "x-layout-grid-hug.lattice"))))))),
  "x-layout-grid-tall": () => host("x-layout-grid-tall", Fixed({ x: false, p: "x-layout-grid-tall.grid" }, Table({ spacing: 12, rowSpacing: 12 }, GridRow({}, V({ spacing: 8, p: "x-layout-grid-tall.card" }, H({ spacing: 8 }, T17("Donuts"), Spacer()), F({ minH: 60, maxH: Infinity, p: "x-layout-grid-tall.frame" }, Lay("donut", "x-layout-grid-tall.lattice"))), F({ h: 200, p: "x-layout-grid-tall.other" }, Shape("blue")))))),
  "x-layout-scroll": () => host("x-layout-scroll", node("scroll-view scroll-vertical", "scroll", { "data-probe": "x-layout-scroll.scroll" }, [F({ minH: 60, maxH: Infinity, p: "x-layout-scroll.frame" }, Lay("donut", "x-layout-scroll.lattice"))])),
  // What holds a screen without a bar (a navigation without chrome); x-navigation-tab is not mapped (macOS's tab bar).
  "x-navigation": () => host("x-navigation", node("navigation-destination", "panel", {}, [T17("Detail", "x-navigation.t")])),
  "x-navigation-pushed": () => host("x-navigation-pushed", node("navigation-destination", "panel", {}, [T17("Pushed", "x-navigation-pushed.t")])),
};

// ---- controls the browser sizes by itself (Tools/LayoutConformance/CssLayoutOracle.swift, "x-divider-*" and the rest) ----------
// Each as the page has it with the stylesheet's rules for it: a Divider is an `hr` with a point of border along its top, a progress
// bar and a slider have no skin (`appearance: none`), so the browser gives them no size.
const Hr = (p) => `<hr data-probe="${p}" style="height:0;border:0 solid;border-top-width:1px">`;
const Bar = (p) => `<progress class="progress-bar" data-probe="${p}" max="1" value="0.4" style="display:block;appearance:none;border:0"></progress>`;
const Range = (p) => `<input type="range" class="slider-control" data-probe="${p}" min="0" max="1" step="any" value="0.4" style="display:block;appearance:none;margin:0">`;
const Meter = (p) => `<div class="gauge-meter" data-probe="${p}" style="display:flex;flex-direction:column;gap:8px">${T17("Level")}<progress max="1" value="0.5" style="width:100%;height:8px;appearance:none;border:0"></progress></div>`;
const Editor = (p) => `<textarea class="text-area" data-probe="${p}" style="resize:none;border:0;padding:0;appearance:none;font:17px/20px -apple-system,system-ui,sans-serif">Notes</textarea>`;
const Draw = (p) => `<canvas data-probe="${p}"></canvas>`;
const Menu = (p) => Select(156, p);
const controls = {
  "x-divider-vstack": () => host("x-divider-vstack", F({ w: 200, p: "x-divider-vstack.v" }, V({ spacing: 8, align: "leading" }, T17("Above"), Hr("x-divider-vstack.d"), T17("Below")))),
  "x-divider-vstack-centred": () => host("x-divider-vstack-centred", V({ spacing: 8, p: "x-divider-vstack-centred.v" }, T17("Above"), Hr("x-divider-vstack-centred.d"), T17("Below"))),
  "x-divider-hstack": () => host("x-divider-hstack", F({ w: 200, h: 40, p: "x-divider-hstack.h" }, H({ spacing: 8 }, T17("Left"), Hr("x-divider-hstack.d"), T17("Right")))),
  "x-divider-hstack-fills": () => host("x-divider-hstack-fills", H({ spacing: 8, p: "x-divider-hstack-fills.h" }, T17("Left"), Hr("x-divider-hstack-fills.d"), T17("Right"))),
  "x-divider-fixed-hstack": () => host("x-divider-fixed-hstack", Fixed({ x: false, p: "x-divider-fixed-hstack.h" }, H({ spacing: 8 }, T17("Left"), Hr("x-divider-fixed-hstack.d"), T17("Right")))),
  "x-divider-fixed-vstack": () => host("x-divider-fixed-vstack", Fixed({ p: "x-divider-fixed-vstack.v" }, V({ spacing: 8, align: "leading" }, T17("Above"), Hr("x-divider-fixed-vstack.d"), T17("Below")))),
  "x-divider-framed": () => host("x-divider-framed", F({ w: 200, p: "x-divider-framed.v" }, V({ spacing: 8, align: "leading" }, F({ w: 100, p: "x-divider-framed.fa" }, Hr("x-divider-framed.a")), F({ h: 20, p: "x-divider-framed.fb" }, Hr("x-divider-framed.b"))))),
  "x-divider-alone": () => host("x-divider-alone", Hr("x-divider-alone.d")),
  "x-divider-width": () => host("x-divider-width", F({ w: 100, p: "x-divider-width.f" }, Hr("x-divider-width.d"))),
  "x-divider-frame-in-hstack": () => host("x-divider-frame-in-hstack", H({ spacing: 8, p: "x-divider-frame-in-hstack.h" }, T17("Left"), F({ h: 20, p: "x-divider-frame-in-hstack.f" }, Hr("x-divider-frame-in-hstack.d")), T17("Right"))),
  "x-divider-padding-in-hstack": () => host("x-divider-padding-in-hstack", F({ w: 200, h: 40, p: "x-divider-padding-in-hstack.h" }, H({ spacing: 8 }, T17("Left"), Pad({ leading: 4, trailing: 4, p: "x-divider-padding-in-hstack.p" }, Hr("x-divider-padding-in-hstack.d")), T17("Right")))),
  "x-divider-width-in-hstack": () => host("x-divider-width-in-hstack", F({ w: 200, h: 40, p: "x-divider-width-in-hstack.h" }, H({ spacing: 8 }, T17("Left"), F({ w: 30, p: "x-divider-width-in-hstack.f" }, Hr("x-divider-width-in-hstack.d")), T17("Right")))),
  "x-divider-max-height-in-hstack": () => host("x-divider-max-height-in-hstack", F({ w: 200, h: 40, p: "x-divider-max-height-in-hstack.h" }, H({ spacing: 8 }, T17("Left"), F({ maxH: Infinity, p: "x-divider-max-height-in-hstack.f" }, Hr("x-divider-max-height-in-hstack.d")), T17("Right")))),
  "x-divider-overlay-in-hstack": () => host("x-divider-overlay-in-hstack", F({ w: 200, h: 40, p: "x-divider-overlay-in-hstack.h" }, H({ spacing: 8 }, T17("Left"), Overlay({ p: "x-divider-overlay-in-hstack.o" }, F({ w: 20 }, ShapeP("transparent", "x-divider-overlay-in-hstack.base")), Hr("x-divider-overlay-in-hstack.d")), T17("Right")))),
  "x-divider-zstack-in-hstack": () => host("x-divider-zstack-in-hstack", F({ w: 200, h: 40, p: "x-divider-zstack-in-hstack.h" }, H({ spacing: 8 }, T17("Left"), Z({ p: "x-divider-zstack-in-hstack.z" }, Hr("x-divider-zstack-in-hstack.d")), T17("Right")))),
  "x-divider-vstack-in-hstack": () => host("x-divider-vstack-in-hstack", F({ w: 200, h: 40, p: "x-divider-vstack-in-hstack.h" }, H({ spacing: 8 }, T17("Left"), V({ p: "x-divider-vstack-in-hstack.v" }, Hr("x-divider-vstack-in-hstack.d")), T17("Right")))),
  "x-slider-row": () => host("x-slider-row", F({ w: 260, h: undefined, p: "x-slider-row.h" }, H({ spacing: 8 }, T17("Vol"), Range("x-slider-row.p"), T17("100")))),
  "x-menu-picker-hstack": () => host("x-menu-picker-hstack", F({ w: 300, p: "x-menu-picker-hstack.h" }, H({ spacing: 8 }, T17("Genre"), Menu("x-menu-picker-hstack.p"), Spacer()))),
  "x-menu-picker-framed": () => host("x-menu-picker-framed", F({ w: 150, p: "x-menu-picker-framed.f" }, Menu("x-menu-picker-framed.p"))),
  "x-menu-picker-wide-frame": () => host("x-menu-picker-wide-frame", F({ w: 250, p: "x-menu-picker-wide-frame.f" }, Menu("x-menu-picker-wide-frame.p"))),
  "x-menu-picker-tiny-frame": () => host("x-menu-picker-tiny-frame", F({ w: 40, p: "x-menu-picker-tiny-frame.f" }, Menu("x-menu-picker-tiny-frame.p"))),
  "x-menu-picker-alone": () => host("x-menu-picker-alone", Menu("x-menu-picker-alone.p")),
  "x-menu-picker-centred": () => host("x-menu-picker-centred", V({ spacing: 8, p: "x-menu-picker-centred.v" }, T17("Genre"), Menu("x-menu-picker-centred.p"))),
  "x-menu-picker-share": () => host("x-menu-picker-share", F({ w: 250, h: 40, p: "x-menu-picker-share.h" }, H({ spacing: 8 }, Menu("x-menu-picker-share.a"), Menu("x-menu-picker-share.b")))),
  "x-editor-height": () => host("x-editor-height", F({ h: 90, p: "x-editor-height.f" }, Editor("x-editor-height.e"))),
  "x-editor-size": () => host("x-editor-size", F({ w: 200, h: 90, p: "x-editor-size.f" }, Editor("x-editor-size.e"))),
  "x-editor-alone": () => host("x-editor-alone", Editor("x-editor-alone.e")),
  "x-editor-vstack": () => host("x-editor-vstack", F({ w: 200, h: 150, p: "x-editor-vstack.v" }, V({ spacing: 8, align: "leading" }, T17("Notes"), Editor("x-editor-vstack.e")))),
  "x-editor-framed-in-vstack": () => host("x-editor-framed-in-vstack", F({ w: 200, p: "x-editor-framed-in-vstack.v" }, V({ spacing: 8, align: "leading" }, T17("Notes"), F({ h: 90, p: "x-editor-framed-in-vstack.f" }, Editor("x-editor-framed-in-vstack.e"))))),
  "x-editor-padded": () => host("x-editor-padded", Pad({ top: 4, leading: 4, bottom: 4, trailing: 4, p: "x-editor-padded.p" }, F({ w: 200, h: 90 }, Editor("x-editor-padded.e")))),
  "x-canvas-size": () => host("x-canvas-size", F({ w: 200, h: 12, p: "x-canvas-size.f" }, Draw("x-canvas-size.c"))),
  "x-canvas-height": () => host("x-canvas-height", F({ w: 200, p: "x-canvas-height.v" }, V({ spacing: 8, align: "leading" }, T17("Canvas"), F({ h: 12, p: "x-canvas-height.f" }, Draw("x-canvas-height.c"))))),
  "x-canvas-alone": () => host("x-canvas-alone", Draw("x-canvas-alone.c")),
  "x-canvas-ideal": () => host("x-canvas-ideal", Fixed({ x: false, p: "x-canvas-ideal.v" }, V({ spacing: 8, align: "leading" }, T17("Canvas"), Draw("x-canvas-ideal.c")))),
  "x-canvas-vstack": () => host("x-canvas-vstack", F({ w: 200, h: 100, p: "x-canvas-vstack.v" }, V({ spacing: 8, align: "leading" }, T17("Canvas"), Draw("x-canvas-vstack.c")))),
};
for (const [name, make] of [["progress", Bar], ["slider", Range], ["gauge", Meter]]) {
  const id = (suffix) => `x-${name}-${suffix}`;
  controls[id("vstack")] = () => host(id("vstack"), F({ w: 200, p: id("vstack") + ".v" }, V({ spacing: 8, align: "leading" }, T17("Label"), make(id("vstack") + ".p"))));
  controls[id("hstack")] = () => host(id("hstack"), F({ w: 260, p: id("hstack") + ".h" }, H({ spacing: 8 }, T17("Label"), make(id("hstack") + ".p"))));
  controls[id("framed")] = () => host(id("framed"), F({ w: 150, p: id("framed") + ".f" }, make(id("framed") + ".p")));
  controls[id("alone")] = () => host(id("alone"), make(id("alone") + ".p"));
  controls[id("centred")] = () => host(id("centred"), V({ spacing: 8, p: id("centred") + ".v" }, T17("Label"), make(id("centred") + ".p")));
}
Object.assign(extras, controls);
// The controls' chrome is the platform's (a macOS progress bar is 20 pt tall, a slider 16, a gauge 46.5 with its label, a pop-up button
// 24; the web authors 8 px, 6 px, 40 px and a select of its own), so only where they are and how wide they are is compared. A
// container that holds one is as tall as its chrome, so its height is left out too.
const PARTIAL = (id) => /^x-(progress|slider|gauge|menu-picker)-/.test(id) ? ["x", "width"] : null;

// ---- the translated conformance cases (expected values are the asserts; proposal is the width of the wrapper) ------------------
const ported = [
  { id: "ported:grid-shares-columns", w: 320, tree: () => Table({ spacing: 10, rowSpacing: 10, align: "topLeading", p: "g" }, GridRow({}, Color(50, 40, "red", "a"), Color(80, 80, "blue", "b")), GridRow({ align: "bottom" }, Color(30, 20, "red", "c"), Color(50, 60, "blue", "d"))), expect: { a: { x: 0, y: 0 }, b: { x: 60, y: 0 }, c: { x: 0, y: 130 }, d: { x: 60, y: 90 }, g: { w: 140, h: 150 } } },
  { id: "ported:grid-unspecified-width", w: 0, tree: () => Table({ spacing: 10, rowSpacing: 0, align: "topLeading", p: "g" }, GridRow({}, Leaf(30, "a"), Leaf(70, "b")), GridRow({}, Leaf(50, "c")), Leaf(200, "s")), expect: { a: { w: 30 }, c: { w: 50 }, b: { x: 60 }, s: { w: 130 }, g: { w: 130, h: 60 } } },
  { id: "ported:grid-without-rows", w: 120, tree: () => Table({ spacing: 8, rowSpacing: 4, align: "topLeading", p: "g" }, Leaf(80, "a"), Leaf(300, "b")), expect: { a: { w: 80 }, b: { w: 120, y: 24 }, g: { w: 120, h: 44 } } },
  { id: "ported:grid-flexible-column-and-spanning", w: 300, tree: () => Table({ spacing: 14, rowSpacing: 8, align: "leading", p: "g" }, GridRow({}, Leaf(24, "k"), F({ maxW: Infinity, p: "f" }, Leaf(120, "t"))), `<div class="shape-layer" data-ideal-w="10" data-ideal-h="1" style="background:gray" data-probe="d"></div>`), expect: { k: { w: 24 }, f: { w: 262, x: 38 }, d: { w: 300, y: 28 } } },
  { id: "ported:text-takes-all-but-spacer-min", w: 190, tree: () => H({ spacing: 0 }, Leaf(260, "t"), Spacer({ min: 0, p: "s" })), expect: { t: { w: 190 }, s: { w: 0 } } },
  { id: "ported:spacer-min-reserved-peers-share", w: 300, tree: () => H({ spacing: 0 }, Color(30, 10, "red"), Leaf(300, "a"), Spacer({ min: 8, p: "s" }), Leaf(99.5, "b")), expect: { b: { w: 99.5 }, a: { w: 162.5 }, s: { w: 8 } } },
  { id: "ported:spacers-split-remainder", w: 190, tree: () => H({ spacing: 0 }, Spacer({ min: 8, p: "s1" }), Leaf(120, "t"), Spacer({ min: 8, p: "s2" })), expect: { t: { w: 120 }, s1: { w: 35 }, s2: { w: 35, x: 155 } } },
  { id: "ported:prioritized-spacer-first", w: 190, tree: () => H({ spacing: 0 }, Leaf(260, "t", { "data-layout-priority": -1 }), Spacer({ min: 8, priority: 0, p: "s" })), expect: { s: { w: 190 }, t: { w: 0 } } },
  { id: "ported:wrapped-spacer-is-flexible", w: 190, tree: () => H({ spacing: 0 }, Leaf(260, "t"), F({ minW: 0 }, Spacer({ min: 8 }))), expect: { t: { w: 95 } } },
  // Food Truck's Glaze row: Apple's picker (156 ideal) keeps its ideal width while the row fits, then shrinks (x-picker-row, x-picker-row-tight).
  { id: "ported:picker-row-fits", w: 270, tree: () => H({ spacing: 0 }, Leaf(43, "l"), Spacer({ min: 12, p: "s" }), Select(156, "p")), expect: { l: { w: 43 }, s: { w: 71 }, p: { w: 156, x: 114 } } },
  { id: "ported:picker-row-tight", w: 150, tree: () => H({ spacing: 0 }, Leaf(43, "l"), Spacer({ min: 12, p: "s" }), Select(156, "p")), expect: { l: { w: 43 }, s: { w: 12 }, p: { w: 95, x: 55 } } },
  { id: "ported:fixed-column-title", w: 190, tree: () => H({ spacing: 12 }, Color(44, 60, "red"), V({ spacing: 0 }, Leaf(300, "t")), Spacer({ min: 0 })), expect: { t: { w: 122, x: 56 } } },
  { id: "ported:lazy-grid-track-alignment", w: 300, tree: () => Grid({ tracks: "flexible:10:inf:30:0.5:0|flexible:10:inf::0.5:0", rowSpacing: 10, p: "g" }, Color(50, 40, "red", "a"), Color(50, 80, "blue", "b")), expect: { a: { x: 42.5, y: 0 }, b: { x: 207.5, y: 0 }, g: { h: 80 } } },
  { id: "ported:lazy-grid-center-and-fill", w: 300, tree: () => Grid({ tracks: "flexible:10|flexible:10", rowSpacing: 10 }, F({ maxH: Infinity, p: "f" }, F({ w: 50 }, Shape("red"))), Color(50, 80, "blue"), Color(50, 40, "green", "c")), expect: { f: { h: 80, y: 0 }, c: { y: 90, x: 48 } } },
  // A LazyHGrid is as wide as its columns, which are `rowSpacing` apart; its rows are the tracks, `spacing` apart.
  { id: "ported:lazy-hgrid-hugs-its-columns", w: 300, tree: () => Grid({ horizontal: true, tracks: "flexible:10:inf:6:0.5:0|flexible:10:inf::0.5:0", rowSpacing: 20, p: "g" }, Color(50, 40, "red", "a"), Color(50, 40, "blue", "b"), Color(60, 40, "green", "c"), Color(60, 40, "red", "d")), expect: { a: { x: 0, y: 0 }, b: { x: 0, y: 46 }, c: { x: 70, y: 0 }, d: { x: 70, y: 46 }, g: { w: 130, h: 86 } } },
  { id: "ported:status-row-wraps-in-nested-stacks", w: 390, tree: () => H({ spacing: 8, p: "root" }, Color(40, 40, "red"), V({ spacing: 0 }, F({ maxW: Infinity }, H({ spacing: 0 }, Fixed({ x: false, y: true }, T(LONG, { p: "t" }))))) ), expect: { t: { w: 342 }, root: { w: 390 } } },
  { id: "ported:status-row-padding-leading-stacks", w: 390, tree: () => H({ spacing: 0 }, Pad({ top: 8, leading: 16, bottom: 8, trailing: 16 }, V({ spacing: 6, align: "leading" }, H({ spacing: 8, align: "top" }, Color(40, 40, "red"), V({ spacing: 6, align: "leading" }, V({ spacing: 0 }, F({ maxW: Infinity }, H({ spacing: 0 }, Fixed({ x: false, y: true }, T(LONG, { p: "t" })))))))))), expect: { t: { w: 390 - 32 - 40 - 8 } } },
  { id: "ported:section-frame-in-background", w: 1192, tree: () => node("backdrop-layer", "background", { "data-align-x": .5, "data-align-y": .5 }, [Color(10, 10, "red"), F({ maxW: Infinity, align: "leading", p: "f" }, V({ spacing: 8, align: "leading" }, Leaf(150, "t")))]), expect: { f: { w: 1192 }, t: { x: 0 } } },
];

// ---- run -----------------------------------------------------------------------------------------------------------
const css = readFileSync(root + "Tools/css-layout.js", "utf8").replace(/^export /gm, "");
const engines = { chromium, webkit, firefox };
const browser = await engines[browserName].launch();
const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
const cases = [];
let html = "<body style='margin:0'>";
let y = 0;
for (const [id, make] of Object.entries(fixtures)) {
  if (!make) continue;
  cases.push({ id, kind: "apple", y });
  html += `<div data-case="${id}" style="position:absolute;left:20px;top:${y}px;width:320px;height:240px">${make()}</div>`;
  y += 300;
}
const appleExtra = JSON.parse(readFileSync(args.includes("--apple-extra") ? args[args.indexOf("--apple-extra") + 1] : root + "Tests/LayoutConformance/apple-macos-css-extra.json", "utf8")).nodes;
if (appleExtra) for (const [id, make] of Object.entries(extras)) {
  cases.push({ id, kind: "extra", y });
  html += `<div data-case="${id}" style="position:absolute;left:20px;top:${y}px;width:320px;height:240px">${make()}</div>`;
  y += 300;
}
for (const c of ported) {
  cases.push({ id: c.id, kind: "ported", y });
  html += `<div data-case="${c.id}" style="position:absolute;left:400px;top:${(ported.indexOf(c)) * 220}px;${c.w ? `width:${c.w}px` : ""}">${F({ w: c.w || undefined, align: "topLeading", p: "__wrapper" }, c.tree())}</div>`;
}
html += "</body>";
await page.setContent(html);
await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
const info = await page.evaluate(() => {
  // What the user-defined Layouts of Food Truck answer for a proposal (nil on an axis: its default of an unbounded length).
  const big = Number.MAX_VALUE;
  const sizers = {
    donut: (w, h) => { const cell = Math.min((w ?? big) / 5, (h ?? big) / 3); return [cell * 5, cell * 3]; },
    hero: (w, h) => { const length = Math.min(((w ?? 100) - 10) * 0.5, h ?? 100); return [length * 2 + 10, length]; },
  };
  const changed = new Set();
  // Swift answers each proposal the page reports by writing the size the Layout takes (`layoutproposal`).
  const layout = new window.CssLayout(document, { baseline: true, onProposal: (box, w, h) => {
    const [cw, ch] = sizers[box.dataset.emulate](w, h).map((v) => String(Math.round(v * 64) / 64));
    if (box.getAttribute("data-layout-content-width") === cw && box.getAttribute("data-layout-content-height") === ch) return;
    box.setAttribute("data-layout-content-width", cw); box.setAttribute("data-layout-content-height", ch); changed.add(box);
  } });
  const unsupported = [], tops = [];
  for (const el of document.querySelectorAll("[data-case]")) {
    const top = el.firstElementChild;
    if (!layout.claim(top)) unsupported.push(el.dataset.case);
    layout.assign(top);
    tops.push(top);
  }
  layout.pending.clear();
  let passes = 0;
  for (; passes < 8; passes++) {
    changed.clear();
    layout.reportLayouts();
    if (!changed.size) break;
    for (const box of changed) { const top = tops.find((t) => t.contains(box)); layout.mark(box, top); layout.pending.add(top); }
    layout.style();
  }
  return { unsupported, stats: layout.stats, passes };
});
await page.waitForTimeout(100);
const measured = await page.evaluate(() => {
  const out = {};
  for (const el of document.querySelectorAll("[data-case]")) {
    const hostRect = el.firstElementChild.getBoundingClientRect();
    const frames = {};
    for (const p of el.querySelectorAll("[data-probe]")) {
      const r = p.getBoundingClientRect();
      frames[p.dataset.probe] = { x: r.x - hostRect.x, y: r.y - hostRect.y, width: r.width, height: r.height };
    }
    out[el.dataset.case] = frames;
  }
  return out;
});
await browser.close();

let total = 0, pass = 0;
const rows = [];
const perFixture = {};
for (const fixture of spec.fixtures) {
  if (!fixtures[fixture.id]) { perFixture[fixture.id] = { nodes: fixture.nodes.length, pass: 0, skipped: true }; continue; }
  const tolerance = Number(fixture.tolerance ?? 1);
  let ok = 0;
  for (const nodeId of fixture.nodes) {
    const a = apple[nodeId], w = measured[fixture.id]?.[nodeId];
    total++;
    if (!a || !w) { rows.push(`${fixture.id}  ${nodeId}  MISSING`); continue; }
    const d = ["x", "y", "width", "height"].map((k) => Math.abs(a[k] - w[k]));
    const good = Math.max(...d) <= tolerance;
    if (good) { pass++; ok++; }
    rows.push(`${good ? "PASS" : "FAIL"}  ${nodeId.padEnd(46)} apple ${["x", "y", "width", "height"].map((k) => a[k].toFixed(1)).join(",")}  css ${["x", "y", "width", "height"].map((k) => w[k].toFixed(1)).join(",")}`);
  }
  perFixture[fixture.id] = { nodes: fixture.nodes.length, pass: ok };
}
let extraTotal = 0, extraPass = 0; const extraRows = [];
if (appleExtra) for (const id of Object.keys(extras)) {
  for (const nodeId of Object.keys(appleExtra).filter((k) => k.startsWith(id + ".") && !k.endsWith(".host"))) {
    const a = appleExtra[nodeId], w = measured[id]?.[nodeId]; extraTotal++;
    if (!w) { extraRows.push(`MISSING ${nodeId}`); continue; }
    const tol = 1.5, keys = PARTIAL(id) ?? ["x", "y", "width", "height"], d = keys.map((k) => Math.abs(a[k] - w[k])), good = Math.max(...d) <= tol;
    if (good) extraPass++;
    extraRows.push(`${good ? "PASS" : "FAIL"}  ${nodeId.padEnd(40)} apple ${["x", "y", "width", "height"].map((k) => a[k].toFixed(1)).join(",")}  css ${["x", "y", "width", "height"].map((k) => w[k].toFixed(1)).join(",")}`);
  }
}
const skippedNodes = Object.values(perFixture).filter((f) => f.skipped).reduce((s, f) => s + f.nodes, 0);
console.log(`Apple fixtures (Tools/LayoutConformance, ${browserName}): ${pass}/${total} measured nodes within tolerance; ${skippedNodes} nodes in fixtures with no mapping (custom Layout, SwiftUI Grid)`);
let portedTotal = 0, portedPass = 0;
const portedRows = [];
for (const c of ported) {
  const frames = measured[c.id] ?? {};
  for (const [name, want] of Object.entries(c.expect)) {
    for (const [k, v] of Object.entries(want)) {
      portedTotal++;
      const key = { w: "width", h: "height", x: "x", y: "y" }[k];
      const got = frames[name]?.[key];
      const good = got !== undefined && Math.abs(got - v) <= 0.5;
      if (good) portedPass++;
      portedRows.push(`${good ? "PASS" : "FAIL"}  ${c.id}  ${name}.${k} expected ${v} got ${got === undefined ? "missing" : got.toFixed(2)}`);
    }
  }
}
if (appleExtra) { console.log(`Extra Apple fixtures (${Object.keys(extras).length} fixtures, ${browserName}): ${extraPass}/${extraTotal} nodes within 1.5`); console.log((verbose ? extraRows : extraRows.filter((r) => !r.startsWith("PASS"))).join("\n")); }
console.log(`Translated conformance cases (${ported.length} cases translated): ${portedPass}/${portedTotal} asserted values within 0.5`);
if (verbose) { console.log(rows.join("\n")); console.log(portedRows.join("\n")); }
else { console.log(rows.filter((r) => !r.startsWith("PASS")).join("\n")); console.log(portedRows.filter((r) => !r.startsWith("PASS")).join("\n")); }
console.log(JSON.stringify({ unsupported: info.unsupported, passes: info.passes, perFixture }, null, 0));

// What CSS cannot express exactly (Documentation/Architecture/CSS_LAYOUT.md, "What CSS does not match"): a truncated Text keeps
// the width of its ellipsis under layoutPriority in SwiftUI, a wrapped Text is as wide as its longest line, and a height
// truncates text.
const KNOWN_MISSES = new Set([
  "layout-priority.high", "layout-priority.low", "layout-priority-reversed.low", "layout-priority-reversed.high",
  "layout-priority-three-levels.high", "layout-priority-three-levels.middle",
  "x-two-texts.a", "x-two-texts.b", "x-three-texts.b", "x-three-texts.c", "x-flex-vs-text.c", "x-flex-vs-text.t",
  "x-text-in-frame-height.t",
  // SwiftUI sizes the capped frame with the aspect box proposed no height (it is 320 x 155 there, which the frame caps at 100), then places
  // the box at the 200 x 100 fit, where the Layout answers 95: the box takes the Layout's size. CSS keeps the box at the fit (the frame, the
  // stack and the Layout match); an aspect box is the size of what it holds when that cannot fill the fit, which the mapper does not follow.
  "x-aspect-hero.aspect",
]);
if (args.includes("--check")) {
  const missed = new Set([...rows, ...extraRows, ...portedRows].filter((r) => !r.startsWith("PASS")).map((r) => r.replace(/^(FAIL|MISSING)\s+/, "").split(/\s+/)[0]));
  const unexpected = [...missed].filter((id) => !KNOWN_MISSES.has(id)), fixed = [...KNOWN_MISSES].filter((id) => !missed.has(id));
  if (unexpected.length) console.log("UNEXPECTED MISSES " + unexpected.join(", "));
  if (fixed.length) console.log("KNOWN MISSES THAT PASS NOW (remove them from KNOWN_MISSES) " + fixed.join(", "));
  console.log(unexpected.length || fixed.length ? "FAIL css layout oracle" : `PASS css layout oracle (${KNOWN_MISSES.size} known misses)`);
  process.exit(unexpected.length || fixed.length ? 1 : 0);
}
