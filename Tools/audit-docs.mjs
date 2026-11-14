#!/usr/bin/env bun
// Fails when checked-in Markdown points at things that no longer exist:
//   - a relative link to a missing file,
//   - a backticked repository path (`Tools/...`, `Sources/...`, ...) that does not exist,
//   - a backticked `make <target>` that the Makefile does not define.
//
// Scope: README.md, AGENTS.md, the Markdown under Documentation/, Examples/, Sources/, Plugins/, Tools/, Tests/ and
// Benchmarks/, and the project skills under .agents/skills/.
// A document that is a dated log of what was true at the time carries the marker `Registro histórico` (or
// `Historical record`); links and paths in it are not checked. Paths are tried from the repository root and from the
// document's own folder (an example's README names paths inside the example).
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SKIP_DIRS = new Set([".build", "node_modules", ".git", ".swiftpm", "DerivedData", "target"]);
const HISTORICAL = /Registro histórico|Historical record/;
const PATH_ROOTS = "Tools|Sources|Examples|Tests|Documentation|Plugins|Benchmarks";
const PATH_PATTERN = new RegExp("`((?:" + PATH_ROOTS + ")/[A-Za-z0-9_./-]*[A-Za-z0-9_])`", "g");

function markdownFiles() {
  const found = [];
  const walk = (directory) => {
    for (const name of readdirSync(directory)) {
      if (SKIP_DIRS.has(name)) continue;
      const path = join(directory, name);
      if (statSync(path).isDirectory()) walk(path);
      else if (name.endsWith(".md")) found.push(path);
    }
  };
  for (const file of ["README.md", "AGENTS.md"]) if (existsSync(join(ROOT, file))) found.push(join(ROOT, file));
  for (const directory of ["Documentation", "Examples", "Sources", "Plugins", "Tools", "Tests", "Benchmarks", ".agents/skills"]) {
    if (existsSync(join(ROOT, directory))) walk(join(ROOT, directory));
  }
  return found;
}

function makeTargets() {
  const text = readFileSync(join(ROOT, "Makefile"), "utf8");
  const targets = new Set();
  for (const match of text.matchAll(/^([A-Za-z0-9_.%-]+)\s*:(?!=)/gm)) targets.add(match[1]);
  for (const match of text.matchAll(/^\.PHONY:\s*(.*)$/gm)) for (const name of match[1].split(/\s+/)) if (name) targets.add(name);
  return targets;
}

// Skills written for other kinds of projects name `make` targets of those projects, not of this Makefile.
const EXTERNAL_SKILLS = new Set(["skip-testing"]);

/** True when a `.gitignore` in `folder` or above names `path` (a generated folder the document may still mention). */
function gitIgnored(folder, path) {
  for (let directory = folder; directory.startsWith(ROOT); directory = dirname(directory)) {
    const ignore = join(directory, ".gitignore");
    if (!existsSync(ignore)) continue;
    const relativePath = relative(directory, resolve(folder, path));
    const fromRoot = relative(directory, join(ROOT, path));
    for (const line of readFileSync(ignore, "utf8").split("\n")) {
      const pattern = line.trim().replace(/\/$/, "");
      if (!pattern || pattern.startsWith("#") || pattern.includes("*")) continue;
      // As in git, a pattern with no slash names a file or folder at any depth (`node_modules` is every `node_modules`).
      if (!pattern.includes("/") && [relativePath, fromRoot].some((candidate) => candidate.split("/").includes(pattern))) return true;
      if ([relativePath, fromRoot].some((candidate) => candidate === pattern || candidate.startsWith(pattern + "/"))) return true;
    }
  }
  return false;
}

const targets = makeTargets();
const problems = [];
for (const file of markdownFiles()) {
  const text = readFileSync(file, "utf8");
  if (HISTORICAL.test(text)) continue;
  const where = relative(ROOT, file);
  const folder = dirname(file);
  for (const match of text.matchAll(/\]\(([^)\s]+)\)/g)) {
    const target = match[1];
    if (/^(#|https?:|mailto:|codex:)/.test(target) || target.includes("{")) continue;
    if (!existsSync(resolve(folder, target.split("#", 1)[0]))) problems.push(`${where}: broken link ${target}`);
  }
  for (const match of text.matchAll(PATH_PATTERN)) {
    const path = match[1];
    if (!existsSync(join(ROOT, path)) && !existsSync(join(folder, path)) && !gitIgnored(folder, path)) problems.push(`${where}: missing path ${path}`);
  }
  const external = [...EXTERNAL_SKILLS].some((name) => where.startsWith(`.agents/skills/${name}/`));
  for (const match of external ? [] : text.matchAll(/`make ([a-z][a-z0-9-]*)[^`]*`/g)) {
    if (!targets.has(match[1])) problems.push(`${where}: unknown make target ${match[1]}`);
  }
}

if (problems.length > 0) {
  console.log("Stale documentation references:");
  for (const problem of [...new Set(problems)].sort()) console.log(`- ${problem}`);
  process.exit(1);
}
console.log("PASS documentation links, paths and make targets");
