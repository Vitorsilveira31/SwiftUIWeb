#!/usr/bin/env bun
// Audits the consolidated Swift -> Fiber -> BrowserIO architecture.
//
// This is intentionally a structural audit, not a replacement for the runtime and browser gates. It reports inventory/size
// evidence and fails when the removed standard/JavaScript bridge or runtime-selection knobs reappear.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { gzipSync } from "node:zlib";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import {
  filesWithSuffix, isMain, jsonDumps, readText, readTextLossy, ROOT, rx, splitlines, suffixOf, walkFiles,
} from "./audit-support.mjs";

const BUILD = join(ROOT, ".build", "architecture-audit");
const BASELINE = {
  trackedFiles: 772,
  swift: { files: 196, loc: 49112 },
  javascript: { files: 69, loc: 10593 },
  documentation: { files: 278, loc: 49233 },
  packageTargets: 40,
  packageProducts: 27,
};

const isFile = (path) => existsSync(path) && statSync(path).isFile();

function tracked() {
  const result = spawnSync("git", ["ls-files"], { cwd: ROOT, encoding: "utf8", maxBuffer: 1 << 28 });
  if (result.status !== 0) throw new Error(`git ls-files failed: ${result.stderr}`);
  return splitlines(result.stdout).map((path) => join(ROOT, path));
}

function inventory(files) {
  const groups = {
    swift: new Set([".swift"]),
    javascript: new Set([".js", ".mjs", ".ts"]),
    documentation: new Set([".md"]),
  };
  const result = { trackedFiles: files.length };
  for (const [name, suffixes] of Object.entries(groups)) {
    const selected = files.filter((path) => suffixes.has(suffixOf(path)) && isFile(path));
    result[name] = { files: selected.length, loc: selected.reduce((sum, path) => sum + splitlines(readTextLossy(path)).length, 0) };
  }
  return result;
}

function packageMetrics() {
  const text = readText(join(ROOT, "Package.swift"));
  const count = (pattern) => [...text.matchAll(rx(pattern, "g"))].length;
  return {
    packageTargets: count(String.raw`\.(?:target|executableTarget|testTarget|systemLibrary)\(name:`),
    packageProducts: count(String.raw`\.(?:library|executable)\(name:`),
  };
}

function bundleMetrics() {
  const bundle = join(ROOT, ".build", "browser", "ShowcaseApp");
  if (!existsSync(bundle) || !statSync(bundle).isDirectory()) return { status: "unavailable", bundle };
  const files = walkFiles(bundle);
  const total = (suffixes) => files.filter((path) => suffixes.includes(suffixOf(path))).reduce((sum, path) => sum + statSync(path).size, 0);
  const initialJs = total([".js", ".mjs"]);
  const css = total([".css"]);
  const wasm = bundleFilePath(bundle, "app.wasm") ?? join(bundle, "app.wasm");
  if (!isFile(wasm)) return { status: "incomplete", bundle, initialJavascriptRaw: initialJs, initialCssRaw: css };
  const payload = readFileSync(wasm);
  const run = spawnSync("brotli", ["-q", "11", "-c"], { input: payload, maxBuffer: 1 << 30 });
  const brotli = run.error || run.status !== 0 ? Buffer.alloc(0) : run.stdout;
  // Bun's own zlib compresses level 9 a little differently from the reference zlib; the system `gzip -9 -n` (header without
  // name or time) writes the stream the golden records for compresslevel 9 and mtime 0.
  const gzip = spawnSync("gzip", ["-9", "-n", "-c"], { input: payload, maxBuffer: 1 << 30 });
  const gzipSize = gzip.error || gzip.status !== 0 ? gzipSync(payload, { level: 9 }).length : gzip.stdout.length;
  return {
    status: "ready",
    bundle,
    wasmRaw: payload.length,
    wasmGzip: gzipSize,
    wasmBrotli: brotli.length > 0 ? brotli.length : null,
    initialJavascriptRaw: initialJs,
    initialCssRaw: css,
    fileCount: files.length,
  };
}

