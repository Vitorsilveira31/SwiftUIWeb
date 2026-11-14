#!/usr/bin/env bun
// Tools/run-test-groups.mjs: groups run at the same time, the targets of a group in order, and a failure is reported
// without stopping the other targets.
import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseGroups, runGroups } from "./run-test-groups.mjs";

const directory = mkdtempSync(join(tmpdir(), "test-groups-"));
try {
  assert.deepEqual(parseGroups(["a: x y", " b :z "]), [
    { name: "a", targets: ["x", "y"] },
    { name: "b", targets: ["z"] },
  ]);
  assert.throws(() => parseGroups(["no colon"]), /name: target/);

  // A stand-in for make: it appends the target it was given to a journal, sleeps a little, and fails for "broken".
  const journal = join(directory, "journal");
  const make = join(directory, "make");
  writeFileSync(make, `#!/bin/bash\necho "start $2" >> "${journal}"\nsleep 0.2\necho "end $2" >> "${journal}"\n[ "$2" != broken ]\n`);
  chmodSync(make, 0o755);
  const lines = [];
  const results = await runGroups(parseGroups(["one: a1 broken a3", "two: b1"]), { make, print: (line) => lines.push(line) });

  assert.deepEqual(results.map((result) => [result.target, result.ok]).sort(), [["a1", true], ["a3", true], ["b1", true], ["broken", false]]);
  const events = (await Bun.file(journal).text()).trim().split("\n");
  // In a group, a target starts only after the previous one ended; the other group overlaps it.
  assert.ok(events.indexOf("end a1") < events.indexOf("start broken"));
  assert.ok(events.indexOf("end broken") < events.indexOf("start a3"), "a failure does not stop the rest of its group");
  assert.ok(events.indexOf("start b1") < events.indexOf("end a1"), "the groups run at the same time");
  assert.ok(lines.some((line) => line.startsWith("FAIL(1)  broken")));
  console.log("ok - run-test-groups: parallel groups, ordered targets, failures reported");
} finally {
  rmSync(directory, { recursive: true, force: true });
}
