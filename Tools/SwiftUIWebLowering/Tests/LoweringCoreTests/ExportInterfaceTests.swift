import Foundation
import Testing

@testable import LoweringCore

/// The `export-interface` pass alone, over one framework source (`lowerCodable: false`, `exportInterface: true`).
private func exported(_ source: String, generic: Set<String> = []) -> LoweringResult {
  let pipeline = LoweringPipeline.standard.selecting(["export-interface"])!
  return lower(pipeline, source, options: LoweringOptions(lowerCodable: false, exportInterface: true, genericTypeNames: generic))
}

private func exportedText(_ source: String, generic: Set<String> = []) -> String {
  exported(source, generic: generic).text
}

@Suite struct ExportInterfaceTests {
  // MARK: Marked

  @Test func aTopLevelFunctionIsMarked() throws {
    let result = exported("func f() -> Int { 1 }\n")
    #expect(result.text == "@export(interface) func f() -> Int { 1 }\n")
    #expect(result.counts["export-interface"] == 1)
  }

  @Test func aStructMethodIsMarkedBeforeItsModifiersAndKeepsItsIndentation() throws {
    #expect(exportedText("struct S {\n  func m() {}\n}\n") == "struct S {\n  @export(interface) func m() {}\n}\n")
    #expect(exportedText("struct S {\n  static func s() {}\n}\n") == "struct S {\n  @export(interface) static func s() {}\n}\n")
  }

  @Test func anInitializerIsMarked() throws {
    #expect(exportedText("struct S {\n  init(x: Int) { _ = x }\n}\n") == "struct S {\n  @export(interface) init(x: Int) { _ = x }\n}\n")
  }

  @Test func aMethodOfAFinalClassIsMarked() throws {
    #expect(exportedText("final class C {\n  func m() {}\n}\n") == "final class C {\n  @export(interface) func m() {}\n}\n")
  }

  @Test func aMethodOfAnExtensionOfANonGenericTypeIsMarked() throws {
    #expect(exportedText("extension S {\n  func e() {}\n}\n") == "extension S {\n  @export(interface) func e() {}\n}\n")
    #expect(exportedText("extension Outer.Inner {\n  func e() {}\n}\n") == "extension Outer.Inner {\n  @export(interface) func e() {}\n}\n")
  }

  @Test func aLocalFunctionIsLeftAloneAndItsEnclosingFunctionIsMarked() throws {
    let source = "func outer() {\n  func inner() {}\n}\n"
    let result = exported(source)
    #expect(result.text == "@export(interface) func outer() {\n  func inner() {}\n}\n")
    #expect(result.counts["export-interface"] == 1)
  }

  // MARK: Skipped

  @Test func aGenericFunctionIsSkipped() throws {
    #expect(exportedText("func g<T>(_ t: T) {}\n") == "func g<T>(_ t: T) {}\n")
    #expect(exportedText("func g<T>(_ t: T) where T: Equatable {}\n") == "func g<T>(_ t: T) where T: Equatable {}\n")
  }

  @Test func aMethodOfAGenericStructIsSkipped() throws {
    let source = "struct G<T> {\n  func m() {}\n}\n"
    #expect(exportedText(source) == source)
  }

  @Test func anExtensionOfAGenericTypeNamedByTheCallerIsSkipped() throws {
    let source = "extension Box {\n  func m() {}\n}\n"
    #expect(exportedText(source, generic: ["Box"]) == source)
    #expect(exportedText("extension Outer.Box {\n  func m() {}\n}\n", generic: ["Outer.Box"]) == "extension Outer.Box {\n  func m() {}\n}\n")
  }

  @Test func anExtensionOfAGenericTypeDeclaredInTheSameFileIsSkipped() throws {
    let source = "struct Box<T> {}\nextension Box {\n  func m() {}\n}\n"
    #expect(exportedText(source) == source)
  }

  @Test func anExtensionOfAStandardGenericTypeIsSkipped() throws {
    for source in ["extension Array {\n  func m() {}\n}\n", "extension Swift.Optional {\n  func m() {}\n}\n", "extension UnsafeMutablePointer {\n  func m() {}\n}\n", "extension [Int] {\n  func m() {}\n}\n"] {
      #expect(exportedText(source) == source, "\(source)")
    }
  }

