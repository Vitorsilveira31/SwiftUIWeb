#!/usr/bin/env bun
// Renders the Showcase's `/stackDepth` fixture at increasing view depths and requires them to render in the Worker.
//
// WebKit gives a Worker's WebAssembly a far shallower call stack than its main thread. Rendering is staged: once the
// render recursion is a few levels deep, a container (a stack, a scroll view, a list, a grid) hands its children to the
// loop that drives the pass, and an erased view boundary hands its content over and returns a node that stands in for it,
// which is what lets a chain of modifiers, conditionals or containers of any kind be as deep as the layout engine allows.
// Every walk over the resulting tree (reconcile, publish, serialization) is a loop too, so the depth a view hierarchy can
// have no longer depends on the stack. Four things are required:
// - every padded depth up to 1000 renders, in the Worker, without the stack overflow that used to restart the app on the
//   main thread, and without any error; so does the unpadded variant (`plain-N`);
// - so do trees nested through modifiers only (`chain-N`, `mods-N`), conditionals (`if-N`), `HStack`s, `ScrollView`s,
//   `List`s, `Grid`s and a mix of them (`mix-N`), up to 1000 levels where it renders in reasonable time. The layout solver
//   no longer recurses per level, so the depth of a layout tree is bounded by memory, not by a stack.
// - so do the ones that used to need their node at once: `onChange` (`eager-N`), preference writers and readers (`pref-N`),
//   presentation (`sheet-N`) and navigation (`nav-N`) modifiers, `.animation` (`anim-N`), a `ViewModifier` with its own
//   `body` (`custom-mod-N`), a mix of all of them (`forcing-N`), and `Form`, `Section`, `DisclosureGroup`, `GroupBox`,
//   `LabeledContent` and `Menu` nested in themselves (`form-N`, `section-N`, `disclosure-N`, `groupbox-N`, `labeled-N`,
//   `menu-N`), and a modifier on a `Group` (`group-N`, `groups-N`): their callbacks are ordered by position, their content is
//   built where it renders and a modifier waits for the children of a group, so none of them makes the render recurse per level.
// - so do the ones that gather what their content registered: a `Picker` (its options), a `TabView` (its tabs, and the
//   `tag`s under it), a `NavigationStack` (toolbars, destinations) and an `EquatableView`, each nested in itself
//   (`picker-N`, `tabview-in-tabview-N`, `tabview-nested-N`, `nav-nested-N`, `equatable-N`) and all of them in turn (`combo-N`):
//   they return a node that stands in for them and finish in stages, the containers inside one before it.
// - staging changes nothing it computes: a few Showcase routes come out with the same text and the same element structure
//   with staging off (`?render-stage=0`) and with the most aggressive staging (`?render-stage=1`).
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default). Bundle: STACK_DEPTH_BUNDLE (.build/browser/ShowcaseApp).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.STACK_DEPTH_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"));
const PORT = Number(process.env.STACK_DEPTH_PORT ?? "8113");
const REQUIRED = 1000;

// [button, depth, expected]: "renders" must show the leaf with no error.
const CASES = [
  ...[20, 40, 60, 80, 100, 120, 200, 300, 500, 1000].map((d) => [`depth-${d}`, d, "renders"]),
  ...[100, 150, 200, 250, 1000].map((d) => [`plain-${d}`, d, "renders"]),
  ...[
    ["chain", 150], ["chain", 300], ["chain", 1000], ["mods", 300], ["mods", 1000], ["if", 300], ["if", 1000],
    ["hstack", 120], ["hstack", 240], ["hstack", 500], ["hstack", 1000],
    ["scroll", 100], ["scroll", 300], ["list", 80], ["list", 200], ["grid", 100], ["grid", 300], ["mix", 250], ["mix", 1000],
    // Modifiers that need their node in the order of the pass, and containers that look at their content. An
    // identity path is a chain that shares its prefix, so a level costs the same at any depth (it was a copy of the
    // whole path, and the 1000-level `nav` and `forcing` took 12 and 25 s).
    ["eager", 150], ["eager", 300], ["eager", 1000], ["pref", 300], ["pref", 1000], ["sheet", 300], ["sheet", 1000],
    ["nav", 300], ["nav", 1000], ["anim", 300], ["anim", 1000], ["custom-mod", 300], ["custom-mod", 1000],
    ["forcing", 300], ["forcing", 1000],
    ["form", 300], ["form", 1000], ["section", 300], ["section", 1000], ["disclosure", 300], ["disclosure", 1000],
    ["groupbox", 300], ["groupbox", 1000], ["labeled", 300], ["labeled", 1000], ["menu", 300], ["menu", 1000],
    ["group", 150], ["group", 300], ["groups", 150], ["groups", 300],
    // Containers that gather what their content registered once it has rendered: they build in stages, innermost
    // first, from the loop that drives the pass.
    ["picker", 300], ["picker", 1000], ["tabview-in-tabview", 60], ["tabview-in-tabview", 90],
    ["tabview-in-tabview", 300], ["tabview-in-tabview", 1000], ["tabview-nested", 300],
    ["tabview-nested", 1000], ["nav-nested", 300], ["nav-nested", 1000], ["equatable", 300], ["equatable", 1000],
    ["combo", 300], ["combo", 1000],
    // Mounting a very large tree: the thousands of levels, and the thousands of siblings, of one commit.
    ["wide", 1000], ["wide", 10000], ["wide-form", 1000], ["wide-form", 5000], ["wide-list", 1000],
  ].map(([name, d]) => [`${name}-${d}`, d, "renders"]),
  ...[2000, 5000, 8000].map((d) => [`depth-${d}`, d, "renders"]),
  ["plain-5000", 5000, "renders"],
];

