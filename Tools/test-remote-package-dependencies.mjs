// Run: bun test ./Tools/test-remote-package-dependencies.mjs
// Covers which remote packages the launcher stages (those that depend on SwiftUIWeb, at any depth, once each), where
// (STAGING/remote/<repository name>), and the rewrite of their URL declarations, in any spelling, to path dependencies.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { normalizedURL, rewriteURLDependency } from "./framework-url-dependency.mjs";
import { remotePackages } from "./remote-package-dependencies.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "remote-package-dependencies.mjs");

const framework = { identity: "swiftuiweb", url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", path: "/c/SwiftUIWeb", dependencies: [] };
const node = (identity, url, dependencies = []) => ({ identity, url, path: `/c/${identity}`, dependencies });

test("a remote package that depends on SwiftUIWeb is staged; others, local ones and the framework are not", () => {
  const graph = node("app", "/work/app", [
    framework,
    node("blurhashswift", "https://github.com/Vitorsilveira31/BlurHashSwift.git", [framework]),
    node("swift-asn1", "https://github.com/apple/swift-asn1.git"),
    node("modules", "/work/Modules", [framework]),
  ]);
  assert.deepEqual(remotePackages(graph, "/s"), [
    { url: "https://github.com/Vitorsilveira31/BlurHashSwift.git", checkout: "/c/blurhashswift", destination: "/s/remote/BlurHashSwift", mode: "lower" },
  ]);
});

test("browser packages are found at any depth and listed once", () => {
  const inner = node("skip-motion", "git@github.com:Vitorsilveira31/skip-motion.git", [framework]);
  const graph = node("app", "/work/app", [
    node("skip-sentry", "https://github.com/Vitorsilveira31/skip-sentry.git", [framework, inner]),
    node("modules", "/work/Modules", [framework, { ...inner, url: "https://github.com/Vitorsilveira31/skip-motion" }]),
  ]);
  assert.deepEqual(
    remotePackages(graph, "/s").map((entry) => entry.destination),
    ["/s/remote/skip-motion", "/s/remote/skip-sentry"],
  );
});

test("two different repositories with the same name are an error, not one overwriting the other", () => {
  const graph = node("app", "/work/app", [
    node("tools", "https://github.com/a/Tools.git", [framework]),
    node("tools", "https://github.com/b/tools.git", [framework]),
  ]);
  assert.throws(() => remotePackages(graph, "/s"), /would both be staged at \/s\/remote\/tools/i);
});

test("a URL is the same repository in every spelling", () => {
  const spellings = [
    "https://github.com/Vitorsilveira31/skip-sentry.git",
    "https://github.com/vitorsilveira31/skip-sentry",
    "git@github.com:Vitorsilveira31/skip-sentry.git",
    "ssh://git@github.com/Vitorsilveira31/skip-sentry/",
  ];
  assert.equal(new Set(spellings.map(normalizedURL)).size, 1);
  assert.notEqual(normalizedURL("https://github.com/Vitorsilveira31/skip-sentry-tools.git"), normalizedURL(spellings[0]));
});

test("every declaration of the URL becomes a path dependency, comments and other packages are left alone", () => {
  const manifest = [
    "dependencies: [",
    '  .package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "0.1.45"),',
    '  // .package(url: "https://github.com/Vitorsilveira31/skip-sentry.git", branch: "main"),',
    '  .package(url: "git@github.com:Vitorsilveira31/skip-sentry.git", .upToNextMajor(from: "1.0.0")),',
    '  .package(url: "https://github.com/Vitorsilveira31/skip-sentry-tools.git", from: "1.0.0"),',
    "]",
  ].join("\n");
  const rewritten = rewriteURLDependency(manifest, "/s/level0/consumer", "https://github.com/Vitorsilveira31/skip-sentry", "/s/remote/skip-sentry");
  assert.equal(
    rewritten,
    manifest.replace(
      '.package(url: "git@github.com:Vitorsilveira31/skip-sentry.git", .upToNextMajor(from: "1.0.0"))',
      '.package(path: "../../remote/skip-sentry")',
    ),
  );
});

test("the command says whether a manifest declares a package by URL other than SwiftUIWeb, and rewrites staged manifests", () => {
  const dir = mkdtempSync(join(tmpdir(), "remote-packages-"));
  try {
    const frameworkOnly = join(dir, "framework-only.swift");
    writeFileSync(frameworkOnly, '.package(url: "https://github.com/Vitorsilveira31/SwiftUIWeb.git", from: "0.1.45")');
    const consumer = join(dir, "staging", "level0", "consumer", "Package.swift");
    mkdirSync(dirname(consumer), { recursive: true });
    writeFileSync(consumer, '.package(url: "https://github.com/Vitorsilveira31/skip-sentry.git", branch: "main")');
    const run = (...args) => spawnSync("bun", [SCRIPT, ...args], { encoding: "utf8" });
    assert.equal(run("--declares-url", frameworkOnly).status, 1);
    assert.equal(run("--declares-url", frameworkOnly, consumer).status, 0);
    const list = join(dir, "remote.tsv");
    writeFileSync(list, `https://github.com/Vitorsilveira31/skip-sentry\t/c/skip-sentry\t${join(dir, "staging", "remote", "skip-sentry")}\n`);
    const result = run("--rewrite", list, consumer, frameworkOnly);
    assert.equal(result.status, 0);
    assert.equal(result.stdout.trim(), consumer);
    assert.equal(readFileSync(consumer, "utf8"), '.package(path: "../../remote/skip-sentry")');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a remote package that only leads to a browser package is staged unlowered, so its manifest can point at the lowered one", () => {
  const inner = node("inner", "https://github.com/o/Inner.git", [framework]);
  const graph = node("app", "/work/app", [
    node("outer", "https://github.com/o/Outer.git", [inner, node("swift-asn1", "https://github.com/apple/swift-asn1.git")]),
    node("leaf", "https://github.com/o/Leaf.git"),
  ]);
  assert.deepEqual(
    remotePackages(graph, "/s").map(({ destination, mode }) => `${destination} ${mode}`),
    ["/s/remote/Inner lower", "/s/remote/Outer copy"],
  );
});

test("a package both leading to and depending on SwiftUIWeb is lowered once", () => {
  const inner = node("inner", "https://github.com/o/Inner.git", [framework]);
  const graph = node("app", "/work/app", [node("outer", "https://github.com/o/Outer.git", [framework, inner]), inner]);
  assert.deepEqual(remotePackages(graph, "/s").map(({ mode }) => mode), ["lower", "lower"]);
});

test("an explicit package name survives the rewrite, since target dependencies may name it", () => {
  const manifest = '.package(name: "BrowserLibrary", url: "https://github.com/o/Inner.git", from: "1.0.0")';
  assert.equal(
    rewriteURLDependency(manifest, "/s/level0/consumer", "https://github.com/o/Inner", "/s/remote/Inner"),
    '.package(name: "BrowserLibrary", path: "../../remote/Inner")',
  );
});

test("a comment before the explicit name does not lose it", () => {
  const manifest = '.package(/* browser library */ name: "BrowserLibrary", url: "https://github.com/o/Inner.git", from: "1.0.0")';
  assert.equal(
    rewriteURLDependency(manifest, "/s/level0/consumer", "https://github.com/o/Inner", "/s/remote/Inner"),
    '.package(name: "BrowserLibrary", path: "../../remote/Inner")',
  );
});
