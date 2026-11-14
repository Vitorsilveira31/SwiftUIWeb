#!/usr/bin/env bun
// Forced layouts of a commit. A script that reads geometry or computed style while the page has pending changes makes
// the browser recalculate style and lay out right there; written and read in turns, a commit does that several times
// where once would do (the cost of an interleaved patch is the same work repeated for the part each write dirtied).
//
// This test counts those synchronous recalculations with Chromium's trace (Layout and UpdateLayoutTree events that
// carry a JavaScript stack, so the ones the rendering step itself runs are not counted) and names the script function
// that caused each, for the production DOM host driven by the contract fixture (Tests/EmbeddedUI/host-fixture.html).
//   bun Tools/test-forced-layouts-browser.mjs [--report] [--host-root <checkout>]
// --report prints the counts instead of asserting them; --host-root runs another checkout's Tools/*.js against this
// fixture (how the numbers of the change were compared with the base). Chromium only: no other engine traces this.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { engineName, launch, ROOT, runSuite } from "./browser-test-support.mjs";

if (engineName() !== "chromium") {
  console.log(`skipped: forced layouts are traced through Chromium's DevTools protocol, not ${engineName()}`);
  process.exit(0);
}

const { values } = parseArgs({ options: { report: { type: "boolean", default: false }, "host-root": { type: "string" } } });
const hostRoot = resolve(values["host-root"] ?? ROOT);
// In --report mode the assertions about the counts only report, so another checkout can be measured too.
const expect = (condition, message) => { if (!values.report && !condition) assert.fail(message); else if (!condition) console.error(`not met: ${message}`); };
const read = (root, path) => readFileSync(join(root, path));

/** Serves the fixture page and the host's modules as real URLs. Inlined as data: URLs, every stack frame the trace records
 * would carry the whole module in its `url` and the trace came back truncated. */
async function serveFixture(context) {
  await context.route("http://fixture.test/**", (route) => {
    const path = new URL(route.request().url()).pathname;
    const root = path.startsWith("/Tools/") ? hostRoot : ROOT;
    let body = read(root, path);
    if (path.endsWith(".html")) body = Buffer.from(body.toString().replace("<head>", '<head><meta name="viewport" content="width=device-width, initial-scale=1">'));
    route.fulfill({ body, contentType: path.endsWith(".js") ? "text/javascript" : "text/html" });
  });
}

/** Groups the forced recalculations of a trace between two markers into flushes: the style recalculation and the layout
 * one read causes come one after the other from the same call stack. */
function flushesBetween(events, begin, end) {
  const marks = events.filter((event) => event.name === "TimeStamp");
  const from = marks.find((event) => event.args.data.message === begin), to = marks.find((event) => event.args.data.message === end);
  assert.ok(from && to, `the trace holds both markers (${events.length} events, ${marks.length} timestamps: ${marks.map((m) => m.args.data.message)})`);
  const forced = events
    .filter((event) => event.tid === from.tid && event.ts >= from.ts && event.ts <= to.ts && (event.name === "Layout" || event.name === "UpdateLayoutTree"))
    .filter((event) => (event.args.beginData?.stackTrace ?? []).some((frame) => frame.url))
    .filter((event) => (event.name === "Layout" ? event.args.beginData.dirtyObjects : event.args.elementCount) > 0)
    .sort((a, b) => a.ts - b.ts);
  const flushes = [];
  for (const event of forced) {
    const frames = event.args.beginData.stackTrace.filter((frame) => frame.url);
    const signature = frames.map((frame) => `${frame.lineNumber}:${frame.columnNumber}`).join(">");
    const size = event.name === "Layout" ? event.args.beginData.dirtyObjects : event.args.elementCount;
    // A read that finds both style and layout dirty reports a style recalculation and then a layout from one call
    // stack; anything else starts a new flush.
    const last = flushes[flushes.length - 1];
    if (event.name === "Layout" && last && last.signature === signature && !last.events.includes("Layout")) {
      last.events.push("Layout"); last.detail += `,Layout:${size}`; last.ms += event.dur / 1000; continue;
    }
    flushes.push({ signature, detail: `${event.name}:${size}`, events: [event.name], ms: event.dur / 1000, functions: frames.map((frame) => frame.functionName).filter(Boolean).slice(0, 6) });
  }
  return flushes;
}

