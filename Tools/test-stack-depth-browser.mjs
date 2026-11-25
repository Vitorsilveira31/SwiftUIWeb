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

// The cost of a mount must grow with the size of the tree. Padded 5000 levels took 41 s before the identity paths and the HTML
// for a deep tree were made linear, and the 1000-level `nav` and `forcing` took 12 and 25 s: a quadratic cost, which grows with
// the square of the size on any machine. A time limit says how fast the machine is as much as how the cost grows (the
// 8 s one for `plain-5000` in WebKit failed at 8.7 s on a machine running other builds: the mount takes 3.6 s on a quiet one and
// 7.2 to 8.3 s with ten browsers and 24 busy loops beside it), so each large mount is compared with a smaller one of the same
// kind, mounted alternately with it three times in fresh pages, each side keeping its fastest mount: load that hits the whole
// measurement slows both and cancels, and a spike that hits one mount does not decide it. [small, large, largest ratio of the
// large mount's time to the small one's]. Measured, in WebKit on a quiet machine (load average 6), in WebKit loaded (19 to 82)
// and in Chromium quiet: depth 5000/1000 4.0, 5.1 and 4.6; depth 8000/1000 6.5, 8.4 and 7.7; wide 10000/1000 5.0, 6.2 and 4.0;
// nav, forcing, chain, mods and labeled 1000/300 at most 5.0, 4.5 and 5.3. A linear cost gives the size ratio, a quadratic one its
// square (25, 64, 100 and 11), so each limit is three times the size ratio: more than the 1.3 times by which load raised a
// ratio, less than the square. `plain` is the exception: WebKit lays out the 512 levels the HTML nests (the leaf of a
// deeper tree follows as siblings) for 3.1 s on the main thread whatever the size, so 5000/1000 is 1.15 there, quiet and loaded,
// and about 5 in Chromium.
const SCALING = [
  ["depth-1000", "depth-5000", 15], ["depth-1000", "depth-8000", 24],
  ["plain-1000", "plain-5000", { webkit: 3, chromium: 15 }],
  ["wide-1000", "wide-10000", 30],
  ["nav-300", "nav-1000", 10], ["forcing-300", "forcing-1000", 10], ["chain-300", "chain-1000", 10], ["mods-300", "mods-1000", 10],
  ["labeled-300", "labeled-1000", 10],
];
const SCALING_ROUNDS = 3;

/** Seconds from the click on `button` to its leaf on screen, in a fresh page. */
async function mountSeconds(browser, base, button) {
  const depth = Number(button.split("-").pop());
  const page = await browser.newPage();
  try {
    await page.goto(`${base}/stackDepth`, { waitUntil: "domcontentloaded" });
    await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
    const started = Date.now();
    await page.locator(`[data-testid="${button}"]`).dispatchEvent("click");
    await page.waitForFunction(
      `document.querySelector('[data-testid="depth-value"]')?.textContent?.trim() === 'depth ${depth}'` +
        ` && document.querySelector('[data-testid="depth-leaf"]')`,
      undefined,
      { timeout: 90_000, polling: 50 },
    );
    return (Date.now() - started) / 1000;
  } finally {
    await page.close();
  }
}

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
      await page.locator(`[data-testid="${button}"]`).dispatchEvent("click");
      await page.waitForFunction(
        `document.querySelector('[data-testid="depth-value"]')?.textContent?.trim() === 'depth ${depth}'` +
          ` && document.querySelector('[data-testid="depth-leaf"]')`,
        undefined,
        { timeout: 90_000, polling: 50 },
      );
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
    // The cost of a mount grows with the size of the tree, not with its square (see SCALING).
    for (const [small, large, limit] of SCALING) {
      if (only.size && !only.has(large)) continue;
      const seconds = { [small]: [], [large]: [] };
      for (let round = 0; round < SCALING_ROUNDS; round++) {
        seconds[small].push(await mountSeconds(browser, base, small));
        seconds[large].push(await mountSeconds(browser, base, large));
      }
      const fastest = { [small]: Math.min(...seconds[small]), [large]: Math.min(...seconds[large]) };
      const ratio = fastest[large] / fastest[small];
      const allowed = typeof limit === "number" ? limit : limit[engine];
      const sizes = Number(large.split("-").pop()) / Number(small.split("-").pop());
      console.log(`${large}: ${fastest[large].toFixed(2)} s, ${ratio.toFixed(1)} times ${small}'s ${fastest[small].toFixed(2)} s (limit ${allowed})`);
      assert.ok(
        ratio < allowed,
        `${large} took ${fastest[large].toFixed(2)} s to mount in ${engine}, ${ratio.toFixed(1)} times the ${fastest[small].toFixed(2)} s of ${small} ` +
          `(fastest of ${SCALING_ROUNDS}, mounted alternately; ${seconds[large].map((value) => value.toFixed(2))} against ${seconds[small].map((value) => value.toFixed(2))}), ` +
          `over ${allowed}: the sizes are ${sizes} times apart, and a quadratic cost would make it ${sizes * sizes}`,
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
