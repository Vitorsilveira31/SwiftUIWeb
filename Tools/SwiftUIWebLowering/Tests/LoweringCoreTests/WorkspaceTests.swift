import Foundation
import Testing

@testable import LoweringCore

@Suite struct WorkspaceTests {
  private func makePackage(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swl-\(UUID().uuidString)")
    for (path, content) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
  }

  @Test func theWorkspaceHoldsTheLoweredPackageAndTheSourceStaysAsItWas() throws {
    let source = "import SwiftUIWeb\nstruct A: Codable { let id: Int }\n"
    let root = try makePackage([
      "Package.swift": "// manifest\n",
      "Sources/A.swift": source,
      "Sources/Plain.swift": "struct P {}\n",
      "Web/Entry.swift": "struct W: Decodable { let w: Int }\n",
      ".build/ignored.swift": "struct Ignored: Codable { let id: Int }\n",
      "node_modules/x/index.js": "x\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.lowerCodable = true
    arguments.report = workspace.deletingLastPathComponent().appendingPathComponent("\(workspace.lastPathComponent).json")
    defer { try? FileManager.default.removeItem(at: arguments.report!) }

    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()

    #expect(summary.changed == ["Sources/A.swift", "Web/Entry.swift"])
    #expect(summary.totals["codable-to-embedded"] == 2)
    let lowered = try String(contentsOf: workspace.appendingPathComponent("Sources/A.swift"), encoding: .utf8)
    #expect(lowered.contains("struct A: EmbeddedCodable"))
    #expect(try String(contentsOf: root.appendingPathComponent("Sources/A.swift"), encoding: .utf8) == source)
    #expect(try String(contentsOf: workspace.appendingPathComponent("Package.swift"), encoding: .utf8) == "// manifest\n")
    #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent(".build/ignored.swift").path))
    #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("node_modules").path))
    let report = try JSONSerialization.jsonObject(with: Data(contentsOf: arguments.report!)) as? [String: Any]
    #expect((report?["files"] as? [String]) == ["Sources/A.swift", "Web/Entry.swift"])
  }

  @Test func onlyTheProductExampleOfAFrameworkRootIsLoweredAsAnApplication() throws {
    let root = try makePackage([
      "Sources/Core.swift": "struct Core: Codable { let id: Int }\n",
      "Examples/Demo/main.swift": "struct Demo: Codable { let id: Int }\n",
      "Examples/Other/main.swift": "struct Other: Codable { let id: Int }\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = "Demo"
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(summary.changed == ["Examples/Demo/main.swift"])
  }

  @Test func theCodeTheExamplesShareIsLoweredAsAnApplicationToo() throws {
    let root = try makePackage([
      "Sources/Core.swift": "struct Core: Codable { let id: Int }\n",
      "Examples/Demo/main.swift": "struct Demo: Codable { let id: Int }\n",
      "Examples/CloneKit/Model.swift": "struct Model: Codable { let id: Int }\n",
      "Examples/Other/main.swift": "struct Other: Codable { let id: Int }\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = "Demo"
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(summary.changed == ["Examples/CloneKit/Model.swift", "Examples/Demo/main.swift"])
  }

  @Test func aTestAppOfAFrameworkRootIsLoweredAsAnApplicationToo() throws {
    let root = try makePackage([
      "Sources/Core.swift": "struct Core: Codable { let id: Int }\n",
      "Tests/Apps/Demo/main.swift": "struct Demo: Codable { let id: Int }\n",
      "Tests/Apps/Other/main.swift": "struct Other: Codable { let id: Int }\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = "Demo"
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(summary.changed == ["Tests/Apps/Demo/main.swift"])
  }

  @Test func theRulesThatApplyToEverySourceAlsoLowerTheFrameworkSources() throws {
    let root = try makePackage([
      "Sources/Core.swift": "let names = rows.map(\\.name)\nstruct Core: Codable { let id: Int }\n",
      "Package.swift": "// manifest\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = "Demo"
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(summary.changed == ["Sources/Core.swift"])
    #expect(summary.totals == ["map-member": 1])
    let lowered = try String(contentsOf: workspace.appendingPathComponent("Sources/Core.swift"), encoding: .utf8)
    #expect(lowered == "let names = rows.map { $0.name }\nstruct Core: Codable { let id: Int }\n")
  }

  @Test func anObservableClassOfAnotherFileMakesAStateAModelState() throws {
    let root = try makePackage([
      "Sources/Model.swift": "@Observable final class Router { var path = 0 }\n@Model final class Note { var title = \"\" }\n",
      "Sources/View.swift": "struct V: View {\n  @State var router = Router()\n  @State var note: Note\n  @State var count = 0\n}\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.lowerCodable = true
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(summary.totals["state-observable-model"] == 2)
    let lowered = try String(contentsOf: workspace.appendingPathComponent("Sources/View.swift"), encoding: .utf8)
    #expect(lowered.contains("@StateObject var router = Router()"))
    #expect(lowered.contains("@StateObject var note: Note"))
    #expect(lowered.contains("@State(memberID: \(stableStateMemberID("count"))) var count = 0"))
  }

  @Test func aRefusedSourceIsReportedWithItsFileLineAndColumnAndTheSourceStaysAsItWas() throws {
    let source = "let title = \"é\"\n@Observable struct Value { var count = 0 }\n"
    let root = try makePackage(["Sources/Invalid.swift": source])
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = "Demo"
    do {
      _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
      Issue.record("an @Observable struct must stop the run")
    } catch {
      #expect("\(error)".hasPrefix("Sources/Invalid.swift:2:1: [SWUI-L001]"), "\(error)")
    }
    #expect(try String(contentsOf: root.appendingPathComponent("Sources/Invalid.swift"), encoding: .utf8) == source)
  }

  @Test func theCommandLineParsesEveryOptionItKeeps() throws {
    let parsed = try LoweringArguments.parse([
      "--apply", "--root", "/r", "--product", "P", "--workspace", "/w", "--lower-codable", "--report", "/x.json", "--rules", "view-inputs",
    ])
    #expect(parsed.root.path == "/r" && parsed.product == "P" && parsed.workspace?.path == "/w")
    #expect(parsed.lowerCodable && parsed.report?.path == "/x.json" && parsed.rules == ["view-inputs"])
    #expect(try LoweringArguments.parse(["--apply"]).workspace == nil)
    #expect(throws: LoweringArguments.Failure.self) { try LoweringArguments.parse(["--workspace", "/w"]) }
    #expect(throws: LoweringArguments.Failure.self) { try LoweringArguments.parse(["--apply", "--unknown"]) }
    #expect(LoweringPipeline.standard.selecting(["nope"]) == nil)
  }

  // MARK: The result cache (`--cache`)

  private struct Outputs: Equatable {
    var files: [String: String]
    var report: String
    var state: String
  }

  private let cachedFixture: [String: String] = [
    "Package.swift": "// manifest\n",
    "Sources/A.swift": "import SwiftUIWeb\nstruct A: Codable { let id: Int }\n",
    "Sources/Plain.swift": "struct P {}\n",
    "Web/Entry.swift": "struct W: Decodable { let w: Int }\n",
  ]

  private func makeCache() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("swl-cache-\(UUID().uuidString)")
  }

  private func cacheEntries(_ cache: URL) -> Set<String> {
    Set(((try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []).filter { $0.hasSuffix(".json") })
  }

  /// Lowers `root` into a fresh workspace, with `cache` when given, and returns what the run wrote. The workspace path is
  /// replaced in the report and the state, so runs over the same package compare equal.
  private func lowerOutputs(_ root: URL, cache: URL? = nil) throws -> Outputs {
    let id = UUID().uuidString
    let parent = root.deletingLastPathComponent()
    let workspace = parent.appendingPathComponent("swl-ws-\(id)")
    let report = parent.appendingPathComponent("swl-report-\(id).json")
    defer {
      try? FileManager.default.removeItem(at: workspace)
      try? FileManager.default.removeItem(at: report)
    }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.lowerCodable = true
    arguments.report = report
    arguments.cachePath = cache?.path
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()

    var files: [String: String] = [:]
    let base = workspace.path
    for relative in try FileManager.default.subpathsOfDirectory(atPath: base) where !relative.hasPrefix(".build") {
      let path = FileSystem.join(base, relative)
      guard !FileSystem.isDirectory(path) else { continue }
      files[relative] = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }
    let state = workspace.appendingPathComponent(".build/embedded-source-lowering/state.json")
    return Outputs(
      files: files,
      report: try String(contentsOf: report, encoding: .utf8).replacingOccurrences(of: base, with: "<workspace>"),
      state: try String(contentsOf: state, encoding: .utf8).replacingOccurrences(of: base, with: "<workspace>")
    )
  }

  @Test func aColdCacheLowersTheSameAsNoCache() throws {
    let root = try makePackage(cachedFixture)
    let cache = makeCache()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    let plain = try lowerOutputs(root)
    let cold = try lowerOutputs(root, cache: cache)
    #expect(cold.files == plain.files, "files: \(cold.files.keys.sorted()) vs \(plain.files.keys.sorted())")
    #expect(cold.report == plain.report)
    #expect(cold.state == plain.state)
    #expect(!cacheEntries(cache).isEmpty)
    #expect(plain.files["Sources/A.swift"]?.contains("struct A: EmbeddedCodable") == true)
  }

  @Test func aWarmCacheLowersTheSameAndIsTakenFromTheEntries() throws {
    let root = try makePackage(cachedFixture)
    let cache = makeCache()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    let plain = try lowerOutputs(root)
    _ = try lowerOutputs(root, cache: cache)
    let warm = try lowerOutputs(root, cache: cache)
    #expect(warm == plain)

    // An entry whose lowered text no longer matches its check is a miss: the file is lowered again and the entry is
    // rewritten, so a poisoned lowering never reaches the output.
    for name in cacheEntries(cache) {
      let url = cache.appendingPathComponent(name)
      // (A report record is an entry too, and is not JSON.)
      guard let parsed = try? JSONSerialization.jsonObject(with: try Data(contentsOf: url)), var object = parsed as? [String: Any],
        object["lowered"] != nil
      else { continue }
      object["lowered"] = "POISON"
      try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
    let poisoned = try lowerOutputs(root, cache: cache)
    #expect(poisoned == plain)
    #expect(try lowerOutputs(root, cache: cache) == plain, "the rewritten entries are intact again")
  }

  @Test func anEntryWhoseFieldsChangedAfterItsCheckWasWrittenIsNotIntact() {
    var lowered = LoweringCache.Lowered(source: "a", lowered: "b", counts: ["rule": 1])
    #expect(lowered.isIntact)
    lowered.lowered = "c"
    #expect(!lowered.isIntact)
    lowered.lowered = "b"
    lowered.counts = ["rule": 2]
    #expect(!lowered.isIntact)
    // A text moved between two fields changes the check too.
    #expect(LoweringCache.Lowered(source: "ab", lowered: "", counts: [:]).check != LoweringCache.Lowered(source: "a", lowered: "b", counts: [:]).check)

    var scan = LoweringCache.Scan(source: "s", names: ["A", "B"])
    #expect(scan.isIntact)
    scan.names = ["A", "C"]
    #expect(!scan.isIntact)
  }

  @Test func aReportRecordComesBackFromItsEntryAndABrokenOneIsAMiss() throws {
    let record = LoweringCache.Record(sourceHash: "aa", generatedHash: "bb", lineMap: "[\n  1,\n  2\n]", mappings: "[]", virtualFiles: "{\n  \"á|b\": 3\n}")
    let back = try #require(LoweringCache.Record(encoded: record.encoded))
    #expect(back.sourceHash == "aa" && back.generatedHash == "bb")
    #expect(back.lineMap == record.lineMap && back.mappings == "[]" && back.virtualFiles == record.virtualFiles)
    // A file cut short, or one that is something else, is not a record.
    #expect(LoweringCache.Record(encoded: record.encoded.dropLast(1)) == nil)
    #expect(LoweringCache.Record(encoded: Data("{\"lowered\":\"x\"}".utf8)) == nil)
    #expect(LoweringCache.Record(encoded: Data()) == nil)
  }

  @Test func aCachedRecordIsWhatTheReportHolds() throws {
    // The report's record of a file is taken from the cache when the entry is intact. A record changed after it was
    // written keeps its old check, so it is a miss and the report holds the computed record, as does a record that
    // cannot be read.
    let root = try makePackage(cachedFixture)
    let cache = makeCache()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    let cold = try lowerOutputs(root, cache: cache)
    var records: [URL] = []
    for name in cacheEntries(cache) {
      let url = cache.appendingPathComponent(name)
      if LoweringCache.Record(encoded: try Data(contentsOf: url)) != nil { records.append(url) }
    }
    #expect(!records.isEmpty)
    for url in records {
      var record = try #require(LoweringCache.Record(encoded: try Data(contentsOf: url)))
      record.lineMap = "[\n        424242\n      ]"
      try record.encoded.write(to: url)
    }
    #expect(try lowerOutputs(root, cache: cache).report == cold.report, "a changed record is not used")
    #expect(!(try lowerOutputs(root, cache: cache).report.contains("424242")))
    for url in records { try Data("broken".utf8).write(to: url) }
    #expect(try lowerOutputs(root, cache: cache).report == cold.report)
  }

  // MARK: The mirror's unread files

  @Test func aCopyOlderThanItsSourceIsReadAndANewerOneIsNot() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swl-mirror-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("a.txt").path, copy = directory.appendingPathComponent("b.txt").path
    try "one".write(toFile: source, atomically: false, encoding: .utf8)
    // A copy is known to hold the source's bytes only when the source's status change is strictly older than the copy's. The
    // file times of some systems (Linux) tick every few milliseconds, so a copy made at once could land in the source's tick.
    Thread.sleep(forTimeInterval: 0.05)
    #expect(!FileSystem.unchangedSinceCopied(source: source, destination: copy), "no copy yet")
    #expect(try FileSystem.copyIfChanged(from: source, to: copy))
    #expect(FileSystem.unchangedSinceCopied(source: source, destination: copy))
    #expect(try !FileSystem.copyIfChanged(from: source, to: copy))
    // The same size, new contents: the source changed after the copy was made, so it is read and copied.
    try "two".write(toFile: source, atomically: false, encoding: .utf8)
    #expect(!FileSystem.unchangedSinceCopied(source: source, destination: copy))
    #expect(try FileSystem.copyIfChanged(from: source, to: copy))
    #expect(try String(contentsOfFile: copy, encoding: .utf8) == "two")
    // Another size is never taken for the same file, whatever the times say.
    try "three".write(toFile: copy, atomically: false, encoding: .utf8)
    #expect(!FileSystem.unchangedSinceCopied(source: source, destination: copy))
  }

  @Test func aChangedSourceIsLoweredAgainWithTheCache() throws {
    let root = try makePackage(cachedFixture)
    let cache = makeCache()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    _ = try lowerOutputs(root, cache: cache)
    try "import SwiftUIWeb\nstruct A: Codable { let id: Int; let name: String }\n"
      .write(to: root.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)
    let changed = try lowerOutputs(root, cache: cache)
    let plain = try lowerOutputs(root)
    #expect(changed == plain)
    #expect(changed.files["Sources/A.swift"]?.contains("struct A: EmbeddedCodable { let id: Int; let name: String }") == true)
  }

  @Test func anObservableClassAddedToAnotherFileRelowersTheDependentFile() throws {
    let root = try makePackage([
      "Sources/Model.swift": "final class Router { var path = 0 }\n",
      "Sources/View.swift": "struct V: View {\n  @State var router = Router()\n}\n",
    ])
    let cache = makeCache()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    let before = try lowerOutputs(root, cache: cache)
    try "@Observable final class Router { var path = 0 }\n"
      .write(to: root.appendingPathComponent("Sources/Model.swift"), atomically: true, encoding: .utf8)
    let after = try lowerOutputs(root, cache: cache)
    let plain = try lowerOutputs(root)
    #expect(after == plain)
    #expect(after.files["Sources/View.swift"] != before.files["Sources/View.swift"])
    #expect(after.files["Sources/View.swift"]?.contains("@StateObject var router = Router()") == true)
  }

  @Test func aCorruptEntryIsAMissAndTheOutputsStayTheSame() throws {
    let root = try makePackage(cachedFixture)
    let cache = makeCache()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    let plain = try lowerOutputs(root)
    _ = try lowerOutputs(root, cache: cache)
    for name in cacheEntries(cache) {
      try "not json".write(to: cache.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let repaired = try lowerOutputs(root, cache: cache)
    #expect(repaired == plain)
  }

  @Test func unusedEntriesArePrunedAfterARun() throws {
    let root = try makePackage(cachedFixture)
    let cache = makeCache()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    _ = try lowerOutputs(root, cache: cache)
    let used = cacheEntries(cache)
    #expect(!used.isEmpty)
    // A stale entry under a cache key name goes; a file that is not a cache entry stays.
    try "{}".write(to: cache.appendingPathComponent("0123456789abcdef.json"), atomically: true, encoding: .utf8)
    try "keep".write(to: cache.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    _ = try lowerOutputs(root, cache: cache)
    #expect(cacheEntries(cache) == used)
    #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("notes.txt").path))
  }

  // MARK: The sync workspace (`--sync-workspace`)

  private let syncFixture: [String: String] = [
    "Package.swift": "// swift-tools-version: 6.0\nlet package = Package(targets: [.executableTarget(name: \"Demo\", path: \"Sources\")])\n",
    "Sources/A.swift": "import SwiftUIWeb\nstruct A: Codable { let id: Int }\n",
    "Sources/Plain.swift": "struct P {}\n",
    "Web/Entry.swift": "struct W: Decodable { let w: Int }\n",
    "Examples/ShowcaseApp/main.swift": "struct Demo: Codable { let id: Int }\n",
    "Assets/notes.txt": "notes\n",
  ]

  private struct SyncRun {
    var summary: WorkspaceLowering.Summary
    var report: String
  }

  private func freshDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("swl-sync-\(UUID().uuidString)")
  }

  /// Lowers `root` into `workspace`, with the sync mode when `sync` is set, and returns the summary and the report with the
  /// workspace path replaced.
  private func lowerSync(_ root: URL, into workspace: URL, sync: Bool, cache: URL? = nil) throws -> SyncRun {
    let report = URL(fileURLWithPath: workspace.path + "-report.json")
    defer { try? FileManager.default.removeItem(at: report) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.lowerCodable = true
    arguments.report = report
    arguments.cachePath = cache?.path
    arguments.syncWorkspace = sync
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    let text = try String(contentsOf: report, encoding: .utf8).replacingOccurrences(of: workspace.path, with: "<workspace>")
    return SyncRun(summary: summary, report: text)
  }

  /// Every file of `base` with its text, the workspace path replaced, `.build` included.
  private func snapshot(_ base: URL) throws -> [String: String] {
    var files: [String: String] = [:]
    for relative in try FileManager.default.subpathsOfDirectory(atPath: base.path) {
      let path = FileSystem.join(base.path, relative)
      guard !FileSystem.isDirectory(path) else { continue }
      files[relative] = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8).replacingOccurrences(of: base.path, with: "<workspace>")
    }
    return files
  }

  /// The modification time of every file of `base` outside `.build`.
  private func modificationDates(_ base: URL) throws -> [String: Date] {
    var dates: [String: Date] = [:]
    for relative in try FileManager.default.subpathsOfDirectory(atPath: base.path) where !relative.hasPrefix(".build") {
      let path = FileSystem.join(base.path, relative)
      guard !FileSystem.isDirectory(path) else { continue }
      dates[relative] = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
    return dates
  }

  /// Sets the modification time of every file of `base` outside `.build` into the past, so a rewrite shows.
  private func ageFiles(_ base: URL) throws {
    let old = Date(timeIntervalSince1970: 1_000_000_000)
    for relative in try FileManager.default.subpathsOfDirectory(atPath: base.path) where !relative.hasPrefix(".build") {
      let path = FileSystem.join(base.path, relative)
      guard !FileSystem.isDirectory(path) else { continue }
      try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
    }
  }

  @Test func aSyncRunIntoAnEmptyWorkspaceIsANormalRun() throws {
    let root = try makePackage(syncFixture)
    let normalWorkspace = freshDirectory()
    let syncWorkspace = freshDirectory()
    defer {
      for url in [root, normalWorkspace, syncWorkspace] { try? FileManager.default.removeItem(at: url) }
    }
    let normal = try lowerSync(root, into: normalWorkspace, sync: false)
    let synced = try lowerSync(root, into: syncWorkspace, sync: true)
    #expect(synced.summary.changed == normal.summary.changed)
    #expect(synced.summary.changed.contains("Sources/A.swift"))
    #expect(synced.report == normal.report)
    #expect(try snapshot(syncWorkspace) == snapshot(normalWorkspace))
  }

  @Test func aSecondSyncRunWithNoSourceChangeRewritesNoWorkspaceFile() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    defer {
      for url in [root, workspace] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true)
    let first = try snapshot(workspace)
    try ageFiles(workspace)
    let aged = try modificationDates(workspace)
    _ = try lowerSync(root, into: workspace, sync: true)
    #expect(try modificationDates(workspace) == aged)
    #expect(try snapshot(workspace) == first)
  }

  @Test func aChangedSourceFileRewritesOnlyItsWorkspaceFileAndTheLowererState() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    let fresh = freshDirectory()
    defer {
      for url in [root, workspace, fresh] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true)
    try ageFiles(workspace)
    let aged = try modificationDates(workspace)
    try "struct P { let changed = 1 }\n".write(to: root.appendingPathComponent("Sources/Plain.swift"), atomically: true, encoding: .utf8)
    _ = try lowerSync(root, into: workspace, sync: true)
    let dates = try modificationDates(workspace)
    #expect(dates.keys.sorted() == aged.keys.sorted())
    for (relative, date) in dates where relative != "Sources/Plain.swift" {
      #expect(date == aged[relative], "\(relative) was rewritten")
    }
    #expect((dates["Sources/Plain.swift"] ?? .distantPast) > aged["Sources/Plain.swift"]!)
    _ = try lowerSync(root, into: fresh, sync: false)
    #expect(try snapshot(workspace) == snapshot(fresh))
  }

  @Test func aLoweredFileThatNoLongerChangesIsWrittenBackAsItIs() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    let fresh = freshDirectory()
    defer {
      for url in [root, workspace, fresh] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true)
    let source = "struct A { let id: Int }\n"
    try source.write(to: root.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)
    _ = try lowerSync(root, into: workspace, sync: true)
    #expect(try String(contentsOf: workspace.appendingPathComponent("Sources/A.swift"), encoding: .utf8) == source)
    _ = try lowerSync(root, into: fresh, sync: false)
    #expect(try snapshot(workspace) == snapshot(fresh))
  }

  @Test func aDeletedSourceFileIsRemovedAndAnAddedOneAppears() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    let fresh = freshDirectory()
    defer {
      for url in [root, workspace, fresh] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Web/Entry.swift"))
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/Deep"), withIntermediateDirectories: true)
    try "struct Added: Codable { let id: Int }\n".write(to: root.appendingPathComponent("Sources/Deep/Added.swift"), atomically: true, encoding: .utf8)
    _ = try lowerSync(root, into: workspace, sync: true)
    #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("Web/Entry.swift").path))
    #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("Sources/Deep/Added.swift").path))
    _ = try lowerSync(root, into: fresh, sync: false)
    #expect(try snapshot(workspace) == snapshot(fresh))
  }

  @Test func theBuildFolderSurvivesAndThePreviousStateDoesNotBlockTheNextRun() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    defer {
      for url in [root, workspace] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true)
    let build = workspace.appendingPathComponent(".build/swiftpm-marker.txt")
    try "keep".write(to: build, atomically: true, encoding: .utf8)
    let state = workspace.appendingPathComponent(".build/embedded-source-lowering/state.json")
    #expect(FileManager.default.fileExists(atPath: state.path))
    _ = try lowerSync(root, into: workspace, sync: true)
    #expect(try String(contentsOf: build, encoding: .utf8) == "keep")
    #expect(FileManager.default.fileExists(atPath: state.path))
  }

  @Test func theLinkerExportsOfTheManifestAreWrittenAndReturnedToTheSourceAfterwards() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    let fresh = freshDirectory()
    defer {
      for url in [root, workspace, fresh] { try? FileManager.default.removeItem(at: url) }
    }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.product = "Demo"
    arguments.workspace = workspace
    arguments.syncWorkspace = true
    arguments.report = URL(fileURLWithPath: workspace.path + "-report.json")
    defer { try? FileManager.default.removeItem(at: arguments.report!) }
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    let patched = try String(contentsOf: workspace.appendingPathComponent("Package.swift"), encoding: .utf8)
    #expect(patched.contains("--export=embedded_browser_start"))
    try ageFiles(workspace)
    let aged = try modificationDates(workspace)
    arguments.workspace = workspace
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(try modificationDates(workspace) == aged)
    arguments.workspace = fresh
    arguments.report = URL(fileURLWithPath: fresh.path + "-report.json")
    defer { try? FileManager.default.removeItem(at: arguments.report!) }
    arguments.syncWorkspace = false
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    #expect(try snapshot(workspace) == snapshot(fresh))
  }

  @Test func syncWorkspaceNeedsAWorkspace() throws {
    let parsed = try LoweringArguments.parse(["--apply", "--workspace", "/w", "--sync-workspace"])
    #expect(parsed.syncWorkspace)
    #expect(!(try LoweringArguments.parse(["--apply", "--workspace", "/w"])).syncWorkspace)
    #expect(throws: LoweringArguments.Failure.self) { try LoweringArguments.parse(["--apply", "--sync-workspace"]) }
  }

  @Test func theSyncSummaryCountsTheWorkspaceChangesAndAnUnchangedTreeCountsNone() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    defer {
      for url in [root, workspace] { try? FileManager.default.removeItem(at: url) }
    }
    let first = try lowerSync(root, into: workspace, sync: true)
    #expect((first.summary.workspaceChanges ?? 0) > 0)
    #expect(first.summary.output.contains("\"workspaceChanges\""))
    let second = try lowerSync(root, into: workspace, sync: true)
    #expect(second.summary.workspaceChanges == 0)
  }

  @Test func editingOneSourceCountsOneWorkspaceChange() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    defer {
      for url in [root, workspace] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true)
    try "struct P { let changed = 1 }\n".write(to: root.appendingPathComponent("Sources/Plain.swift"), atomically: true, encoding: .utf8)
    let edited = try lowerSync(root, into: workspace, sync: true)
    #expect(edited.summary.workspaceChanges == 1)
    let again = try lowerSync(root, into: workspace, sync: true)
    #expect(again.summary.workspaceChanges == 0)
  }

  @Test func deletingASourceFileCountsItsRemoval() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    defer {
      for url in [root, workspace] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Web/Entry.swift"))
    let deleted = try lowerSync(root, into: workspace, sync: true)
    #expect((deleted.summary.workspaceChanges ?? 0) >= 1)
  }

  @Test func aNormalRunReportsNoWorkspaceChanges() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    defer {
      for url in [root, workspace] { try? FileManager.default.removeItem(at: url) }
    }
    let normal = try lowerSync(root, into: workspace, sync: false)
    #expect(normal.summary.workspaceChanges == nil)
    #expect(!normal.summary.output.contains("workspaceChanges"))
  }

  @Test func aSymbolicLinkIsMirroredAsItsContentAndKeepsItsModificationTime() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    let fresh = freshDirectory()
    defer {
      for url in [root, workspace, fresh] { try? FileManager.default.removeItem(at: url) }
    }
    try FileManager.default.createSymbolicLink(
      atPath: root.appendingPathComponent("Assets/link.txt").path, withDestinationPath: "notes.txt")
    _ = try lowerSync(root, into: workspace, sync: true)
    #expect(try String(contentsOf: workspace.appendingPathComponent("Assets/link.txt"), encoding: .utf8) == "notes\n")
    try ageFiles(workspace)
    let aged = try modificationDates(workspace)
    _ = try lowerSync(root, into: workspace, sync: true)
    #expect(try modificationDates(workspace) == aged)
    _ = try lowerSync(root, into: fresh, sync: false)
    #expect(try snapshot(workspace) == snapshot(fresh))
  }

  @Test func aSyncRunWithACacheLowersTheSameAsWithout() throws {
    let root = try makePackage(syncFixture)
    let workspace = freshDirectory()
    let cache = makeCache()
    let fresh = freshDirectory()
    defer {
      for url in [root, workspace, cache, fresh] { try? FileManager.default.removeItem(at: url) }
    }
    _ = try lowerSync(root, into: workspace, sync: true, cache: cache)
    try ageFiles(workspace)
    let aged = try modificationDates(workspace)
    _ = try lowerSync(root, into: workspace, sync: true, cache: cache)
    #expect(try modificationDates(workspace) == aged)
    _ = try lowerSync(root, into: fresh, sync: false)
    #expect(try snapshot(workspace) == snapshot(fresh))
  }

  @Test func anInPlaceLoweringNeverWritesThroughASymbolicLink() throws {
    let secret = "struct Secret: Codable { let id: Int }\n"
    let outside = try makePackage(["secret.swift": secret])
    defer { try? FileManager.default.removeItem(at: outside) }
    let root = try makePackage([
      "Package.swift": "// manifest\n",
      "Sources/A.swift": "import SwiftUIWeb\nstruct A: Codable { let id: Int }\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let linkedFile = root.appendingPathComponent("Sources/Linked.swift").path
    let linkedFolder = root.appendingPathComponent("Sources/Dir").path
    try FileManager.default.createSymbolicLink(atPath: linkedFile, withDestinationPath: outside.appendingPathComponent("secret.swift").path)
    try FileManager.default.createSymbolicLink(atPath: linkedFolder, withDestinationPath: outside.path)
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.lowerCodable = true

    // In place, a linked Swift file or folder stops the run: lowering it would replace the link or rewrite what it points
    // at, and building it unlowered would differ from a workspace run.
    #expect(throws: (any Error).self) { try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run() }
    #expect(try String(contentsOf: outside.appendingPathComponent("secret.swift"), encoding: .utf8) == secret)
    #expect(try String(contentsOf: root.appendingPathComponent("Sources/A.swift"), encoding: .utf8) == "import SwiftUIWeb\nstruct A: Codable { let id: Int }\n")
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linkedFile)) != nil)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linkedFolder)) != nil)
  }

  @Test func aLoweredFileEditedSinceTheLoweringIsKeptByTheRestore() throws {
    let root = try makePackage([
      "Package.swift": "// manifest\n",
      "Sources/A.swift": "import SwiftUIWeb\nstruct A: Codable { let id: Int }\n",
      "Sources/B.swift": "import SwiftUIWeb\nstruct B: Codable { let id: Int }\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.lowerCodable = true
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    let lowered = try String(contentsOf: root.appendingPathComponent("Sources/A.swift"), encoding: .utf8)
    let edited = "// edited by hand\n" + lowered
    try edited.write(to: root.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)

    try WorkspaceRestore.run(arguments: arguments)

    #expect(try String(contentsOf: root.appendingPathComponent("Sources/A.swift"), encoding: .utf8) == edited)
    #expect(try String(contentsOf: root.appendingPathComponent("Sources/B.swift"), encoding: .utf8) == "import SwiftUIWeb\nstruct B: Codable { let id: Int }\n")
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/embedded-source-lowering/state.json").path))

    // The edit is undone: a second restore puts A back, counts the already restored B as done, and removes the state.
    try lowered.write(to: root.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)
    try WorkspaceRestore.run(arguments: arguments)
    #expect(try String(contentsOf: root.appendingPathComponent("Sources/A.swift"), encoding: .utf8) == "import SwiftUIWeb\nstruct A: Codable { let id: Int }\n")
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/embedded-source-lowering/state.json").path))
  }
}
