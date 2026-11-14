import Foundation
import SwiftParser
import SwiftSyntax

/// `--live-literals`, development loop only. Wraps the string, number and boolean literals written inside
/// function bodies of an application file in `_live(id, literal)`, so the running page can be given another value for
/// one of them without a build (SwiftUIWebCore/LiveLiterals.swift). `_live` returns the literal while no other value
/// was sent, so a build with the pass behaves as one without it.
///
/// The id is the file's path hash in the high 32 bits and the literal's ordinal among the wrapped literals of the file
/// in the low 32, so an edit that only changes literal values keeps every id. The pass runs first: the ordinals are the
/// ones of the source as written, which is what the development loop compares on a save.
public struct LiveLiteralsTransform: SourceTransform {
  public static let passName = "live-literals"
  public let name = LiveLiteralsTransform.passName

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.liveLiteralsFile != nil }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard let file = options.liveLiteralsFile else { return text }
    // A lowered file (it holds the calls already, and code other passes generated) is left as it is.
    guard !text.contains(Self.marker) else { return text }
    let sites = LiveLiteralSites.find(in: text)
    // The marker is written even with nothing to wrap: other passes generate code, whose literals are not the source's.
    guard !sites.isEmpty else { return text + Self.marker }
    let prefix = UInt64(LiveLiteralSites.pathHash(file)) << 32
    var edits: [TextEdit] = []
    for (ordinal, site) in sites.enumerated() {
      edits.append(.insert("_live(\(prefix | UInt64(ordinal)), ", at: site.start))
      edits.append(.insert(")", at: site.end))
    }
    counts.add(Self.passName, sites.count)
    return try apply(edits, to: text) + Self.marker
  }

  /// The last line of a file the pass has read, so it is read once.
  static let marker = "\n// swiftuiweb:live-literals\n"
}

/// One literal the pass wraps: its byte range in the source and what it holds.
public struct LiveLiteralSite: Sendable, Equatable {
  public enum Kind: String, Sendable { case string, number, bool }
  public var start: Int
  public var end: Int
  public var kind: Kind
  /// The value as the page is told it: a string's content with its escapes resolved, a number or boolean as written
  /// (without `_` separators).
  public var value: String
}

