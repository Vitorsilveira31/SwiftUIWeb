#!/usr/bin/env bun
// Lets a consumer declare SwiftUIWeb as a versioned URL dependency and still build with the Embedded launcher.
//
// usage: framework-url-dependency.mjs has MANIFEST
//        framework-url-dependency.mjs rewrite MANIFEST FRAMEWORK
//        framework-url-dependency.mjs rewrite-url MANIFEST URL PACKAGE
//
// The launcher lowers the framework's sources in a disposable copy (FRAMEWORK) and builds the consumer against that copy.
// A `.package(url: ".../swiftuiweb.git", from: "0.1.0")` would make SwiftPM fetch the original, unlowered framework
// instead, so in the staged copy of a manifest the declaration is replaced by `.package(path: "<relative FRAMEWORK>")`.
// The package identity stays `swiftuiweb` (the staged directory is called that), so `package: "swiftuiweb"` in the target
// dependencies keeps resolving.
//
// `has` exits 0 when the manifest declares SwiftUIWeb by URL and 1 when it does not. `rewrite` edits MANIFEST in place
// (the staged copy, never the consumer's checkout) and prints the path it wrote, or nothing when there was no such
// declaration. `rewrite-url` does the same for another package declared by URL (Tools/remote-package-dependencies.mjs):
// the declarations of URL, in any of its spellings (https or ssh, with or without `.git`, any case), become
// `.package(path: "<relative PACKAGE>")`.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";

const OPENING = ".package(";

// The text of the string literal that follows `url:` in a `.package(...)` call, or undefined.
function declaredURL(call) {
  return /\burl:\s*"([^"]*)"/u.exec(call)?.[1];
}

// The explicit package name of a `.package(name: "…", url: …)` call, or undefined: target dependencies may refer to it.
function declaredName(call) {
  // Comments count as spaces: `.package(/* browser library */ name: "X", …)` keeps its name too.
  const code = call.replace(/\/\*[\s\S]*?\*\//gu, " ").replace(/\/\/[^\n]*/gu, " ");
  return /^\.package\(\s*name:\s*"([^"]*)"/u.exec(code)?.[1];
}

// The last component of a repository URL, without `.git` and slashes: the package identity SwiftPM derives (in lower case).
export function repositoryName(url) {
  return url.replace(/\/+$/u, "").replace(/\.git$/u, "").split(/[/:]/u).pop() ?? "";
}

// A repository URL is the framework when its last component, without `.git` and slashes, is swiftuiweb (any case).
export function isFrameworkURL(url) {
  return repositoryName(url).toLowerCase() === "swiftuiweb";
}

