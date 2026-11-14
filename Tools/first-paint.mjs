#!/usr/bin/env bun
// First paint: the first screen's markup and styles in index.html, so the page paints before the wasm arrives.
// Design: Documentation/Architecture/FIRST_PAINT.md. Tests: bun test ./Tools/test-first-paint.mjs (pure parts), Tools/test-first-paint-browser.mjs. The launcher runs `build` as the step after the CSP is sealed when
// SWIFTUIWEB_FIRST_PAINT=1.
//
//   first-paint.mjs build <bundle> [--route /] [--viewport 1280x1200] [--no-verify]
//       captures the bundle's first screen in headless Chromium, finds the viewport widths it is valid for, writes it
//       into the bundle's index.html and verifies it
//   first-paint.mjs capture <bundle> ...   the capture alone: the markup for the capture viewport, valid at that width
//   first-paint.mjs verify <bundle> [--route /]
//       loads the bundle twice, with the wasm blocked (the prerendered frame) and normally (the runtime's first frame),
//       and fails unless the two frames are identical pixel for pixel, at the widths and in the schemes the page declares
//   first-paint.mjs strip <bundle>         removes the prerender from index.html
//
// Everything the capture adds sits between `<!--first-paint:begin-->` and `<!--first-paint:end-->` markers (two places:
// the head's <style>, and the app root with its markup and the early-event script), so it can be removed again exactly.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, serveBundle } from "./browser-test-support.mjs";
import { claimPort, compareScreenshots } from "./first-paint-support.mjs";

const BEGIN = "<!--first-paint:begin-->", END = "<!--first-paint:end-->";
const BLOCK = /<!--first-paint:begin-->[\s\S]*?<!--first-paint:end-->\n?/g;
const MOUNTED = 'html[data-embedded-mounted="true"]';
/** The viewport widths the build compares the prerender with the runtime at, to find the range it is valid for. */
export const WIDTH_LADDER = [320, 390, 480, 600, 768, 1024, 1280, 1440, 1920, 2560, 3840];
export const PROBE_HEIGHT = 800;
export const CAPTURE_LOCALE = "en-US", OTHER_LOCALE = "pt-BR";

/**
 * Runs before the wasm. It takes the prerender away before the first paint when the page is not the one that was captured:
 * the viewport is outside the range the capture was verified for (`data-first-paint-media`), the browser speaks another
 * language than a language-dependent capture (`data-first-paint-lang`), the page is opened at another address than the
 * captured one (`data-first-paint-route`, a query the framework does not read counts as another address), or the origin holds stored state (a returning
 * visitor: the capture is of an empty profile, and what an app restores from storage is not known here). Otherwise it records the clicks and the typing a person makes on the
 * prerendered markup, so the runtime can replay them on the real elements once it has taken over. Each event is a path of
 * child indexes from the app root. (Plain text: it is hashed into the Content-Security-Policy and counted in the bytes.)
 */
export const EARLY_EVENT_SCRIPT = `(function(){var r=document.getElementById("embedded-app-root"),m=r.getAttribute("data-first-paint-media"),l=r.getAttribute("data-first-paint-lang"),o=r.getAttribute("data-first-paint-route"),q=window.__firstPaintEvents=[],k=0,x=0;try{k=localStorage.length}catch(e){}
new URLSearchParams(location.search).forEach(function(v,n){if(!/^(render-in-worker|render-performance|swuidiag|swuinomutations)$/.test(n))x=1});
if(k||x||o!==location.pathname||(m&&!matchMedia(m).matches)||(l&&(navigator.language||"").slice(0,2)!==l)){r.replaceChildren();r.removeAttribute("data-first-paint");var s=document.getElementById("first-paint-style");if(s)s.remove();return}
function p(e){var a=[];for(;e&&e!==r;e=e.parentElement)a.unshift(Array.prototype.indexOf.call(e.parentElement.children,e));return a}
function t(e){var n=e.target;return n&&n.nodeType===1&&r.hasAttribute("data-first-paint")?n:null}
r.addEventListener("click",function(e){var n=t(e);if(!n)return;e.preventDefault();e.stopPropagation();var c=n.closest("button,a,[role=button],input,select,summary,label")||n;q.push({type:"click",path:p(c),tag:c.localName,text:(c.textContent||"").slice(0,40)})},true);
r.addEventListener("input",function(e){var n=t(e);if(n)q.push({type:"input",path:p(n),tag:n.localName,value:n.value})},true)})();`;

