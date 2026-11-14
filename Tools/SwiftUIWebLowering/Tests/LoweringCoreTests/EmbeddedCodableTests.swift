import Testing

@testable import LoweringCore

@Suite struct EmbeddedCodableTests {
  @Test func structsAreCodedByTheirStoredProperties() {
    let result = lower(
      """
      import SwiftUIWeb
      struct User: Codable {
        let id: Int
        var name: String = "x"
        var tags: [String]?
        let when = Date()
        static let shared = 1
        var label: String { name }
      }
      """, rules: ["embedded-codable"])
    #expect(result.text.contains("struct User: EmbeddedCodable {"))
    #expect(result.text.contains(".object([\"id\": try self.id._embeddedJSONValue(), \"name\": try self.name._embeddedJSONValue(), \"tags\": try self.tags._embeddedJSONValue(), \"when\": try self.when._embeddedJSONValue()])"))
    #expect(result.text.contains("return Self(id: try _embeddedField(Int.self, object, \"id\"), name: try _embeddedField(String.self, object, \"name\"), tags: try _embeddedField(Optional<[String]>.self, object, \"tags\"))"))
    #expect(result.text.contains("  public init(from decoder: EmbeddedDecoder) throws { self = try Self._embeddedDecodeJSONValue(decoder._value) }\n}\n"))
    #expect(result.counts["codable-to-embedded"] == 1)
    #expect(result.counts["embedded-codable-import"] == nil)
  }

  @Test func theFrameworkImportIsAddedOnlyWhenMissing() {
    let source = "struct Payload: Codable { let value: String }\n"
    #expect(lowered(source, rules: ["embedded-codable"]).hasPrefix("import SwiftUIWeb\nstruct Payload: EmbeddedCodable"))
    #expect(lowered(source, aliased: true, rules: ["embedded-codable"]).hasPrefix("import SwiftUI\n"))
    #expect(lower(source, rules: ["embedded-codable"]).counts["embedded-codable-import"] == 1)
    let imported = "@_spi(Renderer) import SwiftUIWeb\n" + source
    #expect(lowered(imported, rules: ["embedded-codable"]).hasPrefix("@_spi(Renderer) import SwiftUIWeb\nstruct Payload"))
    // An aliased application also reaches the serialization exports through its Foundation shim.
    #expect(lowered("import Foundation\n" + source, aliased: true, rules: ["embedded-codable"]).hasPrefix("import Foundation\nstruct Payload"))
    #expect(lowered("import Foundation\n" + source, rules: ["embedded-codable"]).hasPrefix("import SwiftUIWeb\nimport Foundation\n"))
  }

  @Test func theOutputIsAFixedPoint() {
    let once = lowered(
      """
      import SwiftUIWeb
      struct A: Codable { let a: Int }
      enum B: String, Codable { case x }
      enum C: Codable { case p(Int), q }
      """)
    #expect(lowered(once) == once)
  }

  @Test func aCustomWireFormatIsKept() {
    let output = lowered(
      """
      enum JSONValue: Codable {
        case string(String)
        func _embeddedJSONValue() throws -> EmbeddedJSONValue { .string("value") }
        static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Self { .string("value") }
      }
      """)
    #expect(output.contains("enum JSONValue: EmbeddedCodable"))
    #expect(output.components(separatedBy: "func _embeddedJSONValue()").count == 2)
    #expect(!output.contains("case .string(let v0)"))
  }

  @Test func keysRawEnumsAndAssociatedPayloads() {
    let output = lowered(
      """
      import SwiftUIWeb
      public struct Record: Codable {
        public let title: String
        var count: Int = 0
        enum CodingKeys: String, CodingKey { case title = "display_title"; case count }
        func ignored(value: Int) -> Int { value }
      }
      enum Kind: String, Codable { case text, image }
      enum Event: Codable { case empty; case text(String); case named(value: String, count: Int) }
      """)
    #expect(output.contains("\"display_title\": try self.title._embeddedJSONValue()"))
    #expect(output.contains("title: try _embeddedField(String.self, object, \"display_title\")"))
    #expect(output.contains("let raw = try String._embeddedDecodeJSONValue(value)"))
    #expect(output.contains("guard let result = Self(rawValue: raw)"))
    #expect(output.contains("case .empty: return .object([\"empty\": .object([:])])"))
    #expect(output.contains("case .text(let v0): return .object([\"text\": .object([\"_0\": try v0._embeddedJSONValue()])])"))
    #expect(output.contains("case .named(let v0, let v1)"))
    #expect(output.contains("return .named(value: try String._embeddedDecodeJSONValue(EmbeddedJSONValue.required(payload, \"value\")), count: try Int._embeddedDecodeJSONValue(EmbeddedJSONValue.required(payload, \"count\")))"))
    #expect(output.contains("return .text(try String._embeddedDecodeJSONValue(EmbeddedJSONValue.required(payload, \"_0\")))"))
  }

