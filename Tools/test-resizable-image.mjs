#!/usr/bin/env bun
// A resizable image takes the frame it is offered, as SwiftUI's `resizable()`: a 4:3 picture in a 300 by 200 frame is
// 300 by 200, not 300 by 225 (it overflowed its frame and sat lower than the layers around it). `scaledToFit` keeps the
// picture's ratio inside the same box.
//   bun Tools/test-resizable-image.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
// A 4 by 3 PNG.
const png = "data:image/svg+xml;utf8," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="#c0f"/></svg>');
const html = `<div class="frame-box" data-frame-w="300.0" data-frame-h="200.0" style="display:grid;place-items:center;width:300px;height:200px">
  <img id="stretched" class="picture-view" data-resizable="true" src="${png}" width="400" height="300" style="object-fit: fill; aspect-ratio: 400 / 300">
</div>
<div class="frame-box" data-frame-w="300.0" data-frame-h="200.0" style="display:grid;place-items:center;width:300px;height:200px">
  <img id="fitted" class="picture-view" data-resizable="true" src="${png}" width="400" height="300" style="object-fit: contain; aspect-ratio: 400 / 300">
</div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 500 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    const box = id => page.evaluate(name => {
      const element = document.getElementById(name);
      const rect = element.getBoundingClientRect();
      return { width: Math.round(rect.width), height: Math.round(rect.height), fit: getComputedStyle(element).objectFit };
    }, id);
    assert.deepEqual(await box("stretched"), { width: 300, height: 200, fit: "fill" }, "a resizable image fills its frame");
    assert.deepEqual(await box("fitted"), { width: 300, height: 200, fit: "contain" }, "scaledToFit fits inside the same box");
    console.log("PASS a resizable image takes the frame it is offered");
  } finally {
    await browser.close();
  }
});