  @Test func aProtocolRequirementAndAProtocolExtensionMethodAreSkipped() throws {
    let requirement = "protocol P {\n  func m()\n}\n"
    #expect(exportedText(requirement) == requirement)
    let local = "protocol P {}\nextension P {\n  func m() {}\n}\n"
    #expect(exportedText(local) == local)
    let named = "extension Named {\n  func m() {}\n}\n"
    #expect(exportedText(named, generic: ["Named"]) == named)
  }

  @Test func anInlinableOrOtherCompilerAttributedFunctionIsSkipped() throws {
    #expect(exportedText("@inlinable func f() {}\n") == "@inlinable func f() {}\n")
    #expect(exportedText("@_transparent func f() {}\n") == "@_transparent func f() {}\n")
    #expect(exportedText("@_silgen_name(\"x\") func f() {}\n") == "@_silgen_name(\"x\") func f() {}\n")
    #expect(exportedText("@_specialize(exported: true, where T == Int) func f<T>(_ t: T) {}\n") == "@_specialize(exported: true, where T == Int) func f<T>(_ t: T) {}\n")
  }

  @Test func anOpaqueResultIsSkipped() throws {
    let source = "func f() -> some Equatable {\n  1\n}\n"
    #expect(exportedText(source) == source)
  }

  @Test func anAsyncOrRethrowingFunctionIsSkipped() throws {
    #expect(exportedText("func f() async {}\n") == "func f() async {}\n")
    #expect(exportedText("func r(_ f: () throws -> Void) rethrows {}\n") == "func r(_ f: () throws -> Void) rethrows {}\n")
  }

  @Test func anOverrideIsSkipped() throws {
    let source = "class B {}\nfinal class D: B {\n  override func m() {}\n}\n"
    #expect(exportedText(source) == source)
  }

  @Test func aMethodOfANonFinalClassIsSkipped() throws {
    let source = "class C {\n  func m() {}\n}\n"
    #expect(exportedText(source) == source)
  }

  @Test func aDynamicRequiredOrConvenienceMemberIsSkipped() throws {
    #expect(exportedText("struct S {\n  dynamic func m() {}\n}\n") == "struct S {\n  dynamic func m() {}\n}\n")
    #expect(exportedText("final class C {\n  required init() {}\n}\n") == "final class C {\n  required init() {}\n}\n")
    #expect(exportedText("final class C {\n  convenience init(x: Int) { self.init() }\n}\n") == "final class C {\n  convenience init(x: Int) { self.init() }\n}\n")
  }

  @Test func aFunctionInsideAGenericTypeOrNestedInOneIsSkipped() throws {
    let source = "struct Outer<T> {\n  struct Inner {\n    func m() {}\n  }\n}\n"
    #expect(exportedText(source) == source)
  }

  // MARK: Idempotency and application

  @Test func aMarkedDeclarationIsNotMarkedAgainAndASecondRunChangesNothing() throws {
    let source = "func f() {}\nstruct S {\n  func m() {}\n}\n"
    let once = exportedText(source)
    #expect(once == "@export(interface) func f() {}\nstruct S {\n  @export(interface) func m() {}\n}\n")
    #expect(exported(once).counts["export-interface"] == nil)
    #expect(exportedText("@export(interface) func f() {}\n") == "@export(interface) func f() {}\n")
  }

  @Test func theTransformAppliesOnlyToFrameworkFilesWithTheFlag() throws {
    let pass = ExportInterfaceTransform()
    #expect(pass.applies(to: LoweringOptions(lowerCodable: false, exportInterface: true)))
    #expect(!pass.applies(to: LoweringOptions(lowerCodable: true, exportInterface: true)))
    #expect(!pass.applies(to: LoweringOptions(lowerCodable: false, exportInterface: false)))
    #expect(!pass.applies(to: LoweringOptions()))
  }

  @Test func theFlagIsParsedAndDefaultsToOff() throws {
    #expect(try LoweringArguments.parse(["--apply", "--export-interface"]).exportInterface)
    #expect(try !LoweringArguments.parse(["--apply"]).exportInterface)
  }

  // MARK: Generic-type scan

