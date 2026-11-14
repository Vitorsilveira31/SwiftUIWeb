#!/usr/bin/env bun
// `.environment(\.colorScheme, ...)` sets the scheme of a subtree (`data-color-scheme` with `data-color-scheme-scope`): a light
// subtree inside a dark one reads the light palette and the light `color-scheme`, a dark one inside a light page the dark one.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const css = readFileSync(new URL("./styles.css", import.meta.url), "utf8");
const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  await page.setContent(`<!doctype html><html><head><style>${css}</style></head><body>
    <div id="dark-page" data-color-scheme="dark" data-color-scheme-scope="subtree"><p id="dark-ink">dark</p>
      <div id="light-inside" data-color-scheme="light" data-color-scheme-scope="subtree"><p id="light-ink">light</p></div></div>
    <div id="light-page"><div id="dark-inside" data-color-scheme="dark" data-color-scheme-scope="subtree"><p id="dark-ink-2">dark</p></div></div>
  </body></html>`);
  const read = (id) => page.evaluate((id) => {
    const e = document.getElementById(id), s = getComputedStyle(e);
    return { token: s.getPropertyValue("--color-swu-foreground").trim(), scheme: s.colorScheme, color: s.color };
  }, id);
  const dark = await read("dark-page"), light = await read("light-inside"), nested = await read("dark-inside");
  assert.equal(dark.scheme, "dark");
  assert.equal(light.scheme, "light", "a light subtree inside a dark one resets the browser's color scheme");
  assert.notEqual(light.token, dark.token, "a light subtree inside a dark one reads the light foreground token");
  assert.equal(light.token, "oklch(0.145 0 0)");
  assert.notEqual(light.color, (await read("dark-ink")).color, "its text is the light scheme's ink, not the dark one's");
  assert.equal(nested.scheme, "dark", "a dark subtree inside a light page stays dark");
  console.log("color scheme subtree test: OK");
} finally {
  await browser.close();
}