function checks() {
  const packageText = readText(join(ROOT, "Package.swift"));
  const makefile = readText(join(ROOT, "Makefile"));
  const sources = filesWithSuffix(join(ROOT, "Sources"), ".swift").map((path) => readTextLossy(path)).join("\n");
  const launcher = readText(join(ROOT, "Tools", "run-browser.sh"));
  const browserTarget = rx(
    String.raw`\.target\(name: "SwiftUIWebBrowser".*?(?=\n    \.target\(|\n    \.executableTarget\(|\n    \.testTarget\()`,
    "s",
  ).exec(packageText);
  const browserTargetText = browserTarget ? browserTarget[0] : "";
  const hasAny = (text, tokens) => tokens.some((token) => text.includes(token));
  const values = [
    ["static-browserio-target", packageText.includes('name: "SwiftUIWebBrowserIO"') && packageText.includes('name: "CSwiftUIWebBrowserIO"')],
    ["browserio-is-a-browser-dependency", browserTargetText.includes('"SwiftUIWebBrowserIO"')],
    ["no-dynamic-browserio-target-mutation", !packageText.includes("package.targets.append") && !packageText.includes("package.products.append")],
    ["no-production-js-bridge", !hasAny(packageText + sources, ["JavaScriptKit", "JavaScriptEventLoop", "PackageToJS"])],
    ["embedded-launcher-is-authoritative", launcher.includes("run-browser-embedded.sh") && !launcher.includes("WASM_MODE")],
    ["no-standard-production-targets", !hasAny(packageText + makefile, ["SwiftUIWebWASIExample", "WASM_MODE", "build-wasm.sh", "PackageToJS", "JavaScriptKit"])],
    ["single-browserio-audit-script", isFile(join(ROOT, "Tools/check-single-browser-runtime.mjs"))],
  ];
  return values.map(([name, passed]) => ({ name, status: passed ? "PASS" : "FAIL" }));
}

/** Writes the `{'files': n, 'loc': n}` dictionaries the markdown table prints, in that form. */
const dictRepr = (value) =>
  typeof value === "object" ? `{${Object.entries(value).map(([key, item]) => `'${key}': ${item}`).join(", ")}}` : String(value);

function main() {
  mkdirSync(BUILD, { recursive: true });
  const files = tracked();
  const current = { ...inventory(files), ...packageMetrics() };
  const allChecks = checks();
  const deltas = {};
  for (const key of Object.keys(BASELINE)) if (Number.isInteger(current[key])) deltas[key] = current[key] - BASELINE[key];
  for (const key of ["swift", "javascript", "documentation"]) {
    deltas[key] = { files: current[key].files - BASELINE[key].files, loc: current[key].loc - BASELINE[key].loc };
  }
  const report = {
    schemaVersion: 1,
    status: allChecks.every((item) => item.status === "PASS") ? "PASS" : "FAIL",
    architecture: "Swift semantics -> Fiber identity -> CSS layout -> BrowserIO -> native browser",
    baseline: BASELINE,
    current,
    deltas,
    bundle: bundleMetrics(),
    checks: checks(),
  };
  writeFileSync(join(BUILD, "report.json"), jsonDumps(report) + "\n");
  const lines = [
    "# Architecture audit",
    "",
    `Status: **${report.status}**`,
    "",
    "Authoritative path: Swift semantics → Fiber identity → CSS layout → BrowserIO → native browser primitives.",
    "",
    "## Inventory",
    "",
    "| Metric | Before | Current | Delta |",
    "| --- | ---: | ---: | ---: |",
  ];
  for (const [key, before] of Object.entries(BASELINE)) {
    const value = key in current ? current[key] : "n/a";
    const delta = Number.isInteger(value) ? value - before : "n/a";
    lines.push(`| ${key} | ${dictRepr(before)} | ${dictRepr(value)} | ${delta} |`);
  }
  lines.push("", "## Runtime artifact", "", "```json", jsonDumps(report.bundle), "```", "", "## Checks", "");
  for (const item of report.checks) lines.push(`- \`${item.name}\`: ${item.status}`);
  lines.push("", "No alternate browser runtime or compatibility fixture lane is retained; browser execution is Embedded Swift through BrowserIO.", "");
  writeFileSync(join(BUILD, "report.md"), lines.join("\n"));
  console.log(jsonDumps(report));
  return report.status === "PASS" ? 0 : 1;
}

if (isMain(import.meta.url)) process.exit(main());
