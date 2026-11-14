#!/usr/bin/env bun
// CSS layout styles incrementally (only analysed-again nodes get a new block). Random edits of a tree must leave the
// page as a layout from scratch of the same DOM does.
import { readFileSync } from "node:fs";
import { chromium } from "playwright";
const css = readFileSync(new URL("./css-layout.js", import.meta.url), "utf8").replace(/^export /gm, "");
const html = `<body style="margin:0"><div id="root" data-layout-kind="frame" data-frame-w="400" data-align-x="0" data-align-y="0">
<div class="vstack" data-layout-kind="vstack" data-layout-gap="6" id="v">
  <div class="hstack" data-layout-kind="hstack" data-layout-gap="8"><span data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">alpha beta gamma</span><div class="flex-spacer" data-layout-kind="spacer" data-spacer-min="4"></div><span data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">tail</span></div>
  <div data-layout-kind="padding" data-padding-top="4" data-padding-leading="10"><span data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">padded text that is long enough to wrap around in a narrow column of the layout</span></div>
  <div data-layout-kind="frame" data-frame-max-w="inf" data-align-x="1" data-align-y="0.5" id="f"><span data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">right</span></div>
</div></div></body>`;
const browser = await chromium.launch();
const page = await browser.newPage();
await page.setContent(html);
await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
const rects = () => page.evaluate(() => [...document.querySelectorAll("#root, #root *")].map((e) => { const r = e.getBoundingClientRect(); return [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 100) / 100).join(","); }).join("|"));
const edits = [
  (d) => d.getElementById("v").setAttribute("data-layout-gap", "20"),
  (d) => d.getElementById("f").setAttribute("data-align-x", "0.5"),
  (d) => { const s = d.createElement("span"); s.setAttribute("data-layout-kind", "intrinsic"); s.setAttribute("data-layout-leaf", "text"); s.style.font = "14px sans-serif"; s.textContent = "inserted"; d.getElementById("v").prepend(s); },
  (d) => d.getElementById("v").lastElementChild.remove(),
  (d) => d.getElementById("root").setAttribute("data-frame-w", "250"),
  (d) => d.querySelector("[data-layout-kind=padding]").setAttribute("data-padding-leading", "30"),
];
let failures = 0;
for (let round = 0; round < 40; round++) {
  const sequence = Array.from({ length: 1 + (round % 4) }, (_, i) => (round * 7 + i * 3) % edits.length);
  // incremental: styled once, then edited with a flush after every edit
  await page.setContent(html); await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
  // `setContent` keeps the document, and with it the stylesheets an earlier mapper adopted: their `[data-cl-n]` rules would
  // style this run's elements of the same ids.
  await page.evaluate(() => { document.adoptedStyleSheets = []; window.layout = new CssLayout(document); const root = document.getElementById("root"); window.layout.claim(root); window.layout.assign(root); window.mo = new MutationObserver((records) => { for (const r of records) { if (r.type === "attributes" && r.attributeName.startsWith("data-cl")) continue; window.layout.note(r, r.target.nodeType === 1 ? r.target : r.target.parentElement, root); } }); window.mo.observe(root, { attributes: true, attributeOldValue: true, childList: true, subtree: true }); window.layout.islands.add(root); });
  for (const index of sequence) {
    await page.evaluate(`(${edits[index].toString()})(document)`);
    await page.evaluate(() => { window.mo.takeRecords().forEach((r) => { if (!(r.type === "attributes" && r.attributeName.startsWith("data-cl"))) window.layout.note(r, r.target.nodeType === 1 ? r.target : r.target.parentElement, document.getElementById("root")); }); window.layout.flush(); });
  }
  const incremental = await rects();
  const dom = await page.evaluate(() => document.body.innerHTML.replace(/ data-cl(-\d+)?="[^"]*"/g, ""));
  // from scratch: the same DOM, styled once
  await page.setContent(`<body style="margin:0">${dom}</body>`); await page.addScriptTag({ content: css + "\nwindow.CssLayout = CssLayout;" });
  await page.evaluate(() => { document.adoptedStyleSheets = []; const l = new CssLayout(document), root = document.getElementById("root"); l.claim(root); l.assign(root); });
  const scratch = await rects();
  if (incremental !== scratch) { failures++; console.log("DIVERGED", sequence.join(","), "\n", incremental, "\n", scratch); }
}
console.log(failures === 0 ? "PASS incremental styling equals styling from scratch (40 random edit sequences)" : `FAIL ${failures} sequences diverged`);
await browser.close();
process.exit(failures ? 1 : 0);
