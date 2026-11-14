#!/usr/bin/env bun
// Fails when a tracked file names something that must stay out of the public repository: an absolute home path
// (`/Users/<name>/`, `/home/<name>/`), or a term from the maintainer's private list.
//
// The private list is never committed (committing it would publish the names it protects). It is read from the file
// named by SWIFTUIWEB_PRIVATE_TERMS, or else from `info/private-terms` in the repository's git directory, which git
// shares between worktrees and never pushes. One term per line, matched case-insensitively as a substring; empty
// lines and lines starting with `#` are ignored. Without a list only the path check runs.
//
// Usage: bun Tools/audit-private-terms.mjs
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = process.env.SWIFTUIWEB_AUDIT_ROOT ?? resolve(dirname(fileURLToPath(import.meta.url)), "..");

function git(...args) {
  const result = spawnSync("git", args, { cwd: ROOT, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  if (result.status !== 0) {
    console.error(`git ${args.join(" ")} failed: ${result.stderr}`);
    process.exit(2);
  }
  return result.stdout;
}

function termsFile() {
  if (process.env.SWIFTUIWEB_PRIVATE_TERMS) return process.env.SWIFTUIWEB_PRIVATE_TERMS;
  const common = git("rev-parse", "--git-common-dir").trim();
  return join(isAbsolute(common) ? common : join(ROOT, common), "info", "private-terms");
}

const listPath = termsFile();
const terms = existsSync(listPath)
  ? readFileSync(listPath, "utf8")
      .split("\n")
      .map((line) => line.trim().toLowerCase())
      .filter((line) => line && !line.startsWith("#"))
  : [];

// A home directory with a user name after it. `/Users/` alone, or a placeholder such as `/Users/<you>/`, is fine.
const HOME_PATH = /\/(?:Users|home)\/[A-Za-z0-9._-]+\//;

const files = git("ls-files", "-z").split("\0").filter(Boolean);
const problems = [];
for (const path of files) {
  const lowerPath = path.toLowerCase();
  for (const term of terms) if (lowerPath.includes(term)) problems.push(`${path}: the path names a private term`);
  let text;
  try {
    text = readFileSync(join(ROOT, path));
  } catch {
    continue;
  }
  if (text.includes(0)) continue; // binary
  text.toString("utf8").split("\n").forEach((line, index) => {
    const lower = line.toLowerCase();
    if (terms.some((term) => lower.includes(term))) problems.push(`${path}:${index + 1}: names a private term`);
    if (HOME_PATH.test(line)) problems.push(`${path}:${index + 1}: absolute home path`);
  });
}

if (problems.length) {
  console.error("Private names or local paths found (they must not reach the public repository):");
  for (const problem of problems) console.error(`  ${problem}`);
  process.exit(1);
}
const scope = terms.length ? `${terms.length} private terms and home paths` : "home paths (no private term list)";
console.log(`no private names: ${files.length} tracked files checked for ${scope}`);
