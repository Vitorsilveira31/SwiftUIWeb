#!/usr/bin/env bun
// Fails when Python comes back: a tracked `.py` file, or a `python`/`python3` command in a script, Makefile or
// package script. The third-party skills under .agents/skills are the only exception (AGENTS.md, "Tooling Languages").
// Usage: bun Tools/audit-no-python.mjs
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = process.env.SWIFTUIWEB_AUDIT_ROOT ?? resolve(dirname(fileURLToPath(import.meta.url)), "..");
const tracked = spawnSync("git", ["ls-files", "-z"], { cwd: ROOT, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
if (tracked.status !== 0) {
  console.error(`git ls-files failed: ${tracked.stderr}`);
  process.exit(2);
}
const files = tracked.stdout.split("\0").filter(Boolean).filter((path) => !path.startsWith(".agents/skills/"));

const problems = [];
for (const path of files) {
  if (path.endsWith(".py")) problems.push(`${path}: Python source file`);
}

// A command position: start of a line, after a pipe/semicolon/&&/`(`/`$(`, or after an interpreter prefix like `env`.
const COMMAND = /(^|[|;&(`]|\$\()\s*(?:env\s+)?(?:\S+=\S+\s+)*python3?\b|^#!.*\bpython3?\b/;
const SCRIPT = /(^Makefile$|^package\.json$|\.(sh|bash|zsh|mjs|js|ts|yml|yaml)$)/;
const SELF = "Tools/audit-no-python.mjs";
for (const path of files) {
  if (!SCRIPT.test(path) || path === SELF || path.startsWith("Tools/test-")) continue;
  let text;
  try {
    text = readFileSync(join(ROOT, path), "utf8");
  } catch {
    continue;
  }
  text.split("\n").forEach((line, index) => {
    const code = line.replace(/^\s*(#|\/\/).*$/, "");
    if (COMMAND.test(code)) problems.push(`${path}:${index + 1}: runs python: ${line.trim()}`);
  });
}

if (problems.length) {
  console.error("Python found (AGENTS.md, \"Tooling Languages\"):");
  for (const problem of problems) console.error(`  ${problem}`);
  process.exit(1);
}
console.log(`no Python: ${files.length} tracked files checked`);
