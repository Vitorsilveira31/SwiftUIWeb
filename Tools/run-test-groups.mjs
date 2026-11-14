#!/usr/bin/env bun
// Runs make targets in groups: the groups run at the same time, the targets of a group one after another. A group
// holds the targets that write the same bundle folder or development cache (they would race), so different groups
// never touch the same files; builds take their own temporary folders and SwiftPM locks a shared one.
//
//   bun Tools/run-test-groups.mjs "showcase: controls-browser-test identity-browser-test" "lowering: lowering-test" ...
//
// Each target's output goes to .build/test-logs/<target>.log; the console gets one line per target, and the end of the
// log of every target that failed. The exit status is 1 when any target failed. Every group runs to its end, so one
// failure does not hide the others. TEST_GROUPS_JOBS (default 8) caps how many groups run together; 1 runs them in order.
import { spawn } from "node:child_process";
import { mkdirSync, openSync, closeSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const LOGS = join(ROOT, ".build", "test-logs");

export function parseGroups(args) {
  return args.map((arg) => {
    const match = /^\s*([\w.-]+)\s*:(.*)$/s.exec(arg);
    if (!match) throw new Error(`a group is "name: target target ...", not ${JSON.stringify(arg)}`);
    return { name: match[1], targets: match[2].split(/\s+/).filter(Boolean) };
  });
}

function runTarget(target, make) {
  return new Promise((done) => {
    const log = join(LOGS, `${target}.log`);
    const fd = openSync(log, "w");
    const started = Date.now();
    const child = spawn(make, ["--no-print-directory", target], { cwd: ROOT, stdio: ["ignore", fd, fd] });
    child.on("close", (code, signal) => {
      closeSync(fd);
      done({ target, ok: code === 0, code: code ?? signal, seconds: Math.round((Date.now() - started) / 1000), log });
    });
  });
}

export async function runGroups(groups, { make = process.env.MAKE || "make", jobs = Number(process.env.TEST_GROUPS_JOBS || 8), print = console.log } = {}) {
  mkdirSync(LOGS, { recursive: true });
  const results = [];
  const queue = [...groups];
  const worker = async () => {
    for (let group = queue.shift(); group; group = queue.shift()) {
      for (const target of group.targets) {
        const result = await runTarget(target, make);
        results.push(result);
        print(`${result.ok ? "PASS" : `FAIL(${result.code})`}  ${target}  ${result.seconds}s  [${group.name}]`);
      }
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(jobs, groups.length)) }, worker));
  return results;
}

if (import.meta.main) {
  const groups = parseGroups(process.argv.slice(2));
  const started = Date.now();
  const results = await runGroups(groups);
  const failed = results.filter((result) => !result.ok);
  for (const result of failed) {
    const tail = readFileSync(result.log, "utf8").trimEnd().split("\n").slice(-30).join("\n");
    console.log(`\n--- ${result.target} (${result.log}) ---\n${tail}`);
  }
  const minutes = ((Date.now() - started) / 60000).toFixed(1);
  console.log(`\n${results.length - failed.length} of ${results.length} targets passed in ${minutes} min; logs in ${LOGS}`);
  process.exit(failed.length ? 1 : 0);
}
