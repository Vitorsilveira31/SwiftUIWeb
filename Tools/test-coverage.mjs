#!/usr/bin/env bun
// Tools/coverage.mjs: the LCOV and LLVM-export parsing, the per-module summary, the gate and the report files.
// The expected report text is a checked-in golden, produced from the same inputs, apart
// from the command line it names in the markdown.
import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { buildReport, gate, markdown, metricSummary, parseLcov, summaryFromFiles } from "./coverage.mjs";
import { dumps } from "./format-compat.mjs";
import { finish, ROOT, test, withTemporary } from "./measurement-test-support.mjs";

await test("the LCOV parser counts zero and positive hits", () =>
  withTemporary((directory) => {
    const path = join(directory, "coverage.info");
    writeFileSync(path, "TN:\nSF:Tools/BrowserIO/fixture.mjs\nDA:1,2\nDA:2,0\nDA:2,4\nend_of_record\n");
    assert.deepEqual(parseLcov(path)["Tools/BrowserIO/fixture.mjs"], { count: 3, covered: 2, function_count: 0, function_covered: 0, branch_count: 0, branch_covered: 0 });
  }));

await test("the LCOV parser preserves function and branch metrics", () =>
  withTemporary((directory) => {
    const path = join(directory, "coverage.info");
    writeFileSync(path, "TN:\nSF:Tools/BrowserIO/runtime.mjs\nFNF:3\nFNH:2\nBRF:4\nBRH:3\nDA:1,1\nend_of_record\n");
    assert.deepEqual(parseLcov(path)["Tools/BrowserIO/runtime.mjs"], { count: 1, covered: 1, function_count: 3, function_covered: 2, branch_count: 4, branch_covered: 3 });
  }));

await test("the LLVM summary scopes controlled sources and tracks branches", () => {
  const files = [
    { filename: "/workspace/Sources/WebFoundation/JSONValue.swift", summary: { lines: { count: 4, covered: 3 }, functions: { count: 2, covered: 2 }, branches: { count: 2, covered: 1 } } },
    { filename: "/workspace/.build/checkouts/dependency/src/lib.rs", summary: { lines: { count: 100, covered: 0 }, functions: { count: 10, covered: 0 }, branches: { count: 10, covered: 0 } } },
  ];
  const summary = summaryFromFiles(files, (filename) => filename.includes("/Sources/"));
  assert.equal(dumps(summary.lines), '{"count": 4, "covered": 3, "percent": 75.0}');
  assert.equal(dumps(summary.branches), '{"count": 2, "covered": 1, "percent": 50.0}');
});

await test("the gate blocks regressions and the strict target is explicit", () => {
  const result = { modules: { WebFoundation: metricSummary(10, 9, 1, 1, 0, 0, { files: 1 }) } };
  const policy = { targetLine: 100, targetBranch: 100, minimumLine: { WebFoundation: 95 }, minimumFunction: { WebFoundation: 100 } };
  assert.ok(gate(result, policy, false).length > 0);
  assert.ok(gate(result, policy, true).length > 0);
  result.modules.WebFoundation = metricSummary(10, 10, 1, 1, 0, 0, { files: 1 });
  assert.deepEqual(gate(result, policy, true), []);
});

await test("the gate enforces the function floor when configured", () => {
  const result = { modules: { "Tools/BrowserIO": metricSummary(10, 10, 10, 8, 0, 0, { files: 2 }) } };
  const policy = { targetLine: 100, targetBranch: 100, minimumLine: { "Tools/BrowserIO": 100 }, minimumFunction: { "Tools/BrowserIO": 90 } };
  const failures = gate(result, policy, false);
  assert.equal(failures.length, 1);
  assert.match(failures[0], /functions is below regression floor/);
});

await test("percentages round to two decimals, ties to the even digit", () => {
  // 97/800 is exactly 12.125 and that tie rounds to the even digit.
  assert.equal(String(metricSummary(800, 97, 0, 0, 0, 0, { files: 1 }).lines.percent), "12.12");
  assert.equal(String(metricSummary(3, 2, 0, 0, 0, 0, { files: 1 }).lines.percent), "66.67");
  assert.equal(metricSummary(0, 0, 0, 0, 0, 0, { files: 0 }).lines.percent, null);
});

