#!/usr/bin/env bun
// A VideoPlayer under `.allowsHitTesting(false)` shows no AVKit controls, as on iOS: the controls answer a touch, and the
// view takes none. An app that draws its own transport over the video (a player screen) relied on its own CSS for it.
//   bun Tools/test-avkit-hit-testing.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const player = (id, attributes = "") =>
  `<div id="${id}" class="avkit-video-player avkit-responsive" ${attributes}><video class="avkit-media"></video><div class="avkit-controls" data-ctl-hidden="0"><div class="avkit-bar">bar</div></div></div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    await page.setContent(`<style>${styles}</style><body>
      ${player("touchable")}
      ${player("inert", 'data-allows-hit-testing="false" style="pointer-events:none"')}
      <div data-allows-hit-testing="false" style="pointer-events:none">${player("inside-inert")}</div>
    </body>`);
    const shown = (id) => page.evaluate((id) => getComputedStyle(document.querySelector(`#${id} > .avkit-controls`)).display !== "none", id);
    assert.equal(await shown("touchable"), true, "a player that takes touches shows its controls");
    assert.equal(await shown("inert"), false, "a player with allowsHitTesting(false) shows none");
    assert.equal(await shown("inside-inert"), false, "a player inside a container with allowsHitTesting(false) shows none");
    console.log("PASS a VideoPlayer that takes no touches shows no controls");
  } finally {
    await browser.close();
  }
});
