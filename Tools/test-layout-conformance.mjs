#!/usr/bin/env bun
// Tools/LayoutConformance: the report that compares SwiftUI's frames with the web build's, and the static fixture check.
// The expected report is a checked-in golden, produced from the same captures.
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { check } from "./LayoutConformance/check-fixtures.mjs";
import { compare, main as compareMain } from "./LayoutConformance/compare.mjs";
import { capture, finish, ROOT, test, withTemporary } from "./measurement-test-support.mjs";

const SPEC = {
  fixtures: [
    { id: "one", nodes: ["one.host", "one.a"] },
    { id: "two", nodes: ["two.host", "two.b", "two.gone"], tolerance: 3.0 },
    { id: "three", nodes: ["three.host"], tolerance: 0.5 },
  ],
};
// The same captures without the node only the web side has, so every node is measured and within tolerance.
const SPEC_PASSING = { fixtures: SPEC.fixtures.map((fixture) => ({ ...fixture, nodes: fixture.nodes.filter((node) => node !== "two.gone") })) };
const APPLE = {
  os: "macOS 99",
  nodes: {
    "one.host": { x: 0, y: 0, width: 390, height: 100.125 },
    "one.a": { x: 10.5, y: 20, width: 100.125, height: 44 },
    "two.host": { x: 0, y: 0, width: 390, height: 200 },
    "two.b": { x: 1, y: 2, width: 3, height: 4 },
    "three.host": { x: 0.0625, y: 0, width: 1.005, height: 2.675 },
  },
};
const WEB = {
  nodes: {
    "one.host": { x: 0, y: 0, width: 390, height: 100 },
    "one.a": { x: 10.5, y: 20.9, width: 100.25, height: 44 },
    "two.host": { x: 0, y: 0, width: 393.5, height: 200 },
    "two.gone": { x: 0, y: 0, width: 1, height: 1 },
    "two.b": { x: 1, y: 2, width: 3, height: 4 },
    "three.host": { x: 0.5625, y: 0, width: 1, height: 2.6 },
  },
};

const REPORT = `# SwiftUI Geometry Conformance Report

Apple: macOS 99

| Fixture | Node | Tol | Apple size | Web size | Δx | Δy | Δw | Δh | Status |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| one | \`one.host\` | 1.0 | 390.00×100.12 | 390.00×100.00 | 0.00 | 0.00 | 0.00 | 0.12 | PASS |
| one | \`one.a\` | 1.0 | 100.12×44.00 | 100.25×44.00 | 0.00 | 0.90 | 0.12 | 0.00 | PASS |
| two | \`two.host\` | 3.0 | 390.00×200.00 | 393.50×200.00 | 0.00 | 0.00 | 3.50 | 0.00 | FAIL |
| two | \`two.b\` | 3.0 | 3.00×4.00 | 3.00×4.00 | 0.00 | 0.00 | 0.00 | 0.00 | PASS |
| three | \`three.host\` | 0.5 | 1.00×2.67 | 1.00×2.60 | 0.50 | 0.00 | 0.00 | 0.07 | PASS |

Result: **FAIL** (4/5 measured nodes within tolerance)

## Failures
- two.host: max delta 3.50 > 3.00
- two.gone: missing Apple 
`;
const REPORT_PASSING = `# SwiftUI Geometry Conformance Report

Apple: unknown

| Fixture | Node | Tol | Apple size | Web size | Δx | Δy | Δw | Δh | Status |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| one | \`one.host\` | 1.0 | 390.00×100.12 | 390.00×100.00 | 0.00 | 0.00 | 0.00 | 0.12 | PASS |
| one | \`one.a\` | 1.0 | 100.12×44.00 | 100.25×44.00 | 0.00 | 0.90 | 0.12 | 0.00 | PASS |
| two | \`two.host\` | 3.0 | 390.00×200.00 | 392.00×200.00 | 0.00 | 0.00 | 2.00 | 0.00 | PASS |
| two | \`two.b\` | 3.0 | 3.00×4.00 | 3.00×4.00 | 0.00 | 0.00 | 0.00 | 0.00 | PASS |
| three | \`three.host\` | 0.5 | 1.00×2.67 | 1.00×2.60 | 0.50 | 0.00 | 0.00 | 0.07 | PASS |

Result: **PASS** (5/5 measured nodes within tolerance)
`;

await test("the report matches the golden, ties and failures included", () => {
  const { lines, failed } = compare(APPLE, WEB, SPEC);
  assert.equal(`${lines.join("\n")}\n`, REPORT);
  assert.deepEqual(failed, ["two.host: max delta 3.50 > 3.00", "two.gone: missing Apple "]);
});

await test("a capture within every tolerance passes", () => {
  const web = structuredClone(WEB);
  web.nodes["two.host"].width = 392;
  const apple = structuredClone(APPLE);
  delete apple.os;
  const { lines, failed } = compare(apple, web, SPEC_PASSING);
  assert.deepEqual(failed, []);
  assert.equal(`${lines.join("\n")}\n`, REPORT_PASSING);
});

await test("a node missing from the web capture is reported as missing Web", () => {
  const web = structuredClone(WEB);
  delete web.nodes["one.a"];
  assert.ok(compare(APPLE, web, SPEC).failed.includes("one.a: missing Web"));
});

