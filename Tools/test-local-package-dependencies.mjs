// Run: bun test ./Tools/test-local-package-dependencies.mjs
// Covers Tools/local-package-dependencies.mjs: framework detection, breadth-first staging of local libraries,
// cycles, absolute dependencies, and the two error messages (outside the staging area, destination taken).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { isFramework, pathDependencies } from "./local-package-dependencies.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "local-package-dependencies.mjs");

function manifest(directory, dependencies) {
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, "Package.swift"), `let package = Package(dependencies: [${dependencies.join(", ")}])\n`);
}

function run(args) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });
}

function tree(setup) {
  const root = mkdtempSync(join(tmpdir(), "swui-lpd-"));
  setup(root);
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

test("framework dependencies are recognised by the last path component, whatever the case", () => {
  assert.equal(isFramework("../swiftuiweb"), true);
  assert.equal(isFramework("../../SwiftUIWeb/"), true);
  assert.equal(isFramework("../swiftuiweb-copy"), false);
  assert.equal(isFramework("swiftuiweb/."), true);
});

test("--framework-path prints the declared framework path, or nothing when none is declared", () => {
  const { root, cleanup } = tree((base) => {
    manifest(join(base, "consumer"), ['.package(path: "../../fw/SwiftUIWeb")', '.package(path: "../lib")']);
    manifest(join(base, "bare"), ['.package(path: "../lib")']);
  });
  try {
    assert.deepEqual(pathDependencies(join(root, "consumer")), ["../../fw/SwiftUIWeb", "../lib"]);
    const found = run(["--framework-path", join(root, "consumer")]);
    assert.equal(found.status, 0, found.stderr);
    assert.equal(found.stdout, "../../fw/SwiftUIWeb\n");
    assert.equal(run(["--framework-path", join(root, "bare")]).stdout, "\n");
  } finally {
    cleanup();
  }
});

test("libraries of libraries are staged at their own relative place, breadth first, cycles stop", () => {
  const { root, cleanup } = tree((base) => {
    manifest(join(base, "app/consumer"), ['.package(path: "../../fw/swiftuiweb")', '.package(path: "../../libs/Shared")']);
    manifest(join(base, "libs/Shared"), ['.package(path: "../Deep/Deeper")', '.package(path: "../../app/consumer")']);
    manifest(join(base, "libs/Deep/Deeper"), ['.package(path: "../../Shared")']);
    manifest(join(base, "fw/swiftuiweb"), []);
  });
  try {
    const staging = join(root, "stage");
    const workspace = join(staging, "level0/level1/consumer");
    const result = run([join(root, "app/consumer"), workspace, staging, join(root, "fw/swiftuiweb")]);
    assert.equal(result.status, 0, result.stderr);
    const lines = result.stdout.trim().split("\n").map((line) => line.split("\t"));
    assert.deepEqual(
      lines.map(([, destination]) => destination.slice(staging.length + 1)),
      ["level0/libs/Shared", "level0/libs/Deep/Deeper"],
    );
    // Sources are printed as real paths (the script resolves symlinks), destinations lexically.
    assert.equal(lines[0][0], join(realpathSync(root), "libs/Shared"));
  } finally {
    cleanup();
  }
});

test("a dependency that goes above the staging root is an error after the lines printed before it", () => {
  const { root, cleanup } = tree((base) => {
    manifest(join(base, "app/consumer"), ['.package(path: "../lib")', '.package(path: "../../Escape")']);
    manifest(join(base, "app/lib"), []);
    manifest(join(base, "Escape"), []);
  });
  try {
    const staging = join(root, "stage");
    const result = run([join(root, "app/consumer"), join(staging, "consumer"), staging, join(root, "app/swiftuiweb")]);
    assert.equal(result.status, 1);
    assert.equal(result.stdout.trim().split("\n").length, 1);
    assert.match(result.stderr, /^error: the local package dependency '\.\.\/\.\.\/Escape' of .*Package\.swift resolves outside the staging area/);
    assert.match(result.stderr, /keep local package dependencies at most as many levels up as the SwiftUIWeb dependency\n$/);
  } finally {
    cleanup();
  }
});

test("two different sources that would be staged at the same place are an error", () => {
  const { root, cleanup } = tree((base) => {
    manifest(join(base, "d/lib"), ['.package(path: "../Y")']);
    manifest(join(base, "d/Y"), []);
    manifest(join(base, "c/Y"), []);
    manifest(join(base, "c/consumer"), ['.package(path: "../lib-link")', '.package(path: "../Y")']);
    symlinkSync(join(base, "d/lib"), join(base, "c/lib-link"), "dir");
  });
  try {
    const staging = join(root, "stage");
    const result = run([join(root, "c/consumer"), join(staging, "consumer"), staging, join(root, "c/swiftuiweb")]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /would be staged at .*stage\/Y, where another package already is\n$/);
  } finally {
    cleanup();
  }
});

test("absolute path dependencies are ignored and the consumer's framework is never staged", () => {
  const { root, cleanup } = tree((base) => {
    manifest(join(base, "consumer"), ['.package(path: "/usr/lib/x")', '.package(path: "../SwiftUIWeb")']);
    manifest(join(base, "SwiftUIWeb"), []);
  });
  try {
    const staging = join(root, "stage");
    const result = run([join(root, "consumer"), join(staging, "consumer"), staging, join(root, "SwiftUIWeb")]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "");
  } finally {
    cleanup();
  }
});

test("too few arguments fail with exit status 1", () => {
  const result = run(["only-one"]);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
});
