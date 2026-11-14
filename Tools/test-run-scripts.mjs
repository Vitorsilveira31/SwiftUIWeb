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
  const slow = script("slow", 'await Bun.sleep(300); console.log("slow done");');
  const fast = script("fast", 'console.log("fast one"); console.log("fast two");');
  const broken = script("broken", 'console.error("broken output"); process.exit(3);');
  const started = Date.now();
  const results = await runScripts([slow, `${fast} --flag`, broken, slow]);
  assert.ok(Date.now() - started < 1000, "the scripts ran at the same time");
  assert.deepEqual(results.map((result) => result.ok), [true, true, false, true]);
  assert.equal(results[1].output, "fast one\nfast two\n");
  assert.equal(results[2].code, 3);
  assert.match(results[2].output, /broken output/);
  console.log("ok - run-scripts: parallel scripts, whole outputs, failures reported");
} finally {
  rmSync(directory, { recursive: true, force: true });
}
