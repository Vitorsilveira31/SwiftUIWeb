#!/usr/bin/env bun
// A ZStack paints its children in order, the last on top, as SwiftUI does. CSS paints a positioned or transformed box
// (an `.offset`, a clipped frame) after in-flow ones, so without a stacking context per child an earlier offset layer
// covered the content after it (a sign-in form under its own background art).
//   bun Tools/test-zstack-paint-order.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const html = `<div class="zstack" style="width:300px;height:200px">
  <div id="art" style="width:300px;height:200px;background:#c0f;transform:translate(0px, 0px)"></div>
  <div id="clipped" style="width:300px;height:200px;background:#0cf;position:relative;overflow:hidden;opacity:.99"></div>
  <div id="content" style="width:300px;height:200px;background:#cf0"></div>
</div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    const top = await page.evaluate(() => document.elementFromPoint(150, 100)?.id);
    assert.equal(top, "content", "the last child of a ZStack is on top, above earlier offset or clipped layers");
    console.log("PASS a ZStack paints its children in order");
  } finally {
    await browser.close();
  }
});
