#!/usr/bin/env bun
// A background or an overlay whose content is empty (`.background { if hovering { … } }` while not hovering, or
// `EmptyView()`) never changes the view it decorates, as in SwiftUI. The empty layer renders no element, so the
// wrapper's only child is the decorated view itself: it is both the first and the last child. The stylesheet's rules
// for the background layer (`contain: size`, no hit testing) must not reach it there: a card link in a horizontal
// LazyHStack collapsed to 0×0 and could not be clicked. The markup is what `StaticHTMLFiberRenderer` gives for
// `NavigationLink(value:) { Text(…).frame(width: 100, height: 50) }.buttonStyle(.plain).background { if flag { … } }`
// in a horizontal ScrollView.
//   bun Tools/test-empty-layer.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const css = readFileSync(join(ROOT, "Tools/css-layout.js"), "utf8").replace(/^export /gm, "");

const label = (id) => `<div class="frame-box passthrough" data-align-x="0.5" data-align-y="0.5" data-frame-alignment="center" data-frame-h="50.0" data-frame-w="100.0" data-layout-kind="frame" data-layout-schema="1" style="display: grid; height: 50px; place-items: center; width: 100px;">${id}</div>`;
const link = (id) => `<a id="${id}" class="navigation-link" data-button-style="plain" href="#${id}">${label(id)}</a>`;
const wrapper = (kind, body) => `<div id="${kind}-wrapper" class="${kind === "background" ? "backdrop-layer" : "overlay-layer"} passthrough" data-align-x="0.5" data-align-y="0.5" data-layout-kind="${kind}" data-layout-schema="1" style="display: grid; place-items: center;">${body}</div>`;
// The painted layer a background or an overlay holds when its content is shown (a 10×10 color, which the view's size
// must not follow either).
const layer = `<div class="shape-layer" style="width: 10px; height: 10px; background: red"></div>`;
const shelf = (cards) => `<div id="root" class="scroll-view scroll-horizontal" data-layout-kind="scroll" data-scroll-axes="1" data-scroll-node="true" style="width: 600px; height: 200px"><div class="hstack lazy-hstack passthrough" data-layout-alignment="center" data-layout-kind="hstack" data-lazy="horizontal" style="align-items: center;">${cards}</div></div>`;
const cards = [
  wrapper("background", link("empty-background")),
  wrapper("overlay", link("empty-overlay")),
  wrapper("background", layer + link("shown-background")),
  wrapper("overlay", link("shown-overlay") + layer),
].join("");

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 800, height: 400 } });
    for (const mode of ["stylesheet", "css layout"]) {
      await page.setContent(`<style>${styles}</style><body style="margin:0">${shelf(cards)}</body>`);
      if (mode === "css layout") {
        await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
        const claimed = await page.evaluate(() => {
          const mapper = new CssLayout(document), root = document.getElementById("root");
          if (!mapper.claim(root)) return false;
          mapper.flush();
          return true;
        });
        assert.ok(claimed, "the CSS layout takes the shelf");
      }
      const measured = await page.evaluate(() => Object.fromEntries(["empty-background", "empty-overlay", "shown-background", "shown-overlay"].map((id) => {
        const card = document.getElementById(id), r = card.getBoundingClientRect(), w = card.parentElement.getBoundingClientRect();
        const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
        return [id, { card: [r.width, r.height], wrapper: [w.width, w.height], hit: !!hit && card.contains(hit) }];
      })));
      for (const [id, m] of Object.entries(measured)) {
        assert.deepEqual(m.card, [100, 50], `${mode}: ${id}: the link keeps its label's size (${JSON.stringify(m)})`);
        assert.deepEqual(m.wrapper, [100, 50], `${mode}: ${id}: the wrapper is the size of the view it decorates (${JSON.stringify(m)})`);
        if (id !== "shown-overlay") assert.ok(m.hit, `${mode}: ${id}: a click on the card reaches the link (${JSON.stringify(m)})`);
      }
      console.log(`PASS ${mode}: an empty background or overlay leaves the decorated view's size and hit testing alone`);
    }
  } finally {
    await browser.close();
  }
});
