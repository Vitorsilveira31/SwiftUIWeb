import Foundation

/// One structured finding of the report's `diagnostics` array. The lowerer reports each rule that fired in a file as an
/// `SWUI-I001` information entry (`rule observable-attribute applied 2 time(s)`) placed at the first place in the original
/// source where the rule's syntax appears, so an editor can jump from the report to the construct that was rewritten.
struct RuleDiagnostic: Equatable {
  var code: String
  var severity: String
  var message: String
  /// UTF-8 offset into the original source, and the 1-based line and column (Unicode scalars) of it.
  var offset: Int
  var line: Int
  var column: Int

  func json(file: String) -> JSONValue {
    .object([
      "file": .string(file),
      "code": .string(code),
      "severity": .string(severity),
      "message": .string(message),
      "line": .int(line),
      "column": .int(column),
      "offset": .int(offset),
    ])
  }
}

enum RuleDiagnostics {
  static let informationCode = "SWUI-I001"

  /// The text each rule is looked for as; the first needle that occurs decides the place (the previous lowerer's `rule_offset`).
  /// A rule without an entry is placed at the start of the file.
  private static let needles: [String: [String]] = [
    "observable-attribute": ["@Observable"],
    "observation-ignored": ["@ObservationIgnored"],
    "observable-published": ["var ", "let "],
    "map-member": [".map(\\."],
    "binding-member": ["$"],
    "bindable-member": ["Bindable("],
    "allSatisfy-member": [".allSatisfy(\\."],
    "mapValues-member": [".mapValues(\\."],
    "compactMapValues-member": [".compactMapValues(\\."],
    "forEach-member": [".forEach(\\."],
    "labeled-function-member": ["whereSeparator: \\.", "where: \\.", "while: \\.", "by: \\."],
    "foreach-id-member": ["ForEach("],
    "foreach-id-self": ["ForEach("],
    "environment-member": ["@Environment"],
    "environment-modifier": [".environment"],
    "outline-children": ["OutlineGroup"],
    "keyframe-track": ["KeyframeTrack"],
    "content-builder-to-view-builder": ["@ContentBuilder"],
    "table-column-value": ["TableColumn"],
    "table-column-sortable": ["TableColumn"],
    "key-path-comparator": ["KeyPathComparator"],
    "list-id-member": ["List("],
    "codable-to-embedded": ["Codable", "Decodable", "Encodable"],
    "browser-reactor-entry-and-html-exports": ["@main"],
    "state-member-identities": ["@State"],
    "os-macos-condition": ["os(macOS)"],
    "as-data-bridge": [" as Data"],
    "environment-entry": ["@Entry"],
    "state-observable-assignment": ["self."],
    "defaults-object-cast": [".object(forKey", ".array(forKey"],
    "type-of-test": ["type(of:"],
    "model-macro": ["@Model"],
    "preview-macro": ["#Preview"],
    "query-sort-key-path": ["@Query"],
    "protocol-extension-requirement": ["extension"],
    "weak-self": ["weak self"],
    "weak-capture": ["weak "],
    "weak-property": ["weak "],
  ]

  /// The information entries for the rules in `counts`, in rule-name order.
  static func entries(for counts: RuleCounts, in source: String) -> [RuleDiagnostic] {
    let bytes = Array(source.utf8)
    return counts.filter { $0.value != 0 }
      .sorted { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }
      .map { rule, count in
        let offset = (needles[rule] ?? [""]).lazy.compactMap { find(Array($0.utf8), in: bytes) }.first ?? 0
        let place = LoweringError.position(of: offset, in: source)
        return RuleDiagnostic(
          code: informationCode, severity: "info", message: "rule \(rule) applied \(count) time(s)",
          offset: offset, line: place.line, column: place.column
        )
      }
  }

  private static func find(_ needle: [UInt8], in bytes: [UInt8]) -> Int? {
    if needle.isEmpty { return 0 }
    guard bytes.count >= needle.count else { return nil }
    let first = needle[0]
    var index = 0
    let last = bytes.count - needle.count
    while index <= last {
      if bytes[index] == first && bytes[index..<index + needle.count].elementsEqual(needle) { return index }
      index += 1
    }
    return nil
  }
}
