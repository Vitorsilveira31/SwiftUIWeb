// Source-to-source lowering regression checks. The production lowerer is the Swift tool; these tests run the same CLI the
// browser launcher uses (Tools/swiftuiweb-lowering.sh) against isolated Swift sources.
// Run with `bun test ./Tools/test-lowering.mjs`.
import { describe, expect, setDefaultTimeout, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// The first run builds the Swift lowerer (swift-syntax), which takes longer than bun's default timeout.
setDefaultTimeout(600_000);

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const LOWERER = join(ROOT, "Tools", "swiftuiweb-lowering.sh");
const FIXTURES = join(ROOT, "Tests/EmbeddedUI/lowering-fixtures");

function withTempDir(body) {
  const folder = mkdtempSync(join(tmpdir(), "swiftuiweb-lowering-"));
  try {
    return body(folder);
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
}

function run(args) {
  return spawnSync(LOWERER, args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

function runChecked(args) {
  const result = run(args);
  if (result.status !== 0) throw new Error(`${LOWERER} ${args.join(" ")} failed:\n${result.stderr}`);
  return result;
}

// Runs the production lowerer against an isolated Swift source file.
function lowerSnippet(source, { lowerCodable = false } = {}) {
  return withTempDir((temp) => {
    const sourceRoot = join(temp, "source");
    const workspace = join(temp, "workspace");
    mkdirSync(join(sourceRoot, "Sources"), { recursive: true });
    writeFileSync(join(sourceRoot, "Sources", "Fixture.swift"), source);
    const args = ["--apply", "--root", sourceRoot, "--product", "Fixture", "--workspace", workspace];
    if (lowerCodable) args.push("--lower-codable");
    const result = runChecked(args);
    let report = JSON.parse(result.stdout);
    const metadata = join(sourceRoot, ".build/embedded-source-lowering/report.json");
    if (existsSync(metadata)) report = JSON.parse(readFileSync(metadata, "utf8"));
    const output = readFileSync(join(workspace, "Sources", "Fixture.swift"), "utf8");
    return { output, counts: report.rules, report };
  });
}

// Runs the lowerer on a one-file source tree and returns the failed result.
function lowerExpectingFailure(source) {
  return withTempDir((temp) => {
    const sourceRoot = join(temp, "source");
    mkdirSync(join(sourceRoot, "Sources"), { recursive: true });
    writeFileSync(join(sourceRoot, "Sources", "Fixture.swift"), source);
    return run(["--apply", "--root", sourceRoot, "--product", "Fixture"]);
  });
}

function swiftFiles(folder) {
  return readdirSync(folder, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".swift"))
    .map((entry) => join(entry.parentPath ?? entry.path, entry.name));
}

function hashes(folder, paths) {
  const result = {};
  for (const path of paths) {
    result[relative(folder, path)] = createHash("sha256").update(readFileSync(path)).digest("hex");
  }
  return result;
}

describe("LoweringTests", () => {
  test("golden projection fixture", () => {
    const source = readFileSync(join(FIXTURES, "projections.input.swift"), "utf8");
    const expected = readFileSync(join(FIXTURES, "projections.expected.swift"), "utf8");
    expect(lowerSnippet(source).output).toBe(expected);
  });

  test("golden complex observation fixture", () => {
    const source = readFileSync(join(FIXTURES, "complex.input.swift"), "utf8");
    const expected = readFileSync(join(FIXTURES, "complex.expected.swift"), "utf8");
    const { output, counts } = lowerSnippet(source);
    expect(output).toBe(expected);
    expect(counts["observable-attribute"]).toBe(2);
    expect(counts["observable-published"]).toBe(3);
  });

  test("negative fixture is byte stable", () => {
    const source = readFileSync(join(FIXTURES, "negative.input.swift"), "utf8");
    const expected = readFileSync(join(FIXTURES, "negative.expected.swift"), "utf8");
    const { output, counts } = lowerSnippet(source);
    expect(output).toBe(expected);
    expect(counts).toEqual({});
  });

  test("writable keyframe is a real projection", () => {
    const { output } = lowerSnippet(String.raw`KeyframeTrack(\.scale) { LinearKeyframe(2.0, duration: 1) }`);
    expect(output).toContain("_embeddedGet: { $0.scale }");
    expect(output).toContain("_embeddedSet: { $0.scale = $1 }");
  });

  test("binding member projection uses closures", () => {
    const { output, counts } = lowerSnippet("TextField(text: $viewModel.title)");
    expect(output).toContain("Binding(get: { viewModel.title }, set: { viewModel.title = $0 })");
    expect(counts["binding-member"]).toBe(1);
  });

  test("observable view model uses the state object initializer", () => {
    const source = `
@Observable
final class DashboardViewModel {
  var loading = true
}

struct DashboardView: View {
  @State private var viewModel: DashboardViewModel

  init() {
    _viewModel = State(wrappedValue: DashboardViewModel())
  }
}
`;
    const { output, counts } = lowerSnippet(source);
    expect(output).toMatch(/final class DashboardViewModel\s*\{/);
    expect(output).toContain("@Published(memberID: 1) var loading = true");
    expect(output).toContain("@StateObject private var viewModel");
    expect(output).toContain("_viewModel = StateObject(wrappedValue: DashboardViewModel())");
    expect(counts["state-observable-model"]).toBe(1);
    expect(counts["state-observable-init"]).toBe(1);
  });

  test("observable lowering covers inline, generic and ignored models", () => {
    const source = `
@MainActor @Observable final class InlineModel<T> where T: Equatable {
  @ObservationIgnored var cache = 0
  var value: T?
  var computed: Int { cache }
}

@Observable final class NestedModel {
  var value = 1
}
`;
    const { output, counts } = lowerSnippet(source);
    expect(output).not.toContain("@Observable");
    expect(output).not.toContain("@ObservationIgnored");
    expect(output).toContain("@Published(memberID: 1) var value: T?");
    expect(output).toContain("@Published(memberID: 1) var value = 1");
    expect(output).toContain("var computed: Int { cache }");
    expect(counts["observable-attribute"]).toBe(2);
    expect(counts["observable-published"]).toBe(2);
    expect(counts["observation-ignored"]).toBe(1);
    const again = lowerSnippet(output);
    expect(again.output).toBe(output);
    expect(again.counts).toEqual({});
  });

  test("main actor observable members get stable ids", () => {
    const source = `
@Observable @MainActor final class TrackerPurchaseViewModel {
  private(set) var state: State
  var progress = 0
  private let catalog: Any
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var requestID = UUID()
}
`;
    const { output, counts } = lowerSnippet(source);
    expect(output).toContain("@MainActor final class TrackerPurchaseViewModel");
    expect(output).toContain("@Published(memberID: 1) private(set) var state: State");
    expect(output).toContain("@Published(memberID: 2) var progress = 0");
    expect(output).toContain("var task: Task<Void, Never>?");
    expect(output).toContain("var requestID = UUID()");
    expect(output).not.toContain("@ObservationIgnored");
    expect(counts["observable-published"]).toBe(2);
    expect(counts["observation-ignored"]).toBe(2);
  });

  test("observable member initialized by init remains assignable", () => {
    const source = `
@Observable final class Model {
  private(set) var state: State

  init(state: State) {
    self.state = state
  }
}
`;
    const { output, counts } = lowerSnippet(source);
    expect(output).toContain("@Published(memberID: 1) private(set) var state: State");
    // The init assigns through the wrapper so the member keeps its memberID.
    expect(output).toContain("_state = Published(wrappedValue: state, memberID: 1)");
    expect(output).not.toContain("self.state = state");
    expect(output).not.toContain("var state: State =");
    expect(counts["observable-published"]).toBe(1);

    const again = lowerSnippet(output);
    expect(again.output).toBe(output);
    expect(again.counts).toEqual({});
  });

  test("optional observable members receive the embedded default", () => {
    const { output, counts } = lowerSnippet("@Observable final class Model { var value: Int? }");
    expect(output).toContain("@Published(memberID: 1) var value: Int? = nil");
    expect(counts["observable-published"]).toBe(1);
  });

  test("observable scan handles unicode before the declaration", () => {
    const { output, counts } = lowerSnippet('let label = "café"\n@Observable final class Model { var value = 1 }');
    expect(output).toContain("@Published(memberID: 1) var value = 1");
    expect(counts["observable-attribute"]).toBe(1);
  });

  test("observable lowering fails closed for an unsupported declaration", () => {
    const result = lowerExpectingFailure("@Observable struct NotAReferenceModel { var value = 0 }");
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("Sources/Fixture.swift:1:1: [SWUI-L001]");
    expect(result.stderr).toContain("struct `NotAReferenceModel`");
    expect(result.stderr).toContain("make it a class");
  });

  test("enum identity is not lost", () => {
    const { output } = lowerSnippet(String.raw`ForEach(routes, id: \.self) { Text($0.title) }`);
    expect(output).toContain("id: { $0 }");
  });

  test("all public projection rules", () => {
    const source = String.raw`@Environment(\.colorScheme) var scheme
ForEach(rows, id: \.id) { row in Text(row.name) }
ForEach(rows, id: \.self) { row in Text(row.name) }
OutlineGroup(nodes, children: \.children) { node in Text(node.name) }
TableColumn("Name", value: \.name)
TableColumn("Name", value: \Row.name)
KeyframeTrack(\.scale) { LinearKeyframe(1.0, duration: 1) }
let names = rows.map(\.name)
let filtered = rows.filter(\.visible)
`;
    const { output, counts } = lowerSnippet(source);
    for (const fragment of [
      "_embedded:",
      "id: { $0.id }",
      "id: { $0 }",
      "_embeddedChildren:",
      "row in Text(row.name)",
      "_embeddedGet: { $0.scale }",
      ".map { $0.name }",
      ".filter { $0.visible }",
    ]) {
      expect(output).toContain(fragment);
    }
    expect(counts["foreach-id-member"]).toBe(1);
    expect(counts["foreach-id-self"]).toBe(1);
    expect(counts["table-column-value"]).toBe(2);
  });

  test("comments and strings are not rewritten", () => {
    const source = String.raw`// ForEach(rows, id: \.id)
let text = "ForEach(rows, id: \\.id)"
let raw = #"a quote: \" and ForEach(rows, id: \\.id)"#
/* KeyframeTrack(\.scale) */
ForEach(rows, id: \.id) { _ in Text("ok") }
`;
    const { output, counts } = lowerSnippet(source);
    expect(output).toContain(String.raw`// ForEach(rows, id: \.id)`);
    expect(output).toContain(String.raw`"ForEach(rows, id: \\.id)"`);
    expect(output).toContain(String.raw`ForEach(rows, id: \\.id)`);
    expect(output).toContain(String.raw`/* KeyframeTrack(\.scale) */`);
    expect(counts["foreach-id-member"]).toBe(1);
  });

  test("lowering is idempotent", () => {
    const source = String.raw`ForEach(rows, id: \.id) { row in Text(row.name) } KeyframeTrack(\.scale) { }`;
    const once = lowerSnippet(source).output;
    const twice = lowerSnippet(once);
    expect(twice.output).toBe(once);
    expect(twice.counts).toEqual({});
  });

  // The debug development loop of the Embedded profile lowers with options no other build passes (the ones
  // Tools/run-browser-embedded.sh gives the framework and a consumer application), and with them the passes write into
  // each other's output: `export-interface` marks the `_installState()` that `state-installation` wrote. A run fails when
  // lowering its own output would change it (SWUI-L002), so the framework and an example package must lower with them.
  test("the real sources lower with the development loop's options", () => {
    withTempDir((temp) => {
      const framework = join(temp, "framework");
      cpSync(join(ROOT, "Sources"), join(framework, "Sources"), { recursive: true });
      cpSync(join(ROOT, "Tests", "Apps"), join(framework, "Tests", "Apps"), { recursive: true });
      cpSync(join(ROOT, "Package.swift"), join(framework, "Package.swift"));
      const genericTypes = join(temp, "framework-generic-types.txt");
      const loop = ["--apply", "--development-exports", "--export-interface", "--stable-source-locations"];
      runChecked([
        ...loop, "--root", framework, "--product", "MotionApp", "--workspace", join(temp, "framework-workspace"),
        "--report", join(temp, "framework-report.json"), "--generic-types-out", genericTypes,
      ]);
      runChecked([
        ...loop, "--export-interface-application", "--generic-types-in", genericTypes, "--lower-codable",
        "--root", join(ROOT, "Examples/UniversalApp"), "--product", "UniversalWebApp",
        "--workspace", join(temp, "application-workspace"), "--report", join(temp, "application-report.json"),
      ]);
      // Both runs met the case: a view that keeps state and is not generic, whose installation is marked.
      const installation = /@export\(interface\) (public )?func _installState\(\)/g;
      const marked = (path) => readFileSync(join(temp, path), "utf8").match(installation)?.length ?? 0;
      expect(marked("framework-workspace/Sources/SwiftUIWebWeb/WebContent.swift")).toBeGreaterThan(0);
      expect(marked("application-workspace/Sources/Shared/SharedViews.swift")).toBeGreaterThan(0);
    });
  }, 120_000);

  test("real showcase restores byte for byte and generates valid syntax", () => {
    withTempDir((temp) => {
      for (const name of ["Sources", "Examples"]) cpSync(join(ROOT, name), join(temp, name), { recursive: true });
      cpSync(join(ROOT, "Tests", "Apps"), join(temp, "Tests", "Apps"), { recursive: true });
      cpSync(join(ROOT, "Package.swift"), join(temp, "Package.swift"));
      const paths = swiftFiles(temp);
      const before = hashes(temp, paths);
      runChecked(["--apply", "--root", temp, "--product", "ShowcaseApp"]);
      const pkg = readFileSync(join(temp, "Package.swift"), "utf8");
      const showcase = readFileSync(join(temp, "Tests/Apps/ShowcaseApp/main.swift"), "utf8");
      expect(pkg).toContain("embedded_browser_html_pointer");
      expect(pkg).toContain("--export=embedded_browser_set_initial_preferences");
      // The generated reactor must declare exactly the application exports the package links: a callback
      // exported without a body fails at instantiation, and one without an export is dead. The exports
      // implemented in C (`browser_io_free`) have no Swift body.
      const nativeExports = ["browser_io_free"];
      const exported = new Set(
        [...pkg.matchAll(/--export=(\w+)/g)]
          .map((match) => match[1])
          .filter((name) => !nativeExports.some((native) => name.startsWith(native))),
      );
      const declared = [...showcase.matchAll(/@_cdecl\("(\w+)"\)/g)].map((match) => match[1]);
      expect(declared.length).toBe(new Set(declared).size);
      expect(new Set(declared)).toEqual(exported);
      expect(showcase).toContain("embedded_browser_set_initial_preferences");
      expect(showcase).toContain("embedded_browser_history_location");
      expect(showcase).not.toContain(String.raw`KeyframeTrack(\.`);
      const swiftc = spawnSync("which", ["swiftc"], { encoding: "utf8" });
      if (swiftc.status === 0) {
        for (const path of [join(temp, "Package.swift"), join(temp, "Tests/Apps/ShowcaseApp/main.swift")]) {
          const parsed = spawnSync(swiftc.stdout.trim(), ["-frontend", "-parse", path], { encoding: "utf8" });
          expect(parsed.status).toBe(0);
        }
      }
      runChecked(["--restore", "--root", temp]);
      expect(hashes(temp, paths)).toEqual(before);
      expect(existsSync(join(temp, ".build/embedded-source-lowering/state.json"))).toBe(false);
    });
  }, 120_000);

  test("disposable workspace preserves the checkout", () => {
    withTempDir((folder) => {
      const source = join(folder, "source");
      const workspace = join(folder, "workspace");
      for (const name of ["Sources", "Examples", "Plugins"]) cpSync(join(ROOT, name), join(source, name), { recursive: true });
      cpSync(join(ROOT, "Tests", "Apps"), join(source, "Tests", "Apps"), { recursive: true });
      cpSync(join(ROOT, "Package.swift"), join(source, "Package.swift"));
      const mainPath = join(source, "Tests/Apps/ShowcaseApp/main.swift");
      const before = readFileSync(mainPath);
      const result = runChecked(["--apply", "--root", source, "--product", "ShowcaseApp", "--workspace", workspace]);
      expect(readFileSync(mainPath).equals(before)).toBe(true);
      expect(result.stdout).toContain("status");
      expect(readFileSync(join(workspace, "Tests/Apps/ShowcaseApp/main.swift"), "utf8")).not.toContain(String.raw`KeyframeTrack(\.`);
      expect(existsSync(join(workspace, "Plugins/SwiftUIWebPlugin"))).toBe(true);
      const reportPath = join(source, ".build/embedded-source-lowering/report.json");
      expect(existsSync(reportPath)).toBe(true);
      const report = JSON.parse(readFileSync(reportPath, "utf8"));
      expect(report.version).toBe(4);
      expect(report.sourceMap.length).toBeGreaterThan(0);
      expect(report.sourceMap[0]).toHaveProperty("lineMap");
      expect(report.sourceMap[0].mappings.length).toBeGreaterThan(0);
      expect(new Set(Object.keys(report.sourceMap[0].hashes))).toEqual(new Set(["source", "generated"]));
      expect(report.diagnostics.length).toBeGreaterThan(0);
    });
  }, 120_000);

  test("complex fixture has file:line:column diagnostics and source points", () => {
    const source = `import Observation
let raw = #"ForEach(rows, id: \\.id) { { not code } }"#
/* braces in comments must not change declaration matching */
@MainActor @Observable final class Complex<T> where T: Equatable {
  @ObservationIgnored private var cache: [String: T] = [:]
  private(set) var values: [String: [Int: T]]
  var title: String = "{still a string}"
  var computed: String { title }
}
@Observable final class Second { var count = 0 }
`;
    const { output, report } = lowerSnippet(source);
    expect(output).toContain("@Published(memberID: 1) private(set) var values");
    expect(output).toContain("@Published(memberID: 2) var title");
    expect(output).toContain("@Published(memberID: 1) var count");
    expect(output).not.toContain("@Observable");
    const diagnostic = report.diagnostics.find((item) => item.message.includes("observable-attribute"));
    expect(diagnostic).toBeDefined();
    expect(diagnostic.file).toBe("Sources/Fixture.swift");
    expect(diagnostic.line).toBe(4);
    expect(diagnostic.column).toBeGreaterThanOrEqual(1);
    const mapping = report.sourceMap[0].mappings;
    expect(mapping.every((point) => "generated" in point && "source" in point)).toBe(true);
    const again = lowerSnippet(output);
    expect(again.output).toBe(output);
    expect(again.counts).toEqual({});
    expect(again.report.diagnostics).toEqual([]);
  });

  test("unsupported declaration reports the exact location", () => {
    const result = lowerExpectingFailure('let prefix = "ok"\n@Observable struct NotAReferenceModel { var value = 0 }\n');
    expect(result.status).not.toBe(0);
    expect(result.stderr).toMatch(/Sources\/Fixture\.swift:2:1: \[SWUI-L001\]/);
  });
});
