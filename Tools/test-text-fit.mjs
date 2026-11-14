#!/usr/bin/env bun
// A Text is as wide as the lines it draws, as SwiftUI sizes it (Tools/css-layout.js `fitTexts`): a truncated one as what it
// shows and the ellipsis, so the lower-priority text beside it takes the rest (`layoutPriority`); a wrapped one as its
// longest line, so a VStack centres the lines; a text that fits keeps no cap; a cap is lifted when the text is offered more.
//   bun Tools/test-text-fit.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const mapper = readFileSync(join(ROOT, "Tools/css-layout.js"), "utf8").replace(/^export /gm, "");
const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const oneLine = "display:block;-webkit-line-clamp:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;";
const text = (id, value, style = "", extra = "") =>
  `<span id="${id}" data-layout-kind="intrinsic" data-layout-leaf="text" ${extra} style="font:17px sans-serif;${style}">${value}</span>`;
const html = `<div id="embedded-app-root"><div id="app" data-layout-kind="vstack" data-layout-gap="10" data-align-x="0.5">
  <div id="row-frame" data-layout-kind="frame" data-frame-w="190" data-frame-h="50" data-align-x="0.5" data-align-y="0.5">
    <div id="row" class="hstack" data-layout-kind="hstack" data-layout-gap="0">${text("high", "HIGH PRIORITY CONTENT", oneLine, 'data-layout-priority="1"')}${text("low", "lower priority content", oneLine)}</div>
  </div>
  <div id="column-frame" data-layout-kind="frame" data-frame-w="140" data-align-x="0.5" data-align-y="0.5">
    <div id="column" class="vstack" data-layout-kind="vstack" data-layout-gap="0" data-align-x="0.5">${text("wrapped", "Lines that wrap in a narrow column")}${text("short", "Fits")}</div>
  </div>
  <div id="shrink-frame" data-layout-kind="frame" data-frame-w="120" data-align-x="0.5" data-align-y="0.5">${text("shrink", "SHRINK ME PLEASE", oneLine, 'data-minimum-scale-factor="0.5"')}</div>
</div></div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 600, height: 400 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    await page.addScriptTag({ content: mapper + "\nwindow.CssLayout = CssLayout;" });
    const box = (id) => page.evaluate((id) => { const r = document.getElementById(id).getBoundingClientRect(); return { x: r.x, w: r.width }; }, id);
    const lines = (id) => page.evaluate((id) => {
      const range = document.createRange(); range.selectNodeContents(document.getElementById(id));
      const byTop = new Map();
      for (const r of range.getClientRects()) { const t = Math.round(r.top); const l = byTop.get(t); byTop.set(t, l ? [Math.min(l[0], r.left), Math.max(l[1], r.right)] : [r.left, r.right]); }
      return [...byTop.values()].map(([left, right]) => ({ left, width: right - left }));
    }, id);
    await page.evaluate(() => {
      const css = (window.css = new CssLayout(document));
      if (!css.claimRoot(document.getElementById("app"), { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" })) throw new Error("not claimed");
      css.flush();
    });

    // Before: CSS gives the higher-priority text the whole row and the other nothing.
    assert.equal((await box("high")).w, 190, "without the measure the box is what CSS offers");
    await page.evaluate(() => window.css.fitTexts());

    const high = await box("high"), low = await box("low"), row = await box("row");
    assert.ok(high.w < 190 && high.w > 150, `the cut text is as wide as what it shows and the ellipsis: ${high.w}`);
    assert.ok(Math.abs(high.w + low.w - row.w) < 0.5 && low.w > 0, `the lower-priority text takes the rest: ${high.w} + ${low.w}`);
    assert.equal(await page.evaluate(() => getComputedStyle(document.getElementById("high")).textOverflow), "ellipsis");

    const wrapped = await box("wrapped"), drawn = await lines("wrapped"), column = await box("column");
    assert.ok(drawn.length > 1, "the long text wraps");
    const longest = Math.max(...drawn.map((l) => l.width));
    assert.ok(Math.abs(wrapped.w - longest) < 0.5, `a wrapped text is as wide as its longest line: ${wrapped.w} vs ${longest}`);
    assert.ok(Math.abs(wrapped.x + wrapped.w / 2 - (column.x + column.w / 2)) < 0.5, "the VStack centres the narrower text");
    assert.equal(await lines("wrapped").then((l) => l.length), drawn.length, "capping the box keeps the line breaks");
    assert.equal(await page.evaluate(() => document.getElementById("short").hasAttribute("data-text-fit")), false, "a text that fits keeps no cap");

    // Offered more, a text is measured again from that: the row grows and the whole of the first text fits.
    await page.evaluate(() => {
      const frame = document.getElementById("row-frame");
      frame.setAttribute("data-frame-w", "500");
      window.css.mark(frame, document.getElementById("app")); window.css.pending.add(document.getElementById("app"));
      window.css.flush(); window.css.fitTexts();
    });
    const wide = await page.evaluate(() => { const e = document.getElementById("high"); return { w: e.getBoundingClientRect().width, capped: e.hasAttribute("data-text-fit"), cut: e.scrollWidth > e.clientWidth + 0.5 }; });
    assert.equal(wide.cut, false, "offered more, the text is not cut any more");
    assert.equal(wide.capped, false, "and it carries no cap");

    // minimumScaleFactor: a text cut in its frame is drawn smaller, on one line, and not below the factor's share.
    const shrunk = await page.evaluate(() => {
      const e = document.getElementById("shrink");
      return { size: parseFloat(getComputedStyle(e).fontSize), cut: e.scrollWidth > e.clientWidth + 0.5, lines: e.getClientRects().length };
    });
    assert.ok(shrunk.size < 17 && shrunk.size >= 17 * 0.5, `the text shrinks to fit, not below its factor: ${shrunk.size}`);
    assert.equal(shrunk.cut, false, "the shrunk text is not cut");
    // A state update that turns the shrink off (the factor 1) or makes the text more than one line restores the size Swift set.
    const sizeAfter = async (change) => page.evaluate((change) => {
      const e = document.getElementById("shrink");
      new Function("e", change)(e);
      window.css.fitTexts();
      return parseFloat(getComputedStyle(e).fontSize);
    }, change);
    assert.equal(await sizeAfter("e.setAttribute('data-minimum-scale-factor', '1')"), 17, "a factor of 1 restores the font size");
    assert.ok(await sizeAfter("e.setAttribute('data-minimum-scale-factor', '0.5')") < 17, "a factor below 1 shrinks it again");
    assert.equal(await sizeAfter("e.style.whiteSpace = 'normal'"), 17, "a text that is no longer one line restores the font size");
    console.log("text fit: OK");
  } finally {
    await browser.close();
  }
});
