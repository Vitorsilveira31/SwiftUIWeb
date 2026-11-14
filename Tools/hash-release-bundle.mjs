#!/usr/bin/env bun
// Gives the files of a release browser bundle content-hashed names, so the server can cache them for a year.
//
// Every file the page loads by name is renamed `<name>.<8 hex digits>.<ext>`, where the digits are the start of the
// SHA-256 of the file's final bytes: the scripts and the render-worker module, the styles, the wasm modules,
// the fonts, the catalog assets and the feature manifest. Every reference to a renamed file is rewritten to match:
// index.html (preloads, scripts, the inline bootstrap, the runtime-environment metas), the JavaScript (the worker URL,
// the wasm fetches, dynamic import()s), the CSS (url() of fonts and images) and the feature manifest. index.html keeps
// its name; it is the one file the browser must revalidate.
//
// A file is hashed after the files it references, so its name covers their new names too: a font whose bytes change
// renames the stylesheet that loads it, and the stylesheet's cached copy cannot outlive the font it points to.
//
// A reference is a file path that is not a suffix of a longer name or property: `app.wasm` matches `./app.wasm` and
// `'app.wasm'`, not `myapp.wasm` or `x.app.wasm`. Files that are neither hashed nor a page text (source copies, logs)
// are left alone. The bundle is hashed once; a second run is refused.
//
// Run it before Tools/seal-csp.mjs: the inline bootstrap script is hashed into the Content-Security-Policy, and it
// changes when its import is renamed.
//
// usage: hash-release-bundle.mjs <bundle-directory>
// Run the tests with: bun test ./Tools/test-hash-release-bundle.mjs

import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const HASH_LENGTH = 8;
// A hashed name: `name.<8 lowercase hex>.ext`, the form Tools/bun-server.ts recognises as immutable.
export const HASHED_NAME = /\.[0-9a-f]{8}\.[a-z0-9]+$/;

// Extensions of the framework's own files, which the page loads by name (the wasm modules, scripts, styles, web fonts).
const HASHED_EXTENSIONS = new Set([".js", ".mjs", ".css", ".wasm", ".woff2", ".woff", ".ttf", ".otf"]);
// Every catalog image is loaded through the runtime-environment metas and catalog-assets.css, so all of them are hashed.
const CATALOG_DIRECTORY = "catalog-assets/";
const FEATURE_MANIFEST = "features-manifest.json";
// Text that can hold references: the hashed files above, the page itself and the runtime environment.
const TEXT_EXTENSIONS = new Set([".html", ".js", ".mjs", ".css", ".json", ".svg", ".txt"]);
const PAGE = "index.html";
const ENVIRONMENT = "runtime-environment";

/** The name the file gets once its content hash is known: `app.wasm` becomes `app.3f9a1c2e.wasm`. */
export function hashedName(relativePath, hash) {
  const extension = extname(relativePath);
  return `${relativePath.slice(0, relativePath.length - extension.length)}.${hash}${extension}`;
}

/** The name a hashed file had before hashing: `app.3f9a1c2e.wasm` becomes `app.wasm`. Other names are returned as they are. */
export function logicalName(name) {
  return name.replace(/\.[0-9a-f]{8}(\.[a-z0-9]+)$/, "$1");
}

/**
 * The path of the file a bundle holds under `name`: the plain name in a debug bundle, or its hashed name in a release
 * one (`app.wasm` finds `app.3f9a1c2e.wasm`). Returns null when the bundle holds neither.
 */
export function bundleFilePath(directory, name) {
  const plain = join(directory, name);
  if (existsSync(plain)) return plain;
  if (!existsSync(directory)) return null;
  const hashed = readdirSync(directory).find((file) => HASHED_NAME.test(file) && logicalName(file) === name);
  return hashed ? join(directory, hashed) : null;
}

/** Whether the bundle-relative path is one of the framework files that gets a hashed name. */
export function isHashedFile(relativePath) {
  if (relativePath === PAGE) return false;
  if (relativePath.startsWith(CATALOG_DIRECTORY)) return true;
  if (relativePath === FEATURE_MANIFEST) return true;
  return HASHED_EXTENSIONS.has(extname(relativePath));
}

