import Foundation
import Testing

@testable import LoweringCore

/// The `stable-source-locations` pass alone, over one framework source at `Sources/A.swift`.
private func located(_ source: String, path: String = "Sources/A.swift") -> String {
  let pipeline = LoweringPipeline.standard.selecting(["stable-source-locations"])!
  return lower(pipeline, source, options: LoweringOptions(stableSourceLocations: true, sourcePath: path)).text
}

private func directive(_ file: String) -> String { "#sourceLocation(file: \"Sources/A.swift|\(file)\", line: 1)" }

/// The `file` values of the directives in `text`, in order.
private func keys(_ text: String) -> [String] {
  StableSourceLocationsTransform.declarationLines(in: text).map { $0.file.replacingOccurrences(of: "Sources/A.swift|", with: "") }
}

@Suite struct StableSourceLocationsTests {
  // MARK: Placement

  @Test func aTopLevelFunctionGetsADirectiveBeforeItsFirstLineAndTheFileEndsWithAReset() {
    #expect(located("func f() {}\n") == "\(directive("func.f()"))\nfunc f() {}\n#sourceLocation()\n")
  }

  @Test func aDirectiveGoesBeforeTheAttributesAndAfterTheDocComment() {
    let source = "/// Doc.\n@inlinable public func f() {}\n"
    #expect(located(source) == "/// Doc.\n\(directive("func.f()"))\n@inlinable public func f() {}\n#sourceLocation()\n")
  }

  @Test func theDirectiveKeepsTheIndentationOfTheDeclaration() {
    let source = "struct S {\n  func m() {}\n}\n"
    #expect(located(source).contains("  \(directive("S.func.m()"))\n  func m() {}\n"))
  }

  @Test func typeMembersAreKeyedByTheirType() {
    let source = "struct S {\n  var x: Int\n  func m(_ a: Int, b: Int) {}\n  init(x: Int) { self.x = x }\n}\n"
    #expect(keys(located(source)) == ["struct.S", "S.var.x", "S.func.m(_:b:)", "S.init.init(x:)"])
  }

  @Test func extensionMembersAreKeyedByTheExtendedType() {
    let source = "extension Array {\n  func foo(_ x: Int) {}\n}\n"
    #expect(keys(located(source)) == ["ext.Array", "ext.Array.func.foo(_:)"])
    #expect(keys(located("extension Outer.Inner where Element: Equatable {\n  func e() {}\n}\n")) == ["ext.Outer.Inner", "ext.Outer.Inner.func.e()"])
  }

  @Test func protocolMembersAreKeyedByTheProtocol() {
    #expect(keys(located("protocol P {\n  func f()\n  var v: Int { get }\n}\n")) == ["protocol.P", "P.func.f()", "P.var.v"])
  }

  @Test func nestedTypesAreKeyedByTheChainOfEnclosingNames() {
    let source = "struct Outer {\n  struct Inner {\n    func g() {}\n  }\n}\n"
    #expect(keys(located(source)) == ["struct.Outer", "Outer.struct.Inner", "Outer.Inner.func.g()"])
  }

  @Test func declarationsInsideABodyAreNotLocated() {
    let source = "func f() {\n  func inner() {}\n  let x = 1\n  _ = { let y = 2; return y }\n}\n"
    #expect(keys(located(source)) == ["func.f()"])
  }

  @Test func declarationsInsideAnIfConfigBranchAreLocated() {
    let source = "#if os(WASI)\nfunc w() {}\n#else\nfunc w() {}\n#endif\n"
    #expect(keys(located(source)) == ["func.w()", "func.w()#2"])
    #expect(located(source).hasPrefix("#if os(WASI)\n\(directive("func.w()"))\nfunc w() {}\n#else\n"))
  }

  @Test func enumCasesAreLocatedBetweenTheCases() {
    let source = "enum E {\n  case a\n  case b, c\n}\n"
    #expect(keys(located(source)) == ["enum.E", "E.case.a", "E.case.b,c"])
    #expect(located(source).contains("  case a\n  \(directive("E.case.b,c"))\n  case b, c\n"))
  }

  @Test func aDeclarationThatDoesNotStartItsLineIsNotLocated() {
    // The members share one line with the type: the type's own directive is enough to keep the line numbers.
    #expect(keys(located("struct S { var x = 1; func m() {} }\n")) == ["struct.S"])
  }

  @Test func aViewInputComparisonWrittenBeforeTheDirectivesIsNotWrittenAgain() {
    // `view-inputs` finds its extension in the text without the directives, so the second lowering changes nothing.
    let pipeline = LoweringPipeline.standard.selecting(["view-inputs", "stable-source-locations"])!
    let options = LoweringOptions(lowerCodable: true, stableSourceLocations: true, sourcePath: "Web/V.swift")
    let source = "struct V: View {\n  var title = \"t\"\n  var body: some View { Text(title) }\n}\n"
    let once = lower(pipeline, source, options: options).text
    #expect(once.components(separatedBy: "static var _comparesInputs").count == 2)
    #expect(lower(pipeline, once, options: options).text == once)
  }

  // MARK: Keys