const GOLDEN_REPORT = `{
  "modules": {
    "Core": {
      "branches": {
        "count": 0,
        "covered": 0,
        "percent": null
      },
      "files": 3,
      "functions": {
        "count": 10,
        "covered": 2,
        "percent": 20.0
      },
      "lines": {
        "count": 1005,
        "covered": 101,
        "percent": 10.05
      }
    },
    "Fiber": {
      "branches": {
        "count": 4,
        "covered": 3,
        "percent": 75.0
      },
      "files": 1,
      "functions": {
        "count": 10,
        "covered": 10,
        "percent": 100.0
      },
      "lines": {
        "count": 1000,
        "covered": 999,
        "percent": 99.9
      }
    },
    "Tools/BrowserIO": {
      "branches": {
        "count": 4,
        "covered": 3,
        "percent": 75.0
      },
      "files": 2,
      "functions": {
        "count": 3,
        "covered": 2,
        "percent": 66.67
      },
      "lines": {
        "count": 4,
        "covered": 3,
        "percent": 75.0
      }
    }
  },
  "policy": {
    "minimumFunction": {
      "Core": 50
    },
    "minimumLine": {
      "Core": 10,
      "Fiber": 99.9
    },
    "requirePolicyForModules": true,
    "targetBranch": 100,
    "targetLine": 100
  }
}
`;
const GOLDEN_MARKDOWN = `# SwiftUIWeb coverage audit

Long-term line target: **100%**; semantic branch target: **100%**.

| Module | Files | Lines | Functions | Branch maps |
|---|---:|---:|---:|---:|
| \`Core\` | 3 | 10.05% (101/1005) | 20.00% (2/10) | unsupported |
| \`Fiber\` | 1 | 99.90% (999/1000) | 100.00% (10/10) | 75.00% (3/4) |
| \`Tools/BrowserIO\` | 2 | 75.00% (3/4) | 66.67% (2/3) | 75.00% (3/4) |

LLVM 21 currently emits no branch maps for Swift source files; this is recorded as \`unsupported\`, not treated as 100%. C/host branch maps and BrowserIO line coverage remain observable separately. Semantic branch behavior is covered by the checked-in failure/fallback/cancellation/lifecycle/property and browser-host suites.

The regression gate uses the floors in \`Tools/coverage-policy.json\`. Run \`bun Tools/coverage.mjs --strict-target\` when evaluating the 100% milestone.
`;

// The report is the golden, byte for byte, except that a dependency's sources (under `.build/checkouts/`) are left out.
await test("a report over Swift and BrowserIO data leaves out dependency sources", () =>
  withTemporary((directory) => {
    const file = (filename, lines, covered, functions, functionsCovered, branches = 0, branchesCovered = 0) => ({
      filename,
      summary: { lines: { count: lines, covered }, functions: { count: functions, covered: functionsCovered }, branches: { count: branches, covered: branchesCovered } },
    });
    const write = (name, files) => {
      const path = join(directory, name);
      writeFileSync(path, JSON.stringify({ data: [{ files }] }));
      return path;
    };
    const swiftA = write("swift-a.json", [
      file("/w/Sources/Core/A.swift", 800, 97, 8, 1), file("/w/Sources/Core/B.swift", 3, 3, 1, 1), file("/w/Sources/Core/B.swift", 5, 1, 2, 1),
      file("/w/Sources/Fiber/C.swift", 1000, 999, 10, 10, 4, 3), file("/w/.build/checkouts/x/Sources/Dep/D.swift", 10, 0, 1, 0), file("/w/other/E.swift", 1, 1, 1, 1),
    ]);
    const swiftB = write("swift-b.json", [file("/w/Sources/Core/Z.swift", 200, 3, 0, 0)]);
    const lcov = join(directory, "lcov.info");
    writeFileSync(
      lcov,
      "TN:\nSF:Tools/BrowserIO/browser-io.mjs\nFNF:3\nFNH:2\nBRF:4\nBRH:3\nDA:1,1\nDA:2,0\nDA:3,5\nend_of_record\nSF:Tools/BrowserIO/protocol.generated.mjs\nDA:1,1\nend_of_record\nSF:Tools/BrowserIO/host.test.mjs\nDA:1,0\nend_of_record\n",
    );
    const result = buildReport([swiftA, swiftB], lcov);
    const policy = {
      targetLine: 100, targetBranch: 100, minimumLine: { Core: 10, Fiber: 99.9 },
      minimumFunction: { Core: 50 }, requirePolicyForModules: true,
    };
    result.policy = policy;
    assert.equal(`${dumps(result, { indent: 2, sortKeys: true })}\n`, GOLDEN_REPORT);
    assert.equal(markdown(result, policy), GOLDEN_MARKDOWN);
    assert.deepEqual(gate(result, policy, false), [
      "Core: 20.00% functions is below regression floor 50.00%",
      "Tools/BrowserIO: no regression floor is defined in coverage-policy.json",
    ]);
    assert.equal(gate(result, policy, true).length, 5);
  }));

await test("the command line prints help with the percent signs, and rejects unknown options with status 2", () => {
  const help = Bun.spawnSync(["bun", join(ROOT, "Tools/coverage.mjs"), "--help"], { stdout: "pipe", stderr: "pipe" });
  assert.equal(help.exitCode, 0);
  assert.match(help.stdout.toString(), /100%/);
  const bad = Bun.spawnSync(["bun", join(ROOT, "Tools/coverage.mjs"), "--nope"], { stdout: "pipe", stderr: "pipe" });
  assert.equal(bad.exitCode, 2);
  assert.match(bad.stderr.toString(), /unrecognized arguments: --nope/);
});

await test("make coverage runs the Bun tool", () => {
  const make = Bun.spawnSync(["make", "-n", "coverage"], { cwd: ROOT, stdout: "pipe", stderr: "pipe" });
  assert.equal(make.exitCode, 0, make.stderr.toString());
  assert.match(make.stdout.toString(), /bun Tools\/coverage\.mjs --gate/);
});

finish();
