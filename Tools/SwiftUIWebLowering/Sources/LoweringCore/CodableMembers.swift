import SwiftSyntax

/// What the Embedded Codable generator reads out of a type's members. The previous lowerer recovers the same facts from
/// text lines at brace depth zero; here they come from the syntax tree.

struct CodableField {
  var name: String
  var type: String
  var key: String
}

private let accessKeywords: Set<Keyword> = [.public, .internal, .private, .fileprivate, .package]

/// A property that holds a value (a computed one has a getter, observers alone do not make it computed).
private func isStoredBinding(_ binding: PatternBindingSyntax) -> Bool {
  guard let block = binding.accessorBlock else { return true }
  switch block.accessors {
  case .getter:
    return false
  case .accessors(let accessors):
    return accessors.allSatisfy { accessor in
      accessor.accessorSpecifier.tokenKind == .keyword(.willSet) || accessor.accessorSpecifier.tokenKind == .keyword(.didSet)
    }
  }
}

private func plainName(_ token: TokenSyntax) -> String? {
  let text = token.text
  return text.hasPrefix("`") ? nil : text
}

/// `let name: Type [= value]` with at most one access modifier and no attributes: the stored properties a Codable
/// struct encodes with a spelled-out type (previously `top_level_fields`).
func codableFields(_ members: [DeclSyntax]) -> [(name: String, type: String)] {
  var fields: [(name: String, type: String)] = []
  for member in members {
    guard let variable = member.as(VariableDeclSyntax.self),
      variable.attributes.isEmpty,
      variable.modifiers.count <= 1,
      variable.bindings.count == 1,
      let binding = variable.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
      let name = plainName(identifier.identifier),
      let annotation = binding.typeAnnotation,
      isStoredBinding(binding)
    else { continue }
    if let modifier = variable.modifiers.first {
      guard modifier.detail == nil, case .keyword(let keyword) = modifier.name.tokenKind, accessKeywords.subtracting([.package]).contains(keyword) else {
        continue
      }
    }
    let type = annotation.type.trimmedDescription
    if type.contains("->") { continue }
    fields.append((name, type))
  }
  return fields
}

/// Names of the stored properties declared directly in a body, including those whose type is inferred (previously:
/// `stored_property_names`). A declaration whose first line holds a brace is computed or closure-initialized and is
/// not listed.
func storedPropertyNames(_ members: [DeclSyntax], bytes: SourceBytes) -> [String] {
  var names: [String] = []
  for member in members {
    guard let variable = member.as(VariableDeclSyntax.self) else { continue }
    var sawLazy = false
    var qualifies = true
    for modifier in variable.modifiers {
      guard case .keyword(let keyword) = modifier.name.tokenKind else { qualifies = false; break }
      if keyword == .lazy {
        sawLazy = true
      } else if sawLazy || !accessKeywords.contains(keyword) {
        qualifies = false
        break
      }
    }
    guard qualifies,
      let binding = variable.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
      let name = plainName(identifier.identifier),
      binding.accessorBlock == nil
    else { continue }
    let start = variable.startOffset
    let line = bytes.slice(bytes.lineStart(start), bytes.lineEnd(start))
    if line.contains("{") { continue }
    names.append(name)
  }
  return names
}

/// The `CodingKeys` of a declaration filtered over `fields`: a field the enum does not list is not coded. Without
/// the enum every field is coded under its own name (previously `coding_keys`).
func codingKeys(_ members: [DeclSyntax], fields: [(name: String, type: String)]) -> [CodableField] {
  guard let keys = members.lazy.compactMap({ $0.as(EnumDeclSyntax.self) }).first(where: {
    $0.name.text == "CodingKeys" && $0.inheritanceClause != nil
  }) else {
    return fields.map { CodableField(name: $0.name, type: $0.type, key: $0.name) }
  }
  var mapping: [String: String] = [:]
  for member in flattenedMembers(keys.memberBlock.members) {
    guard let caseDecl = member.as(EnumCaseDeclSyntax.self) else { continue }
    for element in caseDecl.elements {
      guard let caseName = plainName(element.name) else { continue }
      if let raw = element.rawValue {
        guard let literal = raw.value.as(StringLiteralExprSyntax.self),
          literal.segments.count == 1,
          let segment = literal.segments.first?.as(StringSegmentSyntax.self),
          !segment.content.text.isEmpty
        else { continue }
        // A raw string's text is its value, but the key is written into a normal string literal: escape it there. A normal
        // literal's text is already in source form.
        let text = segment.content.text
        mapping[caseName] = literal.openingPounds == nil ? text : text.replacingOccurrences(of: "\\", with: "\\\\")
          .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
      } else {
        mapping[caseName] = caseName
      }
    }
  }
  return fields.compactMap { field in
    mapping[field.name].map { CodableField(name: field.name, type: field.type, key: $0) }
  }
}

