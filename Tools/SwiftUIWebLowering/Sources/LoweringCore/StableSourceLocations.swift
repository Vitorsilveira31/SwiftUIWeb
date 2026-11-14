import Foundation
import SwiftParser
import SwiftSyntax

/// Gives every declaration its own source location, so that an edit inside one declaration does not renumber the lines of
/// the others. Embedded Swift serializes the SIL of every non-`@export(interface)` function into the `.swiftmodule`,
/// with absolute source locations; a line added in one function shifts every later function of the file, so the module's
/// bytes change and every importing module recompiles, even when the edited body is not serialized at all.
///
/// Rule: `stable-source-locations`. Before the first token of each declaration in a declaration context (file scope, and
/// the member block of a type, extension or protocol), on its own line, the pass inserts
///
///     #sourceLocation(file: "<path>|<key>", line: 1)
///
/// so that the declaration's first line is line 1 of a virtual file. `<key>` is the dotted chain of the enclosing type and
/// extension names, then the declaration's kind and name with its argument labels (`LayoutSubview.func.place(at:anchor:proposal:)`,
/// `Foo.var.bar`, `ext.Array.func.foo(_:)`); a repeated key gets `#2`, `#3`, ... in file order. The key does not depend on
/// the line, so it is the same after an edit elsewhere. A final `#sourceLocation()` ends the file.
///
/// Declarations nested in a function, closure or accessor body are not located, and neither is a declaration that does not
/// start its line. Errors name `<path>|<key>:L:C`, where `L` counts from the declaration's first line; the workspace driver
/// records the original line of each declaration in the report (`virtualFiles`), and `Tools/dev-watch.mjs` maps the
/// errors back to the original file.
///
/// Idempotent: the directives the pass wrote are removed before the file is located again, so lowering the output changes
/// nothing. Runs only with `--stable-source-locations` (the debug development loop), last of all the passes.
public struct StableSourceLocationsTransform: SourceTransform {
  public let name = "stable-source-locations"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.stableSourceLocations }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    let path = options.sourcePath ?? "Source.swift"
    let stripped = Self.strippingDirectives(text)
    // A control character in the path cannot be written into a string literal: such a file gets no directives.
    guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return stripped }
    let locator = DeclarationLocator(path: path, bytes: SourceBytes(stripped))
    locator.collect(Parser.parse(source: stripped))
    counts.add(name, locator.edits.count)
    // A reset closes an opening directive: a file with none written gets none (the compiler rejects a lone reset).
    guard !locator.edits.isEmpty else { return stripped }
    var output = try apply(locator.edits, to: stripped)
    if !output.isEmpty, !output.hasSuffix("\n") { output += "\n" }
    return output + Self.resetLine + "\n"
  }

  /// The declarations this pass located in `text`, as `(file, line)`: the directive's file value (`path|key`) and the
  /// 1-based line of the declaration below it, in the text given (the workspace driver maps it to the original line).
  public static func declarationLines(in text: String) -> [(file: String, line: Int)] {
    var result: [(file: String, line: Int)] = []
    for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      if let file = fileValue(ofDirective: String(line)) { result.append((file, index + 2)) }
    }
    return result
  }

  // MARK: Directives

  static let resetLine = "#sourceLocation()"
  private static let directiveHead = "#sourceLocation(file: \""
  private static let directiveTail = "\", line: 1)"

  static func directive(file: String) -> String { directiveHead + file + directiveTail }

  /// The file value of a directive this pass writes (`path|key`), or nil for any other line.
  static func fileValue(ofDirective line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix(directiveHead), trimmed.hasSuffix(directiveTail), trimmed.count > directiveHead.count + directiveTail.count else {
      return nil
    }
    let value = String(trimmed.dropFirst(directiveHead.count).dropLast(directiveTail.count))
    return value.contains("|") ? value : nil
  }

  /// The text without the directives this pass writes (whole lines, so the text is what it was before the pass ran).
  static func strippingDirectives(_ text: String) -> String {
    guard text.contains("#sourceLocation") else { return text }
    return text.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { line in
        fileValue(ofDirective: String(line)) == nil && line.trimmingCharacters(in: .whitespaces) != resetLine
      }
      .joined(separator: "\n")
  }
}

/// Walks the declaration contexts of a file and records one insertion per located declaration.
private final class DeclarationLocator {
  let path: String
  let bytes: SourceBytes
  private(set) var edits: [TextEdit] = []
  private var used: [String: Int] = [:]

  init(path: String, bytes: SourceBytes) {
    self.path = path
    self.bytes = bytes
  }

  /// What a declaration contributes: its own key part, the name its members are keyed under (nil: members are not keyed
  /// under it), and its member block.
  private struct Described {
    var part: String
    var scope: String?
    var members: MemberBlockSyntax?
  }

  func collect(_ file: SourceFileSyntax) {
    visit(file.statements, context: [])
  }

  private func visit(_ items: CodeBlockItemListSyntax, context: [String]) {
    for item in items {
      if case .decl(let decl) = item.item { visit(decl, context: context) }
    }
  }

  private func visit(_ members: MemberBlockItemListSyntax, context: [String]) {
    for member in members { visit(member.decl, context: context) }
  }

