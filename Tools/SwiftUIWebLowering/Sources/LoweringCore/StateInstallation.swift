import SwiftParser
import SwiftSyntax

/// Gives each view that keeps `@State` or `@StateObject` an installation of it (`View._installState`): the runtime calls
/// it before it forms the view's body, so every property takes the storage of the view's identity first, as SwiftUI
/// installs a view's state before it evaluates the body. Without it a property was adopted when something first read it
/// in a render, so an action that ran before (`onAppear`) read the initial value of one value of the view while the body
/// later adopted the one of another, and a property the body reads only in a later render (behind a condition) took the
/// initial value of the view value of that render. Embedded Swift has no reflection, which the runtime uses elsewhere.
///
/// `extension Player { func _installState() { _engine._install(); _model._install() } }`, the properties in the order
/// they are declared, follows the declaration at file scope that holds the view, as `view-inputs` places its extension.
/// A view nested in a private type, one in another `#if` branch than that declaration, a property inside an `#if` and a
/// `static` one are left alone (the runtime then adopts them when they are first read). So is a view that declares
/// `_installState()` itself, in its body or in an extension.
///
/// Applies to every source, application or framework. Runs after `observable-state`, which turns the `@State` of a model
/// into `@StateObject`.
public struct StateInstallationTransform: SourceTransform {
  public let name = "state-installation"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  private static let installedWrappers: Set<String> = ["State", "StateObject"]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("View"), text.contains("@State") else { return text }
    let tree = Parser.parse(source: text)
    let bytes = SourceBytes(text)
    let index = ScopeIndex(tree)
    // Lowering its own output changes nothing: a view whose installation is in the file already keeps it. It is read from
    // the declarations and not from the text this pass writes, because the passes that run after it write into that text:
    // `export-interface` marks the function and `stable-source-locations` puts a directive above it.
    let installed = ViewDeclarations.typesExtended(withMethod: "_installState", in: index)

    var insertions: [(offset: Int, text: String)] = []
    for scope in index.scopes {
      guard let view = scope.node.as(StructDeclSyntax.self), ViewDeclarations.isView(view) else { continue }
      let path = scope.path
      if path.count > 1 && (view.modifiers.contains(.private) || view.modifiers.contains(.fileprivate)) { continue }
      let names = installedNames(of: view)
      if names.isEmpty { continue }
      // The member witnesses a `View` requirement, so a public (or package) view needs it as visible as itself.
      let access = view.modifiers.lazy.compactMap { modifier -> String? in
        switch modifier.name.tokenKind {
        case .keyword(.public): "public "
        case .keyword(.package): "package "
        default: nil
        }
      }.first ?? ""
      let qualified = path.joined(separator: ".")
      // In an extension, or in the view's own body: either way a second one would be a second declaration.
      if installed.contains(qualified) || ViewDeclarations.declares("_installState", in: view.memberBlock) { continue }
      guard let outer = ViewDeclarations.outermostScope(of: scope, in: index), outer.path.count == 1 else { continue }
      if ViewDeclarations.conditionalBranches(of: scope.node) != ViewDeclarations.conditionalBranches(of: outer.node) { continue }
      let calls = names.map { "_\($0)._install()" }.joined(separator: "; ")
      let insertion = bytes.lineEnd(outer.end) < bytes.bytes.count ? bytes.lineEnd(outer.end) + 1 : bytes.bytes.count
      insertions.append((insertion, "\nextension \(qualified) {\n  \(access)func _installState() { \(calls) }\n}\n"))
    }
    guard !insertions.isEmpty else { return text }
    counts.add("state-installation", insertions.count)
    var edits = insertions.map { TextEdit.insert($0.text, at: $0.offset) }
    var output = text
    if output.utf8.last != 0x0A {
      // The newline is part of the text the insertions sit after.
      output.append("\n")
      edits = edits.map { TextEdit(start: min($0.start, output.utf8.count), end: min($0.end, output.utf8.count), replacement: $0.replacement) }
    }
    return try apply(edits, to: output)
  }

  /// The view's `@State` and `@StateObject` properties declared directly in its body, in order.
  private func installedNames(of view: StructDeclSyntax) -> [String] {
    var names: [String] = []
    for item in view.memberBlock.members {
      guard let variable = item.decl.as(VariableDeclSyntax.self),
        variable.bindingSpecifier.tokenKind == .keyword(.var),
        !variable.modifiers.contains(.static), !variable.modifiers.contains(.class),
        variable.bindings.count == 1,
        let identifier = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)
      else { continue }
      let installed = variable.attributes.names.contains { attribute in
        let name = attribute.split(separator: ".").last.map(String.init) ?? attribute
        return Self.installedWrappers.contains(name)
      }
      if installed { names.append(identifier.identifier.text.trimmingCharacters(in: "`")) }
    }
    return names
  }
}

extension String {
  fileprivate func trimmingCharacters(in character: Character) -> String {
    var text = Substring(self)
    while text.first == character { text.removeFirst() }
    while text.last == character { text.removeLast() }
    return String(text)
  }
}
