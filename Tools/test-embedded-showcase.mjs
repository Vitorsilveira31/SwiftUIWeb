#!/usr/bin/env bun
// Exercise a REAL built Embedded Showcase in an isolated browser context.
// Requires the Swift bundle; never substitutes a fixture for a missing build.
import { expect } from "@playwright/test";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { isDeepStrictEqual, parseArgs } from "node:util";
import { engineName, launch, ROOT, runSuite, serveStatic } from "./browser-test-support.mjs";

const json = (value) => JSON.stringify(value);
const rgb = (text) => (text.match(/[\d.]+/g) ?? []).map(Number);
const sameJson = (a, b) => json(a) === json(b);

await runSuite(async () => {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: { output: { type: "string", default: join(ROOT, ".build/embedded-ui/showcase") } },
  });
  const bundle = resolve(positionals[0] ?? join(ROOT, ".build/browser/ShowcaseApp"));
  const out = resolve(values.output);
  mkdirSync(out, { recursive: true });
  const report = {
    status: "RUNNING_NOT_VALIDATED", scope: "ACTUAL_SHOWCASE_WASM", tests: [], runtime_errors: [],
    not_covered: ["external network/media permissions", "file import/export/clipboard", "Canvas drawing and Map providers", "native-equivalent spring physics", "all drag/drop and gesture APIs"],
  };
  const save = () => writeFileSync(join(out, "result.json"), JSON.stringify(report, null, 2) + "\n");
  save();
  // The single Embedded BrowserIO bundle uses the canonical runtime name `app.wasm`; product names are encoded in the enclosing bundle path.
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) {
    report.status = "BLOCKED";
    report.reason = "Build the Embedded Showcase first";
    save();
    throw new Error(report.reason);
  }
  const server = serveStatic(bundle);
  let browser;
  try {
    browser = await launch();
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    const page = await context.newPage();
    page.on("pageerror", (e) => report.runtime_errors.push(String(e)));
    // The bundle ships a Content-Security-Policy (Tools/seal-csp.mjs); a blocked script, eval or frame is a failure.
    page.on("console", (m) => { if (/Content Security Policy/i.test(m.text())) report.runtime_errors.push(m.text()); });
    await page.goto(`${server.base}/`, { waitUntil: "networkidle" });
    await page.waitForSelector('[data-testid="showcase-shell"]');
    const flush = () => page.evaluate("window.__embeddedSession.flush()");
    const clean = async () => {
      assert.deepEqual(report.runtime_errors, []);
      assert.equal(await page.evaluate("window.__embeddedSession.metrics.errors.length"), 0);
    };
    const settle = async () => assert.ok(await page.evaluate("window.__embeddedSession.settled()"), "the app did not settle");
    const topic = async (key, title) => {
      await page.getByTestId("showcase-topic-" + key).click();
      await flush();
      await clean();
      await expect(page.getByTestId("showcase-page-title")).toHaveText(title ?? key);
      // `.documentHead` on the page title puts the topic into the page's <meta name="description">.
      await expect.poll(() => page.evaluate(() => document.head.querySelector('meta[name="description"]')?.content)).toBe("SwiftUIWeb showcase: " + (title ?? key));
    };
    const stage = async (name, fn) => {
      const start = performance.now();
      try {
        await fn();
        await clean();
        report.tests.push({ name, status: "PASS", seconds: Math.round(((performance.now() - start) / 1000) * 100) / 100 });
      } catch (e) {
        report.tests.push({ name, status: "FAIL", reason: `${e?.name ?? "Error"}: ${e?.message ?? e}` });
        await page.screenshot({ path: join(out, "failure.png"), fullPage: true });
        throw e;
      } finally {
        save();
      }
    };
    const desktop = () => page.setViewportSize({ width: 1440, height: 1000 });
    const pixelsOf = (width, height) => ({ width, height });
    void pixelsOf;

    await stage("Controls: repeated disclosure, dropdown, switch and continuous slider", async () => {
      await topic("components", "Components");
      const checkbox = page.getByRole("switch", { name: "Notifications" });
      await checkbox.uncheck(); await flush(); await expect(checkbox).not.toBeChecked();
      await checkbox.check(); await flush(); await expect(checkbox).toBeChecked();
      const picker = page.getByRole("combobox", { name: "Language" });
      for (const value of ["WASI", "Swift", "WebAssembly", "Swift"]) {
        await picker.selectOption(value); await flush(); await expect(picker).toHaveValue(value);
      }
      const details = page.locator("details[data-controlled-open]");
      // The binding toggle reaches Swift's re-render a frame after the click, so wait for the
      // disclosure to settle instead of asserting right after one flush.
      const settled = async (expected) => {
        await flush();
        try {
          await page.waitForFunction((open) => document.querySelector("details[data-controlled-open]").open === open, expected, { timeout: 3000 });
        } catch {
          throw new assert.AssertionError({ message: `disclosure did not ${expected ? "open" : "close"}; states=${json(await details.evaluateAll((els) => els.map((el) => el.open)))}` });
        }
      };
      for (let index = 0; index < 6; index++) {
        await details.locator("summary").click(); await settled(false);
        await details.locator("summary").click(); await settled(true);
      }
      const slider = page.locator('input[type="range"]').first();
      await slider.scrollIntoViewIfNeeded();
      await slider.evaluate((el) => { window.rangeNode = el; });
      const box = await slider.boundingBox();
      const value = Number.parseFloat(await slider.inputValue());
      const y = box.y + box.height / 2;
      await page.mouse.move(box.x + box.width * value, y); await page.mouse.down();
      for (let n = 2; n < 10; n++) { await page.mouse.move(box.x + (box.width * n) / 10, y, { steps: 3 }); await page.waitForTimeout(35); }
      await page.mouse.up(); await flush();
      assert.ok(Number.parseFloat(await slider.inputValue()) > 0.8, `slider value=${await slider.inputValue()}`);
      assert.ok(await slider.evaluate((el) => el === window.rangeNode), "slider node was replaced");
    });

    await stage("Typed NavigationPath: eight push/replace/pop cycles", async () => {
      for (let index = 0; index < 8; index++) {
        await topic("navigation", "Navigation");
        await page.getByText("Push a detail", { exact: true }).click(); await flush();
        const destination = page.locator('[data-testid="showcase-destination"]:visible');
        await expect(destination).toBeVisible();
        await page.getByText("Push another detail", { exact: true }).click(); await flush();
        await expect(destination).toContainText("Next detail");
        await page.getByRole("button", { name: "Replace this detail", exact: true }).click(); await flush();
        await expect(destination).toContainText("Replaced detail");
        await destination.getByRole("button", { name: "Pop to root", exact: true }).click(); await flush();
        await expect(page.getByTestId("showcase-page-title")).toHaveText("Navigation");
      }
    });

    await stage("Independent parent/child bindings and repeated tabs", async () => {
      await topic("state", "State & Bindings");
      for (let index = 0; index < 5; index++) { await page.getByRole("button", { name: "Increase", exact: true }).click(); await flush(); }
      await expect(page.getByText("Parent state: 5", { exact: true })).toBeVisible();
      await page.getByRole("button", { name: "Change local state" }).click(); await flush();
      await expect(page.getByText("Child-local state: 1", { exact: true })).toBeVisible();
      for (let index = 0; index < 5; index++) {
        await page.getByRole("tab", { name: "Settings" }).click(); await flush();
        await expect(page.getByRole("tab", { name: "Settings" })).toHaveAttribute("aria-selected", "true");
        await page.getByRole("tab", { name: "Home" }).click(); await flush();
        await expect(page.getByRole("tab", { name: "Home" })).toHaveAttribute("aria-selected", "true");
      }
      // Optional selection (TabView(selection: Binding<String?>)): nil shows the first tab, but the binding stays nil until a tap.
      await expect(page.getByText("Alpha panel", { exact: true })).toBeVisible();
      await expect(page.getByText("Optional tab: none", { exact: true })).toBeVisible();
      await page.getByRole("tab", { name: "Beta" }).click(); await flush();
      await expect(page.getByText("Optional tab: beta", { exact: true })).toBeVisible();
      await expect(page.getByRole("tab", { name: "Beta" })).toHaveAttribute("aria-selected", "true");
      await page.getByRole("tab", { name: "Alpha" }).click(); await flush();
      await expect(page.getByText("Optional tab: alpha", { exact: true })).toBeVisible();
    });

    await stage("Forms: Unicode values, validation and save action", async () => {
      await topic("forms", "Forms");
      await page.getByPlaceholder("Name", { exact: true }).fill("Olá 日本"); await flush();
      await page.getByPlaceholder("Password", { exact: true }).fill("example-only"); await flush();
      await expect(page.getByPlaceholder("Name", { exact: true })).toHaveValue("Olá 日本");
      await page.getByRole("button", { name: "Save", exact: true }).click(); await flush();
      await expect(page.getByText("Action completed", { exact: true })).toBeVisible();
      await page.getByRole("button", { name: "Close", exact: true }).click(); await flush();
    });

    await stage("Typed table row payloads after insertion and deletion", async () => {
      await topic("collections", "Collections");
      const table = page.locator("table").first();
      const before = await table.locator("tbody tr").count();
      await page.getByRole("button", { name: "Insert", exact: true }).click(); await flush();
      await expect(table.locator("tbody tr")).toHaveCount(before + 1);
      await page.getByRole("button", { name: "Delete last", exact: true }).click(); await flush();
      await expect(table.locator("tbody tr")).toHaveCount(before);
    });

    const domComponent = async (worker) => {
      // The default runtime runs Swift in a Worker and applies WebMount/DOMView DOM work on the main thread
      // (Documentation/EmbeddedWorker.md). ?render-in-worker=0 runs Swift on the main thread. Both must run the
      // same lifecycle, and each run proves which runtime it got.
      const query = worker ? "" : "?render-in-worker=0";
      const dom = await context.newPage();
      const domErrors = [];
      dom.on("pageerror", (e) => domErrors.push(String(e)));
      await dom.goto(`${server.base}/${query}`, { waitUntil: "networkidle" });
      await dom.waitForSelector('[data-testid="showcase-shell"]');
      assert.equal(await dom.evaluate("window.__embeddedSession.worker"), worker, "runtime mode is not the one requested");
      // The component is a registered function of the page's own files, so the sealed policy has no 'unsafe-eval'.
      const policy = await dom.evaluate(() => document.querySelector('meta[http-equiv="Content-Security-Policy"]')?.content ?? "");
      assert.ok(policy.includes("script-src") && !/(?<!wasm-)unsafe-eval/.test(policy), `the page policy must not allow eval: ${policy}`);
      await dom.evaluate(() => { window.__cspViolations = []; document.addEventListener("securitypolicyviolation", (event) => window.__cspViolations.push(event.violatedDirective)); });
      const dflush = () => dom.evaluate("window.__embeddedSession.flush()");
      await dom.getByTestId("showcase-topic-advanced").click(); await dflush();
      await expect(dom.getByTestId("showcase-page-title")).toHaveText("Advanced");
      const host = dom.locator('[data-dom-view="true"]');
      await expect(host).toHaveCount(1);
      const button = dom.getByTestId("dom-counter-button");
      const label = dom.getByTestId("dom-counter-label");
      // mount: the registered component mounts once and renders into the ShadowRoot.
      await expect(label).toHaveText("Count: 0");
      await expect(dom.getByText("Swift taps: 0", { exact: true })).toBeVisible();
      assert.equal(await dom.evaluate("globalThis.__domMounts"), 1, "mount did not run exactly once");
      assert.equal(await dom.locator("[data-dom-view-error]").count(), 0, "a DOM operation failed");
      await dom.evaluate(() => { window.__domCounterHost = document.querySelector("[data-dom-view=true]"); window.__domDismantlesBefore = globalThis.__domDismantles || 0; });
      // update and message round trip: each click reaches Swift, and Swift's state updates the same component.
      for (let n = 1; n < 4; n++) {
        await button.click(); await dflush();
        await expect(dom.getByText(`Swift taps: ${n}`, { exact: true })).toBeVisible();
        await expect(label).toHaveText(`Count: ${n}`);
      }
      assert.ok(await dom.evaluate(() => window.__domCounterHost === document.querySelector("[data-dom-view=true]")), "DOM host was replaced on update");
      assert.equal(await dom.evaluate("globalThis.__domMounts"), 1, "update remounted the component");
      // dismantle: removing it disposes the component exactly once. In the worker runtime the
      // unmount arrives in a later batch, so wait for it instead of reading it right after the DOM change.
      await dom.getByRole("button", { name: "Remove DOM component", exact: true }).click(); await dflush();
      await expect(host).toHaveCount(0);
      await dom.waitForFunction(() => (globalThis.__domDismantles || 0) - (window.__domDismantlesBefore || 0) === 1, undefined, { timeout: 5000 });
      await dflush(); await dom.waitForTimeout(100);
      const dismantles = await dom.evaluate(() => (globalThis.__domDismantles || 0) - (window.__domDismantlesBefore || 0));
      assert.equal(dismantles, 1, `expected one dismantle on removal, saw ${dismantles}`);
      // remount: a new instance mounts with the current Swift state.
      await dom.getByRole("button", { name: "Mount DOM component", exact: true }).click(); await dflush();
      await expect(host).toHaveCount(1);
      await expect(dom.getByTestId("dom-counter-label")).toHaveText("Count: 3");
      assert.equal(await dom.evaluate("globalThis.__domMounts"), 2, "remount did not run exactly once");
      await dom.getByTestId("dom-counter-button").click(); await dflush();
      await expect(dom.getByTestId("dom-counter-label")).toHaveText("Count: 4");
      assert.equal(await dom.locator("[data-dom-view-error]").count(), 0, "a DOM operation failed");
      assert.deepEqual(await dom.evaluate(() => window.__cspViolations), [], "the component lifecycle violated the page policy");
      assert.deepEqual(domErrors, []);
      await dom.close();
    };
    await stage("DOMViewRepresentable in the default Worker runtime: mount, update, message, dismantle, remount", () => domComponent(true));
    await stage("DOMViewRepresentable in the main-thread runtime (?render-in-worker=0): same lifecycle", () => domComponent(false));

    await stage("All topic mounts twice, retained motion and responsive documentation shell", async () => {
      const topics = [["gettingStarted", "Getting Started"], ["layout", "Layout"], ["state", "State & Bindings"], ["themes", "Themes"], ["responsive", "Responsive"], ["components", "Components"], ["forms", "Forms"], ["collections", "Collections"], ["navigation", "Navigation"], ["presentation", "Presentation"], ["advanced", "Advanced"]];
      for (let round = 0; round < 2; round++) for (const [key, title] of topics) await topic(key, title);
      const target = page.getByTestId("showcase-motion-target");
      await target.scrollIntoViewIfNeeded();
      await target.evaluate((el) => { window.motionNode = el; });
      await page.getByRole("button", { name: "Animate state", exact: true }).click(); await flush(); await page.waitForTimeout(180);
      const width = await target.evaluate((el) => Number.parseFloat(getComputedStyle(el).width));
      assert.ok(width > 74 && width < 178, String(width));
      await page.getByRole("button", { name: "Unrelated counter", exact: true }).click(); await flush();
      assert.ok(await target.evaluate((el) => el === window.motionNode));
      await page.screenshot({ path: join(out, "desktop.png"), fullPage: true });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.getByTestId("showcase-mobile-menu").click(); await flush();
      await expect(page.getByTestId("showcase-sidebar-open")).toBeVisible();
      await page.getByTestId("showcase-topic-components").click(); await flush();
      await expect(page.getByTestId("showcase-page-title")).toHaveText("Components");
      assert.ok(await page.evaluate("document.documentElement.scrollWidth<=window.innerWidth+2"));
      await page.screenshot({ path: join(out, "mobile.png"), fullPage: true });
    });

    const adaptiveShapePaint = async () => {
      // Unresolved semantic (var()), light-dark() and opacity-mixed colors must resolve in SVG fills, strokes and gradient stops
      // for the system scheme and for preferredColorScheme.
      await desktop();
      await topic("advanced", "Advanced");
      const paint = (id) => page.evaluate((testid) => {
        const host = document.querySelector(`[data-testid="${testid}"]`);
        const svg = host.matches("svg") ? host : host.querySelector("svg");
        if (!svg) {
          // A solid fill is a box with a CSS background, not an SVG path.
          const layer = host.matches(".shape-layer") ? host : host.querySelector(".shape-layer");
          return { fill: getComputedStyle(layer).backgroundColor, stroke: "none", stops: [], attributes: false };
        }
        const path = svg.querySelector(":scope > path");
        const style = getComputedStyle(path);
        return {
          fill: style.fill, stroke: style.stroke, stops: [...svg.querySelectorAll("stop")].map((s) => getComputedStyle(s).stopColor),
          attributes: [...svg.querySelectorAll("path,stop")].some((e) => e.hasAttribute("fill") || e.hasAttribute("stroke") || e.hasAttribute("stop-color")),
        };
      }, id);
      const resolve = (value) => page.evaluate((v) => {
        const probe = document.createElement("div");
        probe.style.color = v;
        document.body.append(probe);
        const color = getComputedStyle(probe).color;
        probe.remove();
        return color;
      }, value);
      const expectedStroke = { light: "rgb(11, 107, 203)", dark: "rgb(124, 196, 255)" };
      const verify = async (scheme) => {
        await flush(); await page.waitForTimeout(50);
        // The scheme reaches the document one commit after the click or the media change; wait for it, then assert.
        await page.waitForFunction((wanted) => document.documentElement.getAttribute("data-color-scheme") === wanted, scheme, { timeout: 3000 }).catch(() => {});
        assert.equal(await page.evaluate("document.documentElement.getAttribute('data-color-scheme')"), scheme);
        const fill = await paint("showcase-shape-semantic-fill");
        const background = await resolve("var(--color-swu-background)");
        assert.equal(fill.fill, background, json([scheme, fill, background]));
        assert.ok(!fill.attributes, json(fill));
        const stroke = await paint("showcase-shape-adaptive-stroke");
        assert.ok(stroke.stroke === expectedStroke[scheme] && stroke.fill === "none", json([scheme, stroke]));
        const gradient = await paint("showcase-shape-adaptive-gradient");
        assert.ok(gradient.fill.startsWith("url(") && gradient.stops.length === 2, json([scheme, gradient]));
        assert.equal(gradient.stops[0], background, json([scheme, gradient]));
        const mixed = await resolve(`color-mix(in srgb, ${expectedStroke[scheme]} 50%, transparent)`);
        assert.equal(gradient.stops[1], mixed, json([scheme, gradient, mixed]));
        return fill.fill;
      };
      const light = await verify("light");
      await page.emulateMedia({ colorScheme: "dark" });
      const dark = await verify("dark");
      assert.notEqual(light, dark, json([light, dark]));
      await page.getByTestId("showcase-theme-toggle").click(); await verify("light");
      await page.getByTestId("showcase-theme-toggle").click(); await verify("dark");
      await page.emulateMedia({ colorScheme: "light" });
    };
    const gradientSpread = async () => {
      // Canvas has no tiling gradients, so repeat and mirror are expanded into padded
      // stops. Sampled pixels must show the periodic ramp, not the padded end color.
      await desktop();
      await topic("advanced", "Advanced");
      const result = await page.evaluate(() => {
        const canvas = [...document.querySelectorAll('canvas[data-canvas-command-count="3"]')].find((c) => (c.getAttribute("data-canvas-commands") || "").includes('"black"'));
        if (!canvas) return null;
        const ctx = canvas.getContext("2d");
        const px = (x, y) => [...ctx.getImageData(x, y, 1, 1).data.slice(0, 3)][0];
        return { width: canvas.width, height: canvas.height, repeat: [px(0, 5), px(20, 5), px(60, 5), px(100, 5)], mirror: [px(270, 5), px(310, 5)], radial: [px(605, 5), px(615, 5)] };
      });
      assert.notEqual(result, null, "Gradient spread canvas not found");
      assert.ok(result.width >= 720 && result.height >= 10, json(result));
      const near = (value, expected, tolerance = 14) => assert.ok(Math.abs(value - expected) <= tolerance, json([value, expected, result]));
      near(result.repeat[0], 3, 8);
      near(result.repeat[1], 131);
      near(result.repeat[2], 131);
      near(result.repeat[3], 131);
      near(result.mirror[0], 194);
      near(result.mirror[1], 61);
      near(result.radial[0], 141);
      near(result.radial[1], 141);
    };
    const tiledImage = async () => {
      // Image shading tiles a pattern. The image decodes asynchronously, so the
      // canvas repaints once it loads; sample the tile centers of both rectangles.
      await desktop();
      await topic("advanced", "Advanced");
      const sample = () => page.evaluate(() => {
        const canvas = [...document.querySelectorAll("canvas")].find((c) => (c.getAttribute("data-canvas-commands") || "").includes('"k":"p"'));
        if (!canvas) return null;
        const ctx = canvas.getContext("2d");
        const px = (x, y) => [...ctx.getImageData(x, y, 1, 1).data.slice(0, 3)];
        return [px(5, 5), px(15, 5), px(25, 5), px(35, 5), px(208, 5), px(218, 5)];
      });
      const expected = [[255, 0, 0], [0, 255, 0], [255, 0, 0], [0, 255, 0], [255, 0, 0], [0, 255, 0]];
      let colors = null;
      for (let index = 0; index < 40; index++) {
        await flush(); await page.waitForTimeout(100);
        colors = await sample();
        if (colors && !sameJson(colors[0], [0, 0, 0])) break;
      }
      assert.notEqual(colors, null, "Tiled image canvas not found");
      // A 2x2 image tiled at scale 10 is upscaled by the browser's pattern filter. A pixel is read at x + 0.5 while a tile's
      // centre is at x, so a smoothing filter blends a few percent of the neighbouring tile in ((230,13,13) instead of
      // (255,0,0)); older Chromium sampled nearest and read the pure colour. Both are the same placement: the expected
      // channel dominates at each tile centre and the others stay low.
      colors.forEach((got, i) => {
        const dominant = expected[i].indexOf(255);
        assert.ok(got[dominant] >= 220 && got.every((g, k) => k === dominant || g <= 40), json([colors, expected]));
      });
    };
    const framedCanvas = async () => {
      // `Canvas { ... }.frame(height: 120)` takes the frame's height and the card's width, and paints its
      // gradient into that box. It used to collapse to 0x0 at the frame's owner boundary.
      await desktop();
      await topic("advanced", "Advanced"); await settle();
      const result = await page.evaluate(() => {
        const canvas = [...document.querySelectorAll("canvas[data-draw-canvas]")].find((c) => c.getAttribute("data-canvas-size")?.endsWith(",120"));
        if (!canvas) return null;
        const r = canvas.getBoundingClientRect(), ratio = window.devicePixelRatio || 1;
        const ctx = canvas.getContext("2d");
        return {
          box: [r.width, r.height], backing: [canvas.width, canvas.height], expected: [Math.round(r.width * ratio), Math.round(r.height * ratio)],
          topLeft: [...ctx.getImageData(4, 4, 1, 1).data], inside: [...ctx.getImageData(Math.round(160 * ratio), Math.round(100 * ratio), 1, 1).data],
        };
      });
      assert.notEqual(result, null, "Browser-neutral integrations canvas not found");
      assert.ok(Math.abs(result.box[1] - 120) <= 0.5 && result.box[0] >= 300, json(result));
      assert.deepEqual(result.backing, result.expected, json(result));
      const blue = result.topLeft;
      // The gradient stops are 0.9 and 0.8 opaque, so alpha is high but not 255.
      assert.ok(blue[3] >= 200 && blue[2] > 150 && blue[0] < 120, `gradient not painted ${json(result)}`);
      // The background rectangle is 320pt wide inside the 762pt-wide canvas; (160, 100) is inside it, below the stroke.
      assert.ok(result.inside[3] >= 200, `canvas not painted inside its rectangle ${json(result)}`);
    };
    await stage("Framed Canvas in the Advanced page takes its 120pt frame and paints", framedCanvas);
    await stage("Tiled image shading repeats its image from the origin at scale", tiledImage);
    await stage("Image paint tiles natural size times source rect and scale in backgrounds, shapes and text", async () => {
      // ImagePaint tiles natural size x sourceRect x scale. The 2x2 image decodes asynchronously, so the
      // browser sizes each paint once it loads: poll the computed style until the tile size appears.
      await desktop();
      await topic("advanced", "Advanced");
      const sample = (id) => page.evaluate((testid) => {
        const host = document.querySelector(`[data-testid="${testid}"]`);
        if (!host) return null;
        const style = getComputedStyle(host);
        return {
          size: style.backgroundSize, image: style.backgroundImage, repeat: style.backgroundRepeat, clip: style.backgroundClip,
          patterns: [...host.querySelectorAll("pattern")].map((p) => [p.getAttribute("width"), p.getAttribute("height")]),
          pictures: [...host.querySelectorAll("pattern image")].map((i) => [i.getAttribute("width"), i.getAttribute("height"), i.getAttribute("x"), i.getAttribute("y")]),
        };
      }, id);
      const settleSample = async (identifier, ready) => {
        let result = null;
        for (let index = 0; index < 40; index++) {
          await flush(); await page.waitForTimeout(100);
          result = await sample(identifier);
          if (result && ready(result)) break;
        }
        assert.notEqual(result, null, identifier);
        return result;
      };
      const background = await settleSample("showcase-image-paint-background", (r) => r.size === "20px 20px");
      assert.ok(background.repeat === "repeat" && background.image.startsWith("url("), json(background));
      const sub = await settleSample("showcase-image-paint-sub-rect", (r) => r.size === "10px 20px");
      assert.ok(sub.image.includes("data:image/png"), json(sub));
      const shape = await settleSample("showcase-image-paint-shape", (r) => r.patterns.length > 0 && sameJson(r.patterns[0], ["20", "20"]));
      assert.deepEqual(shape.pictures[0], ["20", "20", "0", "0"], json(shape));
      const text = await settleSample("showcase-image-paint-text", (r) => r.size === "20px 20px");
      assert.ok(text.clip === "text" && text.image.startsWith("url("), json(text));
    });
    await stage("AnyGradient shadings paint Canvas ramps like Gradient shadings", async () => {
      // AnyGradient shadings take the same path as Gradient shadings: the ramp runs black to white across the canvas.
      await desktop();
      await topic("advanced", "Advanced");
      let result = null;
      for (let index = 0; index < 40; index++) {
        await flush(); await page.waitForTimeout(100);
        result = await page.evaluate(() => {
          const canvas = document.querySelector('[data-testid="showcase-any-gradient-canvas"]');
          if (!canvas) return null;
          const ctx = canvas.getContext("2d");
          const px = (x) => ctx.getImageData(x, 5, 1, 1).data[0];
          return { width: canvas.width, left: px(2), middle: px(Math.floor(canvas.width / 2)), right: px(canvas.width - 3) };
        });
        if (result && result.left !== 0) break;
      }
      assert.ok(result !== null && result.width > 0, json(result));
      assert.ok(result.left < 40 && result.right > 215 && result.middle > 90 && result.middle < 165, json(result));
    });
    await stage("Elliptical gradients paint inscribed radial ellipses in shapes and backgrounds", async () => {
      // The shape's SVG radial gradient is objectBoundingBox (cx/cy/r/fr are fractions of the bounds) and
      // the background is a CSS ellipse whose radii are percentages of its box.
      await desktop();
      await topic("advanced", "Advanced");
      const sample = (id) => page.evaluate((testid) => {
        const host = document.querySelector(`[data-testid="${testid}"]`);
        if (!host) return null;
        const svg = host.matches("svg") ? host : host.querySelector("svg");
        const gradient = svg ? svg.querySelector("radialGradient") : null;
        const path = svg ? svg.querySelector(":scope > path") : null;
        return {
          backgroundImage: getComputedStyle(host).backgroundImage,
          radial: gradient ? { cx: gradient.getAttribute("cx"), cy: gradient.getAttribute("cy"), r: gradient.getAttribute("r"), fr: gradient.getAttribute("fr"), stops: [...gradient.querySelectorAll("stop")].map((s) => s.getAttribute("offset")) } : null,
          fill: path ? getComputedStyle(path).fill : null,
        };
      }, id);
      let shape = null;
      for (let index = 0; index < 40; index++) {
        await flush(); await page.waitForTimeout(50);
        shape = await sample("showcase-elliptical-shape");
        if (shape && shape.radial) break;
      }
      assert.ok(shape && shape.radial, json(shape));
      assert.ok(shape.radial.r === "0.5" && shape.radial.cx === "50%" && shape.radial.cy === "50%", json(shape));
      assert.ok(sameJson(shape.radial.stops, ["0%", "100%"]) && shape.fill.startsWith("url("), json(shape));
      const background = await sample("showcase-elliptical-background");
      // Chrome serializes the ellipse with two radii as `radial-gradient(50% 50%, ...)` (the default shape and center).
      assert.ok(background.backgroundImage.startsWith("radial-gradient(50% 50%"), json(background));
      assert.ok(background.backgroundImage.includes("rgb(0, 0, 0) 0%") && background.backgroundImage.includes("rgb(255, 255, 255) 100%"), json(background));
      // The start radius (0.25) sits at half the end radius, so the black stop is padded from 0% to 50%.
      assert.equal(background.backgroundImage.split("rgb(0, 0, 0) ").length - 1, 2, json(background));
      // Decode the element screenshot in the page (no image library needed): the centre is dark and the corner is light.
      const png = await page.getByTestId("showcase-elliptical-shape").screenshot();
      const probe = await page.evaluate(async (base64) => {
        const image = new Image();
        image.src = "data:image/png;base64," + base64;
        await image.decode();
        const canvas = document.createElement("canvas");
        canvas.width = image.width; canvas.height = image.height;
        const ctx = canvas.getContext("2d");
        ctx.drawImage(image, 0, 0);
        const pixel = (x, y) => [...ctx.getImageData(x, y, 1, 1).data.slice(0, 3)];
        return { center: pixel(Math.floor(image.width / 2), Math.floor(image.height / 2)), corner: pixel(2, 2) };
      }, png.toString("base64"));
      assert.ok(Math.max(...probe.center) < 40 && Math.min(...probe.corner) > 215, json(probe));
    });
    await stage("Gradient repeat and mirror spread expand into periodic ramps", gradientSpread);
    await stage("Canvas draws resolved symbols, palette and hierarchical system images", async () => {
      // A tagged symbol paints at its top-left anchor (10,10). A system image with a two-entry palette paints
      // its first entry only (its glyph has one layer), and the secondary hierarchical level paints the
      // translucent secondary color. Pixels are scanned in regions around each drawing.
      await desktop();
      await topic("advanced", "Advanced");
      const result = await page.evaluate(() => {
        const canvas = document.querySelector('canvas[data-canvas-size="300,48"]');
        if (!canvas) return null;
        const ctx = canvas.getContext("2d"), W = canvas.width, k = W / 300, H = canvas.height;
        const d = ctx.getImageData(0, 0, W, H).data;
        const scan = (x0, x1) => {
          let minx = 1e9, miny = 1e9, maxx = -1, maxy = -1, n = 0, red = 0, blue = 0, maxA = 0;
          for (let y = 0; y < H; y++) for (let x = Math.floor(x0 * k); x < Math.floor(x1 * k); x++) {
            const i = (y * W + x) * 4, a = d[i + 3];
            if (a > 0) { n++; if (x < minx) minx = x; if (y < miny) miny = y; if (x > maxx) maxx = x; if (y > maxy) maxy = y; if (a > maxA) maxA = a; }
            if (a > 200 && d[i] > 200 && d[i + 1] < 100 && d[i + 2] < 100) red++;
            if (a > 200 && d[i] < 100 && d[i + 1] < 100 && d[i + 2] > 200) blue++;
          }
          return { n, minx: minx / k, miny: miny / k, red, blue, maxA };
        };
        return { k, badge: scan(0, 140), palette: scan(145, 190), secondary: scan(195, 240) };
      });
      assert.notEqual(result, null, "Canvas symbols canvas not found");
      const { badge, palette, secondary } = result;
      // The tagged "Badge" text is drawn from (10,10): its ink starts just inside that corner.
      assert.ok(badge.n > 20 && badge.minx >= 8 && badge.minx <= 16 && badge.miny >= 8 && badge.miny <= 18, `symbol not drawn at its anchor ${json(result)}`);
      // The palette system image is red (entry 0) and never blue (entry 1: one layer, one entry).
      assert.ok(palette.n > 20 && palette.red > 10 && palette.blue === 0, `palette entry 0 not painted alone ${json(result)}`);
      // The secondary level is the foreground at 60% opacity: no red, and partly transparent ink.
      assert.ok(secondary.n > 20 && secondary.red === 0 && secondary.maxA >= 60 && secondary.maxA <= 230, `secondary level not translucent ${json(result)}`);
    });
    await stage("Foreground levels read the foregroundStyle secondary paint in text and Canvas", async () => {
      // `.foregroundStyle(.red, .blue)` sets the secondary level for its subtree: `.secondary` text and a
      // canvas fill of that level take the blue paint, and primary text stays red.
      await desktop();
      await topic("advanced", "Advanced");
      const result = await page.evaluate(() => {
        const el = document.querySelector('[data-testid="showcase-level-secondary"]');
        const prim = document.querySelector('[data-testid="showcase-level-primary"]');
        const canvas = document.querySelector('canvas[data-canvas-size="40,10"]');
        if (!el || !prim || !canvas) return null;
        const probe = document.createElement("div");
        document.body.append(probe);
        const paint = getComputedStyle(el).getPropertyValue("--secondary-style").trim();
        probe.style.color = paint;
        const expected = getComputedStyle(probe).color;
        probe.remove();
        const pixel = [...canvas.getContext("2d").getImageData(20, 5, 1, 1).data];
        return { paint, expected, secondary: getComputedStyle(el).color, primary: getComputedStyle(prim).color, pixel };
      });
      assert.notEqual(result, null, "Foreground levels elements not found");
      assert.ok(result.paint, `secondary style variable not set ${json(result)}`);
      assert.equal(result.secondary, result.expected, `secondary text not painted with the secondary style ${json(result)}`);
      assert.notEqual(result.primary, result.expected, `primary text took the secondary style ${json(result)}`);
      const want = rgb(result.expected).slice(0, 3);
      assert.ok(result.pixel.slice(0, 3).every((g, i) => Math.abs(g - want[i]) <= 3) && result.pixel[3] === 255, `canvas secondary fill not blue ${json(result)}`);
    });
    await stage("Palette shading paints Canvas fills with its first entry", async () => {
      // A palette paints a Canvas fill with its first entry. The first two bands use light-dark()
      // colors, which the browser resolves at paint time; the empty palette paints nothing.
      await desktop();
      await topic("advanced", "Advanced");
      const result = await page.evaluate(() => {
        const canvas = [...document.querySelectorAll("canvas")].find((c) => c.getAttribute("data-canvas-size") === "300,10");
        if (!canvas) return null;
        const ctx = canvas.getContext("2d");
        const fills = JSON.parse(canvas.getAttribute("data-canvas-commands")).filter((c) => c.o === "f").map((c) => c.s.c);
        const probe = document.createElement("div");
        document.body.append(probe);
        const resolve = (v) => { probe.style.color = v; return getComputedStyle(probe).color; };
        const expected = fills.map(resolve);
        probe.remove();
        return { width: canvas.width, height: canvas.height, pixels: [50, 150, 250].map((x) => [...ctx.getImageData(x, 5, 1, 1).data]), expected };
      });
      assert.notEqual(result, null, "Palette canvas not found");
      assert.ok(result.width >= 300 && result.height >= 10, json(result));
      assert.equal(result.expected.length, 3, json(result));
      const first = rgb(result.expected[0]);
      const second = rgb(result.expected[1]);
      assert.ok(result.pixels[0].slice(0, 3).every((g, i) => Math.abs(g - first[i]) <= 2), `first palette entry ${json(result)}`);
      assert.ok(result.pixels[1].slice(0, 3).every((g, i) => Math.abs(g - second[i]) <= 2), `second palette entry ${json(result)}`);
      assert.equal(result.pixels[2][3], 0, `empty palette paints nothing ${json(result)}`);
    });
    await stage("Gradient shading style resolves unit points against the painted path", async () => {
      // `Shading.style(LinearGradient)` resolves its unit points against the painted band: black at its left
      // edge and white at its right edge.
      await desktop();
      await topic("advanced", "Advanced");
      const result = await page.evaluate(() => {
        const canvas = [...document.querySelectorAll("canvas")].find((c) => c.getAttribute("data-canvas-size") === "200,10");
        if (!canvas) return null;
        const ctx = canvas.getContext("2d");
        return { width: canvas.width, left: [...ctx.getImageData(2, 5, 1, 1).data], right: [...ctx.getImageData(197, 5, 1, 1).data] };
      });
      assert.notEqual(result, null, "Gradient style canvas not found");
      assert.ok(result.width >= 200, json(result));
      assert.ok(result.left.slice(0, 3).every((v) => v <= 40) && result.left[3] === 255, `left edge is black ${json(result)}`);
      assert.ok(result.right.slice(0, 3).every((v) => v >= 215) && result.right[3] === 255, `right edge is white ${json(result)}`);
    });
    await stage("ShapeView stacks fill and stroke layers in call order and insets strokeBorder", async () => {
      // ShapeView stacks paints in call order: the later stroke or fill sits above the earlier one. A
      // strokeBorder insets its path by half its line width, so the stroke stays inside the frame.
      await desktop();
      await topic("advanced", "Advanced");
      const sample = (id) => page.evaluate((testid) => {
        const host = document.querySelector(`[data-testid="${testid}"]`);
        if (!host) return null;
        // The layers in paint order. A solid fill is a box with a CSS background (`div.shape-layer`), a stroke or a gradient an SVG path.
        const box = host.getBoundingClientRect();
        return [...host.querySelectorAll(".shape-layer")].flatMap((layer) => {
          if (layer.localName !== "svg") {
            const r = layer.getBoundingClientRect();
            return [{ fill: getComputedStyle(layer).backgroundColor, stroke: "none", sw: null, bbox: [r.x - box.x, r.y - box.y, r.width, r.height] }];
          }
          return [...layer.querySelectorAll("path")].map((path) => {
            const b = path.getBBox();
            return { fill: getComputedStyle(path).fill, stroke: getComputedStyle(path).stroke, sw: path.getAttribute("stroke-width"), bbox: [b.x, b.y, b.width, b.height] };
          });
        });
      }, id);
      const indexes = (paths, test) => paths.map((p, i) => (test(p) ? i : -1)).filter((i) => i >= 0);
      const red = await sample("showcase-shape-stacked-fill-stroke");
      assert.notEqual(red, null, "stacked shape not found");
      const fills = indexes(red, (p) => p.fill !== "none" && p.stroke === "none");
      const strokes = indexes(red, (p) => p.stroke !== "none" && p.fill === "none");
      assert.ok(fills.length && strokes.length && fills[0] < strokes[0], `fill must be painted before the stroke ${json(red)}`);
      assert.equal(red[strokes[0]].sw, "4", json(red));
      const reversedOrder = await sample("showcase-shape-stacked-stroke-fill");
      const f2 = indexes(reversedOrder, (p) => p.fill !== "none" && p.stroke === "none");
      const s2 = indexes(reversedOrder, (p) => p.stroke !== "none" && p.fill === "none");
      assert.ok(s2.length && f2.length && s2[0] < f2[0], `stroke must be painted before the fill ${json(reversedOrder)}`);
      const border = await sample("showcase-shape-stroke-border");
      assert.notEqual(border, null, "strokeBorder shape not found");
      const stroked = border.filter((p) => p.stroke !== "none");
      assert.ok(stroked.length && sameJson(stroked[0].bbox, [2, 2, 36, 36]), `strokeBorder insets by half its width ${json(border)}`);
      const outline = await sample("showcase-shape-outline-fill");
      assert.notEqual(outline, null, "outline shape not found");
      // `stroke(lineWidth:)` is a Shape: filling it strokes it, so no path is filled.
      assert.ok(outline.every((p) => p.fill === "none"), `an outline is stroked, never filled ${json(outline)}`);
      assert.ok(outline.filter((p) => p.stroke !== "none" && p.sw === "4").length > 0, `filled outline keeps its stroke ${json(outline)}`);
      const painted = border.filter((p) => p.fill !== "none" && p.stroke === "none");
      assert.ok(painted.length && sameJson(painted[0].bbox, [0, 0, 40, 40]), `the fill keeps the full frame ${json(border)}`);
    });
    await stage("Adaptive semantic, light-dark and opacity colors paint SVG shapes and gradient stops", adaptiveShapePaint);
    await stage("Framed Canvas repaints its light-dark colors when the Showcase theme toggles", async () => {
      // The Showcase theme toggle writes an explicit scheme, so this runs after the stages that depend on
      // the system scheme. It compares the canvas pixel before and after one toggle, whatever the start state.
      await desktop();
      await topic("advanced", "Advanced"); await settle();
      const insidePixel = () => page.evaluate(() => {
        const canvas = [...document.querySelectorAll("canvas[data-draw-canvas]")].find((c) => c.getAttribute("data-canvas-size")?.endsWith(",120"));
        const ratio = window.devicePixelRatio || 1;
        return [...canvas.getContext("2d").getImageData(Math.round(160 * ratio), Math.round(100 * ratio), 1, 1).data];
      });
      const distance = (a, b) => Math.max(...[0, 1, 2].map((i) => Math.abs(a[i] - b[i])));
      const before = await insidePixel();
      await page.getByTestId("showcase-theme-toggle").click(); await flush();
      let after = before;
      for (let index = 0; index < 40; index++) {
        await page.waitForTimeout(50);
        after = await insidePixel();
        if (distance(before, after) >= 5) break;
      }
      assert.ok(distance(before, after) >= 5, `canvas did not repaint for the toggled color scheme ${json([before, after])}`);
      await page.getByTestId("showcase-theme-toggle").click(); await flush();
    });
    await stage("fileMover moves into a File System Access folder, or downloads a copy and keeps the source", async () => {
      // Chromium: a stubbed File System Access directory receives the bytes and the move reports a new
      // location. Other engines have no picker, so the move downloads a copy and reports the original.
      await desktop();
      await topic("advanced", "Advanced"); await settle();
      const message = page.getByTestId("showcase-file-message");
      const [exported] = await Promise.all([
        page.waitForEvent("download"),
        (async () => { await page.getByRole("button", { name: "Export report" }).click(); await flush(); })(),
      ]);
      assert.equal(exported.suggestedFilename(), "swiftuiweb-report.txt");
      await expect(message).toContainText("Exported transfer-file://");
      const original = (await message.innerText()).replace("Exported ", "").trim();
      const move = page.getByTestId("showcase-file-move");
      await expect(move).toBeEnabled();
      if (engineName() === "chromium") {
        await page.evaluate(() => {
          window.__moved = {}; window.__pickerCalls = 0;
          const dir = {
            files: {},
            async getFileHandle(name, o) {
              if (!(name in this.files)) {
                if (!o?.create) { const e = new Error("missing"); e.name = "NotFoundError"; throw e; }
                this.files[name] = new Uint8Array();
              }
              const d = this;
              return { name, async createWritable() { return { async write(b) { d.files[name] = b.slice(); window.__moved[name] = new TextDecoder().decode(b); }, async close() {} }; } };
            },
            async removeEntry(n) { delete this.files[n]; },
          };
          window.showDirectoryPicker = () => { window.__pickerCalls++; return Promise.resolve(dir); };
        });
        await move.click(); await flush();
        await expect(message).toContainText("Moved to transfer-file://moved-");
        assert.equal(await page.evaluate("window.__pickerCalls"), 1);
        assert.deepEqual(await page.evaluate("window.__moved"), { "swiftuiweb-report.txt": "SwiftUIWeb export generated at runtime.\n" });
        const moved = (await message.innerText()).replace("Moved to ", "").trim();
        assert.notEqual(moved, original);
        // The new URL carries the bytes: moving it again writes a second, non-clobbering file.
        await move.click(); await flush();
        await expect(message).not.toHaveText("Moved to " + moved);
        assert.equal((await page.evaluate("window.__moved"))["swiftuiweb-report 2.txt"], "SwiftUIWeb export generated at runtime.\n");
        assert.equal(await page.evaluate("window.__pickerCalls"), 2);
        await page.evaluate("delete window.showDirectoryPicker");
      } else {
        await page.evaluate("delete window.showDirectoryPicker;delete window.showSaveFilePicker");
        const [copy] = await Promise.all([page.waitForEvent("download"), (async () => { await move.click(); await flush(); })()]);
        assert.equal(copy.suggestedFilename(), "swiftuiweb-report.txt");
        await expect(message).toHaveText("Moved to " + original);
      }
    });
    report.metrics = await page.evaluate("window.__embeddedSession.metrics");
    report.status = "PASS";
    save();
  } catch (error) {
    report.status = "FAIL";
    report.reason = `${error?.name ?? "Error"}: ${error?.message ?? error}`;
    save();
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = 1;
    return;
  } finally {
    await browser?.close();
    await server.stop();
  }
  console.log(JSON.stringify(report, null, 2));
});

void isDeepStrictEqual;