  @Test func theGenericScanRecordsGenericTypesProtocolsAndTheirNestedTypes() throws {
    let names = GenericTypeScan.names(in: "struct Outer<T> {\n  struct Inner {}\n}\nprotocol P {}\nstruct Plain {\n  struct Kid {}\n}\n")
    #expect(names.isSuperset(of: ["Outer", "Inner", "Outer.Inner", "P"]))
    #expect(names.isDisjoint(with: ["Plain", "Kid", "Plain.Kid"]))
  }

  // MARK: The workspace and the cache

  private func makeFramework(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swl-export-\(UUID().uuidString)")
    for (path, content) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
  }

  /// Lowers `root` into a fresh workspace, with `cache` when given, and returns the lowered `Sources/Lib.swift`.
  private func loweredLibrary(_ root: URL, cache: URL?, exportInterface: Bool) throws -> String {
    let id = UUID().uuidString
    let parent = root.deletingLastPathComponent()
    let workspace = parent.appendingPathComponent("swl-export-ws-\(id)")
    let report = parent.appendingPathComponent("swl-export-report-\(id).json")
    defer {
      try? FileManager.default.removeItem(at: workspace)
      try? FileManager.default.removeItem(at: report)
    }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.report = report
    arguments.cachePath = cache?.path
    arguments.exportInterface = exportInterface
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    return try String(contentsOf: workspace.appendingPathComponent("Sources/Lib.swift"), encoding: .utf8)
  }

  /// The workspace lowers each file a second time and fails the run when that changes it (`SWUI-L002`). A view that keeps
  /// state gets its installation from `state-installation`, which this pass then marks: the second lowering must find it.
  @Test func aFrameworkViewThatKeepsStateLowersWithTheFlag() throws {
    let root = try makeFramework(["Sources/Lib.swift": "public struct V: View {\n  @State var on = false\n}\n"])
    defer { try? FileManager.default.removeItem(at: root) }
    let lowered = try loweredLibrary(root, cache: nil, exportInterface: true)
    #expect(lowered.contains("extension V {\n  @export(interface) public func _installState() { _on._install() }\n}\n"))
    #expect(lowered.components(separatedBy: "func _installState()").count == 2)
  }

  @Test func theApplicationAndGenericFlagsAreParsed() throws {
    let arguments = try LoweringArguments.parse([
      "--apply", "--export-interface", "--export-interface-application", "--generic-types-in", "a.txt", "--generic-types-in", "b.txt",
      "--generic-types-out", "c.txt",
    ])
    #expect(arguments.exportInterfaceApplication)
    #expect(arguments.genericTypesInPaths == ["a.txt", "b.txt"])
    #expect(arguments.genericTypesOutPath == "c.txt")
    let defaults = try LoweringArguments.parse(["--apply"])
    #expect(!defaults.exportInterfaceApplication)
    #expect(defaults.genericTypesInPaths.isEmpty)
    #expect(defaults.genericTypesOutPath == nil)
    #expect(throws: (any Error).self) { _ = try LoweringArguments.parse(["--apply", "--export-interface-application"]) }
  }

  // MARK: Application files

  /// The `export-interface` pass over one application source (`lowerCodable: true`).
  private func exportedApplication(_ source: String, generic: Set<String> = [], applicationFlag: Bool) -> String {
    let pipeline = LoweringPipeline.standard.selecting(["export-interface"])!
    let options = LoweringOptions(
      lowerCodable: true, exportInterface: true, genericTypeNames: generic, exportInterfaceApplication: applicationFlag
    )
    return lower(pipeline, source, options: options).text
  }

  @Test func anApplicationFunctionIsNotMarkedWithoutTheApplicationFlag() throws {
    let source = "struct S {\n  func m() {}\n}\n"
    #expect(exportedApplication(source, applicationFlag: false) == source)
  }

