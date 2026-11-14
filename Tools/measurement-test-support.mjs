// A few helpers for the tests of the measurement tools (coverage, performance contracts, size reports, probes).
// The tests are plain scripts: each case runs, prints `ok`/`FAIL`, and the script exits non-zero if any failed.
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const failures = [];
let count = 0;

export async function test(name, body) {
  count += 1;
  try {
    await body();
    console.log(`ok   ${name}`);
  } catch (error) {
    failures.push(name);
    console.error(`FAIL ${name}\n${error instanceof Error ? error.stack : error}`);
  }
}

/** Run `body` with a fresh temporary directory that is removed afterwards. */
export async function withTemporary(body) {
  const directory = mkdtempSync(join(tmpdir(), "measurement-test-"));
  try {
    return await body(directory);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

/** Run `fn` while `console.log`/`console.error` are captured; returns what it printed and what it returned or threw. */
export function capture(fn) {
  const out = [];
  const err = [];
  const log = console.log;
  const error = console.error;
  console.log = (...args) => out.push(args.join(" "));
  console.error = (...args) => err.push(args.join(" "));
  let result;
  let thrown = null;
  try {
    result = fn();
  } catch (caught) {
    thrown = caught;
  } finally {
    console.log = log;
    console.error = error;
  }
  return { out: out.join("\n"), err: err.join("\n"), result, thrown };
}

export function finish() {
  if (failures.length) {
    console.error(`\n${failures.length} of ${count} failed: ${failures.join(", ")}`);
    process.exit(1);
  }
  console.log(`\n${count} passed`);
}
