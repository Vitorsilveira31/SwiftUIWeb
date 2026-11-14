#!/usr/bin/env bun
// Fills the Content-Security-Policy of a browser bundle's index.html.
//
// Tools/browser-index.html carries the policy with a placeholder for the page's own inline scripts. Those scripts are
// edited while the bundle is assembled (bootstrap patch, showcase host), so their hashes can only be taken at the end:
// this is the last step of the launcher. The policy lets the page run its own files, its inline bootstrap by hash and
// WebAssembly; it allows no other script and no eval. A page whose head.html brings its own policy has the template's
// removed (see inject-app-head.mjs), and this step then changes nothing.
//
// No application gets 'unsafe-eval': DOM components are registered functions of the page's own files, never script text.
//
// usage: seal-csp.mjs <bundle-directory>
// Run the tests with: bun test ./Tools/test-seal-csp.mjs

import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const PLACEHOLDER = "__INLINE_SCRIPT_HASHES__";

/** The CSP source expressions for every inline `<script>` of `html`, such as `'sha256-...'`. */
export function inlineScriptHashes(html) {
  const hashes = [];
  for (const match of html.matchAll(/<script(\s[^>]*)?>([\s\S]*?)<\/script>/gi)) {
    if (/\ssrc\s*=/i.test(match[1] ?? "") || match[2].trim() === "") continue;
    const hash = `'sha256-${createHash("sha256").update(match[2]).digest("base64")}'`;
    if (!hashes.includes(hash)) hashes.push(hash);
  }
  return hashes;
}

/** `html` with the placeholder replaced, or unchanged when it has no placeholder (an application's own policy). */
export function seal(html) {
  if (!html.includes(PLACEHOLDER)) return html;
  return html.replace(PLACEHOLDER, inlineScriptHashes(html).join(" "));
}

export function main(argv) {
  const paths = argv;
  if (paths.length !== 1 || paths[0].startsWith("--")) {
    console.error("usage: seal-csp.mjs <bundle-directory>");
    return 2;
  }
  const index = join(resolve(paths[0]), "index.html");
  if (!existsSync(index)) {
    console.error(`no index.html in ${paths[0]}`);
    return 1;
  }
  const html = readFileSync(index, "utf8");
  const sealed = seal(html);
  if (sealed !== html) writeFileSync(index, sealed);
  return 0;
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
