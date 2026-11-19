#!/usr/bin/env bun
// A NavigationStack lays its screen out below the bar (the screen's safe area) and draws the bar over it, as iOS does: a
// view that ignores the safe area and fills the top of the screen (a reader's paper, `.ignoresSafeArea()`) runs under the
// bar to the top of the stack, while the rest of the screen still starts below the bar. A view that does not reach the top,
// one that keeps its own height, one inside a scroll view and one under a hidden bar stay where they are.
//   bun Tools/test-navigation-under-bar.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const mapper = readFileSync(join(ROOT, "Tools/css-layout.js"), "utf8").replace(/^export /gm, "");
const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const text = (id, value) => `<span id="${id}" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">${value}</span>`;
const paper = (id, extra = "") => `<div id="${id}" data-layout-kind="flexible" data-ignores-safe-area="true" style="background:rgb(250, 244, 230)" ${extra}></div>`;
const back = '<div id="back" class="toolbar-item" data-toolbar-placement="navigation-bar-leading"><button aria-label="Back" style="width:44px;height:44px">‹</button></div>';
const stack = (screen, attributes = 'data-navigation-title="" data-navigation-title-display-mode="automatic"') => `<div id="nav-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf">
  <main id="stack" class="navigation-stack" data-navigation-depth="1" ${attributes}>${back}
    <div class="navigation-root" aria-hidden="true">${text("root-text", "Root")}</div>
    <div id="screen" class="navigation-destination" data-navigation-depth="1">${screen}</div></main></div>`;