  @Test func anApplicationFunctionIsMarkedWithTheApplicationFlag() throws {
    #expect(
      exportedApplication("struct S {\n  func m() {}\n}\n", applicationFlag: true) == "struct S {\n  @export(interface) func m() {}\n}\n")
  }

  @Test func theApplicationFlagAloneDoesNotApplyWithoutExportInterface() throws {
    let pass = ExportInterfaceTransform()
    #expect(!pass.applies(to: LoweringOptions(lowerCodable: true, exportInterface: false, exportInterfaceApplication: true)))
    #expect(pass.applies(to: LoweringOptions(lowerCodable: true, exportInterface: true, exportInterfaceApplication: true)))
  }

  @Test func anExtensionOfAFrameworkGenericNameIsSkippedInAnApplicationFile() throws {
    let source = "extension View {\n  func m() {}\n}\n"
    // With the framework's names (`--generic-types-in`) the extension is generic and left alone.
    #expect(exportedApplication(source, generic: ["View"], applicationFlag: true) == source)
    // Without them the application's own scan cannot know `View` is a protocol, so the method would be marked: the reason the
    // launcher passes the framework's names to the application run.
    #expect(exportedApplication(source, applicationFlag: true) == "extension View {\n  @export(interface) func m() {}\n}\n")
  }

  // MARK: Generic names across runs

  /// Lowers `root` in a fresh workspace with `configure` applied to the arguments, and returns the text of `relative`.
  private func lowerRun(_ root: URL, relative: String, configure: (inout LoweringArguments) -> Void) throws -> String {
    let id = UUID().uuidString
    let parent = root.deletingLastPathComponent()
    let workspace = parent.appendingPathComponent("swl-gen-ws-\(id)")
    let report = parent.appendingPathComponent("swl-gen-report-\(id).json")
    defer {
      try? FileManager.default.removeItem(at: workspace)
      try? FileManager.default.removeItem(at: report)
    }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.report = report
    arguments.exportInterface = true
    configure(&arguments)
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    return try String(contentsOf: workspace.appendingPathComponent(relative), encoding: .utf8)
  }

  @Test func theGenericNamesOfAFrameworkRunReachTheApplicationRunThroughAFile() throws {
    let framework = try makeFramework(["Sources/Kit.swift": "public protocol View {}\npublic struct Box<T> {}\npublic struct Plain {}\n"])
    let app = try makeFramework(["Sources/App.swift": "extension View {\n  public func m() {}\n}\nstruct S {\n  func n() {}\n}\n"])
    let names = FileManager.default.temporaryDirectory.appendingPathComponent("swl-generic-\(UUID().uuidString).txt")
    defer {
      try? FileManager.default.removeItem(at: framework)
      try? FileManager.default.removeItem(at: app)
      try? FileManager.default.removeItem(at: names)
    }

    _ = try lowerRun(framework, relative: "Sources/Kit.swift") { $0.genericTypesOutPath = names.path }
    #expect(try String(contentsOf: names, encoding: .utf8) == "Box\nView\n")

    let appText = try lowerRun(app, relative: "Sources/App.swift") {
      $0.lowerCodable = true
      $0.exportInterfaceApplication = true
      $0.genericTypesInPaths = [names.path]
    }
    #expect(appText == "extension View {\n  public func m() {}\n}\nstruct S {\n  @export(interface) func n() {}\n}\n")
  }

  @Test func aGenericTypesInFileThatDoesNotExistFailsTheRun() throws {
    let app = try makeFramework(["Sources/App.swift": "struct S {\n  func n() {}\n}\n"])
    defer { try? FileManager.default.removeItem(at: app) }
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("swl-missing-\(UUID().uuidString).txt").path
    #expect(throws: (any Error).self) {
      _ = try lowerRun(app, relative: "Sources/App.swift") {
        $0.lowerCodable = true
        $0.exportInterfaceApplication = true
        $0.genericTypesInPaths = [missing]
      }
    }
  }

  @Test func theFlagChangesTheLoweredFrameworkAndTheCacheKeyNotTheCacheHits() throws {
    let root = try makeFramework([
      "Sources/Lib.swift": "public struct Lib {\n  public func f() -> Int { 1 }\n}\n",
      "Sources/Box.swift": "public struct Box<T> {\n  public func g() {}\n}\n",
    ])
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("swl-export-cache-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: cache)
    }
    let withFlag = try loweredLibrary(root, cache: cache, exportInterface: true)
    let withoutFlag = try loweredLibrary(root, cache: cache, exportInterface: false)
    let warmWithFlag = try loweredLibrary(root, cache: cache, exportInterface: true)
    let plain = try loweredLibrary(root, cache: nil, exportInterface: false)

    #expect(withFlag.contains("@export(interface) public func f()"))
    #expect(!withoutFlag.contains("@export"))
    #expect(warmWithFlag == withFlag)
    #expect(withoutFlag == plain)
  }
}
