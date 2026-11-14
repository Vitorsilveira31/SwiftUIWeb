#!/usr/bin/env bun
// Inject an application's document-head hook into a browser bundle.
//
// Consumer packages ship browser-only static files in a package-level
// `Resources/` directory, which the Embedded browser build copies next to
// `index.html`. Two optional files form the document-head hook:
//
// * `Resources/head.html` - an HTML fragment inserted into `<head>` after the
//   framework's `styles.css` (web-font links, `<meta>` configuration such as
//   `tab-breakpoints`, `<title>`, `theme-color`, icons). When the
//   fragment declares a `<title>`, `theme-color` metas or a Content-Security-Policy meta, the template defaults
//   are removed so the application's values win.
// * `catalog-assets.css` - generated from the package's asset catalogs by
//   `Tools/compile-assets.mjs`; linked first so app rules can use its colors.
// * `Resources/app.css` - linked after the fragment, so application rules and
//   custom properties override framework tokens (unlayered CSS always wins over
//   the framework's layered styles).
//
// The operation is idempotent; running it twice leaves one copy of each hook.
//
// usage: inject-app-head.mjs <bundle-directory>
// Run the tests with: bun test ./Tools/test-inject-app-head.mjs

import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { isFile, joinPath, normalizePath, splitLines, stripWhitespace, readText, writeText } from "./compile-assets.mjs";

export const BEGIN = "<!-- app-head -->";
export const END = "<!-- /app-head -->";
export const STYLESHEET = /([ \t]*<link[^>]+href="\.\/styles\.css"[^>]*>\n?)/;

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\/-]/g, "\\$&");
}

const HTML_ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#x27;" };

/** Escapes &, <, >, " and ' for use in HTML text and attributes. */
export function htmlEscape(text) {
  return text.replace(/[&<>"']/g, (ch) => HTML_ESCAPES[ch]);
}

/**
 * `KEY=VALUE` lines of the generated environment file (see `compile-assets.mjs`); each becomes a
 * `runtime-environment` meta that the runtime passes to Swift's `WebEnvironment`.
 */
export function environmentEntries(path) {
  if (!isFile(path)) return [];
  return splitLines(readText(path))
    .filter((line) => line.includes("=") && stripWhitespace(line) !== "")
    .map((line) => stripWhitespace(line));
}

/** `inject(bundle) -> bool`. */
export function inject(bundlePath) {
  const bundle = normalizePath(bundlePath);
  const index = joinPath(bundle, "index.html");
  const head = joinPath(bundle, "head.html");
  const stylesheet = joinPath(bundle, "app.css");
  const assets = joinPath(bundle, "catalog-assets.css");
  const environment = joinPath(bundle, "runtime-environment");
  if (!isFile(index) || !(isFile(head) || isFile(stylesheet) || isFile(assets) || isFile(environment))) {
    return false;
  }
  let html = readText(index);
  html = html.replace(new RegExp(`[ \\t]*${escapeRegExp(BEGIN)}.*?${escapeRegExp(END)}\\n?`, "gs"), "");
  const fragment = isFile(head) ? stripWhitespace(readText(head)) : "";
  // What the fragment declares, without its comments: a commented-out policy must not remove the template's, which would
  // leave the page with no Content-Security-Policy at all.
  const declared = fragment.replace(/<!--[\s\S]*?(-->|$)/g, "");
  if (/<title[\s>]/i.test(declared)) {
    html = html.replace(/[ \t]*<title>.*?<\/title>\n?/si, "");
  }
  if (/http-equiv=["']content-security-policy["']/i.test(declared)) {
    html = html.replace(/[ \t]*<meta http-equiv="Content-Security-Policy"[^>]*>\n?/gi, "");
  }
  if (/name=["']theme-color["']/i.test(declared)) {
    html = html.replace(/[ \t]*<meta name="theme-color"[^>]*>\n?/gi, "");
  }
  const lines = [BEGIN];
  if (fragment) lines.push(...splitLines(fragment));
  if (isFile(assets)) lines.push('<link rel="stylesheet" href="./catalog-assets.css">');
  for (const entry of environmentEntries(environment)) {
    lines.push(`<meta name="runtime-environment" content="${htmlEscape(entry)}">`);
  }
  if (isFile(stylesheet)) lines.push('<link rel="stylesheet" href="./app.css">');
  lines.push(END);
  const block = lines.map((line) => (stripWhitespace(line) !== "" ? "  " + line : line)).join("\n") + "\n";
  const match = STYLESHEET.exec(html);
  if (match) {
    const end = match.index + match[0].length;
    html = html.slice(0, end) + (match[1].endsWith("\n") ? "" : "\n") + block + html.slice(end);
  } else {
    html = html.replace("</head>", () => block + "</head>");
  }
  writeText(index, html);
  return true;
}

/** `main(argv) -> int`; argv[0] is the script name. */
export function main(argv) {
  if (argv.length !== 2) {
    console.error("usage: inject-app-head.mjs <bundle-directory>");
    return 2;
  }
  if (inject(argv[1])) console.log("Injected application document head hook");
  return 0;
}

function isEntryPoint() {
  return process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isEntryPoint()) {
  process.exitCode = main(["inject-app-head.mjs", ...process.argv.slice(2)]);
}
