import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
import SwiftUIWeb

/// A modifier of the framework erases what it modifies when the modified view is formed (`_ModifiedView`), so every
/// modified view has one type. What the type of a `ModifiedContent` tells the runtime, the value of a `_ModifiedView`
/// tells it (`View._swiftUIWebTypeTag`): these tests hold that a modified view is named, kept and replaced as the
/// result of `modifier(_:)` is for the same chain, also where a renderer has only the type of what it renders.
@MainActor
struct ModifiedViewIdentityTests {
  private struct Marked: ViewModifier {}
  private struct Flagged: ViewModifier {}

  private struct Badge: View {
    var body: some View { Text("badge") }
  }

  /// Every fiber of the tree a view renders: its depth, and the descriptor of its node.
  private func descriptors<V: View>(_ view: V) -> [String] {
    let tree = FiberTree(view, deferLazyCollections: true, startLifecycle: false)
    defer { tree._dispose() }
    _ = tree.renderNode
    var found: [String] = []
    func walk(_ fiber: Fiber, depth: Int) {
      found.append("\(depth) \(fiber.renderNode.descriptor ?? "-")")
      fiber.children.forEach { walk($0, depth: depth + 1) }
    }
    walk(tree.root, depth: 0)
    return found
  }

  @Test func `A modifier of the framework forms one type whatever it modifies`() {
    // A modifier of each module that declares some, over a primitive, a container, a view with a body and a chain.
    #expect(Text("a").padding(4) is _ModifiedView)
    #expect(Color.red.frame(width: 10, height: 10) is _ModifiedView)
    #expect(VStack { Text("a") }.zIndex(1) is _ModifiedView)
    #expect(Badge().blur(radius: 1) is _ModifiedView)
    #expect(Badge().webHoverUnderline() is _ModifiedView)
    #expect(Text("a").padding(4).zIndex(1).opacity(0.5).accessibilityIdentifier("a") is _ModifiedView)
  }

  @Test func `The modifier an application applies itself keeps its declared type`() {
    // The annotation is the test: `modifier(_:)` declares `ModifiedContent<Self, Modifier>`, as SwiftUI's does.
    let modified: ModifiedContent<Text, Marked> = Text("a").modifier(Marked())
    // Its type spells the whole chain, so the type names it.
    #expect(!modified._swiftUIWebTypeTag.namesValue)
    #expect(modified._swiftUIWebTypeTag.text == _swiftUIWebTypeName(ModifiedContent<Text, Marked>.self))
  }

  @Test func `A modified view is named as the ModifiedContent of the same chain`() {
    // On a host with type names, as here. An Embedded build has identifiers: the two forms of a chain are then two
    // identifiers, each told from every other chain in the same way.
    #expect(descriptors(Text("a")._modified(Marked())) == descriptors(Text("a").modifier(Marked())))
    #expect(descriptors(Badge()._modified(Marked())._modified(Flagged())) == descriptors(Badge().modifier(Marked()).modifier(Flagged())))
    // The two forms in one chain, each way round.
    #expect(descriptors(Badge().modifier(Marked())._modified(Flagged())) == descriptors(Badge().modifier(Marked()).modifier(Flagged())))
    #expect(descriptors(Badge()._modified(Marked()).modifier(Flagged())) == descriptors(Badge().modifier(Marked()).modifier(Flagged())))
    // The name tells the modifiers and their order.
    let marked = _ViewTypeTag(_ViewTypeTag(Text.self), modifiedBy: Marked.self)
    #expect(marked.text == _swiftUIWebTypeName(ModifiedContent<Text, Marked>.self))
    #expect(_ViewTypeTag(marked, modifiedBy: Flagged.self).text == _swiftUIWebTypeName(ModifiedContent<ModifiedContent<Text, Marked>, Flagged>.self))
    #expect(_ViewTypeTag(marked, modifiedBy: Flagged.self).text != _ViewTypeTag(_ViewTypeTag(_ViewTypeTag(Text.self), modifiedBy: Flagged.self), modifiedBy: Marked.self).text)
  }

  @Test func `A view that renders a modified view in its own place names what that view modifies`() {
    // The type of each pair is the same: only the values tell what the modified view inside modifies.
    let overText = Text("a")._modified(Marked()).modifier(Flagged())
    let overBadge = Badge()._modified(Marked()).modifier(Flagged())
    #expect(type(of: overText) == type(of: overBadge))
    #expect(overText._swiftUIWebTypeTag.namesValue)
    #expect(overText._swiftUIWebTypeTag.text != overBadge._swiftUIWebTypeTag.text)
    #expect(overText._swiftUIWebTypeTag.text == Text("a")._modified(Marked())._modified(Flagged())._swiftUIWebTypeTag.text)

    let textBranch: _ConditionalContent<_ModifiedView, EmptyView> = .trueContent(Text("a")._modified(Marked()))
    let badgeBranch: _ConditionalContent<_ModifiedView, EmptyView> = .trueContent(Badge()._modified(Marked()))
    #expect(textBranch._swiftUIWebTypeTag.namesValue)
    #expect(textBranch._swiftUIWebTypeTag.text != badgeBranch._swiftUIWebTypeTag.text)
    // A branch whose type names it leaves the conditional named by its own type.
    let other: _ConditionalContent<_ModifiedView, EmptyView> = .falseContent(EmptyView())
    #expect(!other._swiftUIWebTypeTag.namesValue)
    #expect(other._swiftUIWebTypeTag.text == _swiftUIWebTypeName(_ConditionalContent<_ModifiedView, EmptyView>.self))
  }

