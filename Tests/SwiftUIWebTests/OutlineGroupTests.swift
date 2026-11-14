import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

private struct TestOutlineNode: Identifiable, Equatable {
  let id: Int
  var title: String
  var children: [TestOutlineNode]?
}

private struct TestOutlineValue {
  let key: String
  let title: String
  let children: [TestOutlineValue]?
}

private final class TestSliceOutlineNode: Identifiable {
  let id: Int
  let title: String
  let children: [TestSliceOutlineNode]?

  init(id: Int, title: String, children: [TestSliceOutlineNode]? = nil) {
    self.id = id
    self.title = title
    self.children = children
  }
}

@Suite
@MainActor
final class OutlineGroupTests {
  private func sampleNodes() -> [TestOutlineNode] {
    [
      TestOutlineNode(id: 1, title: "Sources", children: [
        TestOutlineNode(id: 2, title: "App.swift", children: nil),
        TestOutlineNode(id: 3, title: "Views", children: [
          TestOutlineNode(id: 4, title: "ContentView.swift", children: nil)
        ])
      ]),
      TestOutlineNode(id: 5, title: "README.md", children: nil)
    ]
  }

  @Test
  func testIdentifiableOutlineRendersTreeItemsAndDisclosureGroups() {
    let html = StaticHTMLFiberRenderer().render(
      OutlineGroup(sampleNodes(), children: \.children) { node in
        Text(node.title)
      }
    )

    _expectTrue(html.contains("outline-group"))
    _expectTrue(html.contains("data-outline-group=\"true\""))
    _expectTrue(html.contains("role=\"tree\""))
    _expectTrue(html.contains("Sources"))
    _expectTrue(html.contains("README.md"))
    _expectTrue(html.contains("disclosure-group"))
    _expectTrue(html.contains("aria-expanded=\"false\""))
    _expectFalse(html.contains("App.swift"), "children start collapsed")
  }

  @Test
  func testNonNilEmptyChildrenRemainExpandableParents() {
    let nodes = [TestOutlineNode(id: 7, title: "Empty directory", children: [])]
    let html = StaticHTMLFiberRenderer().render(
      OutlineGroup(nodes, children: \.children) { Text($0.title) }
    )

    _expectTrue(html.contains("disclosure-group"))
    _expectTrue(html.contains("aria-expanded=\"false\""))
  }

  @Test
  func testDisclosureEventExpandsOnlyTheSelectedBranch() {
    let view = OutlineGroup(sampleNodes(), children: \.children) { node in
      Text(node.title)
    }
    let tree = FiberTree(view, deferLazyCollections: false)

    guard let disclosure = tree.findNode(withEvent: "click") else {
      return _fail("Outline parent should reuse DisclosureGroup's click event")
    }
    tree.dispatch(event: "click", on: disclosure)
    _expectTrue(tree.renderNode.htmlDescription.contains("App.swift"))
    _expectFalse(tree.renderNode.htmlDescription.contains("ContentView.swift"), "nested branch remains collapsed")

    guard let expandedDisclosure = tree.findNode(withEvent: "click") else {
      return _fail("Expanded parent should retain its disclosure action")
    }
    tree.dispatch(event: "click", on: expandedDisclosure)
    _expectFalse(tree.renderNode.htmlDescription.contains("App.swift"), "collapsing hides descendants")
  }

  @Test
  func testExpansionFollowsStableIdentityAcrossDataUpdates() {
    let initial = sampleNodes()
    let view = OutlineGroup(initial, children: \.children) { node in Text(node.title) }
    let tree = FiberTree(view, deferLazyCollections: false)
    guard let disclosure = tree.findNode(withEvent: "click") else {
      return _fail("missing disclosure event")
    }
    tree.dispatch(event: "click", on: disclosure)
    _expectTrue(tree.renderNode.htmlDescription.contains("App.swift"))

    let reordered = [initial[1], initial[0]]
    _ = tree.update(OutlineGroup(reordered, children: \.children) { node in Text(node.title) })
    _expectTrue(tree.renderNode.htmlDescription.contains("App.swift"), "expanded state is keyed by model identity")
  }