public enum LiveLiteralSites {
  /// FNV-1a over the path's UTF-8 bytes, 32 bits.
  public static func pathHash(_ path: String) -> UInt32 {
    var hash: UInt32 = 0x811c_9dc5
    for byte in path.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 0x0100_0193
    }
    return hash
  }

  /// The literals the pass wraps, in source order. A literal already inside a `_live(...)` call is one of a lowered
  /// file and is left out, so lowering what was lowered changes nothing.
  public static func find(in text: String) -> [LiveLiteralSite] {
    guard text.contains("\"") || text.contains(where: \.isNumber) || text.contains("true") || text.contains("false") else { return [] }
    let finder = Finder()
    finder.walk(Parser.parse(source: text))
    return finder.sites
  }

  /// The lines the development loop sends for a save that turned `old` into `new`: one `id<TAB>kind<TAB>value` per literal
  /// whose value changed, or nil when the two differ in anything else and the save needs a build. A number that was an
  /// integer and is now written with a fraction or an exponent (or the reverse) needs one too: the type the compiler infers
  /// for `let amount = 1` is not the one it infers for `let amount = 1.5`, and the running page was compiled for the first.
  public static func replacements(old: String, new: String, relativePath: String) throws -> [String]? {
    let before = find(in: old), after = find(in: new)
    guard before.count == after.count, try skeleton(of: old, sites: before) == skeleton(of: new, sites: after) else { return nil }
    let prefix = UInt64(pathHash(relativePath)) << 32
    var lines: [String] = []
    for (ordinal, pair) in zip(before, after).enumerated() {
      guard pair.0.kind == pair.1.kind else { return nil }
      if pair.0.kind == .number, isInteger(pair.0.value) != isInteger(pair.1.value) { return nil }
      guard pair.0.value != pair.1.value else { continue }
      let site = pair.1
      let value = site.kind == .string
        ? site.value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
        : site.value
      lines.append("\(prefix | UInt64(ordinal))\t\(site.kind.rawValue.prefix(1))\t\(value)")
    }
    return lines
  }

  private static func isInteger(_ number: String) -> Bool { number.allSatisfy(\.isNumber) }

  /// The source with every wrapped literal's bytes removed: two sources with the same skeleton differ only in literal
  /// values, which is the edit the page can take without a build.
  public static func skeleton(of text: String, sites: [LiveLiteralSite]) throws -> String {
    try apply(sites.map { TextEdit.remove($0.start, $0.end) }, to: text)
  }

  /// Calls whose string argument must stay a literal the compiler reads (a log message, a static string).
  private static let literalOnlyCallees: Set<String> = [
    "debug", "info", "notice", "error", "warning", "fault", "critical", "log", "trace", "os_log", "os_signpost",
    "fatalError", "precondition", "preconditionFailure", "assert", "assertionFailure", "_live",
  ]

  private final class Finder: SyntaxVisitor {
    var sites: [LiveLiteralSite] = []

    init() { super.init(viewMode: .sourceAccurate) }

    /// Whether the nearest thing that holds `node` is a body that runs again (a function, an accessor, a closure) and
    /// nothing between them needs the literal as a literal.
    private func eligible(_ node: some SyntaxProtocol) -> Bool {
      var inBody = false
      var cursor = node.parent
      while let current = cursor {
        switch current.kind {
        case .closureExpr, .accessorBlock, .accessorDecl:
          inBody = true
        case .codeBlock:
          if let owner = current.parent?.kind, owner == .functionDecl || owner == .initializerDecl || owner == .deinitializerDecl || owner == .accessorDecl {
            inBody = true
          }
        case .functionParameter, .enumCaseParameter, .enumCaseElement, .attribute, .ifConfigClause, .macroExpansionExpr, .macroExpansionDecl,
          .expressionPattern, .switchCaseLabel, .availabilityArgument, .genericArgument, .typeAnnotation, .subscriptCallExpr, .stringLiteralExpr,
          .keyPathExpr, .poundSourceLocation:
          return false
        case .memberBlock:
          // The initial value of a stored member (`var b = "x"`, `static let a = 1`) is evaluated once. The walk goes from
          // the literal outwards, so a member's value reaches the type's members without having met a body; a local `let`
          // in a function meets the function's body first.
          if !inBody { return false }
        case .functionCallExpr:
          if let call = current.as(FunctionCallExprSyntax.self) {
            let callee = call.calledExpression
            let name = callee.as(DeclReferenceExprSyntax.self)?.baseName.text ?? callee.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            if let name, LiveLiteralSites.literalOnlyCallees.contains(name) { return false }
          }
        default:
          break
        }
        cursor = current.parent
      }
      return inBody
    }

    private func add(_ node: some SyntaxProtocol, _ kind: LiveLiteralSite.Kind, _ value: String) {
      sites.append(LiveLiteralSite(start: node.startOffset, end: node.endOffset, kind: kind, value: value))
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
      // A plain one-line literal: no interpolation, no raw delimiter, no multiline quote.
      // (An escaped line break splits the text into segments, so more than one segment is not an interpolation.)
      guard node.openingPounds == nil, node.openingQuote.tokenKind == .stringQuote, eligible(node),
        node.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) })
      else { return .visitChildren }
      guard let value = node.representedLiteralValue else { return .skipChildren }
      add(node, .string, value)
      return .skipChildren
    }

    override func visit(_ node: IntegerLiteralExprSyntax) -> SyntaxVisitorContinueKind {
      let text = node.literal.text.filter { $0 != "_" }
      // Decimal only: a hex or binary literal is usually a mask or a color component, not something to tune.
      if text.allSatisfy(\.isNumber), eligible(node) { add(node, .number, text) }
      return .skipChildren
    }

    override func visit(_ node: FloatLiteralExprSyntax) -> SyntaxVisitorContinueKind {
      let text = node.literal.text.filter { $0 != "_" }
      if !text.hasPrefix("0x"), eligible(node) { add(node, .number, text) }
      return .skipChildren
    }

    override func visit(_ node: BooleanLiteralExprSyntax) -> SyntaxVisitorContinueKind {
      if eligible(node) { add(node, .bool, node.literal.text) }
      return .skipChildren
    }
  }
}
