import Foundation
import SwiftParser
import SwiftSyntax

/// One finding of the lowerer's checks, in the form every failure is printed in: `path:line:column: [code] message`.
public struct LoweringDiagnostic: Sendable, Equatable {
  public var code: String
  public var message: String
  /// 1-based line, and 1-based column counted in Unicode scalars.
  public var line: Int
  public var column: Int

  public func formatted(path: String) -> String {
    "\(path):\(line):\(column): [\(code)] \(message)"
  }
}

/// Apple's Combine is not available in a browser build. Every use of it in one application source is a finding: an
/// `import` (with attributes, or of one declaration, such as `import struct Combine.AnyPublisher`) and a qualified
/// `Combine.X` reference, reported at the `Combine` token. Comments and the text of string literals are not code, so
/// prose that mentions the word is not a finding; the interpolations of a literal are. Nothing is rewritten: the driver
/// stops the lowering on any finding, before anything is written.
///
/// Origin (the previous, text-based lowerer): `combine_diagnostics`. The previous check masks comments and whole string literals and looks for the
/// import and the qualified reference as text at the start of a line / without spaces; this one reads the tokens, so
/// `Combine` inside an interpolation, `Combine .Just` and an import that follows another statement on its line are
/// findings too.
public enum CombineDiagnostics {
  public static let code = "combine-unsupported"
  public static let message =
    "Combine is not supported in SwiftUIWeb browser builds. Replace Combine publishers/subscriptions with Swift Observation (@Observable) and async/await (AsyncStream/Task). Remove 'import Combine'."

  /// The findings of `source`, in source order.
  public static func find(in source: String) -> [LoweringDiagnostic] {
    guard source.contains("Combine") else { return [] }
    let tree = Parser.parse(source: source)
    let tokens = Array(tree.tokens(viewMode: .sourceAccurate))
    var offsets = Set<Int>()
    for (index, token) in tokens.enumerated() where token.tokenKind == .identifier("Combine") {
      let previous = index > 0 ? tokens[index - 1] : nil
      // `Outer.Combine.X` names a member called Combine, not the module.
      if previous?.tokenKind == .period { continue }
      if isImportedModule(token) {
        offsets.insert(token.startOffset)
      } else if index + 1 < tokens.count, tokens[index + 1].tokenKind == .period, startsWithIdentifierCharacter(tokens, after: index + 1) {
        offsets.insert(token.startOffset)
      }
    }
    let bytes = SourceBytes(source)
    return offsets.sorted().map { offset in
      let lineStart = bytes.lineStart(offset)
      return LoweringDiagnostic(
        code: code, message: message,
        line: bytes.bytes[0..<offset].reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) },
        // Columns count characters (Unicode scalars), not bytes.
        column: bytes.bytes[lineStart..<offset].reduce(1) { $0 + (($1 & 0xC0) == 0x80 ? 0 : 1) }
      )
    }
  }

  /// `Combine` as the first component of an import path.
  private static func isImportedModule(_ token: TokenSyntax) -> Bool {
    guard let component = token.parent?.as(ImportPathComponentSyntax.self),
      let path = component.parent?.as(ImportPathComponentListSyntax.self)
    else { return false }
    return path.first?.id == component.id
  }

  private static func startsWithIdentifierCharacter(_ tokens: [TokenSyntax], after period: Int) -> Bool {
    guard period + 1 < tokens.count, let first = tokens[period + 1].text.unicodeScalars.first else { return false }
    return first == "_" || (first.isASCII && first.properties.isAlphabetic)
  }
}

extension WorkspaceLowering {
  /// Whether `relative` is lowered as an application source (with `--lower-codable`, or inside the product's own folder,
  /// an example or a test app).
  func lowersAsApplication(_ relative: String) -> Bool {
    arguments.lowerCodable || WorkspaceLowering.productFolders(arguments.product).contains { relative.hasPrefix($0 + "/") }
  }

  /// Rejects Combine in every application source before anything is lowered: every finding of every source is
  /// reported, and the run fails so the browser build stops before the Swift compiler sees the module.
  func rejectCombine(in relativePaths: [String], root: String) throws {
    var failures: [String] = []
    for relative in relativePaths where lowersAsApplication(relative) {
      let source = try FileSystem.readString(FileSystem.join(root, relative))
      failures.append(contentsOf: CombineDiagnostics.find(in: source).map { $0.formatted(path: relative) })
    }
    if !failures.isEmpty { throw LoweringArguments.Failure.message(failures.joined(separator: "\n")) }
  }
}