/// Whether the declaration spells `init(from decoder: Decoder)` itself.
func declaresDecoderInit(_ members: [DeclSyntax]) -> Bool {
  members.contains { member in
    guard let initializer = member.as(InitializerDeclSyntax.self),
      initializer.optionalMark == nil,
      initializer.signature.parameterClause.parameters.count == 1,
      let parameter = initializer.signature.parameterClause.parameters.first,
      parameter.firstName.text == "from",
      parameter.secondName != nil
    else { return false }
    return ["Decoder", "any Decoder", "EmbeddedDecoder", "any EmbeddedDecoder"].contains(parameter.type.trimmedDescription)
  }
}

/// The argument labels of the declaration's own designated `init(...)`, in order, when they name exactly its coded
/// fields: a class has no memberwise initializer, so the generated decoder must call the written one.
func explicitInitLabels(_ members: [DeclSyntax], fields: [CodableField]) -> [String]? {
  for member in members {
    guard let initializer = member.as(InitializerDeclSyntax.self),
      initializer.optionalMark == nil,
      initializer.genericParameterClause == nil,
      initializer.attributes.isEmpty,
      initializer.modifiers.count <= 1
    else { continue }
    if let modifier = initializer.modifiers.first {
      guard modifier.detail == nil, modifier.name.tokenKind == .keyword(.public) || modifier.name.tokenKind == .keyword(.internal) else { continue }
    }
    let labels = initializer.signature.parameterClause.parameters.map { parameter in
      parameter.secondName.map { "\(parameter.firstName.text) \($0.text)" } ?? parameter.firstName.text
    }
    if labels.first == "from" { continue }
    if labels.allSatisfy({ label in fields.contains { $0.name == label } }) && fields.allSatisfy({ field in labels.contains(field.name) }) {
      return labels
    }
  }
  return nil
}

/// Whether the declaration writes a designated `init(...)` other than the decoder one, which suppresses the
/// memberwise initializer the generated decoder would otherwise call.
func declaresExplicitInit(_ members: [DeclSyntax], bytes: SourceBytes) -> Bool {
  members.contains { member in
    guard let initializer = member.as(InitializerDeclSyntax.self),
      initializer.optionalMark == nil,
      initializer.genericParameterClause == nil,
      initializer.attributes.isEmpty,
      initializer.modifiers.count <= 1
    else { return false }
    if let modifier = initializer.modifiers.first {
      guard modifier.detail == nil, case .keyword(let keyword) = modifier.name.tokenKind, accessKeywords.subtracting([.package]).contains(keyword) else {
        return false
      }
    }
    let start = initializer.startOffset
    return !bytes.slice(bytes.lineStart(start), bytes.lineEnd(start)).contains("from ")
  }
}

/// Whether an `extension Name { init(from decoder: Decoder) ... }` in the file supplies the decoder.
func extensionDeclaresDecoderInit(_ tree: SourceFileSyntax, name: String) -> Bool {
  final class Finder: SyntaxVisitor {
    let name: String
    var found = false
    init(name: String) {
      self.name = name
      super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
      guard let identifier = node.extendedType.as(IdentifierTypeSyntax.self), identifier.name.text == name,
        identifier.genericArgumentClause == nil, node.genericWhereClause == nil
      else { return .visitChildren }
      if declaresDecoderInit(flattenedMembers(node.memberBlock.members)) { found = true }
      return .visitChildren
    }
  }
  let finder = Finder(name: name)
  finder.walk(tree)
  return finder.found
}