  @Test func membersOfMethodsAreNotStoredProperties() {
    let output = lowered("import SwiftUIWeb\nstruct Payload: Codable {\n  let value: String\n  func make() {\n    let local: String = \"not a field\"\n  }\n}\n")
    #expect(output.contains("self.value._embeddedJSONValue()"))
    #expect(!output.contains("local: try"))
  }

  @Test func enumCasesOnOneLineAreAllCoded() {
    let output = lowered("import SwiftUIWeb\nenum Mode: Codable {\n  case home, local, tag(name: String), latest\n}\n")
    for name in ["home", "local", "tag", "latest"] {
      #expect(output.contains("case .\(name)"), "\(name)")
    }
  }

  @Test func backtickedCasesAreCodedByTheirPlainName() {
    let output = lowered("import SwiftUIWeb\nenum Style: Codable {\n  case `default`\n  case other(Int)\n}\n")
    #expect(output.contains("case .default: return .object([\"default\": .object([:])])"))
    #expect(output.contains("case \"default\": return .default"))
    #expect(!output[output.range(of: "extension Style {")!.lowerBound...].contains("`"))
  }

  @Test func trailingCommentsDoNotReachTheGeneratedCode() {
    let output = lowered(
      """
      import SwiftUIWeb
      struct User: Codable {
        let id: Int // the id
        let name: String
        enum CodingKeys: String, CodingKey {
          case id = "identifier" // the wire name
          case name /* as is */
        }
      }
      enum Mode: Codable {
        case light // the default
        case custom(String) // user supplied
      }
      struct Point: Codable {
        let x: Int
        init(from decoder: Decoder) throws { x = 0 }
        enum Keys: CodingKey {
          case x // horizontal
        }
      }
      """)
    #expect(output.contains("case id = \"identifier\" // the wire name"))
    #expect(output.contains("[\"identifier\": try self.id._embeddedJSONValue(), \"name\": try self.name._embeddedJSONValue()]"))
    #expect(output.contains("id: try _embeddedField(Int.self, object, \"identifier\")"))
    #expect(output.contains("case .light: return .object([\"light\": .object([:])])"))
    #expect(output.contains("case \"light\": return .light"))
    #expect(output.contains("switch self { case .x: return \"x\" }"))
    #expect(output.contains("case \"x\": self = .x; default: return nil"))
  }

  @Test func oneSidedConformancesGetOnlyTheirHalf() {
    let output = lowered(
      """
      import SwiftUIWeb
      struct UserResponse: Decodable { let id: Int; let name: String }
      struct SignInPayload: Encodable { let email: String }
      struct BothModel: Codable, Sendable { let id: Int }
      enum Kind: String, Decodable { case a, b }
      enum Event: Encodable { case opened(id: Int), closed }
      func load<Value: Decodable, Body: Encodable>(_ body: Body) -> Value? { nil }
      """)
    #expect(output.contains("struct UserResponse: EmbeddedDecodable"))
    #expect(output.contains("struct SignInPayload: EmbeddedEncodable"))
    #expect(output.contains("struct BothModel: EmbeddedCodable, Sendable"))
    #expect(output.contains("enum Kind: String, EmbeddedDecodable"))
    #expect(output.contains("enum Event: EmbeddedEncodable"))
    #expect(output.contains("<Value: EmbeddedDecodable, Body: EmbeddedEncodable>"))
    for (name, encodes, decodes) in [
      ("UserResponse", false, true), ("SignInPayload", true, false), ("BothModel", true, true), ("Kind", false, true), ("Event", true, false),
    ] {
      let start = output.range(of: "extension \(name) {")!.lowerBound
      let rest = output[start...]
      let section = rest[..<(rest.range(of: "\n}\n")?.lowerBound ?? rest.endIndex)]
      #expect(section.contains("_embeddedJSONValue()") == encodes, "\(name) encode half")
      #expect(section.contains("_embeddedDecodeJSONValue(") == decodes, "\(name) decode half")
    }
  }

