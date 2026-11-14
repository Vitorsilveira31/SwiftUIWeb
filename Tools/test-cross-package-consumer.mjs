#!/usr/bin/env bun
// Compile an application-shaped package against this checkout, as an application would.
//
// Applications are separate SwiftPM packages that depend on SwiftUIWeb and alias `SwiftUI` to it. Declarations that
// compile inside SwiftUIWeb's own package can still be invisible to them (package access, a missing SPI, a stand-in
// that Apple does not export). This test catches those:
//
// 1. `Tests/CrossPackage/Source` is Apple-shaped application source plus string catalogs.
// 2. The production Embedded lowerer (`Tools/swiftuiweb-lowering.sh`) lowers the sources, as the browser build does.
// 3. `Tools/compile-strings.mjs` generates the translation table, as the browser build does.
// 4. The lowered and generated sources are compiled natively in a fresh consumer package under `.build/`, which depends
//    on this checkout by path and aliases `SwiftUI` to `SwiftUIWeb` and `Foundation` to `WebFoundation` (`-module-alias`), as the browser build does.
//
// The lowered output must keep the Renderer-SPI spellings the lowerer emits, so those are checked too.
import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(realpathSync(fileURLToPath(import.meta.url))), "..");
const SOURCE = join(ROOT, "Tests", "CrossPackage", "Source");
const WORK = join(ROOT, ".build", "cross-package");
const LOWERER = join(ROOT, "Tools", "swiftuiweb-lowering.sh");
const COMPILE_STRINGS = join(ROOT, "Tools", "compile-strings.mjs");
const TARGET = "Consumer";

function run(command, env = undefined) {
  const result = spawnSync(command[0], command.slice(1), {
    cwd: ROOT,
    encoding: "utf8",
    env,
  });
  if (result.error) throw result.error;
  return { returncode: result.status, stdout: result.stdout, stderr: result.stderr };
}

// The application aliases SwiftUI to SwiftUIWeb (`-module-alias`), so the lowerer spells its injected imports SwiftUI.
const ALIASED = { ...process.env, SWIFTUIWEB_MODULE_ALIASES: "1" };

function swiftFiles(directory) {
  return readdirSync(directory)
    .filter((name) => name.endsWith(".swift"))
    .sort()
    .map((name) => join(directory, name));
}

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

// Lowers the application sources; returns the lowered target directory.
function lower(workspace) {
  const folder = mkdtempSync(join(tmpdir(), "cross-package-"));
  try {
    const sourceRoot = join(folder, "source");
    mkdirSync(sourceRoot, { recursive: true });
    cpSync(join(SOURCE, "Sources"), join(sourceRoot, "Sources"), { recursive: true, dereference: true });
    const scratch = join(folder, "workspace");
    const result = run(
      [
        LOWERER,
        "--apply",
        "--root",
        sourceRoot,
        "--product",
        TARGET,
        "--workspace",
        scratch,
        "--lower-codable",
      ],
      ALIASED,
    );
    if (result.returncode !== 0) {
      throw new Error(`lowering failed:\n${result.stdout}\n${result.stderr}`);
    }
    let report = JSON.parse(result.stdout || "{}");
    const metadata = join(sourceRoot, ".build/embedded-source-lowering/report.json");
    if (existsSync(metadata)) report = JSON.parse(readFileSync(metadata, "utf8"));
    const lowered = join(scratch, "Sources", TARGET);
    if (!isDirectory(lowered)) {
      throw new Error(`lowering produced no sources at ${lowered}`);
    }
    const target = join(workspace, "Sources", TARGET);
    mkdirSync(dirname(target), { recursive: true });
    cpSync(lowered, target, { recursive: true, dereference: true });
    return { target, report };
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
}

function checkLoweredSpellings(target) {
  const text = swiftFiles(target)
    .map((path) => readFileSync(path, "utf8"))
    .join("\n");
  const required = [
    '.modifier(EnvironmentOverride(apply: { $0.titleStyle = "bold" }))',
    // Embedded Swift cannot compare key paths, so a `\.colorScheme` write gets its own spelling that marks the subtree.
    ".modifier(EnvironmentOverride(colorScheme: .dark))",
    ".modifier(EnvironmentOverride(colorScheme: isDark ? .dark : .light))",
    "@_spi(Renderer) import SwiftUI",
  ];
  const missing = required.filter((needle) => !text.includes(needle));
  if (missing.length > 0) {
    throw new Error("lowered sources lost expected spellings:\n  " + missing.join("\n  "));
  }
}

function generateStrings(target) {
  const output = join(target, "Generated", "LocalizedStrings.generated.swift");
  mkdirSync(dirname(output), { recursive: true });
  // This runs the same Bun that runs this test.
  const result = run([
    process.execPath,
    COMPILE_STRINGS,
    join(SOURCE, "Resources"),
    "-o",
    output,
    "--module",
    "SwiftUI",
  ]);
  if (result.returncode !== 0) {
    throw new Error(`compile-strings failed:\n${result.stdout}\n${result.stderr}`);
  }
}

function writePackage(workspace) {
  const manifest = join(workspace, "Package.swift");
  writeFileSync(
    manifest,
    `// swift-tools-version: 6.4
// Generated by Tools/test-cross-package-consumer.mjs. Depends on the checkout by path, as an application does.
import PackageDescription

let package = Package(
  name: "CrossPackageConsumer",
  platforms: [.macOS(.v15)],
  dependencies: [.package(name: "swiftuiweb", path: ${JSON.stringify(ROOT)})],
  targets: [
    .target(
      name: "${TARGET}",
      dependencies: [.product(name: "SwiftUIWeb", package: "swiftuiweb")],
      path: "Sources/${TARGET}",
      swiftSettings: [
        .define("WEB"),
        .unsafeFlags(["-module-alias", "SwiftUI=SwiftUIWeb", "-module-alias", "Foundation=WebFoundation"]),
        .swiftLanguageMode(.v5)
      ]
    )
  ]
)
`,
  );
  return manifest;
}

function main() {
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(WORK, { recursive: true });
  const { target, report } = lower(WORK);
  checkLoweredSpellings(target);
  generateStrings(target);
  const manifest = writePackage(WORK);
  const result = run(["swift", "build", "--package-path", dirname(manifest)]);
  if (result.returncode !== 0) {
    process.stderr.write(result.stdout.slice(-4000) + "\n" + result.stderr.slice(-8000));
    console.error("cross-package consumer FAILED to compile");
    return 1;
  }
  const rules = Object.keys(report.rules ?? {}).sort();
  console.log(
    `cross-package consumer compiled: ${swiftFiles(target).length} lowered files, ` +
      `rules: ${rules.join(", ") || "none reported"}`,
  );
  return 0;
}

try {
  process.exitCode = main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
