// Run: bun test ./Tools/test-package-web-resources.mjs
// Covers Tools/package-web-resources.mjs: the browser files of a consumer's local packages (transitively, the framework
// excepted) are copied into the bundle, their head.html fragments are collected in order, and a name two packages ship,
// a file that would replace one of the bundle's, or a link leaving a package stops the build.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { HEAD_FILE, copyPackageResources, localPackages } from "./package-web-resources.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "package-web-resources.mjs");

function write(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}

function manifest(directory, dependencies) {
  write(join(directory, "Package.swift"), `let package = Package(dependencies: [${dependencies.map((path) => `.package(path: "${path}")`).join(", ")}])\n`);
}

/** root/App depends on ../Lib and ../../swiftuiweb; Lib depends on ../Sdk. Lib and Sdk ship browser files. */
function tree() {
  const root = mkdtempSync(join(tmpdir(), "swui-pwr-"));
  const workspace = join(root, "work");
  manifest(join(workspace, "App"), ["../Lib", "../../swiftuiweb"]);
  manifest(join(workspace, "Lib"), ["../Sdk"]);
  manifest(join(workspace, "Sdk"), []);
  manifest(join(root, "swiftuiweb"), []);
  write(join(root, "swiftuiweb", "Web", "Resources", "framework.js"), "framework");
  write(join(workspace, "Lib", "Web", "Resources", "lib-service.js"), "lib");
  write(join(workspace, "Lib", "Web", "Resources", "head.html"), '<script defer src="./lib-service.js"></script>\n');
  write(join(workspace, "Lib", "Web", "Resources", ".DS_Store"), "x");
  write(join(workspace, "Sdk", "Web", "Resources", "sdk", "sdk.js"), "sdk");
  write(join(workspace, "Sdk", "Web", "Resources", "head.html"), '<script defer src="./sdk/sdk.js"></script>');
  const bundle = join(root, "bundle");
  mkdirSync(bundle);
  write(join(bundle, "index.html"), "<html></html>");
  return { root, app: join(workspace, "App"), lib: join(workspace, "Lib"), sdk: join(workspace, "Sdk"), bundle, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

test("the local packages are found transitively, in breadth-first order, without the framework", () => {
  const t = tree();
  try {
    assert.deepEqual(localPackages(t.app).map((path) => path.split("/").pop()), ["Lib", "Sdk"]);
  } finally { t.cleanup(); }
});

test("each package's files reach the bundle, and its head fragment is collected in order", () => {
  const t = tree();
  try {
    copyPackageResources(t.app, t.bundle);
    assert.equal(readFileSync(join(t.bundle, "lib-service.js"), "utf8"), "lib");
    assert.equal(readFileSync(join(t.bundle, "sdk", "sdk.js"), "utf8"), "sdk");
    assert.equal(existsSync(join(t.bundle, ".DS_Store")), false, "dotfiles are skipped");
    assert.equal(existsSync(join(t.bundle, "head.html")), false, "a package's head.html is not copied as the page's");
    assert.equal(existsSync(join(t.bundle, "framework.js")), false, "the framework is not a package");
    const heads = readFileSync(join(t.bundle, HEAD_FILE), "utf8");
    assert.ok(heads.indexOf("lib-service.js") < heads.indexOf("sdk/sdk.js"), heads);
    assert.match(heads, /<!-- Lib \(its Web\/Resources\/head\.html\) -->/);
  } finally { t.cleanup(); }
});

test("a file two packages ship, or one that would replace the bundle's, stops the build", () => {
  const t = tree();
  try {
    write(join(t.sdk, "Web", "Resources", "lib-service.js"), "again");
    assert.throws(() => copyPackageResources(t.app, t.bundle), /lib-service\.js is in the browser resources of both Lib and Sdk/);
    rmSync(join(t.sdk, "Web", "Resources", "lib-service.js"));
    write(join(t.lib, "Web", "Resources", "index.html"), "mine");
    assert.throws(() => copyPackageResources(t.app, t.bundle), /would replace the bundle's own index\.html/);
  } finally { t.cleanup(); }
});

test("a link that leaves the package stops the build; one inside it is followed", () => {
  const t = tree();
  try {
    write(join(t.lib, "Shared", "font.woff2"), "font");
    symlinkSync(join(t.lib, "Shared", "font.woff2"), join(t.lib, "Web", "Resources", "font.woff2"));
    copyPackageResources(t.app, t.bundle);
    assert.equal(readFileSync(join(t.bundle, "font.woff2"), "utf8"), "font");
    rmSync(t.bundle, { recursive: true }); mkdirSync(t.bundle);
    symlinkSync(join(t.root, "swiftuiweb", "Web", "Resources", "framework.js"), join(t.sdk, "Web", "Resources", "outside.js"));
    const result = spawnSync(process.execPath, [SCRIPT, t.app, t.bundle], { encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /points outside the package/);
  } finally { t.cleanup(); }
});

test("a consumer without local packages leaves the bundle as it is", () => {
  const root = mkdtempSync(join(tmpdir(), "swui-pwr-"));
  try {
    manifest(join(root, "App"), []);
    mkdirSync(join(root, "bundle"));
    const result = spawnSync(process.execPath, [SCRIPT, join(root, "App"), join(root, "bundle")], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(join(root, "bundle", HEAD_FILE)), false);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("a remote browser package's checkout ships its files and head fragment after the local packages, once", () => {
  const t = tree();
  try {
    const remote = join(t.root, "checkouts", "skip-sentry");
    manifest(remote, []);
    write(join(remote, "Web", "Resources", "sentry", "bundle.js"), "sentry");
    write(join(remote, "Web", "Resources", "head.html"), '<script defer src="./sentry/bundle.js"></script>');
    copyPackageResources(t.app, t.bundle, () => {}, [remote, t.lib]);
    assert.equal(readFileSync(join(t.bundle, "sentry", "bundle.js"), "utf8"), "sentry");
    const heads = readFileSync(join(t.bundle, HEAD_FILE), "utf8");
    assert.ok(heads.indexOf("sdk/sdk.js") < heads.indexOf("sentry/bundle.js"), heads);
    assert.match(heads, /<!-- skip-sentry \(its Web\/Resources\/head\.html\) -->/);
    assert.equal(heads.match(/lib-service\.js/g).length, 1, "a package listed twice is copied once");
  } finally { t.cleanup(); }
});
