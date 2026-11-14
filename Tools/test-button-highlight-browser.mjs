#!/usr/bin/env bun
// Button highlight gate: the hover, pressed, focus and hit area of a button follow its shape.
//
// Drives the linked Showcase fixture at /buttonShape (Tests/Apps/ShowcaseApp/ButtonShapeFixture.swift)
// in a real browser and checks, for every control:
//
// - the computed corner radius of the `<button>` (which carries the highlight, the focus ring
//   and the hit area) equals the radius of the visible shape the label declares (1px tolerance);
// - a shaped control hit-tests only its shape: points inside the shape resolve to the button,
//   while a point just outside its rounded corner, inside the bounding box, does not;
// - the cursor is `not-allowed` across the whole shape of a disabled control and `pointer` across
//   the whole shape of an enabled one;
// - hover and press paint nothing outside the shape: corner pixels read from a screenshot equal
//   the page background, while a point inside the shape is highlighted;
// - a control with no declared shape (plain text) paints no fill on hover or press;
// - keyboard focus reaches each control and its focus ring uses the same radius.
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { ROOT, launch, runSuite, serveBundle } from "./browser-test-support.mjs";
import { bundleFilePath } from "./hash-release-bundle.mjs";

const ROUTE = "/buttonShape";
const VIEWPORTS = [
  [390, 844],
  [1000, 900],
];

// id -> [declared shape, shaped]. "capsule" and "circle" are half the short side; a number is a radius in px.
// A control with no declared shape is expected to stay a rectangle with no fill of its own.
const CONTROLS = new Map([
  ["shape-capsule-plain", ["capsule", true]],
  ["shape-circle-plain", ["circle", true]],
  ["shape-rounded-plain", [16, true]],
  ["shape-content-rounded", [12, true]],
  ["shape-share-capsule", ["capsule", true]],
  ["shape-custom-capsule", ["capsule", true]],
  ["shape-bordered-capsule", ["capsule", true]],
  ["shape-disabled-capsule", ["capsule", true]],
  ["shape-plain-text", [0, false]],
]);
const DISABLED = new Set(["shape-disabled-capsule"]);
// Controls whose style owns its hover and press chrome: the framework must add no fill on hover.
const STYLE_OWNED = new Set(["shape-custom-capsule", "shape-disabled-capsule"]);
const DOM_ORDER = [...CONTROLS.keys()];

// Page-side helpers. They are passed to Playwright as real functions, so they must not reference module state.
const RECT = (id) => {
  const el = document.querySelector(`[data-testid="${id}"]`);
  if (!el) return null;
  const r = el.getBoundingClientRect();
  const cs = getComputedStyle(el);
  return {
    x: r.left,
    y: r.top,
    w: r.width,
    h: r.height,
    radius: cs.borderRadius,
    shaped: el.hasAttribute("data-visible-shape"),
    disabled: el.disabled,
    cursor: cs.cursor,
    bg: cs.backgroundColor,
    opacity: cs.opacity,
    shadow: cs.boxShadow,
  };
};

const HIT = ([id, points]) => {
  const el = document.querySelector(`[data-testid="${id}"]`);
  return points.map(([name, x, y]) => {
    const hit = document.elementFromPoint(x, y);
    return { name, x, y, isButton: hit === el, cursor: hit ? getComputedStyle(hit).cursor : "none" };
  });
};

const PIXELS = async ([b64, points]) => {
  const img = new Image();
  img.src = "data:image/png;base64," + b64;
  await img.decode();
  const c = document.createElement("canvas");
  c.width = img.width;
  c.height = img.height;
  const ctx = c.getContext("2d");
  ctx.drawImage(img, 0, 0);
  return points.map(([x, y]) => Array.from(ctx.getImageData(x, y, 1, 1).data));
};

const FOCUSED_TESTID = () => {
  const a = document.activeElement;
  return a ? a.getAttribute("data-testid") : null;
};

// Rounds halves to the even neighbour.
function roundHalfEven(value) {
  const floor = Math.floor(value);
  const diff = value - floor;
  if (diff !== 0.5) return diff < 0.5 ? floor : floor + 1;
  return floor % 2 === 0 ? floor : floor + 1;
}

async function load(page, base) {
  const response = await page.goto(base + ROUTE, { waitUntil: "domcontentloaded" });
  assert.ok(response && response.status() === 200);
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  await page.waitForSelector(`[data-testid="${DOM_ORDER[0]}"]`, { timeout: 30_000 });
  await page.waitForTimeout(300);
}

// Corner radius in px for a uniform CSS border-radius, clamped the way the browser clamps it.
function effectiveRadius(radiusCss, w, h) {
  const value = radiusCss.split(" ")[0];
  const radius = value.endsWith("%")
    ? (Number(value.slice(0, -1)) / 100) * Math.min(w, h)
    : Number(value.replace(/px$/, ""));
  return Math.min(radius, w / 2, h / 2);
}