  @Test func protocolsThatRefineCodableGiveTheirHalves() {
    let output = lowered(
      """
      import SwiftUIWeb
      protocol Wire: Encodable {}
      struct Out: Wire { let id: Int }
      """)
    #expect(output.contains("protocol Wire: EmbeddedEncodable"))
    let section = output[output.range(of: "extension Out {")!.lowerBound...]
    #expect(section.contains("_embeddedJSONValue()"))
    #expect(!section.contains("_embeddedDecodeJSONValue("))
  }

  @Test func handWrittenDecodersUseTheEmbeddedShim() {
    let output = lowered(
      """
      import SwiftUIWeb
      struct Flags: Decodable {
        var on = false
        enum CodingKeys: String, CodingKey { case on = "onEnabled" }
        init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        }
      }
      struct Plain: Decodable { let id: String; let link: URL? }
      struct Composite: Decodable {
        let plain: Plain
        init(from decoder: any Decoder) throws { plain = try Plain(from: decoder) }
      }
      func fail(_ c: KeyedDecodingContainer<Flags.CodingKeys>) -> Error { DecodingError.dataCorruptedError(forKey: .on, in: c, debugDescription: "x") }
      """)
    #expect(output.contains("init(from decoder: EmbeddedDecoder) throws {\n    let c"))
    #expect(output.contains("init(from decoder: EmbeddedDecoder) throws { plain"))
    #expect(output.contains("enum CodingKeys: String, EmbeddedCodingKey"))
    #expect(output.contains("EmbeddedKeyedDecodingContainer<Flags.CodingKeys>"))
    #expect(output.contains("EmbeddedDecodingError.dataCorruptedError"))
    // A hand-written initializer is the decode contract for its type...
    #expect(output.contains("extension Flags {\n  public static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Self { try Self(from: EmbeddedDecoder(value)) }\n}"))
    // ...and a synthesized one is available to `Parent(from: decoder)`.
    #expect(output.contains("extension Plain {"))
    #expect(output.contains("link: try _embeddedField(Optional<URL>.self, object, \""))
    #expect(!output.contains(" Decoder)"))
  }

  @Test func nestedTypesAreQualifiedInGeneratedExtensions() {
    let output = lowered(
      """
      import SwiftUIWeb
      enum Namespace {
        struct Home: Decodable {
          enum Layout: String, Codable { case row }
          struct Section: Decodable {
            let layout: Layout
            let all: [Layout]?
          }
          let sections: [Section]
        }
      }
      private struct Hidden: Decodable { let id: Int }
      enum Keys: CodingKey { case title, subtitle }
      """)
    #expect(output.contains("extension Namespace.Home.Section {"))
    #expect(output.contains("layout: try _embeddedField(Namespace.Home.Layout.self, object, \""))
    #expect(output.contains("all: try _embeddedField(Optional<[Namespace.Home.Layout]>.self, object, \""))
    #expect(output.contains("sections: try _embeddedField([Namespace.Home.Section].self, object, \""))
    #expect(output.contains("extension Namespace.Home.Layout {"))
    #expect(output.contains("fileprivate struct Hidden: EmbeddedDecodable"))
    #expect(output.contains("extension Hidden {"))
    #expect(output.contains("enum Keys: EmbeddedCodingKey"))
    #expect(output.contains("extension Keys {\n  public var stringValue: String { switch self { case .title: return \"title\"; case .subtitle: return \"subtitle\" } }"))
  }

  @Test func membersOfAPrivateTypeAreNotPublic() {
    let output = lowered("import SwiftUIWeb\nprivate struct Hidden: Codable { let id: Int }\n")
    let section = output[output.range(of: "extension Hidden {")!.lowerBound...]
    #expect(section.contains("fileprivate func _embeddedJSONValue()"))
    #expect(!section.contains("public "))
  }

  @Test func extensionsThatCarryTheConformanceMoveItToTheDeclaration() {
    let output = lowered(
      """
      import SwiftUIWeb
      enum Filter: Hashable {
        case home
        case tag(name: String)
        var title: String {
          switch self {
          case let .tag(name): return name
          default: return ""
          }
        }
      }

      extension Filter: Codable {
      }

      actor Cache {
        private struct Item: Codable { var id: String }
      }
      struct Plain { let id: Int }
      extension Plain: Decodable, Encodable {}
      """)
    #expect(output.contains("enum Filter: Hashable, EmbeddedCodable {"))
    #expect(output.contains("extension Filter {\n public func _embeddedJSONValue()"))
    #expect(!output.contains(".let"))
    #expect(output.contains("fileprivate struct Item"))
    #expect(output.contains("struct Plain: EmbeddedDecodable, EmbeddedEncodable {"))
    #expect(output.contains("extension Plain {}"))
  }

