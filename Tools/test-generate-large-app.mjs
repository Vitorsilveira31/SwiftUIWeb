#!/usr/bin/env bun
// Tools/generate-large-app.mjs: the same arguments write the same bytes, another seed writes other bytes, the view count
// is the one asked for, every view is reachable, the generator refuses to empty a folder it did not write, and the
// output names no home path or private term. The test generates text only; it never builds Swift.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { generateProject, MARKER, ROOT, writeProject } from "./generate-large-app.mjs";
import { finish, test, withTemporary } from "./measurement-test-support.mjs";

const VIEW_DECLARATION = /^struct (\w+): View \{$/gm;

/** The `: View` structs of a generated project, by name, across every Swift file. */
function viewNames(files) {
  const names = [];
  for (const [path, text] of files) {
    if (!path.endsWith(".swift")) continue;
    for (const match of text.matchAll(VIEW_DECLARATION)) names.push(match[1]);
  }
  return names;
}

/** The private list the audit reads: SWIFTUIWEB_PRIVATE_TERMS, else the shared git directory's info/private-terms. */
function privateTerms() {
  let listPath = process.env.SWIFTUIWEB_PRIVATE_TERMS;
  if (!listPath) {
    const common = spawnSync("git", ["rev-parse", "--git-common-dir"], { cwd: ROOT, encoding: "utf8" }).stdout.trim();
    if (!common) return [];
    listPath = join(resolve(ROOT, common), "info", "private-terms");
  }
  if (!existsSync(listPath)) return [];
  return readFileSync(listPath, "utf8")
    .split("\n")
    .map((line) => line.trim().toLowerCase())
    .filter((line) => line && !line.startsWith("#"));
}

const HOME_PATH = /\/(?:Users|home)\/[A-Za-z0-9._-]+\//;
// Under the repository, so the manifest's relative path is the short one a real run writes (no user folder names in it).
const OUT = join(ROOT, ".build", "large-app", "test", "package");

await test("two runs with the same arguments write byte-identical files", () => {
  const first = generateProject({ views: 60, seed: 1, out: OUT }).files;
  const second = generateProject({ views: 60, seed: 1, out: OUT }).files;
  assert.deepEqual([...second.keys()], [...first.keys()]);
  for (const [path, text] of first) assert.equal(second.get(path), text, path);
});

await test("another seed writes different view bodies", () => {
  const one = generateProject({ views: 60, seed: 1, out: OUT }).files;
  const two = generateProject({ views: 60, seed: 2, out: OUT }).files;
  const differing = [...one.keys()].filter((path) => path.endsWith(".swift") && one.get(path) !== two.get(path));
  assert.ok(differing.length > 10, `only ${differing.length} files differ`);
});

for (const views of [60, 200]) {
  await test(`--views ${views} declares about ${views} views (within 15 %)`, () => {
    const { files, views: reported, features } = generateProject({ views, seed: 1, out: OUT });
    const names = viewNames(files);
    assert.equal(reported, views);
    assert.equal(features, Math.max(2, Math.round(views / 10)));
    assert.ok(Math.abs(names.length - views) <= views * 0.15, `${names.length} view structs for --views ${views}`);
    assert.equal(new Set(names).size, names.length, "view type names are unique");
  });
}

await test("every generated view type is used by another declaration", () => {
  const { files } = generateProject({ views: 60, seed: 1, out: OUT });
  const everything = [...files.values()].join("\n");
  for (const name of viewNames(files)) {
    const uses = everything.match(new RegExp(`\\b${name}\\b`, "g")) ?? [];
    assert.ok(uses.length >= 2, `${name} is declared but never used`);
  }
});

await test("the Package manifest reaches the repository root from the output directory", () => {
  const out = join(ROOT, ".build", "large-app", "60", "package");
  const { files } = generateProject({ views: 60, seed: 1, out });
  const manifest = files.get("Package.swift");
  const relative = manifest.match(/\.package\(path: "([^"]+)"\)/)[1];
  assert.equal(resolve(out, relative), ROOT);
  assert.match(manifest, /\.product\(name: "SwiftUIWeb", package: "swiftuiweb"\)/);
  assert.match(manifest, /"-module-alias", \$0/);
});

await test("the output names no home path and no private term", () => {
  const terms = privateTerms();
  const { files } = generateProject({ views: 200, seed: 1, out: OUT });
  for (const [path, text] of files) {
    assert.doesNotMatch(text, HOME_PATH, `${path} names a home path`);
    const lower = text.toLowerCase();
    for (const term of terms) assert.ok(!lower.includes(term), `${path} names a private term`);
    assert.ok(!path.toLowerCase().split("/").some((part) => terms.some((term) => part.includes(term))), `${path} names a private term`);
  }
});

await test("writeProject refuses to empty a folder the generator did not write", () =>
  withTemporary((directory) => {
    const keep = join(directory, "keep.txt");
    writeFileSync(keep, "someone's work");
    const { files } = generateProject({ views: 10, seed: 1, out: directory });
    assert.throws(() => writeProject(directory, files), /refusing to empty/);
    assert.equal(readFileSync(keep, "utf8"), "someone's work");
  }));

await test("writeProject empties and rewrites a folder that carries the marker", () =>
  withTemporary((directory) => {
    const { files } = generateProject({ views: 10, seed: 1, out: directory });
    writeProject(directory, files);
    writeFileSync(join(directory, "stale.swift"), "old");
    writeProject(directory, files);
    assert.equal(existsSync(join(directory, "stale.swift")), false);
    assert.equal(readFileSync(join(directory, MARKER), "utf8"), files.get(MARKER));
    assert.equal(readFileSync(join(directory, "Package.swift"), "utf8"), files.get("Package.swift"));
  }));

await test("writeProject accepts an empty folder", () =>
  withTemporary((directory) => {
    const { files } = generateProject({ views: 10, seed: 1, out: directory });
    writeProject(directory, files);
    assert.ok(existsSync(join(directory, MARKER)));
  }));

await test("the arguments are checked", () => {
  assert.throws(() => generateProject({ views: 9, seed: 1, out: OUT }), /at least 10/);
  assert.throws(() => generateProject({ views: 60, seed: -1, out: OUT }), /--seed/);
});

finish();
