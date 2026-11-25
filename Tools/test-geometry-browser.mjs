#!/usr/bin/env bun
// Chromium test of GeometryReader, onGeometryChange and coordinate spaces.
//
// Drives Tests/Apps/EmbeddedLoweringConformanceApp/EmbeddedGeometryFixture.swift
// through the real Embedded Swift + CSS layout + JavaScript host bundle built by
// `BUILD_ONLY=1 CONFIGURATION=debug Tools/run-browser.sh lowering`.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { engineName, launch, runSuite, serveDirectory } from "./browser-test-support.mjs";

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    port: { type: "string", default: "0" }, // HTTP port (0 selects a free port)
    output: { type: "string", default: ".build/embedded-ui/geometry" },
  },
});

await runSuite(async () => {
  const bundle = resolve(positionals[0] ?? ".build/browser/EmbeddedLoweringConformanceApp");
  const output = resolve(values.output);
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) {
    throw new Error(`Embedded geometry fixture bundle is missing: ${bundle}`);
  }
  mkdirSync(output, { recursive: true });
  const report = { status: "RUNNING", runtime: "Embedded Swift + BrowserIO", checks: [] };
  const errors = [];
  const server = await serveDirectory(bundle, Number(values.port));
  let browser;
  try {
    const base = server.base;
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
    page.on("pageerror", (error) => errors.push(String(error)));
    // While `__reverseResizeEntries` is set, a window resize reaches Swift only through one ResizeObserver delivery
    // (the geometry host's own passive resize listener, which re-measures position readers first, is held back) and
    // that delivery lists its entries in reverse document order.
    await page.addInitScript(() => {
      const Native = window.ResizeObserver;
      window.ResizeObserver = class extends Native {
        constructor(callback) {
          super((entries, observer) => callback(window.__reverseResizeEntries ? [...entries].reverse() : entries, observer));
        }
      };
      const addEventListener = window.addEventListener;
      window.addEventListener = function (type, listener, options) {
        if (type !== "resize" || options?.passive !== true || typeof listener !== "function") {
          return addEventListener.call(this, type, listener, options);
        }
        return addEventListener.call(this, type, function (event) {
          if (!window.__reverseResizeEntries) return listener.call(this, event);
        }, options);
      };
    });

    // Every Web Animation the host starts and every CSS transition that runs below an `.animation(_:value:)`, and the
    // width of the widest box there (the orange bar).
    await page.addInitScript(() => {
      window.__motion = { animations: 0, transitions: 0 };
      const animate = Element.prototype.animate;
      Element.prototype.animate = function (...args) {
        if (this.closest?.("[data-animation]")) window.__motion.animations++;
        return animate.apply(this, args);
      };
      document.addEventListener("transitionrun", (event) => {
        if (event.target.closest?.("[data-animation]")) window.__motion.transitions++;
      }, true);
      window.__animatedWidth = () => {
        const host = document.querySelector("[data-animation]");
        return host ? Math.max(...[...host.querySelectorAll("*")].map((element) => Math.round(element.getBoundingClientRect().width))) : -1;
      };
    });
    const bodyText = () => page.locator("body").innerText();

    async function value(label) {
      const match = new RegExp(`${escapeRegExp(label)}: (-?\\d+)`).exec(await bodyText());
      if (!match) throw new Error(`'${label}' not rendered: ${JSON.stringify((await bodyText()).slice(0, 400))}`);
      return Number(match[1]);
    }

    async function waitValue(label, predicate, description) {
      try {
        // A string predicate is only polled when it is a plain expression, so the arrow function is invoked here.
        await page.waitForFunction(
          "((label) => { const text = document.body.innerText, at = text.indexOf(label + ': ');" +
            " if (at < 0) return false; const m = /^-?\\d+/.exec(text.slice(at + label.length + 2));" +
            " return !!m && (" + predicate + ")(Number(m[0])); })(" + JSON.stringify(label) + ")",
          undefined,
          { timeout: 3000 },
        );
      } catch (error) {
        throw new Error(
          `${label} never became ${description}; body=${JSON.stringify((await bodyText()).slice(0, 600))}; errors=${JSON.stringify(errors)}`,
          { cause: error },
        );
      }
      return value(label);
    }

    function check(name) {
      if (errors.length) throw new Error("browser runtime errors: " + errors.join("; "));
      report.checks.push({ name, status: "PASS" });
    }

    await page.goto(`${base}/`, { waitUntil: "networkidle" });
    await page.getByRole("button", { name: "Open geometry fixture", exact: true }).click();

    await waitValue("Measured height", "v => v === 40", "40");
    await waitValue("Height changes", "v => v === 1", "1 (initial)");
    await page.waitForTimeout(150);
    if ((await value("Height changes")) !== 1) {
      throw new Error("onGeometryChange fired again without a geometry change");
    }
    check("onGeometryChange fires once with the initial value on appear");

    await page.getByRole("button", { name: "Grow measured box", exact: true }).click();
    await waitValue("Measured height", "v => v === 60", "60");
    await waitValue("Height changes", "v => v === 2", "2");
    check("onGeometryChange fires when the transformed value changes");

    const width = await waitValue("Measured width", "v => v > 0", "positive");
    await page.setViewportSize({ width: 700, height: 900 });
    const resized = await waitValue("Measured width", `v => v > 0 && v < ${width}`, `smaller than ${width}`);
    check(`onGeometryChange follows a window resize (${width} -> ${resized})`);

    // One delivery that reports the GeometryReader before the green bar reaches Swift as one batch in that order: the
    // reader queues its own owner, and the bar's later @State write must still be rendered.
    await page.setViewportSize({ width: 1000, height: 900 });
    await waitValue("Measured width", `v => v === ${width}`, `${width} again`);
    await page.evaluate(() => { window.__reverseResizeEntries = true; });
    await page.setViewportSize({ width: 700, height: 900 });
    await waitValue("Measured width", `v => v === ${resized}`, `${resized} with the reader reported first`);
    await page.evaluate(() => { window.__reverseResizeEntries = false; });
    check("a state write reported after a GeometryReader in the same delivery is rendered");

    // coordinateSpace(name: "geometry-scroll") must publish the readable name as render metadata,
    // and the .named("geometry-scroll") lookup below must resolve against that same space.
    const namedHosts = await page.locator('[data-coordinate-space="geometry-scroll"]').count();
    if (namedHosts !== 1) {
      throw new Error(`expected one data-coordinate-space="geometry-scroll" host, found ${namedHosts}`);
    }
    check('coordinateSpace(name: "geometry-scroll") renders the readable name in the DOM');

    const reader = await waitValue("Reader minY", "v => v >= 0", "non-negative");
    const row = await waitValue("Row scrollView minY", "v => v >= 0", "non-negative");
    if (row - reader !== 40) {
      throw new Error(`row should sit 40pt below the reader in scroll space: reader=${reader} row=${row}`);
    }
    await page.evaluate(() => {
      const host = [...document.querySelectorAll(".scroll-view")].find((el) => el.querySelector("[data-geometry-reader]"));
      host.scrollTop = 25;
    });
    await waitValue("Reader minY", `v => v === ${reader - 25}`, `${reader - 25}`);
    await waitValue("Row scrollView minY", `v => v === ${row - 25}`, `${row - 25}`);
    check("named and scrollView frames update while the ScrollView scrolls");

    await page.evaluate(() => {
      const host = [...document.querySelectorAll(".scroll-view")].find((el) => el.querySelector("[data-geometry-reader]"));
      host.scrollTop = 0;
    });
    await waitValue("Reader minY", `v => v === ${reader}`, `${reader}`);
    await waitValue("Row scrollView minY", `v => v === ${row}`, `${row}`);
    check("frames return to their origin when scrolled back");

    const before = await value("Height changes");
    await page.getByRole("button", { name: "Return to conformance app", exact: true }).click();
    await page.getByRole("button", { name: "Open geometry fixture", exact: true }).click();
    // The remounted modifier must fire its initial action exactly once.
    // Whether the fixture's own @State survives the branch switch is a
    // Fiber identity concern, so accept both a fresh and a kept count.
    await waitValue("Height changes", `v => v === 1 || v === ${before + 1}`, `1 or ${before + 1} after remount`);
    await page.waitForTimeout(150);
    const afterRemount = await value("Height changes");
    if (afterRemount !== 1 && afterRemount !== before + 1) {
      throw new Error("remounted onGeometryChange fired more than once");
    }
    check("a remounted view receives a fresh initial onGeometryChange");

    // `.animation(_:value:)` animates the commit in which its value changed, like SwiftUI; a later change below it with
    // the same value, a window resize included, snaps like plain HTML/CSS. The element's own transition eases its width.
    const motion = () => page.evaluate(() => ({ ...window.__motion }));
    const resetMotion = () => page.evaluate(() => { window.__motion = { animations: 0, transitions: 0 }; });
    const animatedWidth = () => page.evaluate(() => window.__animatedWidth());
    {
      const engine = "CSS layout", query = "";
      await page.setViewportSize({ width: 1000, height: 900 });
      await page.goto(`${base}/${query}`, { waitUntil: "networkidle" });
      await page.getByRole("button", { name: "Open geometry fixture", exact: true }).click();
      await page.getByRole("button", { name: "Toggle animated value", exact: true }).waitFor();
      await page.waitForTimeout(600);
      const collapsed = await animatedWidth();
      await resetMotion();
      await page.getByRole("button", { name: "Toggle animated value", exact: true }).click();
      await page.waitForFunction((from) => window.__animatedWidth() !== from, collapsed);
      await page.waitForTimeout(150);
      const midway = await animatedWidth(), started = await motion();
      if (!(midway > collapsed && midway < collapsed + 120) || started.animations + started.transitions === 0) {
        throw new Error(`${engine}: a change of the value did not animate: ${collapsed} -> ${midway}, ${JSON.stringify(started)}`);
      }
      await page.waitForTimeout(900);
      if ((await animatedWidth()) !== collapsed + 120) throw new Error(`${engine}: the animation did not end at ${collapsed + 120}`);
      check(`${engine}: a change of the .animation value animates (${collapsed} -> ${midway} midway, ${JSON.stringify(started)})`);

      await resetMotion();
      await page.getByRole("button", { name: "Widen without the animated value", exact: true }).click();
      await page.waitForFunction((from) => window.__animatedWidth() !== from, collapsed + 120);
      const widened = await animatedWidth();
      await page.waitForTimeout(200);
      const unrelated = await motion();
      if (widened !== collapsed + 160 || unrelated.animations + unrelated.transitions !== 0) {
        throw new Error(`${engine}: a change with the same value animated: first width ${widened}, expected ${collapsed + 160}, ${JSON.stringify(unrelated)}`);
      }
      check(`${engine}: a later change below the same view with the same value snaps`);

      await resetMotion();
      await page.setViewportSize({ width: 800, height: 900 });
      await page.waitForTimeout(700);
      const resizing = await motion();
      if (resizing.animations + resizing.transitions !== 0) {
        throw new Error(`${engine}: a window resize animated below the view: ${JSON.stringify(resizing)}`);
      }
      check(`${engine}: a window resize below the same view snaps`);
    }

    // A view sized from what onGeometryChange measured is never shown at its unmeasured size: SwiftUI applies the
    // measurement before the first frame. With Swift on the main thread the answer is committed before the paint; from a
    // Worker the presentation's piece stays hidden until Swift has answered. Sampled at every frame from the click, as
    // layout heights (a sheet's entrance transform scales its box).
    // The Worker is also sampled with the page's CPU 10 times slower (Chromium's own throttle): Swift is then still running
    // the call before the measurement when the page takes it, so the measurement is held and counts for nothing in the calls
    // sent. The panel was shown at 600 in 11 of 12 rounds like that, and now and then on a loaded machine without it. It is
    // sampled three times, each in a fresh page: a page that shows the panel early does it in nearly every round.
    const throttled = engineName() === "chromium" ? 10 : 1;
    const modes = [["Worker", "", 1], ["main thread", "?render-in-worker=0", 1], ...(throttled > 1 ? [1, 2, 3].map((round) => [`Worker, CPU ${throttled} times slower, round ${round}`, "", throttled]) : [])];
    for (const [mode, query, rate] of modes) {
      const cdp = rate > 1 ? await page.context().newCDPSession(page) : null;
      await cdp?.send("Emulation.setCPUThrottlingRate", { rate });
      await page.goto(`${base}/${query}`, { waitUntil: "networkidle" });
      await page.getByRole("button", { name: "Open geometry fixture", exact: true }).click();
      const toggle = page.getByRole("button", { name: "Toggle measured panel", exact: true });
      await toggle.waitFor();
      // Read after each frame is painted (a message posted from the frame's animation callback arrives after its
      // rendering): what an animation callback reads is laid out but not yet measured, and never painted.
      const frames = await toggle.evaluate((button) => new Promise((done) => {
        const shown = [];
        const channel = new MessageChannel();
        channel.port1.onmessage = () => {
          const panel = document.querySelector('[data-testid="measured-panel"]');
          const visible = panel && panel.closest("[data-measuring]") === null && getComputedStyle(panel).visibility !== "hidden";
          shown.push(visible ? panel.offsetHeight : 0);
          if (shown.length < 30) requestAnimationFrame(frame); else done(shown);
        };
        const frame = () => channel.port2.postMessage(0);
        button.click();
        requestAnimationFrame(frame);
      }));
      const seen = frames.filter((height) => height > 0);
      if (!seen.length) throw new Error(`${mode}: the measured panel never showed: ${frames.join(",")}`);
      if (seen.includes(600)) throw new Error(`${mode}: the panel showed at its unmeasured height (600) before the measurement: ${frames.join(",")}`);
      check(`${mode}: a view sized from onGeometryChange first shows at its measured size (${seen[0]}, frame ${frames.indexOf(seen[0])})`);
      await cdp?.send("Emulation.setCPUThrottlingRate", { rate: 1 });
      await cdp?.detach();
    }

    if (errors.length) throw new Error("browser runtime errors: " + errors.join("; "));
    report.status = "PASS";
  } finally {
    await browser?.close();
    await server.close();
    writeFileSync(join(output, "result.json"), JSON.stringify(report, null, 2) + "\n");
  }
  console.log(JSON.stringify(report, null, 2));
});
