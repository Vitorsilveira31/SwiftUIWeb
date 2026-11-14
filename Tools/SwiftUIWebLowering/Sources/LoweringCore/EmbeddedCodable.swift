import SwiftParser
import SwiftSyntax

/// Generates the Embedded Codable conformances (`_embeddedJSONValue` / `_embeddedDecodeJSONValue`) for the
/// application's `Codable` types and renames the Codable protocol family to its `Embedded*` counterparts.
///
/// Origin (the previous, text-based lowerer): `lower_embedded_codable`, `merge_codable_extensions`, `widen_private_codable`,
/// `drop_hand_written_encoders`, `embedded_protocol_names` and the import it injects.
public struct EmbeddedCodableTransform: SourceTransform {
  public let name = "embedded-codable"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  /// Words that make a file the generator's business; a file without any of them is returned as it is.
  private static let triggers = [
    "Codable", "Decodable", "Encodable", "Decoder", "CodingKey", "KeyedDecodingContainer",
    "SingleValueDecodingContainer", "DecodingError",
  ]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard Self.triggers.contains(where: text.contains) else { return text }
    var text = try Self.mergeCodableExtensions(text)
    text = try Self.widenPrivateCodableAndDropEncoders(text)
    let lowered = try Self.generate(text)
    counts.add("codable-to-embedded", lowered.count)
    return lowered.text
  }

  // MARK: Extensions that carry the conformance

  /// `extension Name: Codable { init(from:) ... }` declares the conformance away from the type; the synthesis needs
  /// it on the declaration, so the conformance moves there.
  static func mergeCodableExtensions(_ text: String) throws -> String {
    var text = text
    while text.contains("extension") {
      let tree = Parser.parse(source: text)
      let bytes = SourceBytes(text)
      guard let edits = firstMergeEdits(in: tree, bytes: bytes) else { break }
      text = try apply(edits, to: text)
    }
    return text
  }

  private static let codableProtocols: Set<String> = ["Codable", "Decodable", "Encodable"]

  private static func firstMergeEdits(in tree: SourceFileSyntax, bytes: SourceBytes) -> [TextEdit]? {
    let finder = ExtensionFinder(codableProtocols: codableProtocols)
    finder.walk(tree)
    guard let (extensionDecl, name) = finder.firstMergeable else { return nil }
    guard let clause = extensionDecl.inheritanceClause,
      let firstItem = clause.inheritedTypes.first, let lastItem = clause.inheritedTypes.last,
      let identifier = extensionDecl.extendedType.as(IdentifierTypeSyntax.self)
    else { return nil }
    let protocols = bytes.slice(firstItem.startOffset, lastItem.endOffset - (lastItem.trailingComma.map { $0.endOffset - $0.startOffset } ?? 0))
    // The extension keeps its body but loses the conformance: `extension Name {`.
    var edits = [TextEdit(start: identifier.endOffset, end: extensionDecl.memberBlock.leftBrace.startOffset, replacement: " ")]
    let primaries = PrimaryFinder(name: name)
    primaries.walk(tree)
    if let primary = primaries.first, let merge = mergeEdit(for: primary, protocols: protocols) {
      edits.append(merge)
    }
    return edits
  }

  private static func mergeEdit(for primary: DeclSyntax, protocols: String) -> TextEdit? {
    let inheritance: InheritanceClauseSyntax?
    let genericWhere: GenericWhereClauseSyntax?
    let nameEnd: Int
    if let declaration = primary.as(StructDeclSyntax.self) {
      inheritance = declaration.inheritanceClause
      genericWhere = declaration.genericWhereClause
      nameEnd = (declaration.genericParameterClause?.endOffset) ?? declaration.name.endOffset
    } else if let declaration = primary.as(ClassDeclSyntax.self) {
      inheritance = declaration.inheritanceClause
      genericWhere = declaration.genericWhereClause
      nameEnd = (declaration.genericParameterClause?.endOffset) ?? declaration.name.endOffset
    } else if let declaration = primary.as(EnumDeclSyntax.self) {
      inheritance = declaration.inheritanceClause
      genericWhere = declaration.genericWhereClause
      nameEnd = (declaration.genericParameterClause?.endOffset) ?? declaration.name.endOffset
    } else {
      return nil
    }
    if let inheritance {
      return .insert(", \(protocols)", at: (genericWhere?.endOffset) ?? inheritance.endOffset)
    }
    // A header with a `where` clause but no conformance list is not one the previous lowerer's pattern reads.
    if genericWhere != nil { return nil }
    return .insert(": \(protocols)", at: nameEnd)
  }

  private final class ExtensionFinder: SyntaxVisitor {
    let codableProtocols: Set<String>
    var firstMergeable: (ExtensionDeclSyntax, String)?

    init(codableProtocols: Set<String>) {
      self.codableProtocols = codableProtocols
      super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
      guard firstMergeable == nil else { return .skipChildren }
      guard node.attributes.isEmpty, node.genericWhereClause == nil,
        node.modifiers.count <= 1,
        node.modifiers.allSatisfy({ modifier in
          modifier.detail == nil && [.keyword(.public), .keyword(.internal), .keyword(.package)].contains(modifier.name.tokenKind)
        }),
        let identifier = node.extendedType.as(IdentifierTypeSyntax.self), identifier.genericArgumentClause == nil,
        let clause = node.inheritanceClause, !clause.inheritedTypes.isEmpty,
        clause.inheritedTypes.allSatisfy({ item in
          item.type.as(IdentifierTypeSyntax.self).map { codableProtocols.contains($0.name.text) } ?? false
        })
      else { return .visitChildren }
      firstMergeable = (node, identifier.name.text)
      return .skipChildren
    }
  }

  private final class PrimaryFinder: SyntaxVisitor {
    let name: String
    var first: DeclSyntax?

    init(name: String) {
      self.name = name
      super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
      if first == nil && node.name.text == name { first = DeclSyntax(node) }
      return first == nil ? .visitChildren : .skipChildren
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
      if first == nil && node.name.text == name { first = DeclSyntax(node) }
      return first == nil ? .visitChildren : .skipChildren
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
      if first == nil && node.name.text == name { first = DeclSyntax(node) }
      return first == nil ? .visitChildren : .skipChildren
    }
  }

  // MARK: Private types and hand-written encoders

  /// Nested `private` Codable types are unreachable from the file-scope extensions the synthesis emits, so they
  /// become `fileprivate`. A hand-written `func encode(to encoder: Encoder)` has no Embedded counterpart (`Encoder`
  /// is unavailable); the synthesized `_embeddedJSONValue` is the encode contract, so the function is dropped.
  static func widenPrivateCodableAndDropEncoders(_ text: String) throws -> String {
    guard text.contains("private") || text.contains("encode") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let visitor = PrivateAndEncoderVisitor(bytes: bytes)
    visitor.walk(tree)
    return try apply(visitor.edits, to: text)
  }

  private final class PrivateAndEncoderVisitor: SyntaxVisitor {
    let bytes: SourceBytes
    var edits: [TextEdit] = []

    init(bytes: SourceBytes) {
      self.bytes = bytes
      super.init(viewMode: .sourceAccurate)
    }

    private func widen(modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax, inheritance: InheritanceClauseSyntax?) {
      guard modifiers.count == 1, let modifier = modifiers.first, modifier.detail == nil,
        modifier.name.tokenKind == .keyword(.private), let inheritance
      else { return }
      // `private` has to start its line: attributes on the same line put something before it.
      if let last = attributes.last, bytes.lineStart(last.endOffset) == bytes.lineStart(modifier.name.startOffset) { return }
      guard inheritance.inheritedTypes.contains(where: { item in
        ["Codable", "Decodable", "Encodable"].contains(where: { word in Self.containsWord(item.type.trimmedDescription, word) })
      }) else { return }
      edits.append(TextEdit(start: modifier.name.startOffset, end: modifier.name.endOffset, replacement: "fileprivate"))
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
      var search = text[...]
      while let range = search.range(of: word) {
        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
        let isWord: (Character?) -> Bool = { $0.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false }
        if !isWord(before) && !isWord(after) { return true }
        search = text[range.upperBound...]
      }
      return false
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
      widen(modifiers: node.modifiers, attributes: node.attributes, inheritance: node.inheritanceClause)
      return .visitChildren
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
      widen(modifiers: node.modifiers, attributes: node.attributes, inheritance: node.inheritanceClause)
      return .visitChildren
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
      widen(modifiers: node.modifiers, attributes: node.attributes, inheritance: node.inheritanceClause)
      return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
      guard node.name.text == "encode", node.attributes.isEmpty, node.genericParameterClause == nil,
        node.modifiers.count <= 1,
        node.modifiers.allSatisfy({ $0.detail == nil && [.keyword(.public), .keyword(.internal)].contains($0.name.tokenKind) }),
        node.signature.returnClause == nil,
        node.signature.effectSpecifiers?.throwsClause?.throwsSpecifier.tokenKind == .keyword(.throws),
        node.signature.effectSpecifiers?.throwsClause?.type == nil,
        node.signature.effectSpecifiers?.asyncSpecifier == nil,
        node.signature.parameterClause.parameters.count == 1,
        let parameter = node.signature.parameterClause.parameters.first,
        parameter.firstName.text == "to", parameter.secondName != nil,
        ["Encoder", "any Encoder"].contains(parameter.type.trimmedDescription),
        let body = node.body
      else { return .visitChildren }
      let start = bytes.lineStart(node.startOffset)
      var end = body.endOffset
      if end < bytes.bytes.count && bytes.bytes[end] == 0x0A { end += 1 }
      edits.append(.remove(start, end))
      return .skipChildren
    }
  }

  // MARK: Generation

  struct Generated {
    var text: String
    var count: Int
  }

  /// Whether the file already reaches the framework through an import the generated code can use.
  static func importsFramework(_ tree: SourceFileSyntax, aliased: Bool) -> Bool {
    let modules: Set<String> = aliased ? ["SwiftUIWeb", "WebFoundation", "SwiftUI", "Foundation"] : ["SwiftUIWeb"]
    let imports = tree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) } + importsInsideConditionals(tree)
    return imports.contains { declaration in
      guard declaration.modifiers.isEmpty, declaration.path.count == 1, let module = declaration.path.first,
        modules.contains(module.name.text)
      else { return false }
      switch declaration.attributes.count {
      case 0:
        return true
      case 1:
        if let attribute = declaration.attributes.first?.as(AttributeSyntax.self), attribute.attributeName.trimmedDescription == "_spi",
          case .argumentList(let arguments)? = attribute.arguments, arguments.count == 1
        {
          return true
        }
        return false
      default:
        return false
      }
    }
  }

  static func generate(_ text: String) throws -> Generated {
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let index = ScopeIndex(tree)
    let refining = refiningProtocols(in: tree)

    var extensions: [String] = []
    var implicitKeys: [String] = []
    var count = 0
    let privateTypeNames = privateTypes(in: tree)
    let mentionsCodingKeys = tokensMention(tree, "CodingKeys")

    for scope in index.scopes {
      guard let declaration = CodableDeclaration(scope: scope, refining: refining) else { continue }
      let before = extensions.count
      let path = scope.path
      let qualifiedName = path.joined(separator: ".")
      let visible = nestedTypeNames(scopes: index.scopes, path: path)
      let qualify = { (type: String) in qualifyTypeNames(type, visible) }
      let members = flattenedMembers(declaration.memberBlock.members)
      let declaredInit = declaresDecoderInit(members) || extensionDeclaresDecoderInit(tree, name: declaration.name)
      let hasCustomCodec = declaration.mentionsCustomCodec

      if hasCustomCodec {
        // A hand-written EmbeddedCodable implementation is the explicit wire-format contract for values such as
        // JSONValue. Do not synthesize Swift-enum tagging around an untagged JSON payload.
        count += 1
      } else if declaration.kind == .enumeration, let raw = declaration.rawType {
        extensions.append(CodableTemplates.rawEnum(qualifiedName, raw: raw))
        count += 1
      } else if declaration.kind == .enumeration {
        extensions.append(associatedEnumExtension(qualifiedName, members: members, qualify: qualify))
        count += 1
      } else {
        let fields = codingKeys(declaration.directMembers, fields: codableFields(members)).map {
          CodableField(name: $0.name, type: qualify($0.type), key: $0.key)
        }
        // Stored properties whose type is inferred from their initializer are encoded too (a decoder cannot name
        // their type, so they keep the declared default there).
        let inferred = storedPropertyNames(members, bytes: bytes)
          .filter { name in !fields.contains { $0.name == name } }
          .map { (name: $0, type: "") }
        let encodedFields = fields + codingKeys(declaration.directMembers, fields: inferred)
        let pairs = encodedFields.map { "\"\($0.key)\": try self.\($0.name)._embeddedJSONValue()" }.joined(separator: ", ")
        let object = pairs.isEmpty ? "[:]" : "[\(pairs)]"
        let orderedFields: [CodableField]
        if let labels = explicitInitLabels(members, fields: fields) {
          orderedFields = labels.compactMap { label in fields.first { $0.name == label } }
        } else {
          orderedFields = fields
        }
        let arguments = orderedFields.map {
          "\($0.name): try _embeddedField(\(CodableTemplates.spellType($0.type)).self, object, \"\($0.key)\")"
        }.joined(separator: ", ")
        let guardClause = fields.isEmpty ? "guard case .object = value" : "guard case .object(let object) = value"
        // `try Parent(from: decoder)` composes a synthesized decoder into a hand-written one, so every synthesized
        // struct also gets the initializer; unused ones are dead-stripped.
        let decoderInit = declaration.kind == .structure ? CodableTemplates.decoderInit : ""
        let storedNames = storedPropertyNames(members, bytes: bytes)
        if declaredInit && !declaration.containsCodingKeysEnum && mentionsCodingKeys && !storedNames.isEmpty {
          // The compiler-synthesized `CodingKeys` of a Codable type does not exist in Embedded Swift.
          implicitKeys.append(CodableTemplates.implicitCodingKeys(qualifiedName, cases: storedNames.joined(separator: ", ")))
        }
        if declaration.kind == .structure && declaresExplicitInit(members, bytes: bytes) && !fields.isEmpty {
          // A written initializer replaces the memberwise one, so the decoder assigns the fields itself.
          let assignments = fields.map {
            "    self.\($0.name) = try _embeddedField(\(CodableTemplates.spellType($0.type)).self, object, \"\($0.key)\")\n"
          }.joined()
          extensions.append(CodableTemplates.structureWithWrittenInit(
            qualifiedName, object: object, guardClause: guardClause, assignments: assignments, decoderInit: decoderInit))
        } else {
          extensions.append(CodableTemplates.structure(
            qualifiedName, object: object, guardClause: guardClause, arguments: arguments, decoderInit: decoderInit))
        }
        count += 1
      }

      let hidden = declaration.modifiers.contains(.private) || declaration.modifiers.contains(.fileprivate)
      let exposesPublicly = !(hidden || path.dropLast().contains(where: privateTypeNames.contains))
      for position in before..<extensions.count {
        if declaredInit && !hasCustomCodec {
          extensions[position] = CodableTemplates.useDeclaredDecoderInit(extensions[position])
        }
        extensions[position] = CodableTemplates.keepRequestedHalves(
          extensions[position], encode: declaration.wantsEncode, decode: declaration.wantsDecode)
        if !exposesPublicly {
          // Members of a type that is not public cannot be public themselves once `Self` is in their signature.
          extensions[position] = makingDeclarationsFileprivate(extensions[position])
        }
      }
    }

    let keyExtensions = codingKeyExtensions(tree, index: index)
    extensions.append(contentsOf: keyExtensions)
    extensions.append(contentsOf: implicitKeys)

    var output = try apply(embeddedProtocolNameEdits(tree), to: text)
    if !extensions.isEmpty {
      output.append("\n")
      output.append(extensions.joined())
    }
    return Generated(text: output, count: count)
  }

  // MARK: Declarations

  struct CodableDeclaration {
    enum Kind { case structure, `class`, enumeration }
    let kind: Kind
    let name: String
    let memberBlock: MemberBlockSyntax
    let modifiers: DeclModifierListSyntax
    let inheritance: InheritanceClauseSyntax
    let node: Syntax
    let wantsEncode: Bool
    let wantsDecode: Bool

    init?(scope: TypeScope, refining: [(name: String, encodes: Bool, decodes: Bool)]) {
      let kind: Kind
      let name: String
      let memberBlock: MemberBlockSyntax
      let modifiers: DeclModifierListSyntax
      let inheritance: InheritanceClauseSyntax?
      if let node = scope.node.as(StructDeclSyntax.self) {
        (kind, name, memberBlock, modifiers, inheritance) = (.structure, node.name.text, node.memberBlock, node.modifiers, node.inheritanceClause)
      } else if let node = scope.node.as(ClassDeclSyntax.self) {
        (kind, name, memberBlock, modifiers, inheritance) = (.class, node.name.text, node.memberBlock, node.modifiers, node.inheritanceClause)
      } else if let node = scope.node.as(EnumDeclSyntax.self) {
        (kind, name, memberBlock, modifiers, inheritance) = (.enumeration, node.name.text, node.memberBlock, node.modifiers, node.inheritanceClause)
      } else {
        return nil
      }
      guard let inheritance else { return nil }
      let names = inheritedNames(inheritance)
      let encodes = names.contains("Codable") || names.contains("Encodable")
        || refining.contains { $0.encodes && names.contains($0.name) }
      let decodes = names.contains("Codable") || names.contains("Decodable")
        || refining.contains { $0.decodes && names.contains($0.name) }
      guard encodes || decodes else { return nil }
      self.kind = kind
      self.name = name
      self.memberBlock = memberBlock
      self.modifiers = modifiers
      self.inheritance = inheritance
      self.node = scope.node
      self.wantsEncode = encodes
      self.wantsDecode = decodes
    }

    var directMembers: [DeclSyntax] { flattenedMembers(memberBlock.members) }

    /// `String` or `Int` when the enum has a raw type, which the generated coding reads through `rawValue`.
    var rawType: String? {
      let names = inheritance.inheritedTypes.map { $0.type.trimmedDescription }
      if names.contains("String") { return "String" }
      if names.contains("Int") { return "Int" }
      return nil
    }

    /// The declaration spells both halves of the wire format itself.
    var mentionsCustomCodec: Bool {
      var joined = ""
      for token in node.tokens(viewMode: .sourceAccurate) { joined += token.text }
      return joined.contains("_embeddedJSONValue()") && joined.contains("_embeddedDecodeJSONValue(")
    }

    /// Whether an `enum CodingKeys` is declared anywhere in the body.
    var containsCodingKeysEnum: Bool {
      let finder = NamedEnumFinder(name: "CodingKeys")
      finder.walk(memberBlock)
      return finder.found
    }
  }

  private final class NamedEnumFinder: SyntaxVisitor {
    let name: String
    var found = false
    init(name: String) {
      self.name = name
      super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
      if node.name.text == name { found = true }
      return .visitChildren
    }
  }

  /// Protocols declared in the file that refine Codable/Encodable/Decodable.
  private static func refiningProtocols(in tree: SourceFileSyntax) -> [(name: String, encodes: Bool, decodes: Bool)] {
    final class Finder: SyntaxVisitor {
      var found: [(name: String, encodes: Bool, decodes: Bool)] = []
      init() { super.init(viewMode: .sourceAccurate) }
      override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let names = inheritedNames(node.inheritanceClause)
        let encodes = names.contains("Codable") || names.contains("Encodable")
        let decodes = names.contains("Codable") || names.contains("Decodable")
        if encodes || decodes { found.append((node.name.text, encodes, decodes)) }
        return .visitChildren
      }
    }
    let finder = Finder()
    finder.walk(tree)
    return finder.found
  }

  private static func importsInsideConditionals(_ tree: SourceFileSyntax) -> [ImportDeclSyntax] {
    final class Finder: SyntaxVisitor {
      var found: [ImportDeclSyntax] = []
      init() { super.init(viewMode: .sourceAccurate) }
      override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        found.append(node)
        return .skipChildren
      }
    }
    let finder = Finder()
    // Top-level imports are listed by the caller; the walk adds the ones inside `#if` blocks.
    for statement in tree.statements {
      if let conditional = statement.item.as(IfConfigDeclSyntax.self) { finder.walk(conditional) }
    }
    return finder.found
  }

  /// Names of the types declared `private` or `fileprivate`, wherever they are in the file.
  private static func privateTypes(in tree: SourceFileSyntax) -> Set<String> {
    final class Finder: SyntaxVisitor {
      var names: Set<String> = []
      init() { super.init(viewMode: .sourceAccurate) }
      private func record(_ name: TokenSyntax, _ modifiers: DeclModifierListSyntax) {
        if modifiers.contains(.private) || modifiers.contains(.fileprivate) { names.insert(name.text) }
      }
      override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name, node.modifiers); return .visitChildren }
      override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name, node.modifiers); return .visitChildren }
      override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name, node.modifiers); return .visitChildren }
      override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name, node.modifiers); return .visitChildren }
    }
    let finder = Finder()
    finder.walk(tree)
    return finder.names
  }

  /// Whether any token (not a comment) of the file mentions `word`.
  private static func tokensMention(_ tree: SourceFileSyntax, _ word: String) -> Bool {
    tree.tokens(viewMode: .sourceAccurate).contains { $0.text.contains(word) }
  }

  // MARK: Names

  /// Names a type expression may use unqualified from inside `path`: every type declared directly in `path` or in one
  /// of its ancestors. A generated extension sits at file scope, where those nested names are not visible, so they
  /// are written out in full.
  static func nestedTypeNames(scopes: [TypeScope], path: [String]) -> [String: String] {
    var names: [String: String] = [:]
    for depth in 1...max(path.count, 1) where depth <= path.count {
      for scope in scopes where scope.path.count == depth + 1 && Array(scope.path[..<depth]) == Array(path[..<depth]) {
        names[scope.path[depth]] = scope.path.joined(separator: ".")
      }
    }
    return names
  }

  static func qualifyTypeNames(_ type: String, _ names: [String: String]) -> String {
    if names.isEmpty { return type }
    let scalars = Array(type.unicodeScalars)
    var output = String.UnicodeScalarView()
    var index = 0
    func isWord(_ scalar: Unicode.Scalar) -> Bool {
      scalar == "_" || (scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)))
    }
    while index < scalars.count {
      let scalar = scalars[index]
      let startsIdentifier = scalar == "_" || (scalar.isASCII && scalar.properties.isAlphabetic)
      if startsIdentifier {
        var end = index
        while end < scalars.count && isWord(scalars[end]) { end += 1 }
        let identifier = String(String.UnicodeScalarView(scalars[index..<end]))
        let previous = index == 0 ? nil : scalars[index - 1]
        let qualified = previous.map { $0 != "." && !isWord($0) } ?? true
        output.append(contentsOf: (qualified ? (names[identifier] ?? identifier) : identifier).unicodeScalars)
        index = end
      } else {
        output.append(scalar)
        index += 1
      }
    }
    return String(output)
  }

  /// `Codable`/`Decodable`/`Encodable` become the matching Embedded protocol, and the decoder family (`Decoder`,
  /// `CodingKey`, the decoding containers, `DecodingError`) its `Embedded*` shim from `EmbeddedDecoder.swift`;
  /// `any Decoder` becomes `EmbeddedDecoder`. Nothing else in the text changes.
  static func embeddedProtocolNameEdits(_ tree: SourceFileSyntax) -> [TextEdit] {
    let renamed: Set<String> = [
      "Codable", "Decodable", "Encodable", "Decoder", "CodingKey", "KeyedDecodingContainer",
      "SingleValueDecodingContainer", "DecodingError",
    ]
    var edits: [TextEdit] = []
    for token in tree.tokens(viewMode: .sourceAccurate) where token.tokenKind != .endOfFile {
      guard case .identifier = token.tokenKind, renamed.contains(token.text) else { continue }
      var start = token.startOffset
      if let previous = token.previousToken(viewMode: .sourceAccurate), previous.tokenKind == .keyword(.any),
        isWhitespaceOnly(previous.trailingTrivia), isWhitespaceOnly(token.leadingTrivia),
        !previous.trailingTrivia.isEmpty || !token.leadingTrivia.isEmpty
      {
        start = previous.startOffset
      }
      edits.append(TextEdit(start: start, end: token.endOffset, replacement: "Embedded" + token.text))
    }
    return edits
  }

  // MARK: Enums

  /// The coding of an enum with associated values: `{"case": {"label": value}}`.
  static func associatedEnumExtension(_ name: String, members: [DeclSyntax], qualify: (String) -> String) -> String {
    var encode: [String] = []
    var decode: [String] = []
    for member in members {
      guard let caseDecl = member.as(EnumCaseDeclSyntax.self) else { continue }
      for element in caseDecl.elements {
        // A backticked case name is coded by its plain name: `.default` needs no backticks after the dot.
        let caseName = element.name.text.replacingOccurrences(of: "`", with: "")
        guard !caseName.isEmpty, caseName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), caseName != "let", caseName != "var" else {
          continue
        }
        let payload: [(key: String, type: String)] = (element.parameterClause?.parameters ?? []).enumerated().map { position, parameter in
          let type = qualify(parameter.type.trimmedDescription.replacingOccurrences(of: "`", with: ""))
          if let label = parameter.firstName, parameter.colon != nil {
            return (label.text.replacingOccurrences(of: "`", with: ""), type)
          }
          return ("_\(position)", type)
        }
        if payload.isEmpty {
          encode.append("case .\(caseName): return .object([\"\(caseName)\": .object([:])])")
          decode.append("case \"\(caseName)\": return .\(caseName)")
        } else {
          let patterns = payload.indices.map { "let v\($0)" }.joined(separator: ", ")
          let pairs = payload.enumerated().map { "\"\($0.element.key)\": try v\($0.offset)._embeddedJSONValue()" }.joined(separator: ", ")
          // A labeled payload (`case edit(status: Status)`) is constructed with its labels.
          let arguments = payload.map { entry in
            let positional = entry.key.hasPrefix("_") && entry.key.count > 1 && entry.key.dropFirst().allSatisfy(\.isASCIIDigit)
            let label = positional ? "" : "\(entry.key): "
            return "\(label)try \(CodableTemplates.spellType(entry.type))._embeddedDecodeJSONValue(EmbeddedJSONValue.required(payload, \"\(entry.key)\"))"
          }.joined(separator: ", ")
          encode.append("case .\(caseName)(\(patterns)): return .object([\"\(caseName)\": .object([\(pairs)])])")
          decode.append("case \"\(caseName)\": guard case .object(let payload)=payloadValue else { throw EmbeddedCodableError.typeMismatch }; return .\(caseName)(\(arguments))")
        }
      }
    }
    return CodableTemplates.associatedEnum(name, encode: encode, decode: decode)
  }

  /// `enum CodingKeys: CodingKey { case a, b }` has no raw value, so the compiler-synthesized `stringValue` is the
  /// case name; spell it out.
  static func codingKeyExtensions(_ tree: SourceFileSyntax, index: ScopeIndex) -> [String] {
    var extensions: [String] = []
    for scope in index.scopes {
      guard let node = scope.node.as(EnumDeclSyntax.self), let clause = node.inheritanceClause else { continue }
      let conformances = clause.inheritedTypes.map { $0.type.trimmedDescription }
      guard conformances.contains("CodingKey"), !conformances.contains("String"), !conformances.contains("Int") else { continue }
      let names = flattenedMembers(node.memberBlock.members).flatMap { member -> [String] in
        guard let caseDecl = member.as(EnumCaseDeclSyntax.self) else { return [] }
        return caseDecl.elements.map { $0.name.text }
      }
      let value = names.map { "case .\($0): return \"\($0)\"" }.joined(separator: "; ")
      let parse = names.map { "case \"\($0)\": self = .\($0)" }.joined(separator: "; ")
      extensions.append(CodableTemplates.codingKeyConformance(scope.path.joined(separator: "."), value: value, parse: parse))
    }
    return extensions
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

/// The generated members of a type that is not public, with each declaration made fileprivate: a line whose first word is
/// `public`. A `public ` inside a string literal (a coding key's raw value) is not a modifier and stays as it is.
private func makingDeclarationsFileprivate(_ text: String) -> String {
  text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
    let indent = line.prefix { $0 == " " }
    let rest = line.dropFirst(indent.count)
    guard rest.hasPrefix("public ") else { return String(line) }
    return String(indent) + "fileprivate " + String(rest.dropFirst("public ".count))
  }.joined(separator: "\n")
}

/// The generated extensions import the framework's serialization types: an application that has not imported the
/// framework yet gets the import. An aliased application spells the module `SwiftUI`. The previous lowerer decides this
/// after the rewrites that follow the Codable pass (`as Data` adds an import of its own), so it is a pass of its own
/// that runs after them; it acts only on a file the Codable pass rewrote and shares its name, `embedded-codable`.
public struct EmbeddedCodableImportTransform: SourceTransform {
  public let name = "embedded-codable"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { options.lowerCodable }

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard counts["codable-to-embedded", default: 0] > 0 else { return text }
    guard !EmbeddedCodableTransform.importsFramework(Parser.parse(source: text), aliased: options.moduleAliases) else { return text }
    counts.add("embedded-codable-import", 1)
    return "import \(options.moduleAliases ? "SwiftUI" : "SwiftUIWeb")\n" + text
  }
}