// A mount that took longer than this (seconds, click to the leaf on screen) has a quadratic cost again: padded 5000 levels
// took 41 s before the identity paths and the HTML for a deep tree were made linear, and 2 to 4 s since. The limit is for
// a machine under load, not a target.
const MOUNT_LIMITS = {
  "depth-5000": 12, "plain-5000": 8, "depth-8000": 20, "wide-10000": 15, "nav-1000": 5, "forcing-1000": 6,
  "chain-1000": 3, "mods-1000": 3, "labeled-1000": 3,
};

await runSuite(async () => {
  const only = new Set((process.env.STACK_DEPTH_ONLY ?? "").split(",").filter(Boolean));
  const server = await serveBundle({ bundle: BUNDLE, port: PORT, logName: "stack-depth-server" });
  const base = server.base;
  let browser;
  try {
    browser = await launch();
    const engine = engineName();
    for (const [button, depth, expected] of CASES) {
      if (only.size && !only.has(button)) continue;
      if (process.env.STACK_DEPTH_VERBOSE) console.log(button);
      const page = await browser.newPage();
      const errors = [];
      page.on("console", (message) => {
        if (message.type() === "error") errors.push(message.text());
      });
      page.on("pageerror", (error) => errors.push(String(error)));
      await page.goto(`${base}/stackDepth`, { waitUntil: "domcontentloaded" });
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
      const workerBefore = await page.evaluate("window.__embeddedSession.worker");
      // The probe buttons sit in a horizontal strip far wider than the viewport. WebKit hit-tests a
      // scroller that was just scrolled with its old offset for a few frames, so a pointer click that
      // Playwright aims at a button it scrolled into view can land on the strip itself (a plain page with
      // the same strip loses it too, see test-click-after-mount-browser.mjs). The DOM `click` event is what
      // the app answers, and test-click-after-mount-browser.mjs covers real pointer and key input.
      const started = Date.now();
      await page.locator(`[data-testid="${button}"]`).dispatchEvent("click");
      await page.waitForFunction(
        `document.querySelector('[data-testid="depth-value"]')?.textContent?.trim() === 'depth ${depth}'` +
          ` && document.querySelector('[data-testid="depth-leaf"]')`,
        undefined,
        { timeout: 90_000, polling: 50 },
      );
      const elapsed = (Date.now() - started) / 1000;
      await page.waitForTimeout(400);
      const leaf = await page.locator('[data-testid="depth-leaf"]').count();
      const workerAfter = await page.evaluate("window.__embeddedSession.worker");
      const nested =
        button.startsWith("depth-") || button.startsWith("plain-")
          ? await page.evaluate(() => {
              const leafElement = document.querySelector('[data-testid="depth-leaf"]');
              let d = 0;
              for (let e = leafElement; e; e = e.parentElement) d++;
              return d;
            })
          : 0;
      await page.close();
      if (Object.hasOwn(MOUNT_LIMITS, button)) {
        console.log(`${button}: ${elapsed.toFixed(2)} s`);
        assert.ok(
          elapsed < MOUNT_LIMITS[button],
          `${button} took ${elapsed.toFixed(1)} s to mount in ${engine}, over ${MOUNT_LIMITS[button]} s`,
        );
      }
      // The HTML writes no deeper nesting than a parser builds: the rest of a deep tree follows as siblings, so
      // the leaf of a 5000-level tree sits about as deep as the 512-level limit of the parsers (the tree is the
      // same one they used to build themselves, but Chromium needed seconds to parse it).
      assert.ok(nested <= 520, `${button}: the leaf is ${nested} levels deep, more than a parser nests`);
      const stack = errors.filter((e) => e.includes("call stack") || e.includes("too much recursion"));
      assert.ok(
        stack.length === 0,
        `${button} overflowed the call stack in ${engine}: ${JSON.stringify(stack.slice(0, 2))}`,
      );
      assert.equal(
        workerAfter,
        workerBefore,
        `${button}: the app moved from the Worker to the main thread in ${engine} (${workerBefore} -> ${workerAfter})`,
      );
      assert.ok(
        leaf === 1 && errors.length === 0,
        `a view tree ${depth} levels deep (${button}) did not render in ${engine}: ${JSON.stringify(errors.slice(0, 2))}`,
      );
    }
    // Staging must not change what a screen is: compare the most staged render with the plain one.
    for (const route of ["components", "layout", "collections", "navigation"]) {
      const shapes = [];
      for (const stage of [0, 1]) {
        const page = await browser.newPage();
        await page.goto(`${base}/${route}?render-stage=${stage}`, { waitUntil: "domcontentloaded" });
        await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
        await page.waitForTimeout(800);
        shapes.push(
          await page.evaluate(() => {
            const root = document.querySelector("#embedded-app-root") || document.body;
            return {
              text: root.innerText,
              structure: [...root.querySelectorAll("*")]
                .map((e) => e.tagName + "." + (e.getAttribute("class") || ""))
                .join(" "),
            };
          }),
        );
        await page.close();
      }
      assert.equal(shapes[0].text, shapes[1].text, `/${route}: the text differs with staging`);
      assert.equal(shapes[0].structure, shapes[1].structure, `/${route}: the element structure differs with staging`);
    }
  } finally {
    await browser?.close();
    await server.stop();
  }
  console.log(
    `PASS ${engineName()} renders view trees up to ${REQUIRED} levels (1000 unpadded too) without a stack overflow`,
  );
});