await runSuite(async () => {
  const report = [];
  const browsers = [];
  try {
    // One browser per scenario: a second renderer process started after a trace did not report its events.
    const open = async (contextOptions) => {
      const browser = await launch({ args: ["--no-sandbox"] });
      browsers.push(browser);
      const context = await browser.newContext(contextOptions);
      const page = await context.newPage();
      const errors = [];
      page.on("pageerror", (error) => errors.push(String(error)));
      await serveFixture(context);
      await page.goto("http://fixture.test/Tests/EmbeddedUI/host-fixture.html", { waitUntil: "domcontentloaded" });
      await page.waitForFunction("window.fixture?.ready === true");
      const cdp = await context.newCDPSession(page);
      const traced = async (expression) => {
        const events = [];
        const collect = (message) => events.push(...message.value);
        cdp.on("Tracing.dataCollected", collect);
        const complete = new Promise((done) => cdp.once("Tracing.tracingComplete", done));
        await cdp.send("Tracing.start", { transferMode: "ReportEvents", traceConfig: { recordMode: "recordAsMuchAsPossible",
          includedCategories: ["devtools.timeline", "disabled-by-default-devtools.timeline", "disabled-by-default-devtools.timeline.stack"] } });
        await page.evaluate(`(() => { console.timeStamp("swui-begin"); ${expression}; console.timeStamp("swui-end"); })()`);
        await cdp.send("Tracing.end");
        await complete;
        cdp.off("Tracing.dataCollected", collect);
        return flushesBetween(events, "swui-begin", "swui-end");
      };
      return { context, page, errors, traced };
    };
    const commit = "fixture.render(); fixture.session.flush()";
    const record = (name, flushes) => {
      report.push({ name, flushes: flushes.length, ms: Math.round(flushes.reduce((sum, flush) => sum + flush.ms, 0) * 100) / 100, causes: flushes.map((flush) => flush.functions.slice(0, 3).join("<") + " [" + flush.detail + "]") });
    };

    // A phone: `window.innerWidth` forces layout there (it is the width of the layout viewport, scrollbars included).
    {
      const { context, page, errors, traced } = await open({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
      await page.evaluate("fixture.state.adaptiveTabs = true; fixture.render(); fixture.session.flush()");
      await page.evaluate("fixture.session.flush()");
      assert.equal(await page.locator("#adaptive-tabs").getAttribute("data-tab-layout"), "mobile", "a 390 px wide phone gets the mobile tab layout");

      // The tab shell asks for the viewport width on every commit. It must not be what makes the browser lay the page
      // out: the patch's pending style would be recalculated there and again by whoever reads next.
      const tabs = await traced("fixture.state.tick++; fixture.render(); fixture.session.flush()");
      record("phone: commit with an adaptive tab view", tabs);
      expect(!tabs.some((flush) => flush.functions.some((name) => /layoutFor|viewportWidth/.test(name))),
        `the tab shell forced a layout: ${JSON.stringify(tabs.map((flush) => flush.functions))}`);

      // The cached width still follows the window: crossing the breakpoint changes the layout, and so does coming back.
      await page.setViewportSize({ width: 900, height: 700 });
      await page.waitForFunction(() => document.getElementById("adaptive-tabs").getAttribute("data-tab-layout") !== "mobile");
      await page.setViewportSize({ width: 390, height: 844 });
      await page.waitForFunction(() => document.getElementById("adaptive-tabs").getAttribute("data-tab-layout") === "mobile");
      assert.deepEqual(errors, []);
      await context.close();
    }

    // Style animations: the target style of each is read after the patch, together, not between the patch's writes.
    {
      const { context, page, errors, traced } = await open({ viewport: { width: 900, height: 700 } });
      const count = 24;
      await page.evaluate(`fixture.state.motionItems = ${count}; fixture.render(); fixture.session.flush()`);
      await page.evaluate("fixture.session.flush()");
      const animated = await traced("fixture.state.transaction = 'all .6s linear'; fixture.state.transactionWidth = 200; fixture.render(); fixture.session.flush()");
      record(`animated commit of ${count} elements`, animated);
      const frames = await page.evaluate(() => [...document.querySelectorAll("#motion-items .motion")].map((element) => element.getAnimations().map((animation) => animation.effect.getKeyframes().map((frame) => frame.width))));
      assert.ok(frames.every((animations) => animations.some((widths) => widths[0] === "70px" && widths[widths.length - 1] === "200px")),
        `every element animates its width from 70px to 200px: ${JSON.stringify(frames[0])}`);
      assert.deepEqual(errors, []);
      // The starting style of every element is read before any of them is written and the targets after all of them
      // are: the count must not grow with the number of animated elements (it was 52 for 24 of them).
      expect(animated.length <= 6, `${animated.length} forced recalculations for ${count} animated elements`);
      await context.close();
    }

    // Icons: the icon adapter turns `data-symbol` into an SVG. Left to its MutationObserver the SVG is written after the
    // commit, in a second round of style work; the patch realizes the icons of the nodes it inserts while they are detached
    // and the icon whose symbol changed, and an icon that keeps its symbol keeps its SVG.
    {
      const tmp = mkdtempSync(join(tmpdir(), "forced-icons-"));
      try {
        const manifest = join(tmp, "manifest.json"), asset = join(tmp, "icon-adapter.js");
        writeFileSync(manifest, JSON.stringify({ icons: { symbols: ["house", "lock", "book"], dynamic: false } }));
        execFileSync("bun", [join(ROOT, "Tools/generate-icon-asset.js"), "--manifest", manifest, "--output", asset], { stdio: "pipe" });
        const { context, page, errors } = await open({ viewport: { width: 900, height: 700 } });
        await page.addScriptTag({ content: readFileSync(asset, "utf8") });
        // Everything below runs in one task: the adapter's observer has not been able to run, so what is there was
        // written by the patch.
        const result = await page.evaluate(() => {
          const icons = () => [...document.querySelectorAll("#icons .symbol-icon")];
          const state = () => icons().map((icon) => `${icon.getAttribute("data-lucide")}/${icon.querySelector("svg") ? "svg" : "-"}/${icon.getAttribute("data-lucide-fallback")}`);
          const commit = () => { fixture.render(); fixture.session.flush(); };
          const out = {};
          fixture.state.icons = ["house", "lock", "book"]; commit();
          out.inserted = state();
          const svgs = icons().map((icon) => icon.querySelector("svg"));
          fixture.state.tick++; commit();
          out.sameSymbolKeepsSvg = icons().every((icon, i) => icon.querySelector("svg") === svgs[i]) && icons().every((icon) => icon.hasAttribute("data-lucide"));
          fixture.state.icons = ["book", "lock", "book"]; commit();
          out.changed = state();
          out.otherIconsKept = icons()[1].querySelector("svg") === svgs[1];
          fixture.state.icons = ["book", "no.such.symbol", "book"]; commit();
          out.unknown = state();
          out.glyph = icons()[1].textContent;
          return out;
        });
        assert.deepEqual(result.inserted, ["home/svg/null", "lock/svg/null", "book-open/svg/null"], "inserted icons arrive realized");
        assert.ok(result.sameSymbolKeepsSvg, "an icon that keeps its symbol keeps its SVG element");
        assert.deepEqual(result.changed, ["book-open/svg/null", "lock/svg/null", "book-open/svg/null"], "a changed symbol is realized by the patch");
        assert.ok(result.otherIconsKept, "the icons that did not change are not rewritten");
        assert.deepEqual(result.unknown, ["book-open/svg/null", "null/-/true", "book-open/svg/null"], "an unknown symbol falls back to its glyph");
        assert.equal(result.glyph, "?");
        // The observer finds nothing left to write: the state is the same after it has run.
        assert.deepEqual(await page.evaluate(() => [...document.querySelectorAll("#icons .symbol-icon")].map((icon) => `${icon.getAttribute("data-lucide")}/${icon.querySelector("svg") ? "svg" : "-"}/${icon.getAttribute("data-lucide-fallback")}`)), result.unknown);
        assert.deepEqual(errors, []);
        await context.close();
      } finally {
        rmSync(tmp, { recursive: true, force: true });
      }
    }
  } finally {
    for (const browser of browsers) await browser.close();
  }
  if (values.report) console.log(JSON.stringify(report, null, 2));
  else console.log(JSON.stringify(report));
});