// One spelling for the URLs of a repository: `git@github.com:o/r.git`, `ssh://git@github.com/o/r` and
// `https://github.com/o/r.git` all become `github.com/o/r`, in lower case.
export function normalizedURL(url) {
  return url
    .trim()
    .replace(/^[a-z+]+:\/\//iu, "")
    .replace(/^[^@/]+@/u, "")
    .replace(/^([^/:]+):(?!\d)/u, "$1/")
    .replace(/\/+$/u, "")
    .replace(/\.git$/u, "")
    .toLowerCase();
}

// Which characters are Swift code: false inside string literals (plain, multi-line and raw), line comments and block
// comments (which nest). A `//` inside a URL string is not a comment, and a `.package(` in a comment is not a dependency.
function codeMask(text) {
  const mask = new Uint8Array(text.length).fill(1);
  const blank = (from, to) => mask.fill(0, from, Math.min(to, text.length));
  for (let index = 0; index < text.length; ) {
    if (text.startsWith("//", index)) {
      const end = text.indexOf("\n", index);
      const stop = end === -1 ? text.length : end;
      blank(index, stop);
      index = stop;
    } else if (text.startsWith("/*", index)) {
      let depth = 1;
      let cursor = index + 2;
      while (cursor < text.length && depth > 0) {
        if (text.startsWith("/*", cursor)) (depth += 1), (cursor += 2);
        else if (text.startsWith("*/", cursor)) (depth -= 1), (cursor += 2);
        else cursor += 1;
      }
      blank(index, cursor);
      index = cursor;
    } else if (text[index] === '"' || (text[index] === "#" && /^#+"/u.test(text.slice(index, index + 8)))) {
      const hashes = /^#*/u.exec(text.slice(index))[0];
      const open = index + hashes.length;
      const quote = text.startsWith('"""', open) ? '"""' : '"';
      const close = quote + hashes;
      let cursor = open + quote.length;
      while (cursor < text.length && !text.startsWith(close, cursor)) cursor += text[cursor] === "\\" && !hashes ? 2 : 1;
      cursor = Math.min(cursor + close.length, text.length);
      blank(index, cursor);
      index = cursor;
    } else index += 1;
  }
  return mask;
}

// The [start, end) ranges of the `.package(url: …, …)` calls whose URL matches, skipping commented-out ones. The closing
// parenthesis is found by counting code parentheses, since a requirement such as `.upToNextMajor(from: "0.1.0")` nests them.
export function urlDependencies(text, matches) {
  const mask = codeMask(text);
  const ranges = [];
  for (let index = text.indexOf(OPENING); index !== -1; index = text.indexOf(OPENING, index + 1)) {
    if (!mask[index]) continue;
    let depth = 0;
    let end = -1;
    for (let cursor = index + OPENING.length - 1; cursor < text.length; cursor += 1) {
      if (!mask[cursor]) continue;
      if (text[cursor] === "(") depth += 1;
      else if (text[cursor] === ")" && --depth === 0) {
        end = cursor + 1;
        break;
      }
    }
    if (end === -1) continue;
    const url = declaredURL(text.slice(index, end));
    if (url !== undefined && matches(url)) ranges.push([index, end, declaredName(text.slice(index, end))]);
  }
  return ranges;
}

// The ranges of the `.package(url: <swiftuiweb>, …)` calls.
export function frameworkURLDependencies(text) {
  return urlDependencies(text, isFrameworkURL);
}

function replaceRanges(text, ranges, manifestDirectory, destination) {
  const path = relative(manifestDirectory, destination) || ".";
  let result = text;
  for (const [start, end, name] of [...ranges].reverse()) {
    const named = name === undefined ? "" : `name: ${JSON.stringify(name)}, `;
    result = result.slice(0, start) + `.package(${named}path: ${JSON.stringify(path)})` + result.slice(end);
  }
  return result;
}

export function rewriteManifest(text, manifestDirectory, framework) {
  return replaceRanges(text, frameworkURLDependencies(text), manifestDirectory, framework);
}

// Replaces the declarations of the package at <url> with a path dependency on <destination>.
export function rewriteURLDependency(text, manifestDirectory, url, destination) {
  const wanted = normalizedURL(url);
  return replaceRanges(text, urlDependencies(text, (declared) => normalizedURL(declared) === wanted), manifestDirectory, destination);
}

export function main(argv = process.argv.slice(2)) {
  const [command, manifest, framework] = argv;
  if (command === "rewrite-url" && argv.length === 4) {
    const [, , url, destination] = argv;
    const text = readFileSync(manifest, "utf8");
    const rewritten = rewriteURLDependency(text, dirname(manifest), url, destination);
    if (rewritten === text) return 0;
    writeFileSync(manifest, rewritten);
    process.stdout.write(manifest + "\n");
    return 0;
  }
  if ((command === "has" && manifest) || (command === "rewrite" && manifest && framework)) {
    const text = readFileSync(manifest, "utf8");
    if (command === "has") return frameworkURLDependencies(text).length ? 0 : 1;
    const rewritten = rewriteManifest(text, dirname(manifest), framework);
    if (rewritten === text) return 0;
    writeFileSync(manifest, rewritten);
    process.stdout.write(manifest + "\n");
    return 0;
  }
  process.stderr.write("usage: framework-url-dependency.mjs (has MANIFEST | rewrite MANIFEST FRAMEWORK | rewrite-url MANIFEST URL PACKAGE)\n");
  return 2;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main();
}
