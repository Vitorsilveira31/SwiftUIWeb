#!/usr/bin/env bun
// A NavigationLink and a Link (an `<a>`) are plain buttons as SwiftUI lays them out (Tools/css-layout.js `kindOf`): their
// label takes the proposal. A label that fills its row (`.frame(maxWidth: .infinity)`) beside a fixed 48-point button
// takes the rest of the row, as the primary button of a hero does on iOS; it hugged its text before, and a pill with a
// fixed height clipped it. A label that does not fill keeps its own width.
//   bun Tools/test-css-layout-links.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const mapper = readFileSync(join(ROOT, "Tools/css-layout.js"), "utf8").replace(/^export /gm, "");
const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const text = (value) => `<span data-layout-kind="intrinsic" data-layout-leaf="text" style="font:15px sans-serif">${value}</span>`;
const fill = (id, value) => `<div id="${id}" class="frame-box" data-layout-kind="frame" data-frame-max-w="inf" data-frame-h="48" data-align-x="0.5" data-align-y="0.5">${text(value)}</div>`;
const fixed = `<div class="frame-box" data-layout-kind="frame" data-frame-w="48" data-frame-h="48" data-align-x="0.5" data-align-y="0.5">${text("i")}</div>`;
const row = (id, link) => `<div id="${id}" class="hstack" data-layout-kind="hstack" data-layout-gap="10">${link}${fixed}</div>`;
const html = `<div id="embedded-app-root"><div id="app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0" data-align-y="0">
  <div class="vstack" data-layout-kind="vstack" data-layout-gap="0" data-align-x="0">
    ${row("navigation-row", `<a id="navigation" class="navigation-link" href="#" data-navigation-link="push" data-button-style="plain">${fill("navigation-label", "Continuar")}</a>`)}
    ${row("link-row", `<a id="link" class="anchor-link" href="https://example.com">${fill("link-label", "Abrir")}</a>`)}
    ${row("hug-row", `<a id="hug" class="navigation-link" href="#" data-navigation-link="push" data-button-style="plain">${text("Detalhes")}</a>`)}
  </div>
</div></div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1000, height: 700 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    await page.addScriptTag({ content: mapper + "\nwindow.CssLayout = CssLayout;" });
    const claimed = await page.evaluate(() => {
      const css = new CssLayout(document);
      const ok = css.claimRoot(document.getElementById("app"), { def: { x: true, y: true }, ax: 0, height: "100dvh", key: "window" });
      css.flush();
      return ok;
    });
    assert.equal(claimed, true, "a root of stacks, frames and links is CSS's");
    const width = (id) => page.evaluate((id) => Math.round(document.getElementById(id).getBoundingClientRect().width), id);
    assert.equal(await width("navigation"), 1000 - 10 - 48, "a NavigationLink whose label fills takes the rest of its row");
    assert.equal(await width("navigation-label"), 942, "and its label is as wide as the link");
    assert.equal(await width("link"), 942, "a Link whose label fills does too");
    const hug = await width("hug");
    assert.ok(hug > 0 && hug < 200, `a NavigationLink whose label does not fill keeps its own width (${hug})`);
    console.log("PASS a NavigationLink or a Link passes its proposal to its label, as a plain button does");
  } finally {
    await browser.close();
  }
});
