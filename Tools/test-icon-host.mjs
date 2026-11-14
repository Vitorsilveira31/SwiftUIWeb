#!/usr/bin/env bun
// Behavior of the generated icon-adapter.js against a real DOM: icons are realized for the first tree, for every
// later mutation (only the added nodes are visited), and when a data-symbol changes in place; unknown symbols fall back.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { launch } from "./browser-test-support.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const tmp = mkdtempSync(join(tmpdir(), "icon-host-"));
let browser;
try {
  const manifest = join(tmp, "manifest.json");
  const asset = join(tmp, "icon-adapter.js");
  // The symbols the Swipe Deck and Markdown Reader demos draw. Each must resolve to a glyph, or it draws as a dot.
  const demoSymbols = [
    "flame.fill", "briefcase.fill", "location.fill", "arrow.uturn.backward", "xmark", "star.fill", "heart.fill",
    "list.bullet", "chevron.left.forwardslash.chevron.right", "textformat.size", "doc.text",
  ];
  writeFileSync(manifest, JSON.stringify({ icons: { symbols: ["house", "lock", "book", ...demoSymbols], dynamic: false } }));
  execFileSync("bun", [join(root, "Tools/generate-icon-asset.js"), "--manifest", manifest, "--output", asset], { stdio: "pipe" });

  browser = await launch();
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.setContent("<!doctype html><html><body><div id='outside'><i data-symbol='house'></i></div></body></html>");
  await page.evaluate(() => {
    window.__visited = 0;
    const q = window.queueMicrotask.bind(window);
    window.queueMicrotask = (f) => q(() => { if (f.name === "apply") window.__visited++; f(); });
  });
  await page.addScriptTag({ content: readFileSync(asset, "utf8") });
  const result = await page.evaluate(async (DEMO_SYMBOLS) => {
    const tick = () => new Promise((r) => setTimeout(r, 30));
    const out = {};
    out.outsideBeforeRoot = !!document.querySelector("#outside svg");
    const appRoot = document.createElement("div");
    appRoot.id = "embedded-app-root";
    appRoot.innerHTML = '<span id="a" data-symbol="book"></span><div><span id="b" data-symbol="house"></span></div>';
    document.body.append(appRoot);
    await tick();
    out.initialTree = !!appRoot.querySelector("#a svg") && !!appRoot.querySelector("#b svg");
    const row = document.createElement("div");
    row.innerHTML = '<p><span id="c" data-symbol="lock"></span></p>';
    appRoot.append(row);
    await tick();
    out.addedLater = !!appRoot.querySelector("#c svg") && appRoot.querySelector("#c").getAttribute("data-lucide") === "lock";
    appRoot.querySelector("#a").setAttribute("data-symbol", "lock");
    await tick();
    out.changedInPlace = appRoot.querySelector("#a").getAttribute("data-lucide");
    const unknown = document.createElement("span");
    unknown.setAttribute("data-symbol", "no.such.symbol");
    appRoot.append(unknown);
    await tick();
    out.fallback = unknown.getAttribute("data-lucide-fallback");
    // A mutation outside the app root is not scanned once the root is observed.
    const stray = document.createElement("i");
    stray.setAttribute("data-symbol", "book");
    document.getElementById("outside").append(stray);
    await tick();
    out.outsideIgnored = !stray.querySelector("svg");
    // Re-adding an unchanged icon keeps its SVG (no rewrite).
    const svg = appRoot.querySelector("#b svg");
    appRoot.append(appRoot.querySelector("#b").parentElement);
    await tick();
    out.svgKept = appRoot.querySelector("#b svg") === svg;
    // The DOM patch realizes a node while it is detached: the SVG is there before the node is inserted, and the observer
    // that sees the insertion afterwards finds nothing left to write.
    const detached = document.createElement("div");
    detached.innerHTML = '<p><span id="d" data-symbol="book"></span><span id="e" data-symbol="no.such.symbol"></span></p>';
    window.__realizeIcons(detached);
    out.realizedDetached = !!detached.querySelector("#d svg") && detached.querySelector("#d").getAttribute("data-lucide") === "book-open" && detached.querySelector("#e").getAttribute("data-lucide-fallback") === "true";
    const detachedSvg = detached.querySelector("#d svg");
    appRoot.append(detached);
    await tick();
    out.insertedKept = appRoot.querySelector("#d svg") === detachedSvg;
    // An icon whose symbol changed to an unknown one drops the glyph's name.
    appRoot.querySelector("#d").setAttribute("data-symbol", "no.such.symbol");
    window.__realizeIcons(appRoot.querySelector("#d"));
    out.staleNameDropped = !appRoot.querySelector("#d").hasAttribute("data-lucide");
    // Every demo symbol draws its glyph (an unmapped one would fall back to the dot).
    const demo = document.createElement("div");
    demo.innerHTML = DEMO_SYMBOLS.map((symbol) => `<i data-symbol="${symbol}"></i>`).join("");
    window.__realizeIcons(demo);
    out.demoGlyphs = [...demo.querySelectorAll("i")].every((icon) => icon.querySelector("svg") && !icon.hasAttribute("data-lucide-fallback"));
    return out;
  }, demoSymbols);
  const expected = { outsideBeforeRoot: true, initialTree: true, addedLater: true, changedInPlace: "lock", fallback: "true", outsideIgnored: true, svgKept: true, realizedDetached: true, insertedKept: true, staleNameDropped: true, demoGlyphs: true };
  if (errors.length || JSON.stringify(result) !== JSON.stringify(expected)) {
    console.log("FAIL", JSON.stringify(result), errors);
    process.exitCode = 1;
  } else {
    console.log("PASS icon host: first tree, added nodes, in-place change, fallback, root-only observation");
  }
} finally {
  await browser?.close();
  rmSync(tmp, { recursive: true, force: true });
}