export function scriptHash(text) { return `'sha256-${createHash("sha256").update(text).digest("base64")}'`; }

/** `html` without anything a previous capture added, the script's hash included. */
export function stripFirstPaint(html) {
  return html.replace(BLOCK, "").split(` ${scriptHash(EARLY_EVENT_SCRIPT)}`).join("");
}

/** Adds the script's hash to the `script-src` of the page's policy; refuses a policy the script cannot be allowed in. */
export function allowScript(html, text) {
  const meta = /<meta http-equiv="Content-Security-Policy" content="([^"]*)">/.exec(html);
  if (!meta) return html; // no policy, nothing to allow
  const hash = scriptHash(text);
  if (meta[1].includes(hash)) return html;
  const directive = /(^|;\s*)script-src\s+([^;]*)/.exec(meta[1]);
  if (!directive) throw new Error("the page's Content-Security-Policy has no script-src: the early-event script cannot be allowed (an application's own policy needs a script-src to take its hash, see FIRST_PAINT.md)");
  const policy = meta[1].replace(directive[0], `${directive[0]} ${hash}`);
  return html.replace(meta[0], meta[0].replace(meta[1], policy));
}

/** Writes index.html and refreshes its precompressed copies when the bundle has them (the server sends those, not the file). */
function writeIndex(bundle, html) {
  const index = join(resolve(bundle), "index.html");
  writeFileSync(index, html);
  if (existsSync(`${index}.br`) || existsSync(`${index}.gz`)) {
    const run = spawnSync(process.execPath, [join(import.meta.dir, "precompress-bundle.mjs"), resolve(bundle)], { stdio: "ignore" });
    if (run.status !== 0) throw new Error("could not refresh the precompressed copies of index.html");
  }
}

export function parseViewport(text) {
  const match = /^(\d+)x(\d+)$/.exec(text);
  if (!match) throw new Error(`--viewport is WIDTHxHEIGHT, not ${text}`);
  return { width: Number(match[1]), height: Number(match[2]) };
}

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** A server and a browser for the bundle, for as long as `use` runs. */
async function session(bundle, use) {
  const port = await claimPort();
  const server = await serveBundle({ bundle, port, logName: null });
  const browser = await launch({ engine: "chromium" });
  try {
    return await use({ base: server.base, browser });
  } finally {
    await browser.close();
    await server.stop();
  }
}

/**
 * A page in a fresh context. `prerender: "keep"` serves index.html as it is, with `blockWasm` so that only the prerender
 * paints; `"strip"` serves it without the prerender, so that only the runtime paints.
 */
async function openPage({ base, browser }, { route, viewport, scheme = "light", locale = "en-US", blockWasm = false, prerender = "strip" }) {
  const context = await browser.newContext({ viewport, colorScheme: scheme, locale, deviceScaleFactor: 1, reducedMotion: "reduce" });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  if (prerender === "strip") {
    await page.route(new RegExp(`^${escapeRegExp(base)}${escapeRegExp(route)}$`), async (r) => {
      const response = await r.fetch();
      await r.fulfill({ response, body: stripFirstPaint(await response.text()) });
    });
  }
  if (blockWasm) await page.route(/\.wasm(\?|$)/, (r) => r.abort());
  await page.goto(`${base}${route}`, { waitUntil: "domcontentloaded" });
  return { page, errors, close: () => context.close() };
}

/** Waits until the app is mounted and has stopped committing: the frame a person would be left looking at. */
async function settle(page) {
  await page.waitForSelector(MOUNTED, { timeout: 60_000, state: "attached" });
  await page.evaluate(() => new Promise((done) => {
    let timer = 0; const quiet = () => { clearTimeout(timer); timer = setTimeout(async () => { await document.fonts.ready; done(); }, 400); };
    window.addEventListener("commit-phase", quiet); quiet();
  }));
  await page.evaluate(() => Promise.all([...document.images].map((image) => image.complete ? null : new Promise((done) => { image.onload = image.onerror = done; }))));
}

