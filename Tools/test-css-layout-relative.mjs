#!/usr/bin/env bun
// A `containerRelativeFrame`'s length as CSS (`relativeLength` in Tools/css-layout.js) against the reference below, the
// function SwiftUI's frame computes: the piecewise-linear function through Swift's samples, sorted by container length,
// extended along the first and last segments, at least 0. Samples that decrease, bend, share a container length (a step,
// which holds the value below it) or arrive unsorted must give the reference's length at every container length.
//   bun Tools/test-css-layout-relative.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const mapper = readFileSync(join(ROOT, "Tools/css-layout.js"), "utf8").replace(/^export /gm, "");

// The reference length, for a container length.
const reference = (samples, length) => {
  const sorted = samples.map((p) => [...p]).sort((a, b) => a[0] - b[0]);
  if (sorted.length === 1) return Math.max(0, sorted[0][1]);
  let i = sorted.findIndex((p, j) => j > 0 && length <= p[0]) - 1;
  if (i < 0) i = sorted.length - 2;
  const [a, b] = [sorted[i], sorted[i + 1]];
  const value = Math.abs(b[0] - a[0]) < Number.EPSILON ? b[1] : a[1] + (length - a[0]) * (b[1] - a[1]) / (b[0] - a[0]);
  return Math.max(0, value);
};

const SETS = [
  [[0, 0], [1000, 1000]],
  [[0, -17.5], [1000, 482.5]],
  [[0, 250], [1000, 250]],
  [[0, 600], [160, 440], [320, 280], [480, 120], [640, 0], [800, -160]],
  [[0, 0], [160, 160], [320, 300], [480, 300], [640, 460], [800, 600], [1024, 600], [1280, 400], [1600, 100]],
  [[0, 40], [200, 120], [200, 20], [600, 220]],
  [[0, 40], [200, 120], [200, 20], [200, 90], [600, 220]],
  [[100, 30], [100, 80], [500, 280]],
  [[0, 30], [500, 280], [500, 30]],
  [[400, 10], [200, 90], [0, 50], [800, 300]],
  [[300, 120], [300, 60]],
  [[0, 33]],
];

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
    await page.setContent("<!doctype html><body style='margin:0'></body>");
    await page.addScriptTag({ content: mapper });
    let checked = 0;
    for (const samples of SETS) {
      const text = samples.map((p) => p.join(":")).join(";");
      const expression = await page.evaluate(([text]) => relativeLength(text, "--sl-cw"), [text]);
      assert.ok(typeof expression === "string", `${text}: the samples are expressed`);
      const steps = new Set(samples.map((p) => p[0]));
      for (let length = 0; length <= 3000; length += 37.5) {
        // Where a step is (a container length with two samples), the browser and the reference may disagree within a hair of it.
        if ([...steps].some((x) => Math.abs(length - x) < 0.01)) continue;
        const width = await page.evaluate(([expression, length]) => {
          const e = document.createElement("div");
          e.style.cssText = `position:absolute;height:1px;--sl-cw:${length}px;width:${expression}`;
          document.body.append(e);
          const w = e.getBoundingClientRect().width;
          e.remove();
          return w;
        }, [expression, length]);
        assert.ok(Math.abs(width - reference(samples, length)) < 0.05, `${text} at ${length}: CSS ${width}, reference ${reference(samples, length)}`);
        checked++;
      }
    }
    // Samples that are not numbers are not a length; no samples at all is an axis the frame does not select.
    assert.equal(await page.evaluate(() => relativeLength(null, "--sl-cw")), undefined);
    assert.equal(await page.evaluate(() => relativeLength("x:y;a:b", "--sl-cw")), undefined);
    console.log(`PASS ${checked} container lengths of ${SETS.length} sample sets give the reference length as CSS`);
  } finally {
    await browser.close();
  }
});
