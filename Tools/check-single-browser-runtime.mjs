#!/usr/bin/env bun
// Fails when a second browser runtime (JavaScriptKit, PackageToJS, a runtime-selection switch) comes back into the
// package, the sources, the Makefile, CI or the tools, or when the Embedded lowering infrastructure goes missing.
import { existsSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { fromRoot, readText, readTextLossy, ROOT, walkFiles } from "./audit-support.mjs";

// The audits themselves name the forbidden words.
const EXEMPT = new Set([
  "check-single-browser-runtime.mjs", "architecture-audit.mjs",
  "check-architecture-invariants.js", "test-single-browser-runtime.mjs", "wasm-audit.mjs",
]);
const FORBIDDEN = ["JavaScriptKit", "JavaScriptEventLoop", "PackageToJS", "SwiftUIWebWASIExample", "WASM_MODE", "build-wasm.sh", "wasi-smoke.sh"];
const isFile = (path) => existsSync(path) && statSync(path).isFile();

const violations = [];
for (const name of ["Package.swift", "Sources", "Makefile", ".github", "Tools"]) {
  const base = join(ROOT, name);
  let files;
  if (isFile(base)) files = [base];
  // Tools/SwiftUIWebLowering is a package of its own; its build folder (swift-syntax) is not the repository's code.
  else if (name === "Tools") files = walkFiles(base, (folder) => folder === ".build");
  else files = walkFiles(base).filter((path) => path.endsWith(".swift"));
  files = files.filter((path) => !EXEMPT.has(path.split("/").pop()));
  for (const path of files) {
    const text = readTextLossy(path);
    for (const forbidden of FORBIDDEN) if (text.includes(forbidden)) violations.push(`${fromRoot(path)}: contains ${forbidden}`);
  }
}
// The package URL/dependency is a hard failure too.
for (const script of ["run-browser.sh", "run-browser-embedded.sh"]) {
  const text = readText(join(ROOT, "Tools", script));
  if (text.includes("run-browser-v45") || text.includes("WASM_MODE")) violations.push(`Tools/${script}: runtime-selection reference`);
}
// Embedded lowering is current production infrastructure, not an optional historical runner. The production path is the
// cached Swift executable (Tools/SwiftUIWebLowering, built by Tools/swiftuiweb-lowering.sh).
const lowerer = join(ROOT, "Tools", "swiftuiweb-lowering.sh");
const manifest = join(ROOT, "Tools", "SwiftUIWebLowering", "Package.swift");
const lowererSources = join(ROOT, "Tools", "SwiftUIWebLowering", "Sources", "LoweringCore");
if (!isFile(lowerer) || !isFile(manifest) || !existsSync(lowererSources)) violations.push("Tools/SwiftUIWebLowering: required Swift lowerer missing");
else {
  readText(lowerer);
  const lowererText = readdirSync(lowererSources).filter((name) => name.endsWith(".swift")).sort()
    .map((name) => readText(join(lowererSources, name))).join("\n");
  const requiredRules = [
    "keyframe-track", "environment-member", "environment-modifier", "outline-children", "foreach-id-member", "foreach-id-self",
    "map-member", "binding-member", "table-column-value", "transfer-error-interpolation", "export-error-interpolation",
    "browser-reactor-entry-and-html-exports", "browser-reactor-linker-exports",
  ];
  for (const rule of requiredRules) {
    if (!lowererText.includes(rule)) violations.push(`embedded lowerer: missing rule ${rule}`);
  }
  const launcher = readText(join(ROOT, "Tools", "run-browser-embedded.sh"));
  if (!launcher.includes("swiftuiweb-lowering.sh") || !launcher.includes("--workspace")) {
    violations.push("run-browser-embedded.sh: canonical build does not use the lowerer/workspace");
  }
}
const fixture = join(ROOT, "Tests", "Apps", "EmbeddedLoweringConformanceApp", "main.swift");
if (!isFile(fixture)) violations.push("EmbeddedLoweringConformanceApp: independent lowering fixture missing");
else if (!["\\.id", "\\.self", "KeyframeTrack(\\."].some((token) => readText(fixture).includes(token))) {
  violations.push("EmbeddedLoweringConformanceApp: normal KeyPath syntax fixture missing");
}
if (violations.length > 0) {
  console.log("Single browser runtime audit: FAIL");
  console.log(violations.join("\n"));
  process.exit(1);
}
console.log("Single browser runtime audit: PASS");
console.log("Browser runtime: Embedded Swift + BrowserIO only");
