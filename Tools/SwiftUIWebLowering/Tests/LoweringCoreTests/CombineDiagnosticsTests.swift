import Foundation
import Testing

@testable import LoweringCore

@Suite struct CombineDiagnosticsTests {
  private func positions(_ source: String) -> [[Int]] {
    CombineDiagnostics.find(in: source).map { diagnostic in
      #expect(diagnostic.code == "combine-unsupported")
      #expect(diagnostic.message.contains("Remove 'import Combine'."))
      return [diagnostic.line, diagnostic.column]
    }
  }

  @Test func importFormsAreReportedAtTheModuleName() {
    let source =
      "import SwiftUI\nimport Combine\n@preconcurrency import Combine\nimport struct Combine.AnyPublisher\n@_exported import Combine\n"
    #expect(positions(source) == [[2, 8], [3, 24], [4, 15], [5, 19]])
  }

  @Test func aQualifiedReferenceIsReportedAndAMemberNamedCombineIsNot() {
    #expect(positions("let p = Combine.Just(1)\n") == [[1, 9]])
    #expect(positions("let x = Outer.Combine.Y\n").isEmpty)
    #expect(positions("var cancellables: Set<Combine.AnyCancellable> = []\n") == [[1, 23]])
    // The module name alone, and another module with the word in its name, are not references.
    #expect(positions("import CombineKit\nlet combine = 1\nlet Combine = 2\n").isEmpty)
  }

  @Test func mentionsInCommentsAndStringsAreNotFindings() {
    let source = "// import Combine\n/* Combine.Foo */\nlet s = \"import Combine and Combine.Bar\"\nlet raw = #\"Combine.Baz\"#\nimport CombineKit\n"
    #expect(positions(source).isEmpty)
    // The code in an interpolation is code.
    #expect(positions("let s = \"\\(Combine.Just(1))\"\n") == [[1, 12]])
  }

  @Test func everyOccurrenceIsReportedInSourceOrder() {
    let source = "import Combine\nlet a = Combine.Just(1)\nlet b = Combine.Empty<Int, Never>()\n"
    #expect(positions(source) == [[1, 8], [2, 9], [3, 9]])
    // An import with a submodule path is one finding, not two.
    #expect(positions("import Combine.Subject\n") == [[1, 8]])
  }

  @Test func columnsCountCharactersNotBytes() {
    #expect(positions("let é = 1; let p = Combine.Just(1)\n") == [[1, 20]])
    #expect(positions("let ünï = \"日本\"\nimport Combine\n") == [[2, 8]])
  }

  @Test func theDiagnosticIsPrintedAsPathLineColumnCodeMessage() {
    let line = CombineDiagnostics.find(in: "import Combine\n")[0].formatted(path: "Sources/App.swift")
    #expect(line == "Sources/App.swift:1:8: [combine-unsupported] \(CombineDiagnostics.message)")
  }

  // MARK: The workspace

  private func makePackage(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swl-\(UUID().uuidString)")
    for (path, content) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
  }

  private func run(_ root: URL, lowerCodable: Bool, rules: [String]? = nil) throws -> WorkspaceLowering.Summary {
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: workspace) }
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = "Demo"
    arguments.lowerCodable = lowerCodable
    arguments.rules = rules
    return try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
  }

  @Test func theWorkspaceRejectsCombineInApplicationSourcesBeforeLoweringAnything() throws {
    let framework = "import Combine\nlet framework = 1\n"
    let example = "import SwiftUI\nlet p = Combine.Just(1)\n"
    let root = try makePackage([
      "Sources/Framework.swift": framework,
      "Examples/Demo/Example.swift": example,
      "Examples/Other/Other.swift": "import Combine\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    // Without --lower-codable only the product's example is an application source.
    #expect(throws: LoweringArguments.Failure.self) { try run(root, lowerCodable: false) }
    do {
      _ = try run(root, lowerCodable: false)
    } catch {
      #expect("\(error)" == "Examples/Demo/Example.swift:2:9: [combine-unsupported] \(CombineDiagnostics.message)")
    }
    #expect(try String(contentsOf: root.appendingPathComponent("Examples/Demo/Example.swift"), encoding: .utf8) == example)

    // Every finding of every application source is reported, one per line, in path order.
    do {
      _ = try run(root, lowerCodable: true)
    } catch {
      let lines = "\(error)".split(separator: "\n").map(String.init)
      #expect(lines.count == 2)
      #expect(lines.first?.hasPrefix("Examples/Demo/Example.swift:2:9: [combine-unsupported]") == true)
      #expect(lines.last?.hasPrefix("Sources/Framework.swift:1:8: [combine-unsupported]") == true)
    }

    // The check can be left out.
    let summary = try run(root, lowerCodable: false, rules: ["browser-exports"])
    #expect(summary.changed.isEmpty)
  }

  @Test func aSourceTheRulesLeaveAloneIsNotListedAsChanged() throws {
    let root = try makePackage([
      "Sources/Framework.swift": "import Combine\nlet framework = 1\n",
      "Examples/Demo/Example.swift": "struct DemoView {\n  @ContentBuilder var body: some View { Text(\"ok\") }\n}\n",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let summary = try run(root, lowerCodable: false)
    #expect(summary.changed == ["Examples/Demo/Example.swift"])
  }
}
