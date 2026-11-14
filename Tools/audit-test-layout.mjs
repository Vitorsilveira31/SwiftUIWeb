#!/usr/bin/env bun
// Enforces the repository's Sources/Examples/Tests boundary (executables live in Examples/ or, as test apps, in Tests/Apps/).
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { compareStrings, fromRoot, isMain, jsonDumps, readText, ROOT, rx } from "./audit-support.mjs";

const GENERATED_DIRECTORIES = new Set([".build", ".git", ".swiftpm", "node_modules"]);

/** Enumerates project Swift sources without descending into generated trees. */
export function swiftSources(root) {
  const found = [];
  const walk = (directory) => {
    const entries = readdirSync(directory, { withFileTypes: true });
    const names = entries.filter((entry) => entry.isDirectory() && !GENERATED_DIRECTORIES.has(entry.name)).map((entry) => entry.name).sort(compareStrings);
    for (const entry of entries.filter((item) => !item.isDirectory()).sort((a, b) => compareStrings(a.name, b.name))) {
      if (entry.name.endsWith(".swift")) found.push(join(directory, entry.name));
    }
    for (const name of names) walk(join(directory, name));
  };
  if (existsSync(root)) walk(root);
  return found;
}

const importsXCTest = (path) => rx(String.raw`^\s*import\s+XCTest\b`, "m").test(readText(path));

export function audit() {
  const packageText = readText(join(ROOT, "Package.swift"));
  const checks = [];
  const check = (name, passed, detail) => checks.push({ name, status: passed ? "PASS" : "FAIL", detail });

  const targetPaths = (kind) => [...packageText.matchAll(
    rx(String.raw`\.${kind}\((?:(?!\.testTarget|\.executableTarget).){0,3000}?path:\s*"([^"]+)"`, "gs"),
  )].map((match) => match[1]);
  const testPaths = targetPaths("testTarget");
  const executablePaths = targetPaths("executableTarget");
  const badTests = testPaths.filter((path) => !path.startsWith("Tests/"));
  const badExecutables = executablePaths.filter((path) => !path.startsWith("Examples/") && !path.startsWith("Tests/Apps/"));
  check("test-targets-live-under-tests", badTests.length === 0, badTests);
  check("executable-targets-live-under-examples-or-test-apps", badExecutables.length === 0, badExecutables);

  const exampleTestImports = [...swiftSources(join(ROOT, "Examples")), ...swiftSources(join(ROOT, "Tests", "Apps"))].filter(importsXCTest).map(fromRoot);
  check("examples-do-not-import-xctest", exampleTestImports.length === 0, exampleTestImports);

  const legacySwiftTestImports = testPaths.flatMap((target) => swiftSources(join(ROOT, target))).filter(importsXCTest).map(fromRoot);
  check("swift-tests-use-swift-testing", legacySwiftTestImports.length === 0, legacySwiftTestImports);

  const staleFixtureRoots = [join(ROOT, "Tests", "BrowserFixtures", "Sources")].filter(existsSync).map(fromRoot);
  check("no-redundant-browser-fixture-source-root", staleFixtureRoots.length === 0, staleFixtureRoots);

  return { status: checks.every((item) => item.status === "PASS") ? "PASS" : "FAIL", checks };
}

if (isMain(import.meta.url)) {
  const result = audit();
  console.log(jsonDumps(result));
  process.exit(result.status === "PASS" ? 0 : 1);
}