  @Test
  func testRowStateFollowsIdentityWhenLeafOrderChanges() {
    struct StatefulRow: View {
      let id: Int
      @State private var taps = 0

      var body: some View {
        Button("\(id):\(taps)") { taps += 1 }
      }
    }

    let initial = [
      TestOutlineNode(id: 11, title: "One", children: nil),
      TestOutlineNode(id: 12, title: "Two", children: nil)
    ]
    let tree = FiberTree(
      OutlineGroup(initial, children: \.children) { node in StatefulRow(id: node.id) },
      deferLazyCollections: false
    )
    guard let button = tree.findNode(withEvent: "click") else {
      return _fail("leaf content should retain its event")
    }
    tree.dispatch(event: "click", on: button)
    _expectTrue(tree.renderNode.htmlDescription.contains("11:1"))

    _ = tree.update(
      OutlineGroup([initial[1], initial[0]], children: \.children) { node in StatefulRow(id: node.id) }
    )
    _expectTrue(tree.renderNode.htmlDescription.contains("11:1"))
    _expectTrue(tree.renderNode.htmlDescription.contains("12:0"))
  }

  @Test
  func testExpandedBranchReflectsDynamicChildInsertion() {
    var nodes = sampleNodes()
    let view = OutlineGroup(nodes, children: \.children) { node in Text(node.title) }
    let tree = FiberTree(view, deferLazyCollections: false)
    guard let disclosure = tree.findNode(withEvent: "click") else {
      return _fail("missing parent disclosure")
    }
    tree.dispatch(event: "click", on: disclosure)
    _expectTrue(tree.renderNode.htmlDescription.contains("App.swift"))

    nodes[0].children = (nodes[0].children ?? []) + [
      TestOutlineNode(id: 13, title: "Package.swift", children: nil)
    ]
    _ = tree.update(OutlineGroup(nodes, children: \.children) { node in Text(node.title) })
    _expectTrue(tree.renderNode.htmlDescription.contains("Package.swift"))
  }

  @Test
  func testExplicitIdentifierInitializerSupportsNonIdentifiableElements() {
    let nodes = [
      TestOutlineValue(key: "root", title: "Root", children: [
        TestOutlineValue(key: "leaf", title: "Leaf", children: nil)
      ])
    ]
    let html = StaticHTMLFiberRenderer().render(
      OutlineGroup(nodes, id: \.key, children: \.children) { Text($0.title) }
    )
    _expectTrue(html.contains("Root"))
    _expectTrue(html.contains("disclosure-group"))
  }

  @Test
  func testBindingInitializerProvidesEditableElementBindings() {
    var nodes = sampleNodes()
    let binding = Binding<[TestOutlineNode]>(get: { nodes }, set: { nodes = $0 })
    let html = StaticHTMLFiberRenderer().render(
      OutlineGroup(binding, children: \.children) { node in
        Text(node.wrappedValue.title)
      }
    )
    _expectTrue(html.contains("Sources"))
    _expectTrue(html.contains("outline-group"))
  }

  @Test
  func testBindingInitializerWritesNestedRowEditsBackToTheSourceTree() {
    var nodes = [
      TestOutlineNode(id: 20, title: "Folder", children: [
        TestOutlineNode(id: 21, title: "Before edit", children: nil)
      ])
    ]
    let binding = Binding<[TestOutlineNode]>(get: { nodes }, set: { nodes = $0 })
    let tree = FiberTree(
      OutlineGroup(binding, children: \.children) { node in
        if node.wrappedValue.id == 20 {
          Text(node.wrappedValue.title)
        } else {
          Button("Rename \(node.wrappedValue.title)") {
            var updated = node.wrappedValue
            updated.title = "After edit"
            node.wrappedValue = updated
          }
        }
      },
      deferLazyCollections: false
    )

    guard let disclosure = tree.findNode(withEvent: "click") else {
      return _fail("The parent row should expose its disclosure action")
    }
    tree.dispatch(event: "click", on: disclosure)
    #expect(tree.renderNode.htmlDescription.contains("Rename Before edit"))

    func findRenameButton(in node: _RenderNode) -> _RenderNode? {
      if node.events["click"] != nil && node.htmlDescription.contains("Rename Before edit") {
        return node
      }
      for child in node.children {
        if let found = findRenameButton(in: child) { return found }
      }
      return nil
    }

    guard let rename = findRenameButton(in: tree.renderNode) else {
      return _fail("The expanded child should expose its edit action")
    }
    tree.dispatch(event: "click", on: rename)
    #expect(nodes[0].children?.first?.title == "After edit")
    _ = tree.update(
      OutlineGroup(binding, children: \.children) { node in
        if node.wrappedValue.id == 20 {
          Text(node.wrappedValue.title)
        } else {
          Button("Rename \(node.wrappedValue.title)") {}
        }
      }
    )
    #expect(tree.renderNode.htmlDescription.contains("Rename After edit"))
  }

