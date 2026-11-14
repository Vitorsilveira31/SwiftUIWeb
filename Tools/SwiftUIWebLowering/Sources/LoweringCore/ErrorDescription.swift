import SwiftParser
import SwiftSyntax

/// Embedded Swift cannot call a protocol-extension method on an error existential ("cannot specialize generic
/// function or default protocol method in this context"), which is what `error.localizedDescription` and
/// `controller.purchaseError?.errorDescription` are. Both become calls to free functions that take the error whole:
/// `_embeddedErrorDescription(error)` and `_embeddedOptionalErrorDescription(controller.purchaseError)`. Only a
/// receiver named like an error is rewritten: `unit.localizedDescription` is an ordinary property of its own type.
/// Applies to every source, application or framework.
///
/// Origin (the previous, text-based lowerer): `lower_error_descriptions`.
public struct ErrorDescriptionTransform: SourceTransform {
  public let name = "error-description"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("localizedDescription") || text.contains("errorDescription") else { return text }
    let tree = Parser.parse(source: text)
    let finder = DescriptionFinder()
    finder.walk(tree)
    var edits: [TextEdit] = []
    for access in finder.accesses {
      guard var receiver = access.base else { continue }
      var optional = false
      if let chained = receiver.as(OptionalChainingExprSyntax.self) {
        receiver = chained.expression
        optional = true
      }
      let base = receiver.trimmedDescription
      guard let last = Self.lastMember(ofChain: base), Self.namesAnError(last) else { continue }
      let function = access.declName.baseName.text == "localizedDescription" && !optional
        ? "_embeddedErrorDescription" : "_embeddedOptionalErrorDescription"
      edits.append(TextEdit(start: access.startOffset, end: access.endOffset, replacement: "\(function)(\(base))"))
    }
    guard !edits.isEmpty else { return text }
    counts.add("error-description", edits.count)
    return try apply(edits, to: text)
  }

  /// The lower-cased last name of a chain of identifiers (or closure arguments such as `$0`) joined by `.` or `?.`, or nil
  /// for any other expression.
  private static func lastMember(ofChain chain: String) -> String? {
    var last = ""
    var sawDot = true
    var index = chain.startIndex
    var segment = ""
    func finishSegment() -> Bool {
      let closureArgument = segment.hasPrefix("$") && segment.count > 1 && segment.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
      guard closureArgument || (segment.isIdentifierStart && !segment.contains(where: { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")) }))
      else { return false }
      last = segment
      segment = ""
      return true
    }
    while index < chain.endIndex {
      let character = chain[index]
      if character == "." {
        guard finishSegment() else { return nil }
        sawDot = true
      } else if character == "?" {
        let next = chain.index(after: index)
        guard next < chain.endIndex, chain[next] == ".", finishSegment() else { return nil }
        index = next
        sawDot = true
      } else {
        segment.append(character)
        sawDot = false
      }
      index = chain.index(after: index)
    }
    guard !sawDot, finishSegment() else { return nil }
    return last.lowercased()
  }

  private static func namesAnError(_ name: String) -> Bool {
    name.hasSuffix("error") || name == "err" || name.hasSuffix("failure")
  }
}

private final class DescriptionFinder: SyntaxVisitor {
  var accesses: [MemberAccessExprSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    if ["localizedDescription", "errorDescription"].contains(node.declName.baseName.text), node.declName.argumentNames == nil {
      accesses.append(node)
    }
    return .visitChildren
  }
}
