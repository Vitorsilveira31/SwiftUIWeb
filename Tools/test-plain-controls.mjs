#!/usr/bin/env bun
// Under `.buttonStyle(.plain)` a Button and a NavigationLink draw their label in the font and foreground style around
// them, as SwiftUI's plain style (a list of rows mixing links and a "Sign out" button read in two colours and two
// sizes). A destructive plain button is red text, not a red fill. A plain link with a declared shape highlights under the
// pointer as a plain button does.
//   bun Tools/test-plain-controls.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const html = `<div style="color: rgb(10, 20, 30); font-size: 19px; font-weight: 600; display: grid; gap: 30px; padding: 20px">
  <button id="button" class="push-button button-plain control-regular" data-button-style="plain">Sair</button>
  <a id="link" class="navigation-link" data-button-style="plain" data-visible-shape="true" href="#">Editar</a>
  <a id="tinted" class="navigation-link" href="#">Ver tudo</a>
  <button id="destructive" class="push-button button-plain control-regular" data-button-style="plain" data-role="destructive">Excluir</button>
</div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 400 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    const look = id => page.evaluate(name => {
      const style = getComputedStyle(document.getElementById(name));
      return { color: style.color, size: style.fontSize, weight: style.fontWeight, background: style.backgroundColor };
    }, id);
    const inherited = { color: "rgb(10, 20, 30)", size: "19px", weight: "600" };
    const button = await look("button");
    assert.deepEqual({ color: button.color, size: button.size, weight: button.weight }, inherited, "a plain button inherits");
    const link = await look("link");
    assert.deepEqual({ color: link.color, size: link.size, weight: link.weight }, inherited, "a plain link inherits");
    assert.notEqual((await look("tinted")).color, "rgb(10, 20, 30)", "a link without the plain style keeps the tint");
    const destructive = await look("destructive");
    assert.equal(destructive.background, "rgba(0, 0, 0, 0)", "a destructive plain button has no fill");
    assert.notEqual(destructive.color, "rgb(10, 20, 30)", "a destructive plain button is drawn in the destructive colour");
    await page.hover("#link");
    assert.notEqual((await look("link")).background, "rgba(0, 0, 0, 0)", "a plain link with a shape highlights under the pointer");
    console.log("PASS plain buttons and links keep the look around them");
  } finally {
    await browser.close();
  }
});
