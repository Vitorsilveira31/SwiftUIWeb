#!/usr/bin/env bun
// A DOMViewRepresentable takes the frame it is offered, as a UIViewRepresentable without an intrinsic size does in SwiftUI:
// a component that draws 100 by 100 in its ShadowRoot, in a 200 by 200 frame, has a 200 by 200 host. The host stylesheet
// gives the host `width: 100%; height: 100%` (embedded-dom.js, `dom-view-host-sizing`); the CSS layout (Tools/css-layout.js)
// laid the host out as an intrinsic leaf instead, whose `width: auto` rule came later at the same specificity and won, so
// the host shrank to its content.
//   bun Tools/test-dom-view-frame.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const mapper = readFileSync(join(ROOT, "Tools/css-layout.js"), "utf8").replace(/^export /gm, "");
const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
// The rule embedded-dom.js adds to the page for every DOM view host.
const hostSizing = '[data-dom-view="true"]{width:100%!important;height:100%!important}';
const html = `<div id="embedded-app-root"><div id="root" class="vstack" data-layout-kind="vstack" data-layout-gap="8" data-align-x="0">
  <div id="frame" class="frame-box" data-layout-kind="frame" data-frame-w="200.0" data-frame-h="200.0" data-align-x="0.5" data-align-y="0.5">
    <div id="host" data-web-mount-key="dom-view-mount" data-dom-view="true"></div>
  </div>
  <div id="wide" class="frame-box" data-layout-kind="frame" data-frame-max-w="inf" data-frame-h="120.0" data-align-x="0.5" data-align-y="0.5">
    <div id="wide-host" data-web-mount-key="dom-view-mount" data-dom-view="true"></div>
  </div>
</div></div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 600, height: 500 } });
    await page.setContent(`<style>${styles}</style><style>${hostSizing}</style><body style="margin:0">${html}</body>`);
    await page.addScriptTag({ content: mapper + "\nwindow.CssLayout = CssLayout;" });
    const claimed = await page.evaluate(() => {
      // What a component draws: a 100 by 100 box in the host's own ShadowRoot.
      for (const id of ["host", "wide-host"]) {
        const box = document.createElement("div");
        box.style.cssText = "width:100px;height:100px";
        document.getElementById(id).attachShadow({ mode: "open" }).append(box);
      }
      const css = new CssLayout(document);
      const ok = css.claimRoot(document.getElementById("root"), { def: { x: true, y: true }, ax: 0, key: "window" });
      css.flush();
      return ok;
    });
    assert.equal(claimed, true, "a stack of frames around DOM views is CSS's");
    const size = (id) => page.evaluate((name) => {
      const rect = document.getElementById(name).getBoundingClientRect();
      return [Math.round(rect.width), Math.round(rect.height)];
    }, id);
    assert.deepEqual(await size("frame"), [200, 200], "the frame is 200 by 200");
    assert.deepEqual(await size("host"), [200, 200], "a DOM view takes its 200 by 200 frame, not its content's 100 by 100");
    assert.deepEqual(await size("wide-host"), [600, 120], "a DOM view takes a frame as wide as the window");
    console.log("PASS a DOMViewRepresentable takes the frame it is offered");
  } finally {
    await browser.close();
  }
});
