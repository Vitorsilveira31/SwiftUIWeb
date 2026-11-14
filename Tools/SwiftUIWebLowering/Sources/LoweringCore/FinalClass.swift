import SwiftParser
import SwiftSyntax

/// Embedded Swift rejects a generic method in a class that could be subclassed ("classes cannot have a non-final,
/// generic method"). Marking such a class `final` makes it legal and changes nothing when nothing subclasses it, which
/// is checked within the file; a class that is subclassed is left alone and reports the compiler's own error.
///
/// Origin (the previous, text-based lowerer): `finalize_classes_with_generic_methods`. Rule: `final-class-generic-method`.
public struct FinalClassTransform: SourceTransform {
  public let name = "final-class-generic-method"

  public init() {}

  public func applies(to options: LoweringOptions) -> Bool { true }

  /// Modifiers the previous lowerer's method pattern accepts before `func`. A method with another one (`final`, `class`,
  /// `open`, `convenience`) is not read as a generic method: `final` and `class` methods are fine in a final class or
  /// are not what the compiler objects to.
  private static let acceptedMethodModifiers: Set<Keyword> = [
    .public, .internal, .private, .fileprivate, .package, .static, .nonisolated, .mutating, .override,
  ]

  /// Access modifiers the previous lowerer's class pattern accepts before `class`. A `private`, `open` or `final` class is
  /// not a candidate.
  private static let acceptedClassModifiers: Set<Keyword> = [.public, .internal, .package]

  public func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String {
    guard text.contains("class"), text.contains("func"), text.contains("<") else { return text }
    let tree = Parser.parse(source: text)
    let classes = ClassCollector.collect(tree)
    var edits: [TextEdit] = []
    for declaration in classes {
      guard isCandidate(declaration), hasGenericMethod(declaration) else { continue }
      let name = declaration.name.text
      let subclassed = classes.contains { other in
        other.id != declaration.id && other.inheritanceClause?.tokens(viewMode: .sourceAccurate).contains { $0.text == name } == true
      }
      if subclassed { continue }
      edits.append(.insert("final ", at: declaration.classKeyword.startOffset))
    }
    counts.add("final-class-generic-method", edits.count)
    return try apply(edits, to: text)
  }

  /// A class with a closed body and at most an access modifier before `class`.
  private func isCandidate(_ declaration: ClassDeclSyntax) -> Bool {
    guard declaration.memberBlock.rightBrace.presence == .present, declaration.memberBlock.leftBrace.presence == .present else { return false }
    guard declaration.modifiers.count <= 1,
      declaration.modifiers.allSatisfy({ modifier in
        if case .keyword(let keyword) = modifier.name.tokenKind { return modifier.detail == nil && Self.acceptedClassModifiers.contains(keyword) }
        return false
      })
    else { return false }
    return true
  }

  /// Whether a method generic over a type is declared anywhere in the class body, nested types included.
  private func hasGenericMethod(_ declaration: ClassDeclSyntax) -> Bool {
    let finder = GenericMethodFinder(accepted: Self.acceptedMethodModifiers)
    finder.walk(declaration.memberBlock)
    return finder.found
  }
}

private final class ClassCollector: SyntaxVisitor {
  private(set) var classes: [ClassDeclSyntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  static func collect(_ tree: SourceFileSyntax) -> [ClassDeclSyntax] {
    let collector = ClassCollector()
    collector.walk(tree)
    return collector.classes
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    classes.append(node)
    return .visitChildren
  }
}

private final class GenericMethodFinder: SyntaxVisitor {
  let accepted: Set<Keyword>
  private(set) var found = false

  init(accepted: Set<Keyword>) {
    self.accepted = accepted
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    if !found, node.genericParameterClause != nil,
      node.modifiers.allSatisfy({ modifier in
        if case .keyword(let keyword) = modifier.name.tokenKind { return modifier.detail == nil && accepted.contains(keyword) }
        return false
      })
    {
      found = true
    }
    return found ? .skipChildren : .visitChildren
  }
}
