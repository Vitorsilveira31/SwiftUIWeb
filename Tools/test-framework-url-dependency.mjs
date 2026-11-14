// Run: bun test ./Tools/test-framework-url-dependency.mjs
// Covers the URL form of the SwiftUIWeb dependency in a consumer manifest: detection, the nested requirement, comments and
// strings, other URL dependencies left alone, the rewrite to a relative path in the staged copy, and the launcher refusing
// the in-place mode for it.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { frameworkURLDependencies, isFrameworkURL, rewriteManifest } from "./framework-url-dependency.mjs";

const TOOLS = dirname(fileURLToPath(import.meta.url));
const SCRIPT = join(TOOLS, "framework-url-dependency.mjs");
const LAUNCHER = join(TOOLS, "run-browser-embedded.sh");

test("the framework is recognised by the last component of its URL", () => {
  assert.equal(isFrameworkURL("git@github.com:Vitorsilveira31/swiftuiweb.git"), true);
  assert.equal(isFrameworkURL("https://github.com/Vitorsilveira31/SwiftUIWeb/"), true);
  assert.equal(isFrameworkURL("https://github.com/apple/swift-crypto.git"), false);
  assert.equal(isFrameworkURL("https://github.com/Vitorsilveira31/swiftuiweb-tools.git"), false);
});

test("only the SwiftUIWeb URL dependency is rewritten, including a nested requirement", () => {
  const manifest = [
    "dependencies: [",
    '  .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1"),',
    '  .package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", .upToNextMajor(from: "0.1.0")),',
    '  .package(path: "../Modules")',
    "]",
  ].join("\n");
  assert.equal(frameworkURLDependencies(manifest).length, 1);
  assert.equal(
    rewriteManifest(manifest, "/s/consumer", "/s/swiftuiweb"),
    manifest.replace('.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", .upToNextMajor(from: "0.1.0"))', '.package(path: "../swiftuiweb")'),
  );
});

test("a commented-out declaration and a path dependency are left alone", () => {
  const manifest = '// .package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0")\n.package(path: "../../swiftuiweb")\n';
  assert.deepEqual(frameworkURLDependencies(manifest), []);
  assert.equal(rewriteManifest(manifest, "/s/a/consumer", "/s/swiftuiweb"), manifest);
});

test("a URL with // on the same line does not hide the SwiftUIWeb declaration", () => {
  const manifest =
    '.package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1"), .package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0"),\n';
  assert.equal(frameworkURLDependencies(manifest).length, 1);
  assert.equal(
    rewriteManifest(manifest, "/s/consumer", "/s/swiftuiweb"),
    '.package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1"), .package(path: "../swiftuiweb"),\n',
  );
});

test("comments and strings are not code: block, nested, trailing and quoted declarations are skipped", () => {
  const declaration = '.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0")';
  for (const manifest of [
    `/* ${declaration} */`,
    `/* outer /* inner */ ${declaration} */`,
    `let a = 1 // ${declaration}`,
    `let s = "${declaration.replaceAll('"', '\\"')}"`,
    `let raw = #"${declaration}"#`,
    `let many = """\n${declaration}\n"""`,
  ]) {
    assert.deepEqual(frameworkURLDependencies(manifest), [], manifest);
  }
  assert.equal(frameworkURLDependencies(`/* note */ ${declaration}`).length, 1);
});

