#!/usr/bin/env bun
// A multi-line field's line limits (`TextField(axis: .vertical).lineLimit(2...3)`) are in lines of text: the stylesheet adds the
// control's own block padding and border to the bounds, so a field limited to three lines shows three whole lines before it
// scrolls, and a maximum alone is not defeated by the base minimum height.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const field = (id, attributes, style, extra = "") =>
  `<textarea id="${id}" class="text-area" ${attributes} style="${style};field-sizing:content" ${extra}>${Array.from({ length: 12 }, (_, i) => `line ${i + 1}`).join("\n")}</textarea>`;
const html = [
  field("range", 'data-lines-min="2" data-lines-max="3"', "--lines-min:2;--lines-max:3"),
  field("one", 'data-lines-min="1" data-lines-max="1"', "--lines-min:1;--lines-max:1"),
  field("lower", 'data-lines-min="2"', "--lines-min:2"),
  field("plain", 'data-lines-min="1" data-lines-max="3" data-field-chrome="plain"', "--lines-min:1;--lines-max:3"),
].join("");

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 600, height: 900 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    const measure = (id) => page.evaluate((id) => {
      const e = document.getElementById(id), s = getComputedStyle(e);
      const chrome = ["paddingTop", "paddingBottom", "borderTopWidth", "borderBottomWidth"].reduce((sum, k) => sum + parseFloat(s[k]), 0);
      const lh = parseFloat(s.lineHeight);
      return { height: e.getBoundingClientRect().height, text: e.getBoundingClientRect().height - chrome, lh, chrome };
    }, id);
    const range = await measure("range");
    assert.ok(Math.abs(range.text - 3 * range.lh) < 1, `lineLimit(2...3) shows three whole lines: ${range.text} of ${3 * range.lh}`);
    assert.ok(range.chrome > 0, "the default field has chrome to account for");
    const one = await measure("one");
    assert.ok(Math.abs(one.text - one.lh) < 1, `lineLimit(1) takes effect over the base minimum height: ${one.text} of ${one.lh}`);
    assert.ok(one.height < 80, `and is shorter than the stylesheet's 80px base: ${one.height}`);
    const lower = await measure("lower");
    assert.ok(lower.text > 5 * lower.lh, `a lower bound alone grows with its text: ${lower.text}`);
    const plain = await measure("plain");
    assert.equal(plain.chrome, 0, "a plain field has no chrome");
    assert.ok(Math.abs(plain.height - 3 * plain.lh) < 1, `and its limit is the lines alone: ${plain.height} of ${3 * plain.lh}`);
    console.log("textarea line limits: OK");
  } finally {
    await browser.close();
  }
});