function expectedRadius(shape, w, h) {
  if (shape === "capsule" || shape === "circle") return Math.min(w, h) / 2;
  return Number(shape);
}

// Hit points around one rounded corner, plus the centre, edges and label-free padding.
function arcPoints(x, y, w, h, radius, outsideBy = 1.5) {
  const cx = x + w / 2;
  const cy = y + h / 2;
  const inward = radius - 2; // just inside the arc
  const outward = radius + outsideBy; // just outside the arc, still inside the box
  const d = Math.sqrt(0.5);
  const inside = [
    ["center", cx, cy],
    ["left-end", x + 4, cy],
    ["right-end", x + w - 4, cy],
    ["top-padding", cx, y + 3],
    ["bottom-padding", cx, y + h - 3],
    ["inside-top-left-arc", x + radius - inward * d, y + radius - inward * d],
    ["inside-bottom-right-arc", x + w - radius + inward * d, y + h - radius + inward * d],
  ];
  const outside = [
    ["OUTSIDE-top-left-arc", x + radius - outward * d, y + radius - outward * d],
    ["OUTSIDE-bottom-right-arc", x + w - radius + outward * d, y + h - radius + outward * d],
  ];
  return { inside, outside };
}

async function checkHitAndCursor(page, controlId, box, radius, shapeName) {
  const { inside, outside } = arcPoints(box.x, box.y, box.w, box.h, radius);
  const results = await page.evaluate(HIT, [controlId, [...inside, ...outside]]);
  const wantCursor = DISABLED.has(controlId) ? "not-allowed" : "pointer";
  for (const r of results) {
    if (r.name.startsWith("OUTSIDE")) {
      assert.ok(
        !r.isButton,
        `${controlId} ${shapeName}: ${r.name} at (${r.x.toFixed(1)},${r.y.toFixed(1)}) hits the button outside its shape`,
      );
      assert.notEqual(r.cursor, wantCursor, `${controlId}: ${r.name} shows ${wantCursor} outside the shape`);
    } else {
      assert.ok(
        r.isButton,
        `${controlId}: ${r.name} at (${r.x.toFixed(1)},${r.y.toFixed(1)}) does not hit the button (${JSON.stringify(r)})`,
      );
      assert.equal(r.cursor, wantCursor, `${controlId}: ${r.name} cursor ${r.cursor} != ${wantCursor}`);
    }
  }
  return results;
}

// Corner pixels outside the shape must equal the page background (a 4px margin around the box is background).
async function pixelProbe(page, controlId, box, radius, expectFillInside) {
  const margin = 4;
  const clip = { x: box.x - margin, y: box.y - margin, width: box.w + 2 * margin, height: box.h + 2 * margin };
  const b64 = (await page.screenshot({ clip })).toString("base64");
  // Probe 3px outside the arc: a pixel 1px outside is anti-aliased and would read as paint.
  const { inside, outside } = arcPoints(margin, margin, box.w, box.h, radius, 3);
  const arcInside = inside.find((p) => p[0] === "inside-top-left-arc");
  const points = [
    [1, 1],
    ...outside.map(([, x, y]) => [roundHalfEven(x), roundHalfEven(y)]),
    [roundHalfEven(arcInside[1]), roundHalfEven(arcInside[2])],
  ];
  const pixels = (await page.evaluate(PIXELS, [b64, points])).map((p) => p.slice(0, 3));
  const background = pixels[0];
  const maxDiff = (a, b) => Math.max(...a.map((v, i) => Math.abs(v - b[i])));
  for (let i = 1; i <= 2; i++) {
    assert.ok(
      maxDiff(pixels[i], background) <= 3,
      `${controlId}: pixel (${points[i][0]}, ${points[i][1]}) outside the shape is ${JSON.stringify(pixels[i])}, page background is ${JSON.stringify(background)}`,
    );
  }
  if (expectFillInside) {
    assert.ok(
      maxDiff(pixels[3], background) > 3,
      `${controlId}: hover fill is not visible inside the shape (${JSON.stringify(pixels[3])} vs background ${JSON.stringify(background)})`,
    );
  }
  return { background, outside_corners: pixels.slice(1, 3), inside: pixels[3] };
}

async function tabTo(page, controlId) {
  for (let i = 0; i < 80; i++) {
    await page.keyboard.press("Tab");
    if ((await page.evaluate(FOCUSED_TESTID)) === controlId) return true;
  }
  return false;
}

function alpha(cssColor) {
  // Playwright returns rgba(...) strings for computed colours.
  const parts = cssColor.replace("rgba(", "").replace("rgb(", "").replace(/\)+$/, "").split(",");
  return parts.length === 4 ? parseFloat(parts[3]) : 1.0;
}

