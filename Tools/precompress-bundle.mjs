#!/usr/bin/env bun
// Writes precompressed copies beside the text and wasm files of a release browser bundle: `<name>.br` (brotli, quality
// 11) and `<name>.gz` (gzip, level 9). Tools/bun-server.ts sends them, with Content-Encoding, to clients that accept the
// coding, so a bundle does not have to be compressed on each request.
//
// Only files of at least 1 KB that come out smaller are written. Already compressed formats (web fonts, images) get no
// copy, and neither do the copies themselves. Run it last, after Tools/seal-csp.mjs, so the copies hold the final bytes.
//
// usage: precompress-bundle.mjs <bundle-directory>
// Run the tests with: bun test ./Tools/test-precompress-bundle.mjs

import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { brotliCompressSync, constants, gzipSync } from "node:zlib";

export const MIN_BYTES = 1024;
const TEXT_EXTENSIONS = new Set([".html", ".js", ".mjs", ".css", ".json", ".svg", ".txt"]);
const COMPRESSIBLE_EXTENSIONS = new Set([...TEXT_EXTENSIONS, ".wasm"]);
const PRECOMPRESSED_EXTENSIONS = new Set([".br", ".gz"]);

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

export function brotli(bytes, extension) {
  return brotliCompressSync(bytes, {
    params: {
      [constants.BROTLI_PARAM_QUALITY]: 11,
      [constants.BROTLI_PARAM_LGWIN]: 24,
      [constants.BROTLI_PARAM_SIZE_HINT]: bytes.length,
      [constants.BROTLI_PARAM_MODE]: TEXT_EXTENSIONS.has(extension) ? constants.BROTLI_MODE_TEXT : constants.BROTLI_MODE_GENERIC,
    },
  });
}

export function gzip(bytes) {
  return gzipSync(bytes, { level: 9 });
}

/** Writes the copies and returns, per file, the sizes written: `[relativePath, original, br, gz]`. */
export function precompressBundle(bundleDirectory) {
  const root = resolve(bundleDirectory);
  const report = [];
  for (const relativePath of listFiles(root)) {
    const extension = extname(relativePath);
    if (!COMPRESSIBLE_EXTENSIONS.has(extension) || PRECOMPRESSED_EXTENSIONS.has(extension)) continue;
    const bytes = readFileSync(join(root, relativePath));
    if (bytes.length < MIN_BYTES) continue;
    const br = brotli(bytes, extension);
    const gz = gzip(bytes);
    const brotliWritten = br.length < bytes.length;
    const gzipWritten = gz.length < bytes.length;
    if (brotliWritten) writeFileSync(join(root, `${relativePath}.br`), br);
    if (gzipWritten) writeFileSync(join(root, `${relativePath}.gz`), gz);
    if (brotliWritten || gzipWritten) {
      report.push([relativePath, bytes.length, brotliWritten ? br.length : null, gzipWritten ? gz.length : null]);
    }
  }
  return report;
}

export function main(argv = process.argv.slice(2)) {
  if (argv.length !== 1) {
    console.error("usage: precompress-bundle.mjs <bundle-directory>");
    return 2;
  }
  const report = precompressBundle(argv[0]);
  for (const [relativePath, original, br, gz] of report) {
    console.log(`${relativePath}: ${original} bytes, br ${br ?? "-"}, gzip ${gz ?? "-"}`);
  }
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main();
}