await test("the command line writes the report, prints it and exits with the result", () =>
  withTemporary((directory) => {
    const write = (name, value) => {
      writeFileSync(join(directory, name), JSON.stringify(value));
      return join(directory, name);
    };
    const argv = (report, web, spec = SPEC) => ["--apple", write("apple.json", APPLE), "--web", web, "--fixtures", write("fixtures.json", spec), "--report", report];
    const report = join(directory, "report.md");
    const failing = capture(() => compareMain(argv(report, write("web.json", WEB))));
    assert.equal(failing.result, 1);
    assert.equal(readFileSync(report, "utf8"), REPORT);
    assert.equal(`${failing.out}\n`, REPORT);
    const passing = structuredClone(WEB);
    passing.nodes["two.host"].width = 392;
    assert.equal(capture(() => compareMain(argv(report, write("web-ok.json", passing), SPEC_PASSING))).result, 0);
    const missing = Bun.spawnSync(["bun", join(ROOT, "Tools/LayoutConformance/compare.mjs"), "--apple", "a"], { stdout: "pipe", stderr: "pipe" });
    assert.equal(missing.exitCode, 2);
    assert.match(missing.stderr.toString(), /the following arguments are required: --web, --fixtures, --report/);
  }));

const copy = (root, path) => {
  mkdirSync(join(root, path, ".."), { recursive: true });
  copyFileSync(join(ROOT, path), join(root, path));
};
const FILES = ["Tools/LayoutConformance/fixtures.json", "Tools/LayoutConformance/AppleOracle.swift", "Tests/Apps/LayoutConformanceApp/main.swift", "Package.swift"];
const copyRepository = (root) => FILES.forEach((path) => copy(root, path));

await test("the fixture check passes on the repository", () => {
  const out = [];
  assert.equal(check(ROOT, (line) => out.push(line), (line) => assert.fail(line)), 0);
  assert.deepEqual(out.map((line) => line.replace(/\d+/g, "N")), [
    "PASS main.swift: N explicit probes",
    "PASS AppleOracle.swift: N explicit probes",
    "PASS fixture manifest: N paired fixtures",
    "PASS public facade import contract",
    "PASS Embedded BrowserApp entrypoint contract",
  ]);
});

await test("a probe missing from the web app fails the check", () =>
  withTemporary((root) => {
    copyRepository(root);
    const path = join(root, "Tests/Apps/LayoutConformanceApp/main.swift");
    writeFileSync(path, readFileSync(path, "utf8").replace('probe("root-text.text")', 'probe("renamed")'));
    const out = [];
    assert.equal(check(root, (line) => out.push(line)), 1);
    assert.equal(out[0], "FAIL main.swift: missing probes: ['root-text.text']");
    assert.match(out[1], /^PASS AppleOracle\.swift/);
  }));

await test("duplicate fixture ids fail the check", () =>
  withTemporary((root) => {
    copyRepository(root);
    const path = join(root, "Tools/LayoutConformance/fixtures.json");
    const spec = JSON.parse(readFileSync(path, "utf8"));
    spec.fixtures.push({ ...spec.fixtures[0] });
    writeFileSync(path, JSON.stringify(spec));
    const out = [];
    assert.equal(check(root, (line) => out.push(line)), 1);
    assert.ok(out.includes("FAIL duplicate fixture IDs"));
  }));

await test("the public facade and BrowserApp contracts are enforced", () =>
  withTemporary((root) => {
    const rewrite = (path, edit) => writeFileSync(join(root, path), edit(readFileSync(join(root, path), "utf8")));
    for (const [path, edit, message] of [
      ["Tests/Apps/LayoutConformanceApp/main.swift", (text) => text.replace("import SwiftUIWeb\n", ""), "LayoutConformanceApp must import the public SwiftUIWeb facade"],
      ["Package.swift", (text) => text.replace('.executableTarget(name: "LayoutConformanceApp", dependencies: ["SwiftUIWeb", "SwiftUIWebBrowser"]', ".executableTarget(name: \"LayoutConformanceApp\", dependencies: [\"SwiftUIWeb\"]"), "LayoutConformanceApp target must depend on SwiftUIWeb and SwiftUIWebBrowser"],
      ["Tests/Apps/LayoutConformanceApp/main.swift", (text) => text.replace("struct LayoutConformanceApp: BrowserApp", "struct LayoutConformanceApp: App"), "LayoutConformanceApp must conform to BrowserApp so Embedded browser entrypoints are synthesized"],
    ]) {
      copyRepository(root);
      rewrite(path, edit);
      const errors = [];
      assert.equal(check(root, () => {}, (line) => errors.push(line)), 1);
      assert.deepEqual(errors, [`FAIL ${message}`]);
    }
  }));

await test("run.sh and the Makefile call the Bun scripts", () => {
  assert.match(readFileSync(join(ROOT, "Tools/LayoutConformance/run.sh"), "utf8"), /bun Tools\/LayoutConformance\/compare\.mjs --apple/);
  const make = Bun.spawnSync(["make", "-n", "layout-conformance-contract-test"], { cwd: ROOT, stdout: "pipe", stderr: "pipe" });
  assert.match(make.stdout.toString(), /bun Tools\/LayoutConformance\/check-fixtures\.mjs/);
});

finish();
