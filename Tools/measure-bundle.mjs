#!/usr/bin/env bun
// Inventory final local deployment files with raw/gzip/Brotli byte counts.
//
// This is not an HTTP transfer trace, retained-symbol attribution, or the size of an entire language runtime.
// Remote dependencies are not counted as zero bytes.
import { createHash } from "node:crypto";
import { lstatSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { brotliCompressSync, constants, gzipSync } from "node:zlib";
import { dumps, parseArguments, resolveReal, rglob } from "./format-compat.mjs";

const DESCRIPTION = `Inventory final local deployment files with raw/gzip/Brotli byte counts.

This is not an HTTP transfer trace, retained-symbol attribution, or the size of an entire language runtime.
Remote dependencies are not counted as zero bytes.`;

/** `Path.suffix`. */
const suffixOf = (name) => {
  const dot = name.lastIndexOf(".");
  return dot <= 0 || dot === name.length - 1 ? "" : name.slice(dot);
};

const isFile = (path) => {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
};
const isSymlink = (path) => lstatSync(path).isSymbolicLink();
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

export function compress(raw, quality) {
  return {
    raw: raw.length,
    gzip: gzipSync(raw, { level: 9 }).length,
    brotli: brotliCompressSync(raw, { params: { [constants.BROTLI_PARAM_QUALITY]: quality, [constants.BROTLI_PARAM_MODE]: constants.BROTLI_MODE_GENERIC } }).length,
  };
}

/** Build the inventory; returns `{ result, rows, groups, total }` or throws `Error` for an unusable bundle. */
export function inventory(bundle, { output = null, brotliQuality = 11 } = {}) {
  const root = resolveReal(bundle);
  if (!statSync(root).isDirectory()) throw new Error(`bundle directory does not exist: ${root}. Build the browser app first.`);
  const entries = rglob(root);
  if (!entries.some((entry) => basename(entry).endsWith(".wasm"))) {
    throw new Error("no final .wasm found. The app build may have failed before packaging. Run make browser-release EXAMPLE=showcase and inspect its first compiler error; static archives are not apps.");
  }
  const ignored = [];
  const rows = [];
  const externals = new Set();
  const groups = {};
  const reportPath = output === null ? null : resolveReal(output);
  for (const relativePath of entries) {
    const path = join(root, relativePath);
    if (!isFile(path)) continue;
    const name = basename(relativePath);
    const suffix = suffixOf(name);
    if (
      isSymlink(path) || path === reportPath || relativePath.split("/").some((part) => part.startsWith(".")) || name === "release-size.json" ||
      [".map", ".a", ".o", ".rlib", ".gz", ".br", ".dcb"].includes(suffix) || [".size.json", ".data.json", ".objects.json"].some((ending) => name.endsWith(ending))
    ) {
      ignored.push(relativePath);
      continue;
    }
    const raw = readFileSync(path);
    const kind = suffix === ".wasm" ? "wasm" : [".js", ".mjs", ".cjs"].includes(suffix) ? "javascript" : suffix === ".css" ? "css" : suffix === ".html" ? "html" : "other";
    const sizes = compress(raw, brotliQuality);
    rows.push({ path: relativePath, group: kind, bytes: sizes, sha256: sha256(raw) });
    const totals = (groups[kind] ??= { raw: 0, gzip: 0, brotli: 0 });
    for (const [key, value] of Object.entries(sizes)) totals[key] += value;
    if ([".js", ".mjs", ".html", ".json", ".css"].includes(suffix)) {
      for (const match of new TextDecoder().decode(raw).matchAll(/https?:\/\/[^\s'"<>`\\)]+/g)) externals.add(match[0]);
    }
  }
  if (!rows.some((row) => row.group === "wasm")) throw new Error("no final .wasm among deployable files; hidden caches and symlinks are not a bundle");
  const total = Object.fromEntries(["raw", "gzip", "brotli"].map((key) => [key, rows.reduce((sum, row) => sum + row.bytes[key], 0)]));
  const result = {
    scope: "LOCAL_FILE_INVENTORY_NOT_HTTP_TRANSFER",
    directory: root,
    files: rows,
    groups,
    total_local_assets: total,
    tool_versions: { bun: Bun.version, brotli: "node:zlib" },
    compression: { gzip_level: 9, gzip_mtime: 0, brotli_quality: brotliQuality, brotli_mode: "generic" },
    excluded_files: ignored,
    external_url_candidates: [...externals].sort(),
    complete_network_transfer_known: false,
    note: "All included files count, including lazy local assets. Remote imports/assets are NOT fetched by this script. Archive bytes cannot be subtracted from compressed Wasm to infer runtime size.",
  };
  return { result, rows, groups, total, reportPath };
}

export function main(argv) {
  const args = parseArguments({
    prog: "measure-bundle.mjs",
    description: DESCRIPTION,
    options: [
      { names: ["--output"], dest: "output", type: "string", help: "Optional JSON report, preferably outside the measured directory" },
      { names: ["--brotli-quality"], dest: "brotliQuality", type: "int", default: 11, choices: Array.from({ length: 12 }, (_, index) => index) },
    ],
    positionals: [{ name: "bundle" }],
  }, argv);
  if (!args.bundle.trim()) args.fail("provide BUNDLE=.build/browser/ShowcaseApp");
  let built;
  try {
    built = inventory(args.bundle, { output: args.output ?? null, brotliQuality: args.brotliQuality });
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "ENOTDIR") args.fail(`bundle directory does not exist: ${resolveReal(args.bundle)}. Build the browser app first.`);
    args.fail(error.message);
  }
  const { result, rows, groups, total, reportPath } = built;
  console.log(`${"file".padEnd(62)} ${"raw B".padStart(12)} ${"gzip B".padStart(12)} ${"Brotli B".padStart(12)}`);
  for (const row of rows) console.log(`${row.path.padEnd(62)} ${String(row.bytes.raw).padStart(12)} ${String(row.bytes.gzip).padStart(12)} ${String(row.bytes.brotli).padStart(12)}`);
  console.log("\nGroups:", dumps(groups, { ensureAscii: false }));
  console.log("Total local files:", dumps(total));
  console.log("No HTTP/network transfer was measured. Check external_url_candidates in the JSON report.");
  if (reportPath) {
    mkdirSync(dirname(reportPath), { recursive: true });
    writeFileSync(reportPath, `${dumps(result, { indent: 2 })}\n`);
    console.log("JSON:", reportPath);
  }
  return 0;
}

if (import.meta.main) process.exit(main(process.argv.slice(2)));
