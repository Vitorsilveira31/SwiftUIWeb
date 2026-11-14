#!/usr/bin/env bun
/*
 * Produce the stylesheet the browser loads from Tools/styles.css.
 *
 * styles.css is plain CSS that is authored by hand, so there is no compile step: this only removes
 * comments and layout whitespace. It never rewrites a value, a selector or the order of anything,
 * because a minifier that "improves" values (expanding font stacks, converting colours) would change
 * what the browser computes.
 *
 * usage: bun Tools/build-styles.mjs <output.css> [--no-minify]
 */
"use strict";

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Remove comments and collapse layout whitespace. Strings and url() contents are copied verbatim. */
export function minify(css) {
  let out = "";
  let pendingSpace = false;
  // A space next to one of these characters is never significant in CSS.
  const tight = new Set(["{", "}", ";", ","]);
  const emit = (text) => {
    if (pendingSpace && out && !tight.has(out[out.length - 1]) && !tight.has(text[0])) out += " ";
    pendingSpace = false;
    out += text;
  };
  for (let i = 0; i < css.length;) {
    const char = css[i];
    if (char === "/" && css[i + 1] === "*") {
      const end = css.indexOf("*/", i + 2);
      if (end < 0) throw new Error("unterminated comment in stylesheet");
      pendingSpace = true;
      i = end + 2;
    } else if (char === '"' || char === "'") {
      let j = i + 1;
      while (j < css.length && css[j] !== char) j += css[j] === "\\" ? 2 : 1;
      if (j >= css.length) throw new Error("unterminated string in stylesheet");
      emit(css.slice(i, j + 1));
      i = j + 1;
    } else if (/\s/.test(char)) {
      pendingSpace = true;
      i += 1;
    } else {
      emit(char);
      i += 1;
    }
  }
  return out;
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const output = args.find((arg) => !arg.startsWith("--"));
  if (!output) {
    console.error("usage: bun Tools/build-styles.mjs <output.css> [--no-minify]");
    process.exit(2);
  }
  const source = readFileSync(resolve(root, "Tools/styles.css"), "utf8");
  const result = args.includes("--no-minify") ? source : minify(source);
  if (!result.trim()) throw new Error("Tools/styles.css produced no CSS");
  mkdirSync(dirname(resolve(output)), { recursive: true });
  writeFileSync(resolve(output), result);
  console.log(`Generated stylesheet: ${output} (${Buffer.byteLength(result)} bytes)`);
}
