import Foundation
import Testing

@testable import LoweringCore

/// The driver around the passes: the files it writes (report, state, backups), restoring, the failures it reports and the
/// formats the build's consumers read (`Tools/run-browser-embedded.sh`, the editors that parse the failure text).
@Suite struct DriverTests {
  private func makePackage(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swl-driver-\(UUID().uuidString)")
    for (path, content) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
    // Compare against the path the lowerer reports, which is the canonical one (`/var` is `/private/var` on macOS).
    return URL(fileURLWithPath: try FileSystem.canonical(root.path))
  }

  private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

  private func json(_ url: URL) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private let view = "struct A: View {\n  @ContentBuilder var body: some View { Text(\"a\") }\n}\n"

  // MARK: Output formats

  @Test func theJSONIsPrettyPrintedWithSortedKeys() {
    let value = JSONValue.object([
      "z": .array([]),
      "a": .object([:]),
      "list": .array([.int(1), .string("tab\t\"quote\" \\ \n é \u{01}"), .bool(true), .null]),
    ])
    #expect(
      value.pretty() == """
        {
          "a": {},
          "list": [
            1,
            "tab\\t\\"quote\\" \\\\ \\n é \\u0001",
            true,
            null
          ],
          "z": []
        }
        """)
  }

  @Test func theKeysOfAnObjectAreInByteOrder() {
    let value = JSONValue.object(["b": .int(1), "B": .int(2), "a": .int(3), "é": .int(4), "_": .int(5)])
    #expect(value.pretty() == "{\n  \"B\": 2,\n  \"_\": 5,\n  \"a\": 3,\n  \"b\": 1,\n  \"é\": 4\n}")
  }

  @Test func theContentHashIsFNV1a() {
    #expect(SourceMap.stableHash("") == "cbf29ce484222325")
    #expect(SourceMap.stableHash("a") == "af63dc4c8601ec8c")
    #expect(SourceMap.stableHash("foobar") == "85944171f73967e8")
  }

  @Test func theLineMapAnchorsUnchangedLinesAndInterpolatesBetweenThem() {
    #expect(SourceMap.lineMap(original: "a\nb\nc\n", generated: "a\nB\nc\n") == [1, 2, 3, 4])
    // A line inserted at the top maps to the first line; the lines after it follow their sources.
    #expect(SourceMap.lineMap(original: "a\nb\n", generated: "x\na\nb\n") == [1, 1, 2, 3])
    #expect(SourceMap.lineMap(original: "", generated: "") == [1])
  }

  @Test func theAnchorsOfALineAreItsFirstCharacterAndTheSharedPrefix() {
    let points = SourceMap.points(original: "  let a = 1\n", generated: "  let b = 1\n")
    // Line 1: the first non-blank column of both, then the prefix they share (`  let ` is 6 characters).
    #expect(points.first == .object([
      "generated": .object(["line": .int(1), "column": .int(3)]),
      "source": .object(["line": .int(1), "column": .int(3)]),
    ]))
    #expect(points.count == 3)
    #expect(points[1] == .object([
      "generated": .object(["line": .int(1), "column": .int(7)]),
      "source": .object(["line": .int(1), "column": .int(7)]),
    ]))
  }

  @Test func theRulesThatFiredAreReportedAtTheirFirstConstruct() {
    let source = "// é\nstruct A: Codable {}\n  @ContentBuilder var x: Int\n"
    let entries = RuleDiagnostics.entries(for: ["content-builder-to-view-builder": 2, "codable-to-embedded": 1, "map-member": 0], in: source)
    #expect(entries.map(\.message) == ["rule codable-to-embedded applied 1 time(s)", "rule content-builder-to-view-builder applied 2 time(s)"])
    #expect(entries[0].line == 2 && entries[0].column == 11 && entries[0].offset == 16)
    #expect(entries[1].line == 3 && entries[1].column == 3)
    #expect(entries.allSatisfy { $0.code == "SWUI-I001" && $0.severity == "info" })
  }

  // MARK: Command line

  @Test func theRestoreModeAndTheStatePathAreParsed() throws {
    let parsed = try LoweringArguments.parse(["--restore", "--root", "/r", "--state", "s/state.json"])
    #expect(parsed.mode == .restore && parsed.rootPath == "/r" && parsed.statePath == "s/state.json")
    let applied = try LoweringArguments.parse(["--apply"])
    #expect(applied.mode == .apply && applied.workspacePath == nil)
    #expect(applied.reportPath == ".build/embedded-source-lowering/report.json")
    #expect(applied.statePath == ".build/embedded-source-lowering/state.json")
    #expect(applied.rootPath == "." && applied.product == "ShowcaseApp")
  }

  @Test func theFailuresOfTheCommandLineNameTheOption() {
    func message(_ values: [String]) -> String {
      do {
        _ = try LoweringArguments.parse(values)
        return ""
      } catch {
        return "\(error)"
      }
    }
    #expect(message([]) == "pass exactly one of --apply or --restore")
    #expect(message(["--apply", "--restore"]) == "pass exactly one of --apply or --restore")
    #expect(message(["--lower-codable"]) == "pass exactly one of --apply or --restore")
    #expect(message(["--apply", "--root"]) == "--root needs a value")
    #expect(message(["--apply", "--state"]) == "--state needs a value")
    #expect(message(["--bogus"]) == "unknown option --bogus")
    // Help ends the parse, whatever follows it.
    #expect(message(["-h", "--bogus"]) == "")
  }

  @Test func filePathsAreJoinedAndOrderedByComponent() {
    #expect(FileSystem.join("/a/b", "c") == "/a/b/c")
    #expect(FileSystem.join("/a/b/", "c") == "/a/b/c")
    #expect(FileSystem.join("/a/b", "/c") == "/c")
    #expect(FileSystem.join("/a/b", "./c") == "/a/b/./c")
    #expect(FileSystem.parent(of: "/a/b/state.json") == "/a/b")
    #expect(FileSystem.parent(of: "state.json") == "")
    #expect(FileSystem.parent(of: "/state.json") == "/")
    let sorted = ["Sources/a.swift", "Sources/a/b.swift", "Sources/a-b.swift", "Sources/B.swift"].sorted(by: FileSystem.pathPrecedes)
    #expect(sorted == ["Sources/B.swift", "Sources/a/b.swift", "Sources/a-b.swift", "Sources/a.swift"])
  }

  // MARK: Workspace

  @Test func theReportRecordsEachRewrittenFileWithItsMapsAndHashes() throws {
    let source = "import SwiftUI\n\(view)"
    let root = try makePackage(["Sources/A.swift": source, "Sources/Plain.swift": "struct P {}\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = "Demo"
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()

    let reportURL = root.appendingPathComponent(".build/embedded-source-lowering/report.json")
    #expect(summary.report == reportURL.path)
    let report = try json(reportURL)
    #expect(report["version"] as? Int == 4 && report["status"] as? String == "LOWERED" && report["product"] as? String == "Demo")
    #expect(report["files"] as? [String] == ["Sources/A.swift"])
    #expect(report["sourceRoot"] as? String == root.path && report["workspace"] as? String == workspace.path)
    #expect((report["rules"] as? [String: Int])?["content-builder-to-view-builder"] == 1)
    let entry = try #require((report["sourceMap"] as? [[String: Any]])?.first)
    #expect(entry["source"] as? String == "Sources/A.swift")
    #expect(entry["generated"] as? String == workspace.appendingPathComponent("Sources/A.swift").path)
    let lowered = try read(workspace.appendingPathComponent("Sources/A.swift"))
    #expect((entry["lineMap"] as? [Int])?.count == lowered.split(separator: "\n", omittingEmptySubsequences: false).count)
    let hashes = try #require(entry["hashes"] as? [String: String])
    #expect(hashes["source"] == SourceMap.stableHash(source) && hashes["generated"] == SourceMap.stableHash(lowered))
    let diagnostics = try #require(report["diagnostics"] as? [[String: Any]])
    #expect(diagnostics.count == 1 && diagnostics[0]["code"] as? String == "SWUI-I001" && diagnostics[0]["file"] as? String == "Sources/A.swift")
    #expect(diagnostics[0]["line"] as? Int == 3 && diagnostics[0]["column"] as? Int == 3)

    // The state is next to the lowered tree, with the original in the backup.
    let state = try json(workspace.appendingPathComponent(".build/embedded-source-lowering/state.json"))
    #expect(state["version"] as? Int == 3 && state["idempotent"] as? Bool == true && state["files"] as? [String] == ["Sources/A.swift"])
    #expect(try read(workspace.appendingPathComponent(".build/embedded-source-lowering/state.backup/Sources/A.swift")) == source)
    #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".build/embedded-source-lowering/state.backup/Sources/Plain.swift").path))
    #expect(summary.output.contains("\"files\": 1") && summary.output.contains("\"status\": \"LOWERED\""))
  }

  @Test func loweringInPlaceKeepsBackupsAndRestoreBringsTheSourcesBack() throws {
    let manifest = "// swift-tools-version: 6.0\nlet package = Package(targets: [.executableTarget(name: \"Demo\", path: \"Sources\")])\n"
    let source = "import SwiftUI\n\(view)"
    let root = try makePackage(["Package.swift": manifest, "Sources/A.swift": source, "Sources/Plain.swift": "struct P {}\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.product = "Demo"
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(summary.changed == ["Sources/A.swift", "Package.swift"])
    #expect(try read(root.appendingPathComponent("Sources/A.swift")).contains("@ViewBuilder"))
    #expect(try read(root.appendingPathComponent("Package.swift")).contains("--export=embedded_browser_start"))
    let backup = root.appendingPathComponent(".build/embedded-source-lowering/state.backup")
    #expect(try read(backup.appendingPathComponent("Package.swift")) == manifest)
    #expect(try json(root.appendingPathComponent(".build/embedded-source-lowering/state.json"))["workspace"] as? String == root.path)

    // A second lowering of a checkout that is still lowered is refused, and touches nothing.
    do {
      _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
      Issue.record("a lowering that is still active must refuse a second one")
    } catch {
      #expect("\(error)" == "embedded source lowering already active; restore it first")
    }

    var restore = LoweringArguments()
    restore.mode = .restore
    restore.root = root
    try WorkspaceRestore.run(arguments: restore)
    #expect(try read(root.appendingPathComponent("Sources/A.swift")) == source)
    #expect(try read(root.appendingPathComponent("Package.swift")) == manifest)
    #expect(!FileManager.default.fileExists(atPath: backup.path))
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/embedded-source-lowering/state.json").path))
    // The report stays (it is written beside the state), so the state folder is not removed.
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/embedded-source-lowering/report.json").path))
    // With no state there is nothing to do, and that is not an error.
    try WorkspaceRestore.run(arguments: restore)
  }

  /// `Tools/run-browser-embedded.sh` lowers the framework and the application in place with two state files in one folder
  /// (`framework-state.json`, `app-state.json`). Each state needs its own backup: sharing one folder meant restoring the
  /// application deleted the framework's originals, so the framework restore put nothing back and stayed lowered.
  @Test func twoStatesInOneFolderKeepTheirOwnBackups() throws {
    let manifest = "// swift-tools-version: 6.0\nlet package = Package(targets: [.executableTarget(name: \"Demo\", path: \"Sources\")])\n"
    let framework = try makePackage(["Package.swift": manifest, "Sources/Native.swift": view])
    let application = try makePackage(["Package.swift": manifest + "// application\n", "Sources/Native.swift": view + "// application\n"])
    defer {
      try? FileManager.default.removeItem(at: framework)
      try? FileManager.default.removeItem(at: application)
    }
    let stateFolder = framework.appendingPathComponent(".build/swiftuiweb-embedded").path
    func arguments(root: URL, state: String) -> LoweringArguments {
      var arguments = LoweringArguments()
      arguments.root = root
      arguments.product = "Demo"
      arguments.statePath = "\(stateFolder)/\(state)"
      arguments.reportPath = "\(stateFolder)/\(state).report"
      return arguments
    }
    let frameworkArguments = arguments(root: framework, state: "framework-state.json")
    let applicationArguments = arguments(root: application, state: "app-state.json")
    _ = try WorkspaceLowering(arguments: frameworkArguments, pipeline: .standard, moduleAliases: false).run()
    _ = try WorkspaceLowering(arguments: applicationArguments, pipeline: .standard, moduleAliases: false).run()
    #expect(try read(framework.appendingPathComponent("Sources/Native.swift")).contains("@ViewBuilder"))
    #expect(try read(application.appendingPathComponent("Sources/Native.swift")).contains("@ViewBuilder"))

    // The order of the build script's cleanup: the application first, then the framework.
    for (root, restoreArguments) in [(application, applicationArguments), (framework, frameworkArguments)] {
      var restore = restoreArguments
      restore.mode = .restore
      try WorkspaceRestore.run(arguments: restore)
      #expect(try read(root.appendingPathComponent("Sources/Native.swift")).contains("@ContentBuilder"), "\(root.lastPathComponent)'s sources are restored")
    }
    #expect(try read(framework.appendingPathComponent("Sources/Native.swift")) == view)
    #expect(try read(framework.appendingPathComponent("Package.swift")) == manifest)
    #expect(try read(application.appendingPathComponent("Sources/Native.swift")) == view + "// application\n")
    #expect(try read(application.appendingPathComponent("Package.swift")) == manifest + "// application\n")
  }

  @Test func aStateFolderThatHoldsNothingElseIsRemovedByTheRestore() throws {
    let root = try makePackage(["Sources/A.swift": view])
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.statePath = "state/lowering.json"
    arguments.reportPath = "reports/report.json"
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("state/lowering.json").path))
    arguments.mode = .restore
    try WorkspaceRestore.run(arguments: arguments)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("state").path))
    #expect(try read(root.appendingPathComponent("Sources/A.swift")) == view)
  }

  @Test func aStateWrittenBeforeEachStateHadItsOwnBackupIsRestoredFromBackup() throws {
    let root = try makePackage(["Sources/A.swift": "lowered\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let stateFolder = root.appendingPathComponent(".build/embedded-source-lowering")
    try FileManager.default.createDirectory(at: stateFolder.appendingPathComponent("backup/Sources"), withIntermediateDirectories: true)
    try "original\n".write(to: stateFolder.appendingPathComponent("backup/Sources/A.swift"), atomically: true, encoding: .utf8)
    // The lowered text is recorded, as every state now records it: restore puts a file back only while it still holds that text.
    let state = #"{"files": ["Sources/A.swift"], "hashes": {"Sources/A.swift": {"generated": ""# + SourceMap.stableHash("lowered\n") + #""}}}"#
    try state.write(to: stateFolder.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
    var restore = LoweringArguments()
    restore.mode = .restore
    restore.root = root
    try WorkspaceRestore.run(arguments: restore)
    #expect(try read(root.appendingPathComponent("Sources/A.swift")) == "original\n")
    #expect(!FileManager.default.fileExists(atPath: stateFolder.appendingPathComponent("backup").path))
  }

  @Test func aStateThatNamesABackupOutsideItsFolderIsNotFollowed() throws {
    let root = try makePackage(["Sources/A.swift": "lowered\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let stateFolder = root.appendingPathComponent(".build/embedded-source-lowering")
    try FileManager.default.createDirectory(at: stateFolder, withIntermediateDirectories: true)
    try #"{"files": ["Sources/A.swift"], "backup": "../.."}"#.write(to: stateFolder.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
    var restore = LoweringArguments()
    restore.mode = .restore
    restore.root = root
    #expect(throws: LoweringArguments.Failure.self) { try WorkspaceRestore.run(arguments: restore) }
  }

  @Test func aStateThatNamesAFileOutsideTheRootIsNotFollowed() throws {
    let root = try makePackage(["Sources/A.swift": "struct A {}\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let stateFolder = root.appendingPathComponent(".build/embedded-source-lowering")
    try FileManager.default.createDirectory(at: stateFolder, withIntermediateDirectories: true)
    try #"{"files": ["../escape.swift"]}"#.write(to: stateFolder.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
    var restore = LoweringArguments()
    restore.mode = .restore
    restore.root = root
    #expect(throws: LoweringArguments.Failure.self) { try WorkspaceRestore.run(arguments: restore) }
  }

  @Test func filesAreLoweredInPathOrderNotStringOrder() throws {
    let root = try makePackage([
      "Sources/a.swift": view, "Sources/a/b.swift": view, "Sources/a-b.swift": view, "Sources/B.swift": view,
      "Sources/.swift": view, "Sources/notes.txt": "@ContentBuilder\n", "Sources/dir.swift/inner.swift": view,
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = LoweringArguments()
    arguments.root = root
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(summary.changed == ["Sources/B.swift", "Sources/a/b.swift", "Sources/a-b.swift", "Sources/a.swift", "Sources/dir.swift/inner.swift"])
  }

  @Test func aSourceThatIsNotUTF8StopsTheRun() throws {
    let root = try makePackage(["Sources/A.swift": "struct A {}\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([0x6C, 0x65, 0x74, 0x20, 0x78, 0x20, 0x3D, 0x20, 0x22, 0xE9, 0x22, 0x0A]).write(to: root.appendingPathComponent("Sources/Latin.swift"))
    var arguments = LoweringArguments()
    arguments.root = root
    do {
      _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
      Issue.record("a source that is not UTF-8 must stop the run")
    } catch {
      #expect("\(error)" == "stream did not contain valid UTF-8")
    }
  }

  @Test func aMissingRootIsReportedAsTheOperatingSystemDoes() {
    var arguments = LoweringArguments()
    arguments.rootPath = "/nonexistent-swiftuiweb-lowering-root"
    do {
      _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
      Issue.record("a missing root must stop the run")
    } catch {
      #expect("\(error)" == "No such file or directory (os error 2)")
    }
  }

  // MARK: Idempotency

  /// Appends `x` to a source that has none, so lowering its own output changes it again.
  private struct Divergent: SourceTransform {
    var name: String { "divergent" }
    func applies(to options: LoweringOptions) -> Bool { true }
    func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String { text + "x" }
  }

  /// Rewrites a source once and refuses to read what it wrote.
  private struct Unreadable: SourceTransform {
    var name: String { "unreadable" }
    func applies(to options: LoweringOptions) -> Bool { true }
    func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
      if text.hasSuffix("x") { throw LoweringError(code: "SWUI-L001", message: "unsupported generated source", offset: 0) }
      return text + "x"
    }
  }

  @Test func outputThatIsNotIdempotentOrCannotBeReadAgainStopsTheRunAndLeavesTheSourceAsItWas() throws {
    for (transform, expected) in [
      (Divergent() as any SourceTransform, "Sources/Demo.swift:1:1: [SWUI-L002] lowering is not idempotent"),
      (Unreadable(), "Sources/Demo.swift: generated output is not re-parseable: [SWUI-L001] unsupported generated source"),
    ] {
      let root = try makePackage(["Sources/Demo.swift": "let a = 1\n"])
      defer { try? FileManager.default.removeItem(at: root) }
      var arguments = LoweringArguments()
      arguments.root = root
      do {
        _ = try WorkspaceLowering(arguments: arguments, pipeline: LoweringPipeline(transforms: [transform]), moduleAliases: false).run()
        Issue.record("a lowering that is not stable must stop the run")
      } catch {
        #expect("\(error)" == expected)
      }
      #expect(try read(root.appendingPathComponent("Sources/Demo.swift")) == "let a = 1\n")
      #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/embedded-source-lowering/state.json").path))
    }
  }

  // MARK: Line endings

  @Test func aViewInAFileWithWindowsLineEndingsGetsItsComparisonAfterTheLastLine() {
    let text = lowered("struct A: View {\r\n  var title: String\r\n}\r\n")
    #expect(text == "struct A: View {\r\n  var title: String\r\n}\r\n\nextension A {\n  static var _comparesInputs: Bool { true }\n  static func _sameInputs(_ lhs: Self, _ rhs: Self) -> Bool { _swiftUIWebSame(lhs.title, rhs.title) }\n}\n")
  }
}