  private func visit(_ decl: DeclSyntax, context: [String]) {
    if let config = decl.as(IfConfigDeclSyntax.self) {
      // The `#if` lines themselves are not declarations; the branches are, in whichever context the `#if` stands.
      for clause in config.clauses {
        switch clause.elements {
        case .statements(let items)?: visit(items, context: context)
        case .decls(let members)?: visit(members, context: context)
        default: break
        }
      }
      return
    }
    guard let described = Self.describe(decl) else { return }
    locate(decl, key: key(context: context, part: described.part))
    if let members = described.members {
      visit(members.members, context: context + [described.scope ?? described.part])
    }
  }

  private func key(context: [String], part: String) -> String {
    let base = (context + [part]).joined(separator: ".")
    let count = (used[base] ?? 0) + 1
    used[base] = count
    return count == 1 ? base : "\(base)#\(count)"
  }

  /// Inserts the directive on the line of the declaration's first token, when that token starts its line.
  private func locate(_ decl: DeclSyntax, key: String) {
    let start = decl.startOffset
    let lineStart = bytes.lineStart(start)
    let indent = bytes.slice(lineStart, start)
    guard indent.allSatisfy({ $0 == " " || $0 == "\t" }) else { return }
    // The path goes into a string literal, so its quotes and backslashes are escaped.
    let escapedPath = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    edits.append(.insert(indent + StableSourceLocationsTransform.directive(file: "\(escapedPath)|\(Self.sanitized(key))") + "\n", at: lineStart))
  }

  // MARK: Keys

  /// Keys are written into a string literal and split at `|` and `:`, so they carry no quote, backslash, bar or white space.
  static func sanitized(_ key: String) -> String {
    String(key.unicodeScalars.map { scalar -> Character in
      if scalar == "\"" || scalar == "\\" || scalar == "|" || scalar.properties.isWhitespace { return "_" }
      return Character(scalar)
    })
  }

  private static func labels(_ parameters: FunctionParameterListSyntax) -> String {
    "(" + parameters.map { $0.firstName.text + ":" }.joined() + ")"
  }

  private static func typeKey(_ type: TypeSyntax) -> String {
    if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
    if let member = type.as(MemberTypeSyntax.self) { return typeKey(member.baseType) + "." + member.name.text }
    return type.trimmedDescription
  }

  private static func describe(_ decl: DeclSyntax) -> Described? {
    if let node = decl.as(StructDeclSyntax.self) {
      return Described(part: "struct.\(node.name.text)", scope: node.name.text, members: node.memberBlock)
    }
    if let node = decl.as(ClassDeclSyntax.self) {
      return Described(part: "class.\(node.name.text)", scope: node.name.text, members: node.memberBlock)
    }
    if let node = decl.as(ActorDeclSyntax.self) {
      return Described(part: "actor.\(node.name.text)", scope: node.name.text, members: node.memberBlock)
    }
    if let node = decl.as(EnumDeclSyntax.self) {
      return Described(part: "enum.\(node.name.text)", scope: node.name.text, members: node.memberBlock)
    }
    if let node = decl.as(ProtocolDeclSyntax.self) {
      return Described(part: "protocol.\(node.name.text)", scope: node.name.text, members: node.memberBlock)
    }
    if let node = decl.as(ExtensionDeclSyntax.self) {
      let part = "ext." + typeKey(node.extendedType)
      return Described(part: part, scope: part, members: node.memberBlock)
    }
    if let node = decl.as(FunctionDeclSyntax.self) {
      return Described(part: "func.\(node.name.text)\(labels(node.signature.parameterClause.parameters))", scope: nil, members: nil)
    }
    if let node = decl.as(InitializerDeclSyntax.self) {
      return Described(part: "init.init\(labels(node.signature.parameterClause.parameters))", scope: nil, members: nil)
    }
    if decl.is(DeinitializerDeclSyntax.self) {
      return Described(part: "deinit.deinit", scope: nil, members: nil)
    }
    if let node = decl.as(VariableDeclSyntax.self) {
      let names = node.bindings.map { $0.pattern.trimmedDescription }.joined(separator: ",")
      return Described(part: "\(node.bindingSpecifier.text).\(names)", scope: nil, members: nil)
    }
    if let node = decl.as(SubscriptDeclSyntax.self) {
      return Described(part: "subscript.subscript\(labels(node.parameterClause.parameters))", scope: nil, members: nil)
    }
    if let node = decl.as(TypeAliasDeclSyntax.self) {
      return Described(part: "typealias.\(node.name.text)", scope: nil, members: nil)
    }
    if let node = decl.as(AssociatedTypeDeclSyntax.self) {
      return Described(part: "associatedtype.\(node.name.text)", scope: nil, members: nil)
    }
    if let node = decl.as(EnumCaseDeclSyntax.self) {
      let names = node.elements.map { $0.name.text }.joined(separator: ",")
      return Described(part: "case.\(names)", scope: nil, members: nil)
    }
    if let node = decl.as(ImportDeclSyntax.self) {
      return Described(part: "import.\(node.path.map { $0.name.text }.joined(separator: "."))", scope: nil, members: nil)
    }
    if let node = decl.as(OperatorDeclSyntax.self) {
      return Described(part: "operator.\(node.name.text)", scope: nil, members: nil)
    }
    if let node = decl.as(MacroExpansionDeclSyntax.self) {
      return Described(part: "macro.\(node.macroName.text)", scope: nil, members: nil)
    }
    return nil
  }
}