  @Test func `A row that is a modified view is named by what it modifies`() {
    // The rows are the fibers below the `ForEach`, whose own type names it.
    func rows<Row: View>(@ViewBuilder _ row: @escaping () -> Row) -> [String] {
      descriptors(ForEach(0..<2, id: \.self) { _ in row() }).filter { $0.hasPrefix("1 ") }
    }
    let erased = rows { Badge()._modified(Marked()) }
    #expect(erased == Array(repeating: "1 " + _swiftUIWebTypeName(ModifiedContent<Badge, Marked>.self), count: 2))
    #expect(erased == rows { Badge().modifier(Marked()) })
    #expect(erased != rows { Text("a")._modified(Marked()) })
  }

  /// How often the content appeared and disappeared when the root of a tree became another view.
  private struct Lifecycle: Equatable {
    var appears: Int
    var disappears: Int
    static let kept = Lifecycle(appears: 1, disappears: 0)
    static let replaced = Lifecycle(appears: 2, disappears: 1)
  }

  private func lifecycle<First: View, Second: View>(
    from first: (_ appear: @escaping () -> Void, _ disappear: @escaping () -> Void) -> First,
    to second: (_ appear: @escaping () -> Void, _ disappear: @escaping () -> Void) -> Second
  ) -> Lifecycle {
    var appears = 0
    var disappears = 0
    let tree = FiberTree(first({ appears += 1 }, { disappears += 1 }))
    defer { tree._dispose() }
    _ = tree.renderNode
    _ = tree.update(second({ appears += 1 }, { disappears += 1 }))
    _ = tree.renderNode
    return Lifecycle(appears: appears, disappears: disappears)
  }

  @Test func `A modified view is kept while its chain is the same`() {
    let erased = lifecycle(
      from: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()) },
      to: { appear, disappear in Text("b").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()) })
    let typed = lifecycle(
      from: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear).modifier(Marked()) },
      to: { appear, disappear in Text("b").onAppear(perform: appear).onDisappear(perform: disappear).modifier(Marked()) })
    #expect(erased == .kept)
    #expect(typed == .kept)
  }

  @Test func `A modified view is replaced when a modifier of its chain is of another type`() {
    let erased = lifecycle(
      from: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()) },
      to: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Flagged()) })
    let typed = lifecycle(
      from: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear).modifier(Marked()) },
      to: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear).modifier(Flagged()) })
    #expect(erased == .replaced)
    #expect(typed == .replaced)
  }

  @Test func `A modified view is replaced when what it modifies is of another type`() {
    // The type of the two roots is the same in each pair: `_ModifiedView`, and `ModifiedContent<_ModifiedView, Marked>`.
    let erased = lifecycle(
      from: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()) },
      to: { appear, disappear in Badge().onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()) })
    let typed = lifecycle(
      from: { appear, disappear in Text("a").onAppear(perform: appear).onDisappear(perform: disappear).modifier(Marked()) },
      to: { appear, disappear in Badge().onAppear(perform: appear).onDisappear(perform: disappear).modifier(Marked()) })
    #expect(erased == .replaced)
    #expect(typed == .replaced)
  }

  @Test func `A conditional is replaced when the modified view in its branch modifies another type`() {
    // The type of the two roots is the same, and so is the branch taken: only what the modified view modifies differs.
    typealias Branch = _ConditionalContent<_ModifiedView, EmptyView>
    let another = lifecycle(
      from: { appear, disappear -> Branch in
        .trueContent(Text("a").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()))
      },
      to: { appear, disappear -> Branch in
        .trueContent(Badge().onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()))
      })
    #expect(another == .replaced)
    let same = lifecycle(
      from: { appear, disappear -> Branch in
        .trueContent(Text("a").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()))
      },
      to: { appear, disappear -> Branch in
        .trueContent(Text("b").onAppear(perform: appear).onDisappear(perform: disappear)._modified(Marked()))
      })
    #expect(same == .kept)
  }

  @Test func `The identifier of a modified view tells chains apart`() {
    // Identifiers of types are addresses: aligned, and far below the top bit.
    let contents = (0..<400).map { UInt64(0x0001_0000 + $0 * 8) }
    let modifiers = (0..<60).map { UInt64(0x0009_0000 + $0 * 8) }
    var seen = Set<UInt64>()
    var first: [UInt64] = []
    for content in contents {
      for modifier in modifiers {
        let id = _modifiedViewTypeID(content: content, modifier: modifier)
        #expect(id >> 63 == 1, "apart from the identifier of a type")
        #expect(seen.insert(id).inserted, "two chains of one modifier with one identifier")
        first.append(id)
      }
    }
    // A second and a third modifier over each of a sample of those chains.
    var chains = stride(from: 0, to: first.count, by: 37).map { first[$0] }
    for _ in 0..<2 {
      var next: [UInt64] = []
      for chain in chains {
        for modifier in modifiers.prefix(12) {
          let id = _modifiedViewTypeID(content: chain, modifier: modifier)
          #expect(seen.insert(id).inserted, "two chains with one identifier")
          next.append(id)
        }
      }
      chains = stride(from: 0, to: next.count, by: 11).map { next[$0] }
    }
    // The order of two modifiers is part of the chain.
    let a = modifiers[0], b = modifiers[1], content = contents[0]
    #expect(
      _modifiedViewTypeID(content: _modifiedViewTypeID(content: content, modifier: a), modifier: b)
        != _modifiedViewTypeID(content: _modifiedViewTypeID(content: content, modifier: b), modifier: a))
  }
}
