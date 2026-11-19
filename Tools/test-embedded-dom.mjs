#!/usr/bin/env bun
// Real Chromium regression tests for the production retained DOM host.
// The HTML producer is an ABI fixture, not a Swift application build.
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const read = (path) => readFileSync(join(ROOT, path));
const dataUrl = (path) => "data:text/javascript;base64," + read(path).toString("base64");

/** Longest increasing subsequence length (patience sorting). */
function lis(sequence) {
  const tails = [];
  for (const value of sequence) {
    let low = 0, high = tails.length;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (tails[mid] < value) low = mid + 1; else high = mid;
    }
    if (low === tails.length) tails.push(value); else tails[low] = value;
  }
  return tails.length;
}

await runSuite(async () => {
  const { values } = parseArgs({ options: { output: { type: "string", default: join(ROOT, ".build/embedded-ui/dom-tests.json") } } });
  const output = resolve(values.output);
  const results = [];
  const errors = [];
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, JSON.stringify({ status: "RUNNING_NOT_VALIDATED", scope: "Production JS host with ABI fixture" }) + "\n");
  let browser;
  try {
    browser = await launch({ args: ["--no-sandbox"] });
    const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
    const heldImageRoutes = [];
    await page.route("https://images.test/**", (route) => { heldImageRoutes.push(route); });
    page.on("pageerror", (err) => errors.push(String(err)));
    page.on("console", (message) => { if (message.type() === "error") errors.push(`console.${message.type()}: ${message.text()}`); });
    // `page.setContent` has an opaque about:blank base URL. Inline the host's dependency modules as data URLs as well, otherwise
    // the browser rejects the relative imports before the fixture can publish `window.fixture.ready`.
    let hostSource = read("Tools/embedded-dom.js").toString();
    // layout-host.js imports the document scroll (a touch screen's page scroll view), inlined into it the same way.
    const layoutHostUrl = "data:text/javascript;base64," + Buffer.from(read("Tools/layout-host.js").toString().replaceAll("'./document-scroll.js'", () => `'${dataUrl("Tools/document-scroll.js")}'`)).toString("base64");
    for (const module of ["layout-host", "css-layout", "host-interactions", "first-paint-host", "tab-shell", "event-value", "geometry-host", "media-host", "split-view-host", "transition-host"]) {
      hostSource = hostSource.replaceAll(`'./${module}.js'`, `'${module === "layout-host" ? layoutHostUrl : dataUrl(`Tools/${module}.js`)}'`);
    }
    // The hosts embedded-dom.js imports after the first screen, with the modules they gather.
    let deferredSource = read("Tools/deferred-hosts.js").toString();
    for (const module of ["presentation-host", "transfer-host", "text-layout-host"]) {
      deferredSource = deferredSource.replaceAll(`'./${module}.js'`, `'${dataUrl(`Tools/${module}.js`)}'`);
    }
    hostSource = hostSource.replaceAll("'./deferred-hosts.js'", `'data:text/javascript;base64,${Buffer.from(deferredSource).toString("base64")}'`);
    // The binary publication reader imports the atoms it was generated with, so its data URL needs the same treatment.
    const binarySource = read("Tools/binary-publication.js").toString().replaceAll("'./binary-atoms.generated.js'", `'${dataUrl("Tools/binary-atoms.generated.js")}'`);
    hostSource = hostSource.replaceAll("'./binary-atoms.generated.js'", `'${dataUrl("Tools/binary-atoms.generated.js")}'`);
    hostSource = hostSource.replaceAll("'./binary-publication.js'", `'data:text/javascript;base64,${Buffer.from(binarySource).toString("base64")}'`);
    const host = Buffer.from(hostSource).toString("base64");
    // The fixture's encoder of the binary publications it serves, inlined the same way, with the atoms it was generated with.
    const binaryRootSource = read("Tests/EmbeddedUI/binary-root.js").toString().replace("'../../Tools/binary-atoms.generated.js'", `'${dataUrl("Tools/binary-atoms.generated.js")}'`);
    const fixture = read("Tests/EmbeddedUI/host-fixture.html").toString()
      .replace("../../Tools/embedded-dom.js", "data:text/javascript;base64," + host)
      .replace("'./binary-root.js'", `'data:text/javascript;base64,${Buffer.from(binaryRootSource).toString("base64")}'`);
    await page.setContent(fixture, { waitUntil: "domcontentloaded" });
    await page.waitForFunction("window.fixture?.ready === true");

    const check = async (name, fn) => {
      const start = performance.now();
      await fn();
      assert.deepEqual(errors, []);
      results.push({ name, status: "PASS", seconds: Math.round(((performance.now() - start) / 1000) * 1000) / 1000 });
    };
    const flush = () => page.evaluate("window.__embeddedSession.flush()");
    const text = (selector) => page.locator(selector).innerText();
    const evalOn = (selector, fn) => page.locator(selector).evaluate(fn);

    await check("AsyncImage pipeline synchronizes on initial mount and source refresh", async () => {
      await page.waitForFunction("window.imagePipelineCalls?.length === 1");
      let calls = await page.evaluate("window.imagePipelineCalls");
      assert.equal(calls[0].initial, true);
      assert.ok(calls[0].source.endsWith("/asset-1.gif"));
      assert.equal(await page.locator("#async-image").getAttribute("loading"), "eager",
        JSON.stringify(await evalOn("#async-image", (image) => ({ html: image.outerHTML, calls: window.imagePipelineCalls }))));
      await page.locator("#b17").click();
      await flush();
      await page.waitForFunction("window.imagePipelineCalls?.length === 2");
      calls = await page.evaluate("window.imagePipelineCalls");
      assert.equal(calls[1].initial, false);
      assert.ok(calls[1].source.endsWith("/asset-2.gif"));
      assert.equal(await page.locator("#async-image").getAttribute("loading"), "eager");
      await evalOn("#async-image", (image) => image.dispatchEvent(new Event("load")));
      await flush();
      assert.equal(await text("#count"), "1");
      assert.deepEqual(await page.evaluate("fixture.stats.namedDispatches.slice(-1)[0]"), { id: 18, name: "load", value: "" });
      await evalOn("#async-image", (image) => image.dispatchEvent(new Event("error")));
      await flush();
      assert.equal(await text("#count"), "0");
      assert.deepEqual(await page.evaluate("fixture.stats.namedDispatches.slice(-1)[0]"), { id: 18, name: "error", value: "" });
    });

    await check("an AsyncImage loader whose image is already loaded reports its load once", async () => {
      // The browser already holds the image (another card shows the same URL): the new loader is complete as it is
      // created and can fire its load before it joins the page, where the root never sees it. That lost event is
      // stood in for by a listener on the document (a load never reaches the window), which runs before the root's and
      // stops it. The commit reports the
      // load all the same, once.
      const source = "data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==";
      await page.evaluate(async (url) => {
        const image = new Image(); image.src = url; await image.decode(); window.__heldImage = image;
        window.__swallowCachedLoad = (event) => { if (event.target?.id === "cached-image") event.stopPropagation(); };
        document.addEventListener("load", window.__swallowCachedLoad, true);
      }, source);
      await page.evaluate((url) => { fixture.state.cachedImage = url; fixture.render(); }, source);
      await flush();
      await page.waitForTimeout(150);
      const loads = await page.evaluate(() => fixture.stats.namedDispatches.filter((entry) => entry.id === 19));
      assert.deepEqual(loads, [{ id: 19, name: "load", value: "" }], JSON.stringify(loads));
      // Its own load, when it does reach the root, is not sent a second time.
      await page.evaluate(() => { document.removeEventListener("load", window.__swallowCachedLoad, true); document.getElementById("cached-image").dispatchEvent(new Event("load")); });
      await flush();
      assert.equal(await page.evaluate(() => fixture.stats.namedDispatches.filter((entry) => entry.id === 19).length), 1, "the load is reported once");
      await page.evaluate(() => { fixture.state.cachedImage = null; fixture.render(); });
      await flush();
    });

    await check("hover rules arrive as changes and touch only their own rules", async () => {
      const publish = (rules) => page.evaluate((r) => { fixture.state.hoverRules = r; fixture.state.tick++; fixture.render(); fixture.session.flush(); }, rules);
      const sheet = () => page.evaluate(() => {
        const rules = [...document.getElementById("hover-effect-rules").sheet.cssRules];
        window.__hoverRuleObjects ||= [];
        return rules.map((rule) => ({ text: rule.cssRules[0].cssText, seen: window.__hoverRuleObjects.includes(rule), keep: window.__hoverRuleObjects.push(rule) }))
          .map(({ text, seen }) => ({ text, seen }));
      });
      await publish("+1\t#hover-one:hover { color: red !important; }\n+2\t#hover-two:hover { color: blue !important; }\n");
      assert.deepEqual((await sheet()).map((r) => r.text), ["#hover-one:hover { color: red !important; }", "#hover-two:hover { color: blue !important; }"]);
      assert.equal(await page.locator("section[data-hover-rules]").count(), 0, "the carrier attribute never reaches the DOM");
      // A change sent again before the page acknowledged it leaves the rule it already holds alone.
      await publish("+2\t#hover-two:hover { color: blue !important; }\n");
      assert.deepEqual(await sheet(), [{ text: "#hover-one:hover { color: red !important; }", seen: true }, { text: "#hover-two:hover { color: blue !important; }", seen: true }]);
      await publish("-1\n+2\t#hover-two:hover { color: green !important; }\n");
      assert.deepEqual(await sheet(), [{ text: "#hover-two:hover { color: green !important; }", seen: false }]);
      // No attribute: nothing changed.
      await publish(null);
      assert.deepEqual((await sheet()).map((r) => r.text), ["#hover-two:hover { color: green !important; }"]);
      await publish("-2\n");
      assert.deepEqual(await sheet(), []);
      await publish(null);
    });

    await check("lazy rows refresh at the same count and range without a publish loop", async () => {
      await page.evaluate("fixture.state.lazyRevision=1;fixture.render();fixture.session.flush()");
      await page.waitForFunction('document.getElementById("lazy-value")?.textContent === "First"');
      await page.evaluate('fixture.state.lazyTitle="Updated at same count";fixture.state.lazyRevision=2;fixture.render();fixture.session.flush()');
      await page.waitForFunction('document.getElementById("lazy-value")?.textContent === "Updated at same count"', undefined, { timeout: 3000 });
      const calls = await page.evaluate("fixture.stats.lazyWindows.length");
      for (let index = 0; index < 3; index++) await flush();
      await page.waitForTimeout(60);
      assert.equal(await page.evaluate("fixture.stats.lazyWindows.length"), calls, "materialization must not cause a commit loop");
      await page.evaluate("fixture.state.lazyRevision=0;fixture.render();fixture.session.flush()");
    });

    const recycle = async (windowFrom, windowTo, { withInput = false, enabled = true } = {}) => {
      await page.evaluate((v) => { window.__lazyRecycle = v; }, enabled);
      await page.evaluate(([items, input]) => { fixture.state.recycleInput = input; fixture.state.recycleItems = items; fixture.render(); fixture.session.flush(); }, [windowFrom, withInput]);
      await page.evaluate(() => { window.cellRefs = {}; for (const c of document.querySelectorAll("#rc > [data-lazy-cell]")) cellRefs[c.getAttribute("data-lazy-index")] = c; });
      await page.evaluate(([items]) => { fixture.state.recycleItems = items; fixture.render(); fixture.session.flush(); }, [windowTo]);
      return page.evaluate(() => {
        const out = {};
        for (const c of document.querySelectorAll("#rc > [data-lazy-cell]")) {
          const i = c.getAttribute("data-lazy-index");
          out[i] = {
            same: window.cellRefs[i] === c, title: c.querySelector("h3")?.textContent, body: c.querySelector("span")?.textContent,
            tip: c.getAttribute("title"), outline: (c.getAttribute("style") || "").includes("outline"), nodeId: c.getAttribute("data-embedded-node-id"),
            odd: !!c.querySelector("em"), old: Object.keys(window.cellRefs).filter((k) => window.cellRefs[k] === c),
          };
        }
        return out;
      });
    };
    await check("lazy cells that leave the window are recycled for cells that enter it", async () => {
      const result = await recycle([0, 1, 2, 3], [2, 3, 4, 5]);
      assert.ok(result["2"].same && result["3"].same, "cells that stay keep their element");
      // 4 and 5 entered while 0 and 1 left: they reuse those elements.
      assert.ok(JSON.stringify(result["4"].old) === '["0"]' && JSON.stringify(result["5"].old) === '["1"]', JSON.stringify(result));
      for (const i of ["2", "3", "4", "5"]) {
        assert.ok(result[i].title === `Title ${i}` && result[i].body === `Body ${i}` && result[i].tip === `cell ${i}`, JSON.stringify(result[i]));
        assert.equal(result[i].nodeId, "cell-" + i, JSON.stringify(result[i]));
        assert.equal(result[i].odd, Number(i) % 2 === 1, "structure that differs by item must be rebuilt in place");
        assert.equal(result[i].outline, Number(i) >= 4, "a shorthand declared with var() must follow the item it is recycled for");
      }
      const back = await recycle([2, 3, 4, 5], [0, 1, 2, 3]);
      assert.ok(JSON.stringify(back["0"].old) === '["4"]' && JSON.stringify(back["1"].old) === '["5"]', JSON.stringify(back));
      assert.ok(!back["0"].outline && !back["1"].outline, "a var() shorthand must be removed when the item no longer has it");
    });
    await check("lazy cells hosting form controls are not recycled", async () => {
      const result = await recycle([0, 1, 2, 3], [2, 3, 4, 5], { withInput: true });
      assert.ok(result["4"].old.length === 0 && result["5"].old.length === 0, "cells hosting form controls are never recycled");
    });
    await check("lazy cell recycling can be turned off", async () => {
      const result = await recycle([0, 1, 2, 3], [2, 3, 4, 5], { enabled: false });
      assert.ok(result["4"].old.length === 0 && result["5"].old.length === 0, "the opt-out must disable recycling");
      await page.evaluate(() => { window.__lazyRecycle = true; fixture.state.recycleItems = null; fixture.render(); fixture.session.flush(); });
    });
    await check("a commit that removes the focused field gives focus to the view around it", async () => {
      const show = (overlay) => page.evaluate((overlay) => { fixture.state.focusShell = true; fixture.state.focusOverlay = overlay; fixture.render(); fixture.session.flush(); }, overlay);
      const focused = () => page.evaluate(() => new Promise((resolve) => queueMicrotask(() => resolve(document.activeElement?.id || document.activeElement?.localName))));
      await show(true);
      await page.locator("#fs-field").focus();
      await show(false);
      assert.equal(await focused(), "fs-shell", "the shell around the removed field takes focus");
      await show(true);
      await page.locator("#fs-button").focus();
      await show(false);
      assert.equal(await focused(), "fs-button", "focus that was not removed stays");
      await show(true);
      await page.locator("#fs-field").focus();
      await page.evaluate(() => { document.activeElement.blur(); });
      await show(false);
      assert.equal(await focused(), "body", "nothing takes focus the person had already left");
      await page.evaluate(() => { fixture.state.focusShell = false; fixture.state.focusOverlay = false; fixture.render(); fixture.session.flush(); });
    });
    await check("Return in a text field outside a form submits it to its onSubmit", async () => {
      await page.evaluate(() => { fixture.state.submitFields = true; fixture.render(); fixture.session.flush(); });
      const submits = async (selector, keys) => {
        await page.evaluate(() => { fixture.stats.dispatches.length = 0; });
        await page.locator(selector).focus();
        for (const key of keys) await page.keyboard.press(key);
        await page.evaluate(() => fixture.session.flush());
        return page.evaluate(() => fixture.stats.dispatches.filter((d) => d.code === 2).map((d) => d.id));
      };
      assert.deepEqual(await submits("#submit-text", ["a", "Enter"]), [41], "Return submits a text field to the onSubmit around it");
      assert.deepEqual(await submits("#submit-text", ["Shift+Enter"]), [], "Shift+Return does not submit");
      assert.deepEqual(await submits("#submit-search", ["Enter"]), [], "an onSubmit of .text does not take a search field");
      assert.deepEqual(await submits("#search-only", ["Enter"]), [42], "an onSubmit of .search takes a search field");
      assert.deepEqual(await submits("#submit-area", ["Enter"]), [], "Return in a text editor is a new line");
      assert.deepEqual(await submits("#form-field", ["Enter"]), [43], "a field in a form is submitted once, by the form");
      await page.evaluate(() => { fixture.state.submitFields = false; fixture.render(); fixture.session.flush(); });
    });
    await check("commits leave the attributes the tab shell owns alone", async () => {
      await page.evaluate(() => { fixture.state.tabShell = true; fixture.render(); fixture.session.flush(); });
      await page.evaluate(() => {
        const v = document.getElementById("tab-shell"), s = document.getElementById("tab-shell-sidebar");
        v.setAttribute("data-tab-layout", "rail"); v.setAttribute("data-tab-sidebar-expanded", "false");
        s.setAttribute("role", "navigation"); s.setAttribute("aria-label", "from host");
      });
      for (let index = 0; index < 3; index++) await page.evaluate(() => { fixture.state.tick++; fixture.render(); fixture.session.flush(); });
      const owned = await page.evaluate(() => {
        const v = document.getElementById("tab-shell"), s = document.getElementById("tab-shell-sidebar");
        return [v.getAttribute("data-tab-layout"), v.getAttribute("data-tab-sidebar-expanded"), s.getAttribute("role"), s.getAttribute("aria-label")];
      });
      assert.deepEqual(owned, ["rail", "false", "navigation", "from host"]);
      await page.evaluate(() => { fixture.state.tabShell = false; fixture.render(); fixture.session.flush(); });
    });

    await check("commits keep the load hints and the managed size the image pipeline set on an image", async () => {
      await page.evaluate(() => { fixture.state.pipelineImage = true; fixture.render(); fixture.session.flush(); });
      // What the image pipeline writes: the load hints, and the width it gave the image as its intrinsic ratio (managed).
      await page.evaluate(() => {
        const image = document.getElementById("pipeline-image");
        image.setAttribute("loading", "lazy"); image.setAttribute("fetchpriority", "low"); image.setAttribute("decoding", "async");
        image.setAttribute("width", "40"); image.__managedWidth = true; image.__managedWidthValue = "40";
      });
      const state = () => page.evaluate(() => {
        const image = document.getElementById("pipeline-image");
        return [image.getAttribute("loading"), image.getAttribute("fetchpriority"), image.getAttribute("decoding"), image.getAttribute("width"), image.getAttribute("height")];
      });
      // A commit that changes something else on the image visits it. Swift sends none of the pipeline's attributes.
      await page.evaluate(() => { fixture.state.pipelineAlt = "second"; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.locator("#pipeline-image").getAttribute("alt"), "second");
      assert.deepEqual(await state(), ["lazy", "low", "async", "40", null]);
      // A width that is not the managed value, and a height the pipeline did not set, are Swift's: a commit that does not send them removes them.
      await page.evaluate(() => {
        const image = document.getElementById("pipeline-image");
        image.setAttribute("width", "99"); image.setAttribute("height", "55");
        fixture.state.pipelineAlt = "third"; fixture.render(); fixture.session.flush();
      });
      assert.equal(await page.locator("#pipeline-image").getAttribute("alt"), "third");
      assert.deepEqual(await state(), ["lazy", "low", "async", null, null]);
      // Swift sends an image `loading="lazy"`; one the pipeline made eager stays eager.
      await page.evaluate(() => { const image = document.getElementById("pipeline-image"); image.setAttribute("loading", "eager"); fixture.state.pipelineLazy = true; fixture.state.pipelineAlt = "fourth"; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.locator("#pipeline-image").getAttribute("loading"), "eager");
      await page.evaluate(() => { fixture.state.pipelineImage = false; fixture.state.pipelineLazy = false; fixture.render(); fixture.session.flush(); });
    });

    await check("a click on a tab not built yet keeps the panel on screen until Swift builds it", async () => {
      await page.evaluate(() => { fixture.state.panelTabs = { selected: "a", builtC: false }; fixture.render(); fixture.session.flush(); });
      const shown = () => page.evaluate(() => ["a", "b", "c"].filter((v) => document.getElementById("pp-" + v).getAttribute("data-tab-hidden") === "false").join(","));
      const selected = () => page.evaluate(() => ["a", "b", "c"].filter((v) => document.getElementById("pt-" + v).getAttribute("aria-selected") === "true").join(","));
      await page.locator("#pt-b").click();
      assert.equal(await shown(), "b", "a built tab is shown at once");
      await page.locator("#pt-c").click();
      assert.equal(await selected(), "c", "the button follows the click at once");
      assert.equal(await shown(), "b", "the unbuilt tab's empty panel is not shown");
      await page.evaluate(() => { fixture.state.tick++; fixture.render(); fixture.session.flush(); });
      assert.equal(await shown(), "b", "an unrelated commit does not show it either");
      await page.evaluate(() => { fixture.state.panelTabs = { selected: "c", builtC: true }; fixture.render(); fixture.session.flush(); });
      assert.equal(await shown(), "c", "the publication that builds it shows it");
      assert.equal(await page.evaluate(() => document.getElementById("pp-c").textContent), "panel c");
      await page.evaluate(() => { fixture.state.panelTabs = null; fixture.render(); fixture.session.flush(); });
    });

    await check("a click on a built tab whose screen hides the tab bar waits for the publication that removes the bar", async () => {
      await page.evaluate(() => { fixture.state.panelTabs = { selected: "a", builtC: true, hidesBarC: true }; fixture.render(); fixture.session.flush(); });
      const shown = () => page.evaluate(() => ["a", "b", "c"].filter((v) => document.getElementById("pp-" + v).getAttribute("data-tab-hidden") === "false").join(","));
      const selected = () => page.evaluate(() => ["a", "b", "c"].filter((v) => document.getElementById("pt-" + v).getAttribute("aria-selected") === "true").join(","));
      await page.locator("#pt-c").click();
      assert.equal(await selected(), "c", "the button follows the click at once");
      assert.equal(await shown(), "a", "the panel is not shown before the bar goes");
      await page.evaluate(() => { fixture.state.panelTabs = { selected: "c", builtC: true, hidesBarC: true }; fixture.render(); fixture.session.flush(); });
      assert.equal(await shown(), "c", "the publication that selects it shows it");
      await page.evaluate(() => { fixture.state.panelTabs = null; fixture.render(); fixture.session.flush(); });
    });

    await check("25 nested button updates preserve root, scripts and native input identity", async () => {
      await page.evaluate('window.rootRef=document.getElementById("embedded-app-root");window.inputRef=document.getElementById("range");window.scriptRef=document.querySelector("body script")');
      for (let index = 0; index < 25; index++) { await page.locator("#b1 span").click(); await flush(); }
      assert.equal(await text("#count"), "25");
      assert.ok(await page.evaluate('window.rootRef===document.getElementById("embedded-app-root") && window.inputRef===document.getElementById("range") && window.scriptRef.isConnected && window.sentinel.retained'));
    });

    await check("keyed reorders keep row elements and move only rows that leave their order", async () => {
      // Each case: the rows before, the rows after, and the most moves allowed (rows outside the longest run kept in order).
      // Rows keep their element; rows that stay in order never move.
      const n = 200;
      const rows = Array.from({ length: n }, (_, i) => i);
      const shuffled = [...rows];
      let seed = 7n;
      for (let i = n - 1; i > 0; i--) {
        seed = (seed * 1103515245n + 12345n) % 2n ** 31n;
        const j = Number(seed % BigInt(i + 1));
        [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
      }
      const swapped = [...rows];
      [swapped[1], swapped[n - 2]] = [swapped[n - 2], swapped[1]];
      const cases = [
        ["remove first", rows, rows.slice(1)], ["remove middle", rows, [...rows.slice(0, 100), ...rows.slice(101)]], ["remove last", rows, rows.slice(0, -1)],
        ["swap two", rows, swapped], ["move one to front", rows, [150, ...rows.slice(0, 150), ...rows.slice(151)]],
        ["insert first", rows, [1000, ...rows]], ["insert middle", rows, [...rows.slice(0, 100), 1000, ...rows.slice(100)]],
        ["reverse", rows, [...rows].reverse()], ["shuffle", rows, shuffled],
        ["remove first after unkeyed text", ["Header", ...rows], ["Header", ...rows.slice(1)]],
      ];
      for (const [name, before, after] of cases) {
        await page.evaluate((r) => { fixture.state.reorder = r; fixture.render(); fixture.session.flush(); }, before);
        await page.evaluate(() => {
          window.rowRefs = new Map([...document.querySelectorAll("#reorder > li")].map((e) => [e.getAttribute("data-embedded-node-id"), e]));
          window.movedBefore = fixture.session.metrics.moved;
        });
        await page.evaluate((r) => { fixture.state.reorder = r; fixture.render(); fixture.session.flush(); }, after);
        const keys = after.filter((r) => typeof r !== "string");
        const result = await page.evaluate(() => {
          const list = [...document.querySelectorAll("#reorder > li")];
          return {
            order: list.map((e) => e.getAttribute("data-embedded-node-id")),
            kept: list.filter((e) => window.rowRefs.has(e.getAttribute("data-embedded-node-id"))).every((e) => window.rowRefs.get(e.getAttribute("data-embedded-node-id")) === e),
            text: document.getElementById("reorder").firstChild.nodeType === 3 ? document.getElementById("reorder").firstChild.data : null,
            moved: fixture.session.metrics.moved - window.movedBefore,
          };
        });
        assert.deepEqual(result.order, keys.map((k) => `row-${k}`), `${name}: ${JSON.stringify(result.order.slice(0, 8))}`);
        assert.ok(result.kept, `${name}: a surviving row was recreated`);
        if (typeof after[0] === "string") assert.equal(result.text, after[0], `${name}: ${result.text}`);
        const beforeSet = new Set(before);
        const common = keys.filter((k) => beforeSet.has(k));
        const position = new Map(before.filter((r) => typeof r !== "string").map((r, i) => [r, i]));
        const allowed = common.length - lis(common.map((k) => position.get(k)));
        assert.ok(result.moved <= allowed, `${name}: moved ${result.moved} rows, at most ${allowed} needed`);
      }
      await page.evaluate(() => { fixture.state.reorder = null; fixture.render(); fixture.session.flush(); });
    });

    await check("a worker snapshot older than the field never takes typed text back; the caught-up one wins", async () => {
      // A worker publishes snapshots that reflect older keystrokes than the field shows. They must not take
      // the newer text back; the snapshot that reflects the last keystroke wins, even when Swift changed it.
      await page.evaluate(() => { fixture.state.text = ""; fixture.render(); fixture.session.flush(); });
      const field = page.locator("#text");
      await field.fill("");
      await field.click();
      await page.evaluate(() => { fixture.state.lagReflected = fixture.stats.calls || 0; fixture.state.lagText = "h"; });
      await page.keyboard.type("hello", { delay: 10 });
      for (let index = 0; index < 3; index++) await page.evaluate(() => { fixture.render(); fixture.session.flush(); });
      assert.equal(await field.inputValue(), "hello", await field.inputValue());
      await page.evaluate(() => { fixture.state.lagReflected = undefined; fixture.state.lagText = undefined; fixture.state.text = "HELLO"; fixture.render(); fixture.session.flush(); });
      assert.equal(await field.inputValue(), "HELLO", await field.inputValue());
      await page.evaluate(() => { fixture.state.text = "Taylor"; fixture.render(); fixture.session.flush(); });
      assert.equal(await field.inputValue(), "Taylor", await field.inputValue());
    });

    await check("a commit that finds the publication it already committed does not decode it again", async () => {
      // A commit scheduled by an event often runs before the worker's publication arrives: the buffer it
      // finds is the one already committed, so it must not be decoded again; a new publication must be.
      await page.evaluate(() => { fixture.render(); fixture.session.flush(); });
      const before = await page.evaluate("fixture.stats.pointerReads");
      for (let index = 0; index < 3; index++) await flush();
      assert.equal(await page.evaluate("fixture.stats.pointerReads"), before, "an already committed publication was read again");
      await page.evaluate(() => { fixture.state.count++; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.evaluate("fixture.stats.pointerReads"), before + 1, "a new publication must be read");
      assert.equal(await text("#count"), String(await page.evaluate("fixture.state.count")));
    });

    await check("controlled disclosure closes repeatedly and native details retain only native state", async () => {
      const open = (selector) => evalOn(selector, (el) => el.open);
      for (let index = 0; index < 12; index++) {
        await page.locator("#controlled summary span").click(); await flush(); assert.ok(!(await open("#controlled")));
        await page.locator("#controlled summary").click(); await flush(); assert.ok(await open("#controlled"));
      }
      await page.locator("#b7").click(); await flush(); assert.ok(await open("#controlled"));
      await page.locator("#native summary").click(); assert.ok(await open("#native"));
      await page.locator("#b1").click(); await flush(); assert.ok(await open("#native"));
      await page.locator("#native summary").click(); assert.ok(!(await open("#native")));
      await page.locator("#b1").click(); await flush(); assert.ok(!(await open("#native")));
    });

    await check("continuous pointer drag crosses multiple animation frames without replacing range", async () => {
      await page.locator("#range").scrollIntoViewIfNeeded();
      const before = await page.evaluate("fixture.stats.inputs");
      const box = await page.locator("#range").boundingBox();
      const x = box.x, y = box.y + box.height / 2;
      await page.mouse.move(x + box.width * 0.2, y);
      await page.mouse.down();
      for (let index = 3; index < 10; index++) {
        await page.mouse.move(x + (box.width * index) / 10, y, { steps: 3 });
        await page.waitForTimeout(35);
      }
      await page.mouse.up();
      await flush();
      assert.ok((await page.evaluate("fixture.stats.inputs")) - before >= 6);
      assert.ok(Number.parseInt(await text("#progress"), 10) >= 85);
      assert.ok(await page.evaluate('inputRef===document.getElementById("range")'));
      await page.locator("#b1").click();
      await flush();
      assert.ok(Number.parseInt(await page.locator("#range").inputValue(), 10) >= 85);
    });

    await check("select, checked, Unicode, focus, selection and IME round trips", async () => {
      await page.locator("#select").selectOption("WASI"); await flush(); assert.equal(await page.evaluate("fixture.state.selected"), "WASI");
      await page.locator("#check").uncheck(); await flush(); assert.ok(!(await page.evaluate("fixture.state.check")));
      await page.locator("#check").check(); await flush(); assert.ok(await page.evaluate("fixture.state.check"));
      await page.locator("#text").fill("Olá 日本 🦊"); await flush(); assert.equal(await page.locator("#textarea").inputValue(), "Olá 日本 🦊");
      await evalOn("#text", (el) => { el.focus(); el.setSelectionRange(2, 5); });
      await page.evaluate("fixture.state.count++;fixture.render();fixture.session.flush()");
      assert.ok(await evalOn("#text", (el) => el === document.activeElement && el.selectionStart === 2 && el.selectionEnd === 5));
      await evalOn("#text", (el) => el.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true })));
      await evalOn("#text", (el) => { el.value = "編集中"; el.dispatchEvent(new InputEvent("input", { bubbles: true, isComposing: true })); });
      await page.evaluate("fixture.state.count++;fixture.render();fixture.session.flush()");
      assert.equal(await page.locator("#text").inputValue(), "編集中");
      await evalOn("#text", (el) => el.dispatchEvent(new CompositionEvent("compositionend", { bubbles: true })));
      await flush();
      assert.equal(await page.evaluate("fixture.state.text"), "編集中");
    });

    const named = async (name) => (await page.evaluate("fixture.stats.namedDispatches")).filter((d) => d.name === name);
    await check("onKeyPress walks from the focused view outward and .handled prevents the default", async () => {
      await page.evaluate("window.__keyEvents=[];window.addEventListener('keydown',e=>window.__keyEvents.push(e),true)");
      // One call per press, at the focused view, naming the enclosing handler; the handlers run inner first until one handles it.
      const runs = async () => page.evaluate("fixture.stats.keyPressRuns.length");
      const ranSince = async (from) => (await page.evaluate("fixture.stats.keyPressRuns")).slice(from);
      let before = (await named("keyPress")).length, ran = await runs();
      await page.locator("#kp-inner").focus();
      await page.keyboard.press("ArrowDown");
      const calls = (await named("keyPress")).slice(before);
      assert.deepEqual(calls.map((c) => c.id), [31, 31], JSON.stringify(calls));
      assert.deepEqual(calls.map((c) => c.value.split("\t").slice(0, 2).concat(c.value.split("\t")[3]).join(" ")), ["down ArrowDown 30", "up ArrowDown 30"], JSON.stringify(calls));
      assert.deepEqual(await ranSince(ran), [31, 31]); // the focused view handles both phases, so its ancestor never sees them
      before = (await named("keyPress")).length; ran = await runs(); await page.keyboard.press("x");
      assert.deepEqual((await named("keyPress")).slice(before).map((c) => c.id), [31, 31]);
      assert.deepEqual(await ranSince(ran), [31, 30, 31, 30]); // ignored inner propagates to the ancestor
      before = (await named("keyPress")).length; ran = await runs(); await page.keyboard.press("z");
      assert.deepEqual((await named("keyPress")).slice(before).map((c) => c.id), [31, 31]);
      assert.deepEqual(await ranSince(ran), [31, 30, 31, 30]);
      before = (await named("keyPress")).length; await page.keyboard.press("Shift");
      assert.equal((await named("keyPress")).length, before, "modifier-only keys are not key presses");
      const prevented = await page.evaluate("window.__keyEvents.map(e=>e.key+':'+e.defaultPrevented)");
      assert.deepEqual(prevented, ["ArrowDown:true", "x:true", "z:false", "Shift:false"]);
    });
    await check("a focused text field keeps the keys that edit its text from the views around it", async () => {
      // As in SwiftUI: a shell's single-letter shortcut (`onKeyPress` on an ancestor) does not fire while someone types.
      const field = page.locator("#kp-field");
      await field.fill("");
      await field.focus();
      let before = (await named("keyPress")).length;
      await page.keyboard.type("xn");
      await page.keyboard.press("Backspace");
      assert.equal((await named("keyPress")).length, before, "a key that edits the field reached an enclosing onKeyPress");
      assert.equal(await field.inputValue(), "x", "the field did not receive its keys");
      before = (await named("keyPress")).length;
      await page.keyboard.press("Escape");
      assert.deepEqual((await named("keyPress")).slice(before).map((c) => c.id), [30, 30], "Escape did not go outward from the field");
      // A field's own onKeyPress still sees the keys that edit it, and only it does.
      const own = page.locator("#kp-field-own");
      await own.focus();
      before = (await named("keyPress")).length;
      await page.keyboard.press("y");
      const calls = (await named("keyPress")).slice(before);
      assert.deepEqual(calls.map((c) => c.id), [33, 33], JSON.stringify(calls));
      assert.ok(calls.every((c) => c.value.split("\t").length === 3), `the field's press named enclosing handlers: ${JSON.stringify(calls)}`);
    });
    await check("keys pressed with focus on the page body reach the outermost keyDown owner", async () => {
      await page.evaluate("document.activeElement?.blur?.()");
      assert.ok(await page.evaluate("document.activeElement===document.body"));
      let before = (await named("keyDown")).length;
      await page.keyboard.press("Meta+k"); await page.keyboard.press("Escape");
      const calls = (await named("keyDown")).slice(before); // body keys reach the outermost keyDown owner (the modifier press included, like inside the app)
      assert.deepEqual(calls.map((c) => [c.id, c.value]), [[90, "MetaLeft,0,0,1,0,0,0"], [90, "KeyK,0,0,1,0,0,0"], [90, "Escape,0,0,0,0,0,0"]], JSON.stringify(calls));
      await page.locator("#kd-shell").focus(); before = (await named("keyDown")).length; await page.keyboard.press("Escape");
      assert.deepEqual((await named("keyDown")).slice(before).map((c) => c.id), [90], "a focused owner dispatches once, not twice");
    });
    await check("keyboardShortcut matches exact modifiers, skips disabled controls and clicks the control", async () => {
      const mod = (await page.evaluate("/Mac|iPhone|iPad/.test(navigator.platform)")) ? "Meta" : "Control";
      await page.locator("#count").click();
      const before = Number.parseInt(await text("#count"), 10);
      await page.keyboard.press(mod + "+k"); await flush();
      assert.equal(Number.parseInt(await text("#count"), 10), before + 1);
      await page.keyboard.press("k"); await page.keyboard.press(mod + "+Shift+k"); await page.keyboard.press(mod + "+j"); await flush();
      assert.equal(Number.parseInt(await text("#count"), 10), before + 1, "wrong modifiers and disabled controls never fire");
      await page.locator("#text").focus(); await page.keyboard.press(mod + "+k"); await flush();
      assert.equal(Number.parseInt(await text("#count"), 10), before + 2, "command shortcuts fire from text fields");
    });
    await check("ButtonStyle isPressed follows pointer hold, leave/re-enter and Space", async () => {
      const button = page.locator("#press");
      await button.scrollIntoViewIfNeeded();
      const box = await button.boundingBox();
      const pressed = async () => (await named("pressed")).map((d) => [d.name, d.value]);
      let before = (await pressed()).length;
      await page.mouse.move(box.x + 5, box.y + box.height / 2); await page.mouse.down();
      await page.mouse.move(box.x + box.width + 40, box.y + box.height / 2);
      await page.mouse.move(box.x + 5, box.y + box.height / 2); await page.mouse.up();
      assert.deepEqual((await pressed()).slice(before), [["pressed", "true"], ["pressed", "false"], ["pressed", "true"], ["pressed", "false"]]);
      before = (await pressed()).length; await button.focus(); await page.keyboard.down(" "); await page.keyboard.up(" ");
      assert.deepEqual((await pressed()).slice(before), [["pressed", "true"], ["pressed", "false"]]);
    });
    await check("a mouse drag over a DragGesture view selects no text, and other text stays selectable", async () => {
      const drag = async (selector) => {
        const element = page.locator(selector);
        await element.scrollIntoViewIfNeeded();
        await page.evaluate(() => getSelection().removeAllRanges());
        const box = await element.boundingBox();
        await page.mouse.move(box.x + 4, box.y + box.height / 2); await page.mouse.down();
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 4 });
        await page.mouse.move(box.x + box.width - 4, box.y + box.height / 2, { steps: 4 }); await page.mouse.up();
        return page.evaluate(() => getSelection().toString());
      };
      assert.equal(await drag("#drag-card"), "", "the carousel card's title is not selected");
      assert.notEqual(await drag("#plain-text"), "", "text without a drag gesture is selected as before");
      await page.evaluate(() => getSelection().removeAllRanges());
    });
    await check("a vertical scroll view off its top carries data-scrolled, and a render keeps it", async () => {
      const view = page.locator("#scroll-edge");
      await view.scrollIntoViewIfNeeded();
      const marked = () => view.evaluate((e) => e.hasAttribute("data-scrolled"));
      assert.equal(await marked(), false, "at its top it is not marked");
      await view.evaluate((e) => { e.scrollTop = 120; });
      await page.waitForFunction(() => document.querySelector("#scroll-edge").hasAttribute("data-scrolled"));
      const text = () => view.evaluate((e) => e.textContent);
      const before = await text();
      await page.evaluate(() => { fixture.state.count++; fixture.render(); fixture.session.flush(); });
      assert.notEqual(await text(), before, "the render reached the view");
      assert.equal(await marked(), true, "a render from Swift does not remove the host's mark");
      await view.evaluate((e) => { e.scrollTop = 0; });
      await page.waitForFunction(() => !document.querySelector("#scroll-edge").hasAttribute("data-scrolled"));
    });
    await check("a click on a Button inside a view with a DragGesture reaches the button, and a drag still reaches the gesture", async () => {
      const clicks = () => page.evaluate(() => fixture.stats.dispatches.filter((d) => d.id === 96).length);
      const button = page.locator("#drag-chrome-button");
      await button.scrollIntoViewIfNeeded();
      const before = await clicks();
      await button.click();
      assert.equal(await clicks(), before + 1, "the button acts, as it does under a SwiftUI drag gesture");
      const box = await page.locator("#drag-chrome").boundingBox();
      await page.mouse.move(box.x + 20, box.y + box.height / 2); await page.mouse.down();
      await page.mouse.move(box.x + 20, box.y + box.height / 2 + 120, { steps: 6 }); await page.mouse.up();
      assert.ok(await page.evaluate(() => fixture.stats.namedDispatches.some((d) => d.id === 95 && d.name === "drag-ended")), "the drag reaches the gesture");
    });
    await check("onHover pointer enter/leave, grouped activation, and touch has no hover phase", async () => {
      const row = page.locator("#hover-row");
      await row.scrollIntoViewIfNeeded();
      const box = await row.boundingBox();
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      assert.equal(await page.locator("#hover-peer").getAttribute("data-hover-group-active"), "true");
      assert.deepEqual(await page.evaluate("fixture.stats.namedDispatches.slice(-1)[0]"), { id: 16, name: "mouseenter", value: "true" });
      await page.mouse.move(box.x + 3, box.y + 3);
      assert.equal(await page.locator("#hover-peer").getAttribute("data-hover-group-active"), "true");
      await page.mouse.move(5, 5);
      assert.equal(await page.locator("#hover-peer").getAttribute("data-hover-group-active"), null);
      assert.deepEqual(await page.evaluate("fixture.stats.namedDispatches.slice(-1)[0]"), { id: 16, name: "mouseleave", value: "false" });
      const before = await page.evaluate("fixture.stats.namedDispatches.length");
      await row.evaluate((el) => el.dispatchEvent(new PointerEvent("pointerover", { bubbles: true, pointerType: "touch" })));
      assert.equal(await page.evaluate("fixture.stats.namedDispatches.length"), before);
    });
    await check("Nested onHover: entering or leaving through the inner view reaches the outer one too", async () => {
      await page.mouse.move(5, 5);
      const inner = page.locator("#hover-inner");
      await inner.scrollIntoViewIfNeeded();
      const box = await inner.boundingBox();
      const outer = await page.locator("#hover-outer").boundingBox();
      const has = (list, event) => list.some((d) => JSON.stringify(d) === JSON.stringify(event));
      let before = await page.evaluate("fixture.stats.namedDispatches.length");
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      const entered = await page.evaluate(`fixture.stats.namedDispatches.slice(${before})`);
      assert.ok(has(entered, { id: 92, name: "mouseenter", value: "true" }) && has(entered, { id: 91, name: "mouseenter", value: "true" }), JSON.stringify(entered));
      before = await page.evaluate("fixture.stats.namedDispatches.length");
      await page.mouse.move(outer.x + 5, outer.y + 5);
      const moved = await page.evaluate(`fixture.stats.namedDispatches.slice(${before})`);
      assert.deepEqual(moved, [{ id: 92, name: "mouseleave", value: "false" }]);
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      before = await page.evaluate("fixture.stats.namedDispatches.length");
      await page.mouse.move(5, 5);
      const left = await page.evaluate(`fixture.stats.namedDispatches.slice(${before})`);
      assert.ok(has(left, { id: 92, name: "mouseleave", value: "false" }) && has(left, { id: 91, name: "mouseleave", value: "false" }), JSON.stringify(left));
    });
    await check("onHover ignores a leave the pointer did not make (redraw under a still pointer)", async () => {
      const inner = page.locator("#hover-inner");
      const box = await inner.boundingBox();
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      const before = await page.evaluate("fixture.stats.namedDispatches.length");
      // A redraw under a still pointer reports a leave towards nothing.
      await inner.evaluate((el) => el.dispatchEvent(new PointerEvent("pointerout", { bubbles: true, pointerType: "mouse", relatedTarget: null })));
      assert.deepEqual(await page.evaluate(`fixture.stats.namedDispatches.slice(${before})`), [], "no leave while the pointer is still over the view");
      await page.mouse.move(5, 5);
    });
    await check("30 alternating navigation commits, fresh callbacks and keyboard tabs", async () => {
      for (let i = 0; i < 30; i++) {
        await page.locator(i % 2 === 0 ? "#b3" : "#b2").click(); await flush();
        const expected = i % 2 === 0 ? 1 : 0;
        assert.equal(await text("#page h1"), `Page ${expected}`);
        await page.locator("#b" + String(100 + expected)).click(); await flush();
      }
      assert.equal(await page.evaluate("fixture.stats.invalid"), 0);
      assert.ok(await page.evaluate("rootRef===fixture.session.root"));
      await page.locator("#tab0").focus(); await page.keyboard.press("ArrowRight"); await flush();
      assert.equal(await page.locator("#tab1").getAttribute("aria-selected"), "true");
      assert.ok(await evalOn("#tab1", (el) => el === document.activeElement));
    });
    await check("looping, triggered, CSS motion persists and reduced-motion stops runs", async () => {
      const width = (selector) => evalOn(selector, (el) => Number.parseFloat(getComputedStyle(el).width));
      await page.evaluate('window.phaseAnimation=document.getElementById("phase").getAnimations()[0]');
      const first = await page.evaluate("phaseAnimation.currentTime");
      await page.waitForTimeout(90);
      await page.locator("#b1").click(); await flush(); await page.waitForTimeout(50);
      assert.ok(await page.evaluate(`phaseAnimation===document.getElementById("phase").getAnimations()[0] && phaseAnimation.currentTime>=${first} && phaseAnimation.playState==="running"`));
      await page.locator("#b4").click(); await flush(); await page.waitForTimeout(180);
      const w = await width("#timing");
      assert.ok(w > 75 && w < 195, String(w));
      await page.locator("#b1").click(); await flush(); await page.waitForTimeout(600);
      assert.equal(await width("#timing"), 200);
      await page.locator("#b5").click(); await flush(); assert.equal(await evalOn("#keyframe", (el) => el.getAnimations().length), 1);
      await page.evaluate('window.kf=document.getElementById("keyframe").getAnimations()[0]');
      await page.waitForTimeout(40); await page.locator("#b1").click(); await flush();
      assert.ok(await page.evaluate('kf===document.getElementById("keyframe").getAnimations()[0]'));
      await page.locator("#b5").click(); await flush(); assert.ok(await page.evaluate('kf!==document.getElementById("keyframe").getAnimations()[0]'));
      await page.evaluate("fixture.transaction();fixture.repeat()"); await page.waitForTimeout(160);
      for (const selector of ["#transaction", "#repeating"]) {
        const value = await width(selector);
        assert.ok(value > 75 && value < 195, `${selector} ${value}`);
      }
      await page.evaluate('window.repeatAnimation=document.getElementById("repeating").getAnimations()[0]');
      await page.locator("#b1").click(); await flush();
      assert.ok(await page.evaluate('repeatAnimation===document.getElementById("repeating").getAnimations()[0]'));
      await page.evaluate("fixture.removePhase()");
      assert.equal(await page.evaluate("phaseAnimation.playState"), "idle");
      await page.emulateMedia({ reducedMotion: "reduce" }); await page.waitForTimeout(40);
      assert.equal(await evalOn("#keyframe", (el) => el.getAnimations().length), 0);
      assert.equal(await evalOn("#repeating", (el) => el.getAnimations().length), 0,
        JSON.stringify(await evalOn("#repeating", (el) => ({
          matches: matchMedia("(prefers-reduced-motion: reduce)").matches, transition: getComputedStyle(el).transition,
          animations: el.getAnimations().map((a) => ({ type: a.constructor.name, state: a.playState, time: a.currentTime, timing: a.effect.getTiming() })),
        }))));
    });
    await check(".animation(_:value:) animates the commit whose value changed, lets it finish, then snaps", async () => {
      const width = () => evalOn("#valued", (el) => Number.parseFloat(getComputedStyle(el).width));
      // The check before leaves reduced motion on; it is restored at the end.
      await page.emulateMedia({ reducedMotion: "no-preference" });
      await page.evaluate("fixture.valued(200,false)");
      assert.equal(await width(), 200, "the first width a value never changed for is written at once");
      await page.evaluate("fixture.valued(70,true)"); await page.waitForTimeout(160);
      const first = await width();
      assert.ok(first > 75 && first < 195, `the value changed and the width eases: ${first}`);
      // A commit with the same value before the animation ends leaves it running.
      await page.evaluate("fixture.valued(70,false)"); await page.waitForTimeout(160);
      const second = await width();
      assert.ok(second < first && second > 70, `the running animation goes on: ${first} -> ${second}`);
      await page.waitForTimeout(500);
      assert.equal(await width(), 70);
      assert.equal(await evalOn("#valued", (el) => el.style.transition), "", "the host lets the transition go once it ran");
      await page.evaluate("fixture.valued(200,false)");
      assert.equal(await width(), 200, "a later change with the same value snaps");
      assert.equal(await evalOn("#valued", (el) => el.getAnimations().length), 0);
      await page.emulateMedia({ reducedMotion: "reduce" });
    });
    await check("SecureField hydration is skipped when no secure ids are published and falls back without the export", async () => {
      // Swift publishes the SecureField ids with every publication; with none, the host must not
      // scan the DOM for them on each commit. Without the export it cannot know and scans.
      await page.evaluate(() => {
        window.__secureScans = 0;
        const scan = Element.prototype.querySelectorAll;
        Element.prototype.querySelectorAll = function (selector) { if (selector === "[data-keep-secure-id]") window.__secureScans++; return scan.call(this, selector); };
        window.__restoreScan = () => { Element.prototype.querySelectorAll = scan; };
      });
      try {
        for (let index = 0; index < 3; index++) await flush();
        await page.evaluate("fixture.render();fixture.session.flush()");
        assert.equal(await page.evaluate("window.__secureScans"), 0, "no secure fields published, yet the DOM was scanned");
        await page.evaluate("fixture.state.secureField=true;fixture.render();fixture.session.flush()");
        assert.ok((await page.evaluate("window.__secureScans")) >= 1);
        assert.equal(await page.locator("#secure").inputValue(), "s3cret", "a published SecureField was not hydrated");
        assert.ok(await page.evaluate("fixture.api.embedded_browser_secure_ids_length ? true : false"));
        await page.evaluate(() => {
          fixture.state.secureField = false; fixture.render(); fixture.session.flush();
          window.__secureIdsExport = fixture.api.embedded_browser_secure_ids_length;
          delete fixture.api.embedded_browser_secure_ids_length; fixture.session = fixture.mount(); window.__secureScans = 0;
        });
        await page.evaluate("fixture.render();fixture.session.flush()");
        assert.ok((await page.evaluate("window.__secureScans")) >= 1, "a build without secure_ids_length must fall back to scanning");
        await page.evaluate(() => {
          fixture.api.embedded_browser_secure_ids_length = window.__secureIdsExport;
          fixture.state.secureField = true; fixture.session = fixture.mount(); fixture.render(); fixture.session.flush();
        });
        assert.equal(await page.locator("#secure").inputValue(), "s3cret");
        await page.evaluate("fixture.state.secureField=false;fixture.render();fixture.session.flush()");
      } finally {
        await page.evaluate("window.__restoreScan?.()");
      }
    });
    await check("a worker snapshot older than the typed secret never writes it back into a SecureField", async () => {
      // The published secret is stale until a snapshot reflects the last input. Writing it back mid-edit undid
      // the text, and a fill that had just selected the old text then inserted after the stale copy ("abcabc").
      await page.evaluate("fixture.state.secureField=true;fixture.render();fixture.session.flush()");
      const field = page.locator("#secure");
      assert.equal(await field.inputValue(), "s3cret");
      await page.evaluate(() => { fixture.state.lagReflected = fixture.stats.calls || 0; });
      await field.fill("abc");
      for (let index = 0; index < 3; index++) await page.evaluate(() => { fixture.render(); fixture.session.flush(); });
      assert.equal(await field.inputValue(), "abc", "a stale published secret replaced the typed one");
      assert.equal(await page.evaluate(() => fixture.stats.dispatches.at(-1).value), "abc");
      await page.evaluate(() => { fixture.state.lagReflected = undefined; fixture.render(); fixture.session.flush(); });
      assert.equal(await field.inputValue(), "s3cret", "the caught-up snapshot (Swift is authoritative) was not applied");
      await page.evaluate("fixture.state.secureField=false;fixture.render();fixture.session.flush()");
    });
    await check("document head elements follow the visible screens and give the static head back", async () => {
      const publish = (heads) => page.evaluate((value) => { fixture.state.heads = value; fixture.render(); fixture.session.flush(); }, heads);
      const link = (rel, href, extra = {}) => ({ tag: "link", attrs: { rel, href, ...extra } });
      const meta = (name, content, extra = {}) => ({ tag: "meta", attrs: { name, content, ...extra } });
      const headState = () => page.evaluate(() => [...document.head.querySelectorAll("meta[name=robots],meta[name=theme-color],link[rel=icon],script[data-x]")]
        .map((node) => node.localName + ":" + (node.getAttribute("rel") || node.getAttribute("name")) + "=" + (node.getAttribute("href") ?? node.getAttribute("content")) + "@" + (node.getAttribute("media") || "") + (node.hasAttribute("onload") ? "!" : "")));
      await page.evaluate(() => {
        document.head.insertAdjacentHTML("beforeend", '<link rel="icon" href="/static.ico"><meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)"><meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)"><meta name="robots" content="all">');
      });
      const baseline = await headState();
      assert.deepEqual(baseline, ["link:icon=/static.ico@", "meta:theme-color=#ffffff@(prefers-color-scheme: light)", "meta:theme-color=#000000@(prefers-color-scheme: dark)", "meta:robots=all@"]);

      // A screen overrides the icon and one theme-color variant; the other variant and nothing else is displaced.
      await publish([{ entries: [link("icon", "/alert.png"), meta("robots", "noindex"), meta("theme-color", "#121118", { media: "(prefers-color-scheme: dark)" })] }]);
      assert.deepEqual((await headState()).sort(), ["link:icon=/alert.png@", "meta:robots=noindex@", "meta:theme-color=#121118@(prefers-color-scheme: dark)", "meta:theme-color=#ffffff@(prefers-color-scheme: light)"].sort());

      // The later (inner) screen wins a shared key and keeps the other screen's elements; a hidden screen does not count.
      await publish([{ entries: [link("icon", "/alert.png"), meta("robots", "noindex")] }, { entries: [meta("robots", "index,follow")] }]);
      assert.ok((await headState()).includes("meta:robots=index,follow@") && (await headState()).includes("link:icon=/alert.png@"));
      await publish([{ entries: [link("icon", "/alert.png"), meta("robots", "noindex")] }, { entries: [meta("robots", "index,follow")], hidden: true }]);
      assert.ok((await headState()).includes("meta:robots=noindex@") && !(await headState()).includes("meta:robots=index,follow@"));

      // The same key updates in place instead of adding another element.
      await publish([{ entries: [link("icon", "/second.png")] }]);
      assert.equal(await page.evaluate(() => document.head.querySelectorAll("link[rel=icon]").length), 1);
      assert.ok((await headState()).includes("link:icon=/second.png@"));

      // Only <meta> and <link> with the allowed attributes get through, and bad payloads are ignored.
      await publish([{ entries: [{ tag: "script", attrs: { src: "/x.js", "data-x": "1" } }, { tag: "meta", attrs: { name: "robots", content: "noarchive", onload: "alert(1)", "http-equiv": "refresh" } }, null, { tag: "meta" }, { tag: "meta", attrs: { content: "no identity" } }] }, { raw: "not json" }, { raw: "{}" }]);
      const filtered = await headState();
      assert.ok(filtered.includes("meta:robots=noarchive@") && !filtered.some((entry) => entry.startsWith("script") || entry.endsWith("!")), filtered.join(" | "));
      assert.equal(await page.evaluate(() => document.head.querySelector("meta[name=robots]").hasAttribute("http-equiv")), false);

      // Leaving every screen puts the page's own head back where it was.
      await publish(null);
      assert.deepEqual(await headState(), baseline);
      assert.equal(await page.evaluate(() => document.head.querySelectorAll("[data-document-head]").length), 0);
      await page.evaluate(() => { for (const node of document.head.querySelectorAll("link[rel=icon],meta[name=theme-color],meta[name=robots]")) node.remove(); });
    });

    await check("a tab a click selected stays selected when a publication rewrites the tab buttons", async () => {
      await page.evaluate(() => { fixture.state.panelTabs = { selected: "a", builtC: true, rev: 0 }; fixture.render(); fixture.session.flush(); });
      const selected = () => page.evaluate(() => ["a", "b", "c"].filter((v) => document.getElementById("pt-" + v).getAttribute("aria-selected") === "true").join(","));
      const shown = () => page.evaluate(() => ["a", "b", "c"].filter((v) => document.getElementById("pp-" + v).getAttribute("data-tab-hidden") === "false").join(","));
      await page.locator("#pt-b").click();
      assert.equal(await selected(), "b", "the click selects the tab at once");
      // Swift still names "a" but its markup differs, so the publication writes the buttons' selection back onto the page.
      for (const rev of [1, 2]) {
        await page.evaluate((r) => { fixture.state.panelTabs = { selected: "a", builtC: true, rev: r }; fixture.render(); fixture.session.flush(); }, rev);
        assert.equal(await selected(), "b", "the publication does not take the clicked tab back");
        assert.equal(await shown(), "b", "the clicked panel stays on screen");
      }
      await page.evaluate(() => { fixture.state.panelTabs = null; fixture.render(); fixture.session.flush(); });
    });

    await check("the document title follows the visible navigation title and gives the page's own back when hidden", async () => {
      const base = await page.title();
      await page.evaluate(() => { fixture.state.navigationTitle = "Inbox"; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.title(), "Inbox");
      await page.evaluate(() => { fixture.state.navigationTitle = "Outbox"; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.title(), "Outbox", "a changed title follows");
      await page.evaluate(() => { fixture.state.titleHidden = true; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.title(), base, "a hidden screen gives the page its own title back");
      await page.evaluate(() => { fixture.state.titleHidden = false; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.title(), "Outbox", "the screen shows again");
      await page.evaluate(() => { fixture.state.navigationTitle = ""; fixture.state.titleHidden = false; fixture.render(); fixture.session.flush(); });
      assert.equal(await page.title(), base, "without a title the page keeps its own");
    });

    await check("a resize and a color-scheme change reach the platform report and the document theme", async () => {
      await page.setViewportSize({ width: 820, height: 700 });
      await page.waitForFunction("fixture.stats.viewports.some((v) => v[0] === 820)");
      await page.emulateMedia({ colorScheme: "dark" });
      await page.waitForFunction('document.documentElement.getAttribute("data-color-scheme") === "dark"');
      assert.equal((await page.evaluate("fixture.stats.viewports")).at(-1)[2], 1, "the report carries the dark scheme");
      const reports = await page.evaluate("fixture.stats.viewports.length");
      await page.evaluate("fixture.state.tick++;fixture.render();fixture.session.flush()");
      assert.equal(await page.evaluate("fixture.stats.viewports.length"), reports, "an unchanged viewport is not reported again");
      assert.equal(await page.evaluate('document.documentElement.getAttribute("data-color-scheme")'), "dark", "a commit keeps the theme");
      await page.emulateMedia({ colorScheme: "light" });
      await page.waitForFunction('document.documentElement.getAttribute("data-color-scheme") === "light"');
      assert.equal((await page.evaluate("fixture.stats.viewports")).at(-1)[2], 0, "the report follows the light scheme");
      await page.setViewportSize({ width: 1100, height: 900 });
      await page.waitForFunction("fixture.stats.viewports.at(-1)[0] !== 820");
    });

    await check("a SecureField value reaches the field through a publication that changes no markup", async () => {
      await page.evaluate("fixture.state.secureField=true;fixture.render();fixture.session.flush()");
      await page.waitForFunction('document.getElementById("secure")?.value === "s3cret"');
      await page.evaluate('document.getElementById("secure").value = ""');
      await page.evaluate("fixture.render();fixture.session.flush()");
      assert.equal(await page.evaluate('document.getElementById("secure").value'), "s3cret");
      await page.evaluate("fixture.state.secureField=false;fixture.render();fixture.session.flush()");
    });

    await check("memory growth refreshes UTF8 view, remount does not duplicate listeners, disposal detaches", async () => {
      await page.evaluate("fixture.grow()");
      assert.equal(await page.locator("#text").inputValue(), "編集中");
      assert.equal(await page.evaluate("fixture.stats.byteReads"), 0);
      const listeners = await page.evaluate("fixture.session.metrics.listeners");
      await page.evaluate("window.oldSession=fixture.session;fixture.session=fixture.mount()");
      let before = await page.evaluate("fixture.state.count");
      await page.locator("#b1").click(); await flush();
      assert.equal(await page.evaluate("fixture.state.count"), before + 1);
      assert.equal(await page.evaluate("fixture.session.metrics.listeners"), listeners);
      await page.evaluate("fixture.session.dispose()");
      before = await page.evaluate("fixture.state.count");
      await page.locator("#b1").click();
      assert.equal(await page.evaluate("fixture.state.count"), before);
    });
    await page.evaluate("fixture.session.dispose()");
    for (const route of heldImageRoutes) {
      try { await route.abort(); } catch { /* the page may already be gone */ }
    }
    await browser.close();
    browser = undefined;
    const report = { status: "PASS", scope: "Production JS host in Chromium with synthetic ABI producer; not full Showcase WASM", tests: results, page_errors: errors };
    mkdirSync(dirname(output), { recursive: true });
    writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
    console.log(JSON.stringify(report, null, 2));
  } catch (error) {
    writeFileSync(output, JSON.stringify({ status: "FAIL", tests: results, page_errors: errors, reason: String(error?.message ?? error) }, null, 2) + "\n");
    throw error;
  } finally {
    await browser?.close();
  }
});