  @Test func aRepeatedKeyGetsANumberInFileOrder() {
    let source = "extension Array {\n  func f() {}\n}\nextension Array {\n  func f() {}\n}\n"
    #expect(keys(located(source)) == ["ext.Array", "ext.Array.func.f()", "ext.Array#2", "ext.Array.func.f()#2"])
  }

  @Test func keysDoNotChangeWhenADeclarationAboveGainsLines() {
    let before = "struct S {\n  func a() {}\n  func target(x: Int) {}\n}\n"
    let after = "struct S {\n  func a() {\n    let grew = 1\n    _ = grew\n  }\n  func target(x: Int) {}\n}\n"
    let beforeKeys = keys(located(before))
    let afterKeys = keys(located(after))
    #expect(beforeKeys == afterKeys)
    #expect(afterKeys.contains("S.func.target(x:)"))
    // The text after the directive of `target` is the same declaration, so its lines start at 1 again.
    #expect(located(after).contains("\(directive("S.func.target(x:)"))\n  func target(x: Int) {}\n"))
  }

  @Test func aKeyNeverContainsAQuoteBackslashOrBar() {
    let source = "struct S {\n  static func |(lhs: Int, rhs: Int) -> Int { lhs }\n}\n"
    for key in keys(located(source)) {
      #expect(!key.contains("\""))
      #expect(!key.contains("\\"))
      #expect(!key.contains("|"))
    }
  }

  // MARK: Idempotency and options

  @Test func loweringTheOutputChangesNothing() {
    let source = "/// Doc.\nstruct S {\n  var x: Int\n  func m() {}\n}\nextension S {\n  func e() {}\n}\n"
    let once = located(source)
    #expect(located(once) == once)
  }

  @Test func strippingTheDirectivesGivesBackTheOriginalText() {
    let source = "func f() {}\n"
    let once = located(source)
    #expect(StableSourceLocationsTransform.strippingDirectives(once) == "func f() {}\n")
  }

  @Test func aFileWithoutALocatedDeclarationGetsNoReset() {
    // A reset without an opening directive is a compiler error, so the reset comes only with a directive.
    #expect(located("// only a comment\n") == "// only a comment\n")
    #expect(located("#if DEBUG\n#endif\n") == "#if DEBUG\n#endif\n")
  }

  @Test func theOptionIsOffByDefault() {
    let pipeline = LoweringPipeline.standard.selecting(["stable-source-locations"])!
    let source = "func f() {}\n"
    #expect(lower(pipeline, source, options: LoweringOptions()).text == source)
  }

  @Test func theCountIsTheNumberOfDirectivesWritten() {
    let pipeline = LoweringPipeline.standard.selecting(["stable-source-locations"])!
    let result = lower(pipeline, "struct S {\n  func a() {}\n  func b() {}\n}\n", options: LoweringOptions(stableSourceLocations: true, sourcePath: "A.swift"))
    #expect(result.counts["stable-source-locations"] == 3)
  }

  @Test func theDirectiveFileValueCarriesThePathGivenToThePass() {
    let text = located("func f() {}\n", path: "Web/main.swift")
    #expect(StableSourceLocationsTransform.declarationLines(in: text).map(\.file) == ["Web/main.swift|func.f()"])
  }

  @Test func declarationLinesGiveTheLineOfTheDeclarationBelowEachDirective() {
    let text = located("import Foundation\n\nfunc f() {}\n")
    let lines = StableSourceLocationsTransform.declarationLines(in: text)
    #expect(lines.map(\.file) == ["Sources/A.swift|import.Foundation", "Sources/A.swift|func.f()"])
    let textLines = text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.map { textLines[$0.line - 1] } == ["import Foundation", "func f() {}"])
  }
}

/// The driver with `--stable-source-locations`: the report maps each located declaration to its original line.
@Suite struct StableSourceLocationsDriverTests {
  @Test func theReportMapsEachLocatedDeclarationToItsOriginalLine() throws {
    // Two added directive lines must not move the original lines: the report names the lines of the source.
    let source = "// header\nimport Foundation\n\nstruct S {\n  var x = 1\n  func m() {\n    _ = x\n  }\n}\n"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swl-stable-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    try source.write(to: root.appendingPathComponent("Sources/A.swift"), atomically: true, encoding: .utf8)
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-stable-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = URL(fileURLWithPath: try FileSystem.canonical(root.path))
    arguments.workspace = workspace
    arguments.product = "Demo"
    arguments.stableSourceLocations = true
    _ = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()

    let report = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: arguments.root.appendingPathComponent(".build/embedded-source-lowering/report.json"))) as? [String: Any])
    let entry = try #require((report["sourceMap"] as? [[String: Any]])?.first)
    let virtualFiles = try #require(entry["virtualFiles"] as? [String: Int])
    #expect(virtualFiles == [
      "Sources/A.swift|import.Foundation": 2,
      "Sources/A.swift|struct.S": 4,
      "Sources/A.swift|S.var.x": 5,
      "Sources/A.swift|S.func.m()": 6,
    ])
    // The lowered file says what the report says: the directive is above the declaration's line.
    let lowered = try String(contentsOf: workspace.appendingPathComponent("Sources/A.swift"), encoding: .utf8)
    #expect(lowered.contains("#sourceLocation(file: \"Sources/A.swift|S.func.m()\", line: 1)\n  func m() {\n"))
  }
}