test("has and rewrite work on a manifest file", () => {
  const root = mkdtempSync(join(tmpdir(), "swui-fud-"));
  try {
    mkdirSync(join(root, "level0", "consumer"), { recursive: true });
    const file = join(root, "level0", "consumer", "Package.swift");
    writeFileSync(file, 'let d = [.package(url: "https://github.com/Vitorsilveira31/swiftuiweb.git", from: "0.1.0")]\n');
    assert.equal(spawnSync(process.execPath, [SCRIPT, "has", file]).status, 0);
    const result = spawnSync(process.execPath, [SCRIPT, "rewrite", file, join(root, "swiftuiweb")], { encoding: "utf8" });
    assert.equal(result.status, 0);
    assert.equal(result.stdout.trim(), file);
    assert.equal(readFileSync(file, "utf8"), 'let d = [.package(path: "../../swiftuiweb")]\n');
    assert.equal(spawnSync(process.execPath, [SCRIPT, "has", file]).status, 1);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("a declaration after a trailing // comment on the previous declaration is found", () => {
  const manifest = [
    '.package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1"), // see https://example.com/pin',
    '.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0"),',
    "",
  ].join("\n");
  assert.equal(frameworkURLDependencies(manifest).length, 1);
  assert.equal(
    rewriteManifest(manifest, "/s/consumer", "/s/swiftuiweb"),
    manifest.replace('.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0")', '.package(path: "../swiftuiweb")'),
  );
});

test("a string that holds // and /* does not turn the rest of the manifest into a comment", () => {
  const manifest = [
    'let note = "see https://example.com and /* not a comment"',
    '.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0"),',
    "",
  ].join("\n");
  assert.equal(frameworkURLDependencies(manifest).length, 1);
});

test("a declaration inside a // comment stays untouched while the real one after it is rewritten", () => {
  const commented = '// .package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.0.9")';
  const real = '.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0")';
  const manifest = `${commented}\n${real}\n`;
  assert.equal(rewriteManifest(manifest, "/s/consumer", "/s/swiftuiweb"), `${commented}\n.package(path: "../swiftuiweb")\n`);
});

test("several declarations on one line are all rewritten", () => {
  const manifest =
    '[.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0"), .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1"), .package(url: "https://github.com/Vitorsilveira31/swiftuiweb.git", branch: "main")]\n';
  assert.equal(frameworkURLDependencies(manifest).length, 2);
  assert.equal(
    rewriteManifest(manifest, "/s/consumer", "/s/swiftuiweb"),
    '[.package(path: "../swiftuiweb"), .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1"), .package(path: "../swiftuiweb")]\n',
  );
});

// The launcher refuses the in-place mode when the manifest names SwiftUIWeb by URL. A stub `swift` stands in for the toolchain
// (the launcher only lists SDKs and asks for the version before it reaches this check) and a no-op lowerer stand in, so the
// test needs neither the Embedded SDK nor a build of the lowerer.
test("the launcher refuses SWIFTUIWEB_LOWER_IN_PLACE=1 for a manifest that names SwiftUIWeb by URL", () => {
  const root = mkdtempSync(join(tmpdir(), "swui-fud-launcher-"));
  try {
    mkdirSync(join(root, "app"), { recursive: true });
    writeFileSync(join(root, "app", "Package.swift"), '.package(url: "git@github.com:Vitorsilveira31/swiftuiweb.git", from: "0.1.0")\n');
    const swift = join(root, "swift");
    writeFileSync(
      swift,
      '#!/bin/sh\ncase "$1" in\n  sdk) echo swift-6.4.0-RELEASE_wasm-embedded ;;\n  --version) echo "Swift version 6.4 (swift-6.4-RELEASE)" ;;\nesac\n',
      { mode: 0o755 },
    );
    const result = spawnSync("bash", [LAUNCHER, "Hello"], {
      encoding: "utf8",
      env: {
        ...process.env,
        SWIFTUIWEB_SKIP_TOOLCHAIN_REPORT: "1",
        SWIFTUIWEB_SWIFT: swift,
        SWIFTUIWEB_LOWERING_TOOL: "/usr/bin/true",
        SWIFTUIWEB_PACKAGE_ROOT: join(root, "app"),
        SWIFTUIWEB_LOWER_IN_PLACE: "1",
        SWIFTUIWEB_BUILD_ROOT: join(root, "build"),
        BUILD_ONLY: "1",
      },
    });
    assert.equal(result.status, 2, result.stderr);
    assert.match(result.stderr, /names SwiftUIWeb by URL/u);
    assert.match(result.stderr, /Unset SWIFTUIWEB_LOWER_IN_PLACE/u);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