  @Test
  func staleEditableRowReadsItsSnapshotAndIgnoresWritesAfterRemoval() {
    var nodes = [TestOutlineNode(id: 30, title: "Temporary", children: nil)]
    let binding = Binding<[TestOutlineNode]>(get: { nodes }, set: { nodes = $0 })
    let tree = FiberTree(
      OutlineGroup(binding, children: \.children) { node in
        Button("Rename \(node.wrappedValue.title)") {
          var updated = node.wrappedValue
          updated.title = "Must not be reinserted"
          node.wrappedValue = updated
        }
      },
      deferLazyCollections: false
    )
    guard let rename = tree.findNode(withEvent: "click") else {
      return _fail("The row should retain an edit callback before removal")
    }

    nodes.removeAll()
    tree.dispatch(event: "click", on: rename)

    #expect(nodes.isEmpty, "A stale callback must not recreate a removed model element")
  }

  @Test
  func testArrayRootOutlineRendersSampleTree() {
    let roots = sampleNodes()
    let html = StaticHTMLFiberRenderer().render(
      OutlineGroup(roots, children: \.children) { Text($0.title) }
    )
    _expectTrue(html.contains("Sources"))
  }

  @Test
  func testRootElementConvenienceInitializer() {
    let root = sampleNodes()[0]
    let html = StaticHTMLFiberRenderer().render(
      OutlineGroup(root, children: \.children) { Text($0.title) }
    )
    _expectTrue(html.contains("Sources"))

    let explicitHTML = StaticHTMLFiberRenderer().render(
      OutlineGroup(root, id: \.id, children: \.children) { Text($0.title) }
    )
    _expectTrue(explicitHTML.contains("Sources"))
  }

  @Test
  func rootConvenienceInitializersRenderArrayChildren() {
    let leaf = TestSliceOutlineNode(id: 42, title: "Leaf")
    let root = TestSliceOutlineNode(id: 41, title: "Root", children: [leaf])

    let identifiable = FiberTree(
      OutlineGroup(root, children: \.children) { Text($0.title) },
      deferLazyCollections: false
    )
    #expect(identifiable.renderNode.htmlDescription.contains("Root"))
    guard let identifiableDisclosure = identifiable.findNode(withEvent: "click") else {
      return _fail("Identifiable root with a non-array child collection should expand")
    }
    identifiable.dispatch(event: "click", on: identifiableDisclosure)
    #expect(identifiable.renderNode.htmlDescription.contains("Leaf"))

    let explicitID = FiberTree(
      OutlineGroup(root, id: \.id, children: \.children) { Text($0.title) },
      deferLazyCollections: false
    )
    #expect(explicitID.renderNode.htmlDescription.contains("Root"))
    guard let explicitDisclosure = explicitID.findNode(withEvent: "click") else {
      return _fail("Explicit-ID root with a non-array child collection should expand")
    }
    explicitID.dispatch(event: "click", on: explicitDisclosure)
    #expect(explicitID.renderNode.htmlDescription.contains("Leaf"))
  }

  @Test
  func explicitIDInitializerExpandsArrayRoots() {
    let child = TestOutlineValue(key: "child", title: "Child slice", children: nil)
    let root = TestOutlineValue(key: "root", title: "Root slice", children: [child])
    let roots = [root]
    let tree = FiberTree(
      OutlineGroup(roots, id: \.key, children: \.children) { Text($0.title) },
      deferLazyCollections: false
    )

    #expect(tree.renderNode.htmlDescription.contains("Root slice"))
    guard let disclosure = tree.findNode(withEvent: "click") else {
      return _fail("An array root collection with array children should be expandable")
    }
    tree.dispatch(event: "click", on: disclosure)
    #expect(tree.renderNode.htmlDescription.contains("Child slice"))
  }

  @Test
  func testLargeOutlineUsesExistingLazyCollectionDescriptor() {
    let nodes = (0..<200).map { TestOutlineNode(id: $0, title: "Node \($0)", children: nil) }
    let tree = FiberTree(
      OutlineGroup(nodes, children: \.children) { Text($0.title) }
    )
    let lazy = tree._lazyCollections()
    _expectEqual(lazy.count, 1)
    _expectEqual(lazy[0].descriptor.count, 200)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-outline-virtualized=\"true\""))
  }
}