/** What the page shows once mounted: the root's markup (only what some selector needs), the styles the runtime wrote. */
const EXTRACT = () => {
  const root = document.getElementById("embedded-app-root");
  const used = new Set();
  const sheets = [];
  for (const sheet of [...document.styleSheets, ...document.adoptedStyleSheets]) {
    let cssText = "";
    try { cssText = [...sheet.cssRules].map((rule) => rule.cssText).join("\n"); } catch { /* a sheet of another origin */ }
    for (const match of cssText.matchAll(/\[([a-zA-Z_][-\w:.]*)/g)) used.add(match[1]);
    if (document.adoptedStyleSheets.includes(sheet)) sheets.push(cssText);
  }
  const clone = root.cloneNode(true);
  const walk = (element) => {
    for (const attribute of [...element.attributes]) if (attribute.name.startsWith("data-") && !used.has(attribute.name)) element.removeAttribute(attribute.name);
    for (const child of element.children) walk(child);
  };
  walk(clone);
  return {
    markup: clone.innerHTML,
    rootAttributes: Object.fromEntries([...root.attributes].filter((a) => !a.name.startsWith("data-embedded") && a.name !== "id").map((a) => [a.name, a.value])),
    adopted: sheets,
    styles: [...document.querySelectorAll("style")].map((s) => s.textContent),
  };
};

async function captureOnce(ctx, bundle, { route, viewport, scheme }, staticStyles) {
  const { page, errors, close } = await openPage(ctx, { route, viewport, scheme });
  try {
    await settle(page);
    assert.deepEqual(errors, [], `the page raised errors while it was captured: ${errors.join("; ")}`);
    const extracted = await page.evaluate(EXTRACT);
    const css = [...extracted.adopted, ...extracted.styles.filter((text) => text.trim() && !staticStyles.includes(text))].filter((text) => text.trim()).join("\n");
    return { ...extracted, css };
  } finally { await close(); }
}

/** The text of the static page's own <style> elements, to tell them from the ones the runtime added. */
function staticStyleTexts(html) {
  return [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((match) => match[1]);
}

export function composePage(staticHTML, { markup, css, rootAttributes, media, lang, route = "/" }) {
  const attributes = Object.entries(rootAttributes).map(([k, v]) => ` ${k}="${v.replace(/"/g, "&quot;")}"`).join("");
  // The route goes into an attribute unescaped, so a quote or angle bracket could break out of it.
  if (/["<>]/.test(route)) throw new Error(`the route ${JSON.stringify(route)} cannot contain quotes or angle brackets`);
  // The media query and language are escaped for the attribute like the root attributes above.
  const quoted = (value) => String(value).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const mediaAttribute = ` data-first-paint-route="${route}"` + (media ? ` data-first-paint-media="${quoted(media)}"` : "") + (lang ? ` data-first-paint-lang="${quoted(lang)}"` : "");
  // A </style inside captured CSS would end the element early; the escaped form still parses as CSS text.
  const head = `${BEGIN}<style id="first-paint-style">${css.replace(/<\/style/gi, "<\\/style")}</style>${END}\n`;
  const body = `${BEGIN}<div id="embedded-app-root" data-first-paint${mediaAttribute}${attributes}>${markup}</div><script>${EARLY_EVENT_SCRIPT}</script>${END}\n`;
  assert.ok(staticHTML.includes("</head>") && /<body[^>]*>/.test(staticHTML), "index.html has no head and body");
  const html = staticHTML.replace("</head>", () => `${head}</head>`).replace(/(<body[^>]*>\s*)/, (m) => `${m}${body}`);
  return allowScript(html, EARLY_EVENT_SCRIPT);
}

/**
 * Captures the first screen at `viewport` and writes it into the bundle's index.html (valid at the capture width only; `build`
 * widens that to the verified range). Captures twice and refuses a screen that differs from itself (a clock, random ids).
 */
export async function capture(bundle, { route = "/", viewport = { width: 1280, height: 1200 }, scheme = "light" } = {}) {
  if (!route.startsWith("/") || /[?#]/.test(route)) throw new Error(`the route is a path such as / or /en, not ${route}`);
  const index = join(resolve(bundle), "index.html");
  const staticHTML = stripFirstPaint(readFileSync(index, "utf8"));
  const staticStyles = staticStyleTexts(staticHTML);
  const options = { route, viewport, scheme };
  const taken = await session(bundle, async (ctx) => {
    const first = await captureOnce(ctx, bundle, options, staticStyles);
    const second = await captureOnce(ctx, bundle, options, staticStyles);
    return { first, second };
  });
  if (taken.first.markup !== taken.second.markup) throw new Error(`the first screen of ${route} differs between two loads of the same bundle (a clock, a random value or a request that answers differently): it cannot be prerendered`);
  const { css } = taken.first;
  if (/@import|url\(\s*["']?https?:/i.test(css)) throw new Error("the captured styles load a remote resource; the prerender holds only same-document rules");
  const html = composePage(staticHTML, { ...taken.first, media: undefined, route });
  writeIndex(bundle, html);
  return { bytes: Buffer.byteLength(html) - Buffer.byteLength(staticHTML), markupBytes: Buffer.byteLength(taken.first.markup), styleBytes: Buffer.byteLength(css), staticHTML, ...taken.first };
}

/** Compares, in one session, the prerendered frame with the runtime's at each of `cases` ({ width, height, scheme }). */
export async function compare(bundle, cases, { route = "/", tolerance = 0 } = {}) {
  return session(bundle, async (ctx) => {
    const results = [];
    for (const { width, height = PROBE_HEIGHT, scheme = "light", locale = "en-US" } of cases) {
      const viewport = { width, height };
      const shown = await openPage(ctx, { route, viewport, scheme, locale, blockWasm: true, prerender: "keep" });
      let prerender;
      try {
        const present = await shown.page.locator("#embedded-app-root[data-first-paint]").count();
        await shown.page.waitForTimeout(250);
        prerender = present ? await shown.page.screenshot() : null;
      } finally { await shown.close(); }
      const real = await openPage(ctx, { route, viewport, scheme, locale });
      try {
        await settle(real.page);
        const runtime = await real.page.screenshot();
        const diff = prerender ? await compareScreenshots(ctx.browser, prerender, runtime, { tolerance }) : null;
        results.push({ width, height, scheme, locale, prerendered: Boolean(prerender), diff, prerender, runtime });
      } finally { await real.close(); }
    }
    return results;
  });
}

const describe = (r) => !r.prerendered ? `${r.width}x${r.height} ${r.scheme} ${r.locale}: the page was not prerendered there`
  : !r.diff.sameSize ? `${r.width}x${r.height} ${r.scheme} ${r.locale}: sizes differ ${JSON.stringify(r.diff.left)} vs ${JSON.stringify(r.diff.right)}`
  : `${r.width}x${r.height} ${r.scheme} ${r.locale}: ${r.diff.different} pixels differ (largest channel difference ${r.diff.maxDelta}) within ${JSON.stringify(r.diff.box)}`;
const matches = (r) => r.prerendered && r.diff.sameSize && r.diff.different === 0;

/** The media condition of the widths (contiguous run of matching ladder steps around the capture) and the capture height. */
export function mediaFor(results, captureWidth, captureHeight) {
  const at = (w) => results.find((r) => r.width === w);
  const ladder = WIDTH_LADDER.includes(captureWidth) ? WIDTH_LADDER : [...WIDTH_LADDER, captureWidth].sort((a, b) => a - b);
  let i = ladder.indexOf(captureWidth), lo = i, hi = i;
  while (lo > 0 && at(ladder[lo - 1]) && matches(at(ladder[lo - 1]))) lo--;
  while (hi < ladder.length - 1 && at(ladder[hi + 1]) && matches(at(ladder[hi + 1]))) hi++;
  const parts = [`(min-width:${ladder[lo]}px)`];
  if (hi < ladder.length - 1) parts.push(`(max-width:${ladder[hi]}px)`);
  parts.push(`(max-height:${captureHeight}px)`);
  return parts.join(" and ");
}

/**
 * The whole step: capture, find the width range the capture is valid for, write it, then verify the page as it will ship
 * (every ladder step inside the range, plus the capture's own height, in light and dark). Throws on any difference.
 */
export async function build(bundle, { route = "/", viewport = { width: 1280, height: 1200 }, verifyPages = true } = {}) {
  const captured = await capture(bundle, { route, viewport });
  if (!verifyPages) return { ...captured, media: undefined };
  const probes = [...new Set([...WIDTH_LADDER, viewport.width])].sort((a, b) => a - b).map((width) => ({ width, height: PROBE_HEIGHT }));
  const probed = await compare(bundle, probes, { route });
  const own = probed.find((r) => r.width === viewport.width);
  if (!matches(own)) throw new Error(`first paint does not match the runtime's first frame at its own capture width: ${describe(own)}`);
  const media = mediaFor(probed, viewport.width, viewport.height);
  // An app that follows the browser language shows another frame in another language: the prerender is then kept for the capture's language only.
  const [other] = await compare(bundle, [{ width: viewport.width, height: PROBE_HEIGHT, locale: OTHER_LOCALE }], { route });
  const lang = matches(other) ? undefined : CAPTURE_LOCALE.slice(0, 2);
  const html = composePage(captured.staticHTML, { ...captured, media, lang, route });
  writeIndex(bundle, html);
  await verify(bundle, { route, media, lang, viewport });
  return { ...captured, media, lang, bytes: Buffer.byteLength(html) - Buffer.byteLength(captured.staticHTML), probed: probed.map(({ width, prerendered, diff }) => ({ width, matches: prerendered && diff.different === 0 })) };
}

/** The cases a page's declared media covers: the ladder widths inside it, at the probe height and at the capture height, both schemes. */
export async function verify(bundle, { route = "/", media = null, lang = undefined, viewport = { width: 1280, height: 1200 } } = {}) {
  const page = readFileSync(join(resolve(bundle), "index.html"), "utf8");
  const declared = media ?? /data-first-paint-media="([^"]*)"/.exec(page)?.[1] ?? null;
  const declaredLang = lang ?? /data-first-paint-lang="([^"]*)"/.exec(page)?.[1] ?? null;
  const inside = (width) => !declared || window_matches(declared, width, viewport.height);
  const cases = [];
  for (const width of WIDTH_LADDER.filter(inside)) for (const scheme of ["light", "dark"]) cases.push({ width, height: PROBE_HEIGHT, scheme });
  cases.push({ width: viewport.width, height: viewport.height, scheme: "light" });
  // A language-independent capture must hold in the other language too; a language-bound one is not shown there.
  if (!declaredLang) cases.push({ width: viewport.width, height: PROBE_HEIGHT, scheme: "light", locale: OTHER_LOCALE });
  const results = await compare(bundle, cases, { route });
  const failed = results.filter((r) => !matches(r));
  if (failed.length) throw new Error(`first paint does not match the runtime's first frame (${route}):\n  ${failed.map(describe).join("\n  ")}`);
  return results;
}

/** Whether the media condition `build` writes holds for a viewport (min-width, max-width, max-height only). */
function window_matches(media, width, height) {
  const min = /min-width:(\d+)px/.exec(media), max = /max-width:(\d+)px/.exec(media), maxHeight = /max-height:(\d+)px/.exec(media);
  return (!min || width >= Number(min[1])) && (!max || width <= Number(max[1])) && (!maxHeight || height <= Number(maxHeight[1]));
}

async function main(argv) {
  const [command, bundle, ...rest] = argv;
  const { values } = parseArgs({ args: rest, options: { route: { type: "string", default: "/" }, viewport: { type: "string", default: "1280x1200" }, "no-verify": { type: "boolean", default: false } } });
  if (!["build", "capture", "verify", "strip"].includes(command) || !bundle) { console.error("usage: first-paint.mjs build|capture|verify|strip <bundle> [--route /] [--viewport 1280x1200] [--no-verify]"); return 2; }
  const viewport = parseViewport(values.viewport);
  const index = join(resolve(bundle), "index.html");
  if (!existsSync(index)) { console.error(`no index.html in ${bundle}`); return 1; }
  if (command === "strip") { writeIndex(bundle, stripFirstPaint(readFileSync(index, "utf8"))); return 0; }
  if (command === "capture") {
    const r = await capture(bundle, { route: values.route, viewport });
    console.log(`first paint: ${r.bytes} bytes added to index.html (${r.markupBytes} of markup, ${r.styleBytes} of layout styles)`);
  } else if (command === "build") {
    const r = await build(bundle, { route: values.route, viewport, verifyPages: !values["no-verify"] });
    console.log(`first paint: ${r.bytes} bytes added to index.html (${r.markupBytes} of markup, ${r.styleBytes} of layout styles); shown when ${r.media ?? "(unverified)"}${r.lang ? `, to browsers in ${r.lang}` : ""}`);
  } else {
    const results = await verify(bundle, { route: values.route, viewport });
    console.log(`first paint verified: ${results.length} frames identical`);
  }
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === new URL(import.meta.url).pathname) {
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; }, (error) => { console.error(`error: ${error.message}`); process.exitCode = 1; });
}
