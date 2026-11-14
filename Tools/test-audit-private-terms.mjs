#!/usr/bin/env bun
// Tools/audit-private-terms.mjs passes on a clean tree and fails, naming the file and line, on a tree with a private
// term or a home path in it. The terms used here are made up; the real list is never committed.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const AUDIT = join(ROOT, "Tools/audit-private-terms.mjs");

function tree(files) {
  const root = mkdtempSync(join(tmpdir(), "private-terms-"));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(root, path, ".."), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  assert.equal(spawnSync("git", ["init", "-q"], { cwd: root }).status, 0);
  assert.equal(spawnSync("git", ["add", "-A"], { cwd: root }).status, 0);
  return root;
}

function audit(root, list) {
  const env = { ...process.env, SWIFTUIWEB_AUDIT_ROOT: root };
  delete env.SWIFTUIWEB_PRIVATE_TERMS;
  if (list !== undefined) {
    const file = join(root, ".git", "info", "private-terms");
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, list);
  }
  return spawnSync("bun", [AUDIT], { env, encoding: "utf8" });
}

const cases = [
  ["a clean tree", { "a.md": "Hello\n" }, "# list\nacmecorp\n", 0, /no private names: 1 tracked files checked for 1 private terms/],
  ["no list: only paths are checked", { "a.md": "acmecorp\n" }, undefined, 0, /no private term list/],
  ["a term in the text, any case", { "Tools/a.mjs": "x\n// built for AcmeCorp\n" }, "acmecorp\n", 1, /Tools\/a\.mjs:2: names a private term/],
  ["a term inside a longer word", { "a.swift": "let AcmeCorpBrand = 1\n" }, "acmecorp\n", 1, /a\.swift:1/],
  ["a term in a file name", { "Tests/AcmeCorpPayload.swift": "x\n" }, "acmecorp\n", 1, /AcmeCorpPayload\.swift: the path names/],
  ["a home path", { "a.md": `see /Users/${"someone"}/Developer/x\n` }, undefined, 1, /a\.md:1: absolute home path/],
  ["a placeholder home path is fine", { "a.md": "under /Users/<you>/ or /home/\n" }, undefined, 0, /no private names/],
  ["binary files are skipped", { "a.bin": Buffer.from([0, 97, 99, 109, 101, 99, 111, 114, 112]) }, "acmecorp\n", 0, /no private names/],
];

let failed = 0;
for (const [name, files, list, status, pattern] of cases) {
  const root = tree(files);
  try {
    const result = audit(root, list);
    const output = result.stdout + result.stderr;
    assert.equal(result.status, status, `${name}: exit ${result.status}\n${output}`);
    assert.match(output, pattern, `${name}\n${output}`);
    console.log(`ok - ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`not ok - ${name}\n${error.message}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
if (failed) process.exit(1);
