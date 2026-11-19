#!/usr/bin/env bun
// A Link and a NavigationLink keep their look under the pointer, as in SwiftUI: neither underlines its label (a poster or
// a card behind a NavigationLink underlined its titles on hover). An underline the app asks for still shows:
// `.buttonStyle(.link)` underlines on hover.
//   bun Tools/test-link-hover.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const html = `<a id="navigation" class="navigation-link" href="#"><span data-layout-leaf="text">Entre Luzes</span></a>
<a id="anchor" class="anchor-link" href="#"><span data-layout-leaf="text">Termos de Uso</span></a>
<button id="link-style" class="push-button button-link">Ver mais</button>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0;display:grid;gap:40px;padding:20px">${html}</body>`);
    const decorationUnderPointer = async id => {
      await page.hover(`#${id}`);
      return page.evaluate(name => {
        const element = document.getElementById(name);
        const label = element.querySelector("span") ?? element;
        return [getComputedStyle(element).textDecorationLine, getComputedStyle(label).textDecorationLine];
      }, id);
    };
    assert.deepEqual(await decorationUnderPointer("navigation"), ["none", "none"], "a NavigationLink does not underline on hover");
    assert.deepEqual(await decorationUnderPointer("anchor"), ["none", "none"], "a Link does not underline on hover");
    assert.equal((await decorationUnderPointer("link-style"))[0], "underline", ".buttonStyle(.link) still underlines");
    console.log("PASS links keep their look under the pointer");
  } finally {
    await browser.close();
  }
});
