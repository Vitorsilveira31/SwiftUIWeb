#!/usr/bin/env bun
// Tools/audit-no-python.mjs passes on this repository and fails, naming the file, on a tree with Python in it.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const AUDIT = join(ROOT, "Tools/audit-no-python.mjs");

const audit = (root) =>
  spawnSync("bun", [AUDIT], { env: { ...process.env, SWIFTUIWEB_AUDIT_ROOT: root }, encoding: "utf8" });

function tree(files) {
  const root = mkdtempSync(join(tmpdir(), "no-python-"));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(root, path, ".."), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  assert.equal(spawnSync("git", ["init", "-q"], { cwd: root }).status, 0);
  assert.equal(spawnSync("git", ["add", "-A"], { cwd: root }).status, 0);
  return root;
}

const cases = [
  ["the repository itself", null, 0, /no Python/],
  ["a clean tree", { "Tools/a.mjs": "console.log(1)\n", "Makefile": "x:\n\tbun Tools/a.mjs\n" }, 0, /no Python/],
  ["third-party skills are allowed", { ".agents/skills/s/run.py": "print(1)\n" }, 0, /no Python/],
  ["a tracked .py file", { "Tools/old.py": "print(1)\n" }, 1, /Tools\/old\.py: Python source file/],
  ["a python3 call in a Makefile", { Makefile: "x:\n\tpython3 Tools/a.mjs\n" }, 1, /Makefile:2: runs python/],
  ["a python call after a pipe in a shell script", { "Tools/b.sh": "cat x | python -m json.tool\n" }, 1, /Tools\/b\.sh:1/],
  ["a python variable assignment prefix", { "Tools/d.sh": "PYTHONPATH=x python3 y\n" }, 1, /Tools\/d\.sh:1/],
  ["a comment that mentions python3", { "Tools/e.sh": "# python3 is gone\necho hi\n" }, 0, /no Python/],
];

for (const [name, files, status, pattern] of cases) {
  const root = files ? tree(files) : ROOT;
  try {
    const result = audit(root);
    assert.equal(result.status, status, `${name}: ${result.stdout}${result.stderr}`);
    assert.match(result.stdout + result.stderr, pattern, name);
    console.log(`ok   ${name}`);
  } finally {
    if (files) rmSync(root, { recursive: true, force: true });
  }
}