function listFiles(root) {
  const files = [];
  const walk = (directory, prefix) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) walk(join(directory, entry.name), relativePath);
      else if (entry.isFile()) files.push(relativePath);
    }
  };
  walk(root, "");
  return files.sort();
}

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Matches each hashed file's path where it stands alone: not preceded by a name character, a dot or a dash, and not
 * followed by one. `./index.js` and `"index.js"` match; `shaka-loader.js`, `x.index.js` and `index.js.map` do not.
 */
function referenceMatcher(paths) {
  if (paths.length === 0) return null;
  const alternatives = [...paths].sort((a, b) => b.length - a.length).map(escapeRegExp).join("|");
  return new RegExp(`(?<![A-Za-z0-9_.\\-])(?:${alternatives})(?![A-Za-z0-9_\\-]|\\.[A-Za-z0-9])`, "g");
}

/**
 * Renames the bundle's hashed files and rewrites every reference to them. Returns the map from each old path to its new
 * one, and the number of bytes of the hashed files.
 */
export function hashBundle(bundleDirectory) {
  const root = resolve(bundleDirectory);
  if (!existsSync(join(root, PAGE))) throw new Error(`no ${PAGE} in ${root}`);
  const files = listFiles(root);
  const hashed = files.filter(isHashedFile);
  for (const relativePath of hashed) {
    if (HASHED_NAME.test(basename(relativePath))) {
      throw new Error(`${relativePath} already has a content-hashed name: ${root} was hashed before`);
    }
  }
  const matcher = referenceMatcher(hashed);
  const hashedSet = new Set(hashed);
  const names = new Map();
  const contents = new Map();
  const visiting = new Set();

  // The bytes of `relativePath` with its references replaced, computed after the files it references.
  const finalize = (relativePath) => {
    if (names.has(relativePath)) return names.get(relativePath);
    if (visiting.has(relativePath)) throw new Error(`${relativePath} references itself through a cycle of hashed files`);
    visiting.add(relativePath);
    const original = readFileSync(join(root, relativePath));
    const extension = extname(relativePath);
    let bytes = original;
    if (TEXT_EXTENSIONS.has(extension)) {
      bytes = Buffer.from(rewriteReferences(original.toString("utf8"), relativePath), "utf8");
    }
    const hash = createHash("sha256").update(bytes).digest("hex").slice(0, HASH_LENGTH);
    const name = hashedName(relativePath, hash);
    names.set(relativePath, name);
    contents.set(relativePath, bytes);
    visiting.delete(relativePath);
    return name;
  };

  const rewriteReferences = (text, owner) => {
    if (!matcher) return text;
    return text.replace(matcher, (reference) => {
      if (reference === owner) throw new Error(`${owner} references itself`);
      return hashedSet.has(reference) ? finalize(reference) : reference;
    });
  };

  for (const relativePath of hashed) finalize(relativePath);

  // The page and the runtime environment keep their names; they are rewritten with the final names.
  const kept = [PAGE, ENVIRONMENT].filter((relativePath) => files.includes(relativePath));
  const keptText = new Map();
  for (const relativePath of kept) {
    keptText.set(relativePath, rewriteReferences(readFileSync(join(root, relativePath), "utf8"), relativePath));
  }

  let bytes = 0;
  for (const relativePath of hashed) {
    const target = join(root, names.get(relativePath));
    if (existsSync(target)) throw new Error(`${names.get(relativePath)} already exists in ${root}`);
    writeFileSync(target, contents.get(relativePath));
    bytes += contents.get(relativePath).length;
  }
  for (const relativePath of hashed) rmSync(join(root, relativePath));
  for (const [relativePath, text] of keptText) writeFileSync(join(root, relativePath), text);

  const renamed = new Map(hashed.map((relativePath) => [relativePath, names.get(relativePath)]));
  return { renamed, bytes };
}

export function main(argv = process.argv.slice(2)) {
  if (argv.length !== 1) {
    console.error("usage: hash-release-bundle.mjs <bundle-directory>");
    return 2;
  }
  const { renamed, bytes } = hashBundle(argv[0]);
  console.log(`hashed ${renamed.size} files (${bytes} bytes) in ${resolve(argv[0])}`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main();
}
