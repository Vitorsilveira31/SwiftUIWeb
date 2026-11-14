import SwiftParser
import SwiftSyntax

/// Lowers the key-path call sites of SwiftUI table sorting into Embedded-safe closure calls. Embedded Swift has no key
/// paths, so `KeyPathComparator` and sortable `TableColumn`s take a stable member name plus a getter closure
/// (`_embeddedMember:` / `_embeddedValue:`); the member name is the identity a sortable column uses to find its
/// comparator inside a table's `sortOrder`.
///
/// - `KeyPathComparator(\Order.status, order: .reverse)` becomes
///   `KeyPathComparator(_embeddedMember: "status", { (row: Order) in row.status }, order: .reverse)`.
/// - `KeyPathComparator(\.name)` becomes `KeyPathComparator(_embeddedMember: "name", { $0.name })`.
/// - `TableColumn("Status", value: \.status) { … }` becomes
///   `TableColumn("Status", _embeddedMember: "status", _embeddedValue: { $0.status }) { … }`.
///
/// A `TableColumn(title, value:)` without a trailing content closure is left to the `table-column-value` rule of the
/// simple rules, which renders the value as `Text`.
///
/// Origin (the previous, text-based lowerer): `lower_table_sorting`. Rules: `key-path-comparator`, `table-column-sortable`.
public struct TableSortingTransform: SourceTransform {
  public let name = "table-sorting"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    var text = text
    if text.contains("KeyPathComparator") {
      let tree = Parser.parse(source: text)
      let edits = comparatorEdits(tree, SourceBytes(text))
      counts.add("key-path-comparator", edits.count)
      text = try apply(edits, to: text)
    }
    if text.contains("TableColumn") {
      let tree = Parser.parse(source: text)
      let edits = sortableColumnEdits(tree, SourceBytes(text))
      counts.add("table-column-sortable", edits.count)
      text = try apply(edits, to: text)
    }
    return text
  }

  /// The getter closure for a key path: it names the row type when the key path does.
  static func getter(_ keyPath: PropertyKeyPath) -> String {
    switch keyPath.root {
    case let root?: "{ (row: \(root)) in row.\(keyPath.path) }"
    case nil: "{ $0.\(keyPath.path) }"
    }
  }

  /// `KeyPathComparator(<key path>[, order: <order>])`: the key path alone or with its sort order, nothing else.
  private func comparatorEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "KeyPathComparator", !call.hasTrailingClosure,
        let (leftParen, rightParen) = call.parentheses,
        let first = call.arguments.first, first.label == nil, let keyPath = PropertyKeyPath(first.expression)
      else { return }
      var order = ""
      switch call.arguments.count {
      case 1:
        break
      case 2:
        let second = call.arguments[call.arguments.index(after: call.arguments.startIndex)]
        guard second.label?.text == "order", second.trailingComma == nil else { return }
        order = ", order: \(second.expression.trimmedDescription)"
      default:
        return
      }
      edits.append(TextEdit(
        start: leftParen.startOffset, end: rightParen.endOffset,
        replacement: "(_embeddedMember: \"\(keyPath.path)\", \(Self.getter(keyPath))\(order))"
      ))
    })
    return edits
  }

  /// `TableColumn(<title>, value: <key path>[, comparator: <comparator>]) { … }`: a column with a content closure.
  private func sortableColumnEdits(_ tree: SourceFileSyntax, _ bytes: SourceBytes) -> [TextEdit] {
    var edits: [TextEdit] = []
    tree.walkCode(calls: { call in
      guard calleeName(call.calledExpression) == "TableColumn", call.parentheses != nil,
        let closure = call.trailingClosure
      else { return }
      let arguments = Array(call.arguments)
      guard arguments.count == 2 || arguments.count == 3,
        arguments[0].label == nil, let comma = arguments[0].trailingComma,
        arguments[1].label?.text == "value", let keyPath = PropertyKeyPath(arguments[1].expression)
      else { return }
      var comparator = ""
      if arguments.count == 3 {
        guard arguments[1].trailingComma != nil, arguments[2].label?.text == "comparator", arguments[2].trailingComma == nil else { return }
        comparator = ", comparator: \(arguments[2].expression.trimmedDescription)"
      }
      // From the comma after the title to the brace that opens the content closure.
      edits.append(TextEdit(
        start: comma.startOffset, end: closure.leftBrace.endOffset,
        replacement: ", _embeddedMember: \"\(keyPath.path)\", _embeddedValue: \(Self.getter(keyPath))\(comparator)) {"
      ))
    })
    return edits
  }
}
