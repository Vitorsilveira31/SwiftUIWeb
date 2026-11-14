#!/usr/bin/env bun
// Regression tests of the static audits and gates (accessibility-audit, audit-browser-integration,
// audit-embedded-fallbacks, audit-test-layout, check-single-browser-runtime, architecture-audit).
// Each audit runs against a small fixture tree (`SWIFTUIWEB_AUDIT_ROOT`) built from the real
// files it reads: the intact tree must pass, and a deliberately broken one must fail.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { runCases } from "./audit-support.mjs";

const TOOLS = dirname(fileURLToPath(import.meta.url));
const REPOSITORY = dirname(TOOLS);
// Written in pieces: the single-runtime audit scans Tools/ for these words.
const FORBIDDEN = "Java" + "ScriptKit";
const MODE = "WASM" + "_MODE";

function fixture(files) {
  const root = mkdtempSync(join(tmpdir(), "audit-fixture-"));
  for (const file of files) {
    const target = join(root, file);
    mkdirSync(dirname(target), { recursive: true });
    cpSync(join(REPOSITORY, file), target, { recursive: true });
  }
  return root;
}
const put = (root, file, text) => {
  mkdirSync(dirname(join(root, file)), { recursive: true });
  writeFileSync(join(root, file), text);
};
const edit = (root, file, from, to) => {
  const text = readFileSync(join(root, file), "utf8");
  assert(text.includes(from), `${file} does not contain ${from}`);
  writeFileSync(join(root, file), text.replaceAll(from, () => to));
};
const run = (script, root, args = []) => {
  const result = spawnSync("bun", [join(TOOLS, script), ...args], { encoding: "utf8", env: { ...process.env, SWIFTUIWEB_AUDIT_ROOT: root } });
  return { status: result.status, out: result.stdout, err: result.stderr };
};
const using = (root, body) => {
  try {
    return body(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
};

const RUNTIME_FILES = [
  "Package.swift", "Makefile", "Tools/run-browser.sh", "Tools/run-browser-embedded.sh", "Tools/swiftuiweb-lowering.sh", "Tools/SwiftUIWebLowering/Package.swift",
  "Tools/SwiftUIWebLowering/Sources/LoweringCore", "Tests/Apps/EmbeddedLoweringConformanceApp/main.swift",
];
const checkNamed = (result, name) => JSON.parse(result.out).checks.find((item) => item.name === name);

await runCases({
  "accessibility-audit passes on the backend contract and fails without it"() {
    using(fixture(["Sources/SwiftUIWebCore/Accessibility.swift"]), (root) => {
      const ok = run("accessibility-audit.mjs", root);
      assert.equal(ok.status, 0);
      assert.equal(ok.out, "PASS accessibility backend source contract\n");
      edit(root, "Sources/SwiftUIWebCore/Accessibility.swift", "data-a11y-backend", "data-a11y");
      assert.notEqual(run("accessibility-audit.mjs", root).status, 0);
    });
  },
  "audit-browser-integration needs the connectivity cases and a Sendable-safe cancellation token"() {
    const files = ["Sources/SwiftUIWebNetworking/Networking.swift", "Sources/SwiftUIWebBrowser/BrowserApp.swift"];
    using(fixture(files), (root) => {
      const script = "BrowserIO/audit-browser-integration.mjs";
      const ok = run(script, root);
      assert.equal(ok.status, 0, ok.err);
      assert(ok.out.includes("PASS: Embedded Browser cancellation tokens do not directly capture BrowserIOOperation"));
      edit(root, files[1], "let box = _EmbeddedBrowserIOOperationBox()", "let box = nothing()");
      assert.notEqual(run(script, root).status, 0);
    });
    using(fixture(files), (root) => {
      edit(root, files[0], "  case online\n  case offline\n}", "  case online\n  case gone\n}");
      const result = run("BrowserIO/audit-browser-integration.mjs", root);
      assert.notEqual(result.status, 0);
      assert(result.err.includes("NetworkConnectivity missing offline"));
    });
  },
  "audit-embedded-fallbacks lists wasm32 and Embedded boundary lines"() {
    const root = mkdtempSync(join(tmpdir(), "audit-fixture-"));
    using(root, () => {
      put(root, "Sources/A/A.swift", "// fine\n#if arch(wasm32) && !hasFeature(Embedded)\n  #if hasFeature(Embedded)  // no-op here\nlet é = 1 // hasFeature(Embedded) unavailable\n");
      const result = run("audit-embedded-fallbacks.mjs", root);
      assert.equal(result.status, 0);
      const report = JSON.parse(result.out);
      assert.equal(report.status, "AUDIT");
      assert.equal(report.embedded_boundary_hits, 3);
      assert.deepEqual(report.items.map((item) => item.line), [2, 3, 4]);
      assert.equal(report.items[0].file, "Sources/A/A.swift");
      assert(result.out.includes("\\u00e9"), "non-ASCII text is escaped like json.dumps does");
    });
  },
  "audit-test-layout enforces the Sources/Examples/Tests boundary"() {
    const root = mkdtempSync(join(tmpdir(), "audit-fixture-"));
    using(root, () => {
      const manifest = (testPath, exePath) =>
        `let package = Package(targets: [\n  .executableTarget(name: "App", path: "${exePath}"),\n  .testTarget(name: "AppTests", dependencies: [], path: "${testPath}"),\n])\n`;
      put(root, "Package.swift", manifest("Tests/AppTests", "Examples/App"));
      put(root, "Examples/App/main.swift", "print(1)");
      put(root, "Examples/App/.build/checkouts/dep/Tests/DepTests.swift", "import XCTest");
      put(root, "Tests/AppTests/AppTests.swift", "import Testing");
      const ok = run("audit-test-layout.mjs", root);
      assert.equal(ok.status, 0, ok.out);
      assert.equal(JSON.parse(ok.out).status, "PASS");

      put(root, "Package.swift", manifest("Sources/Wrong", "Examples/App"));
      let result = run("audit-test-layout.mjs", root);
      assert.equal(result.status, 1);
      assert.deepEqual(JSON.parse(result.out).checks[0], { name: "test-targets-live-under-tests", status: "FAIL", detail: ["Sources/Wrong"] });

      put(root, "Package.swift", manifest("Tests/AppTests", "Elsewhere/App"));
      assert.deepEqual(checkNamed(run("audit-test-layout.mjs", root), "executable-targets-live-under-examples-or-test-apps").detail, ["Elsewhere/App"]);

      put(root, "Package.swift", manifest("Tests/AppTests", "Tests/Apps/App"));
      put(root, "Tests/Apps/App/main.swift", "print(1)");
      assert.equal(checkNamed(run("audit-test-layout.mjs", root), "executable-targets-live-under-examples-or-test-apps").status, "PASS");

      put(root, "Package.swift", manifest("Tests/AppTests", "Examples/App"));
      put(root, "Examples/App/Probe.swift", "import XCTest\n");
      put(root, "Tests/AppTests/Legacy.swift", "  import XCTest\n");
      put(root, "Tests/BrowserFixtures/Sources/Fixture.swift", "");
      result = run("audit-test-layout.mjs", root);
      assert.equal(result.status, 1);
      assert.deepEqual(checkNamed(result, "examples-do-not-import-xctest").detail, ["Examples/App/Probe.swift"]);
      assert.deepEqual(checkNamed(result, "swift-tests-use-swift-testing").detail, ["Tests/AppTests/Legacy.swift"]);
      assert.deepEqual(checkNamed(result, "no-redundant-browser-fixture-source-root").detail, ["Tests/BrowserFixtures/Sources"]);
    });
  },
  "check-single-browser-runtime rejects a second runtime and a missing lowerer"() {
    const status = (root) => run("check-single-browser-runtime.mjs", root);
    using(fixture(RUNTIME_FILES), (root) => {
      put(root, "Sources/Demo/Demo.swift", "struct Demo {}\n");
      const ok = status(root);
      assert.equal(ok.status, 0, ok.out);
      assert.equal(ok.out, "Single browser runtime audit: PASS\nBrowser runtime: Embedded Swift + BrowserIO only\n");
    });
    using(fixture(RUNTIME_FILES), (root) => {
      put(root, "Sources/Demo/Demo.swift", `import ${FORBIDDEN}\n`);
      put(root, "Tools/notes.txt", `${MODE}=standard\n`);
      put(root, "Tools/wasm-audit.mjs", `${MODE}\n`);
      const result = status(root);
      assert.equal(result.status, 1);
      assert.equal(
        result.out,
        `Single browser runtime audit: FAIL\nSources/Demo/Demo.swift: contains ${FORBIDDEN}\nTools/notes.txt: contains ${MODE}\n`,
      );
    });
    using(fixture(RUNTIME_FILES), (root) => {
      // The rule's name appears in several of the lowerer's sources; none may keep it.
      const lowererSources = "Tools/SwiftUIWebLowering/Sources/LoweringCore";
      for (const name of readdirSync(join(root, lowererSources))) {
        if (readFileSync(join(root, lowererSources, name), "utf8").includes("keyframe-track")) edit(root, `${lowererSources}/${name}`, "keyframe-track", "renamed-rule");
      }
      edit(root, "Tools/run-browser.sh", "run-browser-embedded.sh", `run-browser-embedded.sh ${MODE}`);
      const result = status(root);
      assert.equal(result.status, 1);
      assert(result.out.includes("embedded lowerer: missing rule keyframe-track"));
      assert(result.out.includes("Tools/run-browser.sh: runtime-selection reference"));
    });
    using(fixture(RUNTIME_FILES), (root) => {
      rmSync(join(root, "Tests/Apps/EmbeddedLoweringConformanceApp/main.swift"));
      assert(status(root).out.includes("EmbeddedLoweringConformanceApp: independent lowering fixture missing"));
    });
  },
  "architecture-audit writes its report and fails when the removed bridge returns"() {
    const files = ["Package.swift", "Makefile", "Tools/run-browser.sh"];
    using(fixture(files), (root) => {
      put(root, "Tools/check-single-browser-runtime.mjs", "// stand-in\n");
      put(root, "Sources/Demo/Demo.swift", "struct Demo {}\n// two\n");
      put(root, "Notes.md", "# notes\n");
      for (const command of [["init", "-q"], ["add", "-A"]]) spawnSync("git", command, { cwd: root });
      const ok = run("architecture-audit.mjs", root);
      assert.equal(ok.status, 0, ok.out + ok.err);
      const report = JSON.parse(ok.out);
      assert.equal(report.status, "PASS");
      // Package.swift is a tracked Swift file too.
      const manifestLines = readFileSync(join(REPOSITORY, "Package.swift"), "utf8").split("\n").length - 1;
      assert.deepEqual(report.current.swift, { files: 2, loc: manifestLines + 2 });
      assert.deepEqual(report.current.documentation, { files: 1, loc: 1 });
      assert.equal(report.bundle.status, "unavailable");
      const written = JSON.parse(readFileSync(join(root, ".build/architecture-audit/report.json"), "utf8"));
      assert.deepEqual(written, report);
      const markdown = readFileSync(join(root, ".build/architecture-audit/report.md"), "utf8");
      assert(markdown.startsWith("# Architecture audit\n\nStatus: **PASS**\n"));
      assert(markdown.includes(`| swift | {'files': 196, 'loc': 49112} | {'files': 2, 'loc': ${manifestLines + 2}} | n/a |`));
      assert(markdown.endsWith("browser execution is Embedded Swift through BrowserIO.\n"));

      put(root, "Sources/Demo/Bridge.swift", `import ${FORBIDDEN}\n`);
      const broken = run("architecture-audit.mjs", root);
      assert.equal(broken.status, 1);
      assert.equal(JSON.parse(broken.out).checks.find((item) => item.name === "no-production-js-bridge").status, "FAIL");
    });
  },
  "lint-styles.mjs and the semantic wiring tests pass on the repository"() {
    assert.equal(spawnSync("bun", [join(TOOLS, "lint-styles.mjs")], { encoding: "utf8" }).status, 0);
    const wiring = spawnSync("bun", [join(TOOLS, "test-semantic-integration.mjs")], { encoding: "utf8" });
    assert.equal(wiring.status, 0, wiring.stdout);
    assert(existsSync(join(REPOSITORY, "Tools/styles.css")));
  },
}, "test-audits");
