#!/usr/bin/env bun
// Tools/run-scripts.mjs: scripts run at the same time, each one's output is kept whole, and a failure is reported
// without stopping the others.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runScripts } from "./run-scripts.mjs";

const directory = mkdtempSync(join(tmpdir(), "run-scripts-"));
try {
  const script = (name, body) => {
    const path = join(directory, `${name}.mjs`);
    writeFileSync(path, body);
    return path;
  };
  // Each slow run prints when it started and ended; the two runs overlap if they ran at the same time, however long the
  // machine takes to start a process (a total-time bound failed on a loaded machine).
  const slow = script("slow", 'const start = Date.now(); await Bun.sleep(300); console.log(JSON.stringify({ start, end: Date.now() }));');
  const fast = script("fast", 'console.log("fast one"); console.log("fast two");');
  const broken = script("broken", 'console.error("broken output"); process.exit(3);');
  const results = await runScripts([slow, `${fast} --flag`, broken, slow]);
  const [first, second] = [results[0], results[3]].map((result) => JSON.parse(result.output));
  assert.ok(first.start < second.end && second.start < first.end, "the scripts ran at the same time");
  assert.deepEqual(results.map((result) => result.ok), [true, true, false, true]);
  assert.equal(results[1].output, "fast one\nfast two\n");
  assert.equal(results[2].code, 3);
  assert.match(results[2].output, /broken output/);
  console.log("ok - run-scripts: parallel scripts, whole outputs, failures reported");
} finally {
  rmSync(directory, { recursive: true, force: true });
}