await runSuite(async () => {
  const bundle = resolve(process.env.BUTTON_SHAPE_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
  const port = Number(process.env.BUTTON_SHAPE_PORT ?? "8106");
  for (const name of ["app.wasm", "index.html", "index.js"]) {
    if (!bundleFilePath(bundle, name)) {
      throw new Error(`${name} missing from ${bundle}; run BUILD_ONLY=1 CONFIGURATION=release Tools/run-browser.sh showcase`);
    }
  }

  const { base, stop } = await serveBundle({ bundle, port, logName: "button-highlight-browser-server" });
  const report = [];
  let browser;
  try {
    browser = await launch();
    for (const [width, height] of VIEWPORTS) {
      const page = await browser.newPage({ viewport: { width, height } });
      await load(page, base);
      for (const controlId of DOM_ORDER) {
        const [shape, shaped] = CONTROLS.get(controlId);
        await page.mouse.move(2, 2);
        await page.waitForTimeout(150);
        const box = await page.evaluate(RECT, controlId);
        assert.ok(box && box.w > 0 && box.h > 0, `${controlId} is not laid out at ${width}px`);
        assert.equal(box.shaped, shaped, `${controlId}: data-visible-shape is ${box.shaped}, expected ${shaped}`);

        // 1. Computed radius of the element that carries highlight, focus and hit area.
        const actual = effectiveRadius(box.radius, box.w, box.h);
        if (shaped) {
          const want = expectedRadius(shape, box.w, box.h);
          assert.ok(
            Math.abs(actual - want) <= 1.0,
            `${controlId} at ${width}px: button radius ${actual.toFixed(1)}px != shape radius ${want.toFixed(1)}px (${JSON.stringify(box)})`,
          );
        } else {
          assert.equal(actual, 0, `${controlId} at ${width}px: unshaped button radius ${actual}px, expected 0 (${JSON.stringify(box)})`);
        }

        // 2. Hit testing and cursor over the shape only.
        const hits = shaped ? await checkHitAndCursor(page, controlId, box, actual, shape) : [];

        // 3. Hover: a shaped system control fills its shape; nothing paints outside it.
        await page.mouse.move(box.x + box.w / 2, box.y + box.h / 2);
        await page.waitForTimeout(250);
        const hover = await page.evaluate(RECT, controlId);
        let pixels = null;
        if (shaped) {
          pixels = await pixelProbe(page, controlId, hover, actual, controlId === "shape-capsule-plain");
        }
        if (DISABLED.has(controlId) || STYLE_OWNED.has(controlId)) {
          assert.equal(alpha(hover.bg), 0, `${controlId}: framework paints a hover fill ${hover.bg}`);
        } else if (shape === 0) {
          assert.equal(alpha(hover.bg), 0, `${controlId}: plain text paints a hover fill ${hover.bg}`);
        }

        // 4. Press: system plain styles dim the label; plain text paints no fill.
        await page.mouse.down();
        await page.waitForTimeout(250);
        const pressed = await page.evaluate(RECT, controlId);
        await page.mouse.up();
        await page.mouse.move(2, 2);
        await page.waitForTimeout(150);
        if (controlId === "shape-plain-text") {
          assert.equal(alpha(pressed.bg), 0, `plain text paints a pressed fill ${pressed.bg}`);
          assert.ok(parseFloat(pressed.opacity) < 1, "plain text does not dim on press");
        }
        if (controlId === "shape-capsule-plain") {
          assert.ok(parseFloat(pressed.opacity) < 1, "plain capsule does not dim on press");
          assert.ok(alpha(pressed.bg) > 0, "plain capsule shows no hover/press fill inside its shape");
        }

        // 5. Keyboard focus reaches the control and its focus ring uses the same radius.
        if (!DISABLED.has(controlId)) {
          assert.ok(await tabTo(page, controlId), `${controlId} is not reachable with Tab at ${width}px`);
          const focused = await page.evaluate(RECT, controlId);
          const ringRadius = effectiveRadius(focused.radius, focused.w, focused.h);
          if (shaped) {
            assert.ok(
              Math.abs(ringRadius - actual) <= 1.0,
              `${controlId}: focus ring radius ${ringRadius} != ${actual}`,
            );
          }
          assert.ok(focused.shadow !== "none" || shape === 0, `${controlId}: no focus ring`);
        }

        const insideHits = hits.length ? hits.filter((h) => h.isButton).length : [];
        report.push([width, controlId, Math.round(actual * 10) / 10, insideHits, pixels]);
      }
      await page.close();
    }
  } finally {
    await browser?.close();
    await stop();
  }

  for (const [width, controlId, radius, insideHits, pixels] of report) {
    console.log(
      `${String(width).padStart(5)}px ${controlId.padEnd(24)} radius=${radius.toFixed(1).padStart(5)}px ` +
        `inside-hits=${JSON.stringify(insideHits)} pixels=${pixels === null ? "None" : JSON.stringify(pixels)}`,
    );
  }
  console.log("button highlight shape checks passed");
});