  @Test func handWrittenEncodersAreDropped() {
    let output = lowered(
      """
      import SwiftUIWeb
      struct Card: Codable {
        let id: Int
        func encode(to encoder: Encoder) throws {
          var container = encoder.singleValueContainer()
          try container.encode(id)
        }
        func keep() {}
      }
      """)
    #expect(!output.contains("func encode(to"))
    #expect(output.contains("func keep() {}"))
    #expect(output.contains("self.id._embeddedJSONValue()"))
  }

  @Test func classesDecodeThroughTheirDesignatedInitializer() {
    let output = lowered(
      """
      import SwiftUIWeb
      final class Account: Codable {
        let id: Int
        let name: String
        init(name: String, id: Int) { self.id = id; self.name = name }
      }
      """)
    #expect(output.contains("return Self(name: try _embeddedField(String.self, object, \"name\"), id: try _embeddedField(Int.self, object, \"id\"))"))
    #expect(!output.contains("init(from decoder: EmbeddedDecoder)"))
  }

  @Test func structsWithAWrittenInitializerAssignTheirFields() {
    let output = lowered(
      """
      import SwiftUIWeb
      struct Slider: Codable {
        let value: Double
        let label: String
        init(position: Double) { value = position; label = "" }
      }
      """)
    #expect(output.contains("fileprivate init(_embeddedObject object: [String: EmbeddedJSONValue]) throws {"))
    #expect(output.contains("    self.value = try _embeddedField(Double.self, object, \"value\")\n"))
    #expect(output.contains("return try Self(_embeddedObject: object)"))
  }

  @Test func aDeclaredDecoderWithoutCodingKeysGetsTheSpelledOutKeys() {
    let output = lowered(
      """
      import SwiftUIWeb
      struct Point: Decodable {
        let x: Int
        let y: Int
        init(from decoder: Decoder) throws {
          let c = try decoder.container(keyedBy: CodingKeys.self)
          x = try c.decode(Int.self, forKey: .x)
          y = try c.decode(Int.self, forKey: .y)
        }
      }
      """)
    #expect(output.contains("extension Point {\n  fileprivate enum CodingKeys: String, EmbeddedCodingKey { case x, y }\n}"))
  }

  @Test func unclosedDeclarationsAreLeftAlone() {
    // The parser recovers them, but the text is not a declaration the lowerer can rewrite safely.
    let broken = lowered("struct Broken: Codable { let value: Int", rules: ["embedded-codable"])
    #expect(!broken.contains("_embeddedJSONValue"))
    #expect(!lowered("enum Keys: CodingKey {\n  case a\n", rules: ["embedded-codable"]).contains("stringValue"))
  }

  /// The previous lowerer reads a trailing comment as part of the type and writes it into the generated code.
  @Test func aCommentAfterAFieldTypeIsNotPartOfTheType() {
    let output = lowered("import SwiftUIWeb\nstruct A: Codable {\n  let id: Int // the id\n}\n", rules: ["embedded-codable"])
    #expect(output.contains("_embeddedField(Int.self, object, \"id\")"))
  }

  @Test func filesWithoutCodableAreReturnedAsTheyAre() {
    let source = "struct Plain { let id: Int }\nfunc f() { print(\"x\") }\n"
    #expect(lowered(source) == source)
    #expect(lower(source).counts.isEmpty)
  }

  @Test func theFrameworkPassLeavesFilesAlone() {
    let source = "struct A: Codable { let id: Int }\n"
    let result = lower(LoweringPipeline.standard, source, options: LoweringOptions(lowerCodable: false))
    #expect(result.text == source)
  }

  @Test func aRawStringKeyIsWrittenAsItsValueInANormalLiteral() {
    let result = lower(
      """
      import SwiftUIWeb
      struct Raw: Codable {
        let value: Int
        enum CodingKeys: String, CodingKey { case value = #"a\\nb"# }
      }
      """, rules: ["embedded-codable"])
    // The key is the three characters `a\nb`, so the literal holds `\\`, not an escape for a newline.
    #expect(result.text.contains(#""a\\nb""#))
  }

  @Test func aPublicInsideAKeyStaysAKeyWhenTheTypeIsMadeFileprivate() {
    let result = lower(
      """
      import SwiftUIWeb
      private struct Hidden: Codable {
        let value: Int
        enum CodingKeys: String, CodingKey { case value = "public key" }
      }
      """, rules: ["embedded-codable"])
    #expect(result.text.contains("\"public key\""))
    #expect(!result.text.contains("\"fileprivate key\""))
  }
}