// ZStack { paper.ignoresSafeArea(); VStack { header; Spacer } }: the reader of a novel.
const reader = `<div id="reader" class="zstack" data-layout-kind="zstack">${paper("paper")}
  <div id="column" class="vstack" data-layout-kind="vstack" data-layout-gap="0">${text("header", "Chapter 1 of 9")}<div class="flex-spacer" data-layout-kind="spacer"></div></div></div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 402, height: 874 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0"></body>`);
    await page.addScriptTag({ content: mapper + "\nwindow.CssLayout = CssLayout;" });
    /** Lays `markup` out as the layout host does (`claimRoot`, `flush`, then the measured steps) and returns the boxes. */
    const lay = (markup, ids) => page.evaluate(({ markup, ids }) => {
      document.body.innerHTML = markup;
      document.adoptedStyleSheets = [];
      const css = (window.css = new CssLayout(document));
      const ok = css.claimRoot(document.getElementById("nav-app"), { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" });
      css.flush(); css.fitTexts(); css.extendUnderBars?.();
      const stack = document.getElementById("stack").getBoundingClientRect();
      const box = (id) => { const r = document.getElementById(id).getBoundingClientRect(); return [r.x - stack.x, r.y - stack.y, r.width, r.height].map(Math.round); };
      const bar = Math.round(parseFloat(getComputedStyle(document.getElementById("stack")).gridTemplateRows) || 0);
      return { ok, bar, boxes: Object.fromEntries(ids.map((id) => [id, box(id)])) };
    }, { markup, ids });
    const again = (ids) => page.evaluate((ids) => {
      window.css.flush(); window.css.fitTexts(); window.css.extendUnderBars?.();
      const stack = document.getElementById("stack").getBoundingClientRect();
      return Object.fromEntries(ids.map((id) => { const r = document.getElementById(id).getBoundingClientRect(); return [id, [r.x - stack.x, r.y - stack.y, r.width, r.height].map(Math.round)]; }));
    }, ids);

    const under = await lay(stack(reader), ["paper", "column", "header", "screen"]);
    assert.equal(under.ok, true, "the stack is CSS's");
    assert.ok(under.bar >= 44, `the bar row holds the back button (${under.bar})`);
    assert.deepEqual(under.boxes.screen.slice(1), [under.bar, 402, 874 - under.bar], "the screen is laid out below the bar (its safe area)");
    assert.deepEqual(under.boxes.paper, [0, 0, 402, 874], "a view that ignores the safe area runs under the bar to the top of the stack");
    assert.deepEqual([under.boxes.column[1], under.boxes.column[3]], [under.bar, 874 - under.bar], "the views beside it keep the safe area");
    assert.equal(under.boxes.header[1], under.bar, "and the content starts below the bar");
    const drawn = await page.evaluate(() => {
      const back = document.getElementById("back").getBoundingClientRect();
      return { back: document.elementFromPoint(back.x + back.width / 2, back.y + back.height / 2)?.closest("#back") !== null, bar: document.elementFromPoint(200, 10)?.id };
    });
    assert.equal(drawn.back, true, "the back button is drawn over the view under the bar");
    assert.equal(drawn.bar, "stack", "and so is the bar");
    assert.deepEqual(await again(["paper", "column"]), { paper: [0, 0, 402, 874], column: under.boxes.column }, "a second pass keeps the view where it is");

    // The bar's height follows the bar: a large title makes it taller, and the view still reaches the top.
    await page.evaluate(() => { const s = document.getElementById("stack"); s.setAttribute("data-navigation-title", "Chapter"); s.setAttribute("data-navigation-title-display-mode", "large"); });
    const taller = await page.evaluate(() => Math.round(parseFloat(getComputedStyle(document.getElementById("stack")).gridTemplateRows) || 0));
    assert.ok(taller > under.bar, `a large title makes the bar taller (${taller})`);
    assert.deepEqual((await again(["paper"])).paper, [0, 0, 402, 874], "the view grows with the bar");

    // A hidden bar takes no room, and a view that grew under it is back in the flow.
    await page.evaluate(() => { const s = document.getElementById("stack"); s.setAttribute("data-navigation-bar-hidden", "true"); document.getElementById("back").remove(); });
    const hidden = await again(["paper", "column"]);
    assert.deepEqual([hidden.paper, hidden.column[1], hidden.column[3]], [[0, 0, 402, 874], 0, 874], "under a hidden bar the screen starts at the top");
    assert.equal(await page.evaluate(() => document.getElementById("paper").hasAttribute("data-cl-under-bar")), false, "and nothing is marked under a bar");

    // An ordinary screen starts below the bar.
    const plain = await lay(stack(`<div class="scroll-view scroll-vertical" data-layout-kind="scroll" data-scroll-axes="vertical">${text("first", "First")}</div>`), ["first"]);
    assert.equal(plain.boxes.first[1], plain.bar, "a screen without such a view starts below the bar");

    // A view that does not reach the top of the screen, one of its own height and one inside a scroll view stay put.
    const below = await lay(stack(`<div id="column" class="vstack" data-layout-kind="vstack" data-layout-gap="0">${text("title", "Title")}${paper("low")}</div>`), ["title", "low"]);
    assert.equal(below.boxes.low[1], below.boxes.title[1] + below.boxes.title[3], "a view below another one does not reach the bar");
    const rigid = await lay(stack(`<div data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-y="0"><div id="badge" data-layout-kind="size" data-size-w="100" data-size-h="40" data-ignores-safe-area="true"></div></div>`), ["badge"]);
    assert.equal(rigid.boxes.badge[1], rigid.bar, "a view that keeps its own height stays below the bar");
    const scrolled = await lay(stack(`<div class="scroll-view scroll-vertical" data-layout-kind="scroll" data-scroll-axes="vertical">${paper("inside", 'data-frame-h="300"')}</div>`), ["inside"]);
    assert.equal(scrolled.boxes.inside[1], scrolled.bar, "a view inside a scroll view stays in it");

    // A background that ignores the safe area (a layer of the view it backs) runs under the bar too.
    const backed = await lay(stack(`<div id="content" class="backdrop-layer" data-layout-kind="background">${paper("behind")}<div id="fill" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf">${text("label", "Label")}</div></div>`), ["behind", "fill", "label"]);
    assert.deepEqual(backed.boxes.behind, [0, 0, 402, 874], "a background layer runs under the bar");
    assert.deepEqual(backed.boxes.fill.slice(1), [backed.bar, 402, 874 - backed.bar], "the view it backs keeps the safe area");
    console.log("PASS a view that ignores the safe area runs under the navigation bar; the screen keeps its safe area below it");
  } finally {
    await browser.close();
  }
});
