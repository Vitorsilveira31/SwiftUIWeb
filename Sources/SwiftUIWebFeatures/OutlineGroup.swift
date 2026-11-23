@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable
/// SwiftUI-compatible recursive tree rendering.
///
/// `OutlineGroup` deliberately keeps expansion in SwiftUI state rather than
/// encoding it in DOM attributes.  Rows are keyed by the complete path of
/// their model identifiers, so inserting, removing, or moving a sibling does
/// not transfer another row's state.  The visible projection is a normal
/// `ForEach`; when it grows past the renderer's collection threshold it is
/// hosted by `LazyVStack`, allowing the existing browser virtualization path
/// to materialize only the viewport window.
///
/// `Parent`, `Leaf`, and `Subgroup` are SwiftUI's row types: a content closure
/// produces the same `Leaf` view for both parent and leaf rows, and its
/// `Subgroup` is the `DisclosureGroup` that wraps a parent row.
///
/// As in SwiftUI, `Data` is the type of the children collection. A single root
/// element is supplied directly, so its row data is not wrapped in a collection.
public struct OutlineGroup<Data: RandomAccessCollection, ID: Hashable, Parent, Leaf, Subgroup> {
  /// The root rows, read by position so a binding-backed collection is never copied.
  private let rootCount: Int
  private let rootElement: (Int) -> Data.Element
  private let id: (Data.Element) -> ID
  private let children: (Data.Element) -> [Data.Element]?
  private let childrenCount: (Data.Element) -> Int?
  private let content: (Data.Element) -> Leaf

  private init(
    rootCount: Int,
    rootElement: @escaping (Int) -> Data.Element,
    id: @escaping (Data.Element) -> ID,
    children: @escaping (Data.Element) -> [Data.Element]?,
    childrenCount: @escaping (Data.Element) -> Int?,
    content: @escaping (Data.Element) -> Leaf
  ) {
    self.rootCount = rootCount
    self.rootElement = rootElement
    self.id = id
    self.children = children
    self.childrenCount = childrenCount
    self.content = content
  }

  /// Reads the roots of a collection by position.
  private static func _positional(_ roots: Data) -> (Int) -> Data.Element {
    { offset in roots[roots.index(roots.startIndex, offsetBy: offset)] }
  }

  /// Creates an outline from identified elements and a recursive children
  /// collection.  A non-`nil` empty children collection is intentionally
  /// treated as a parent (for example, an empty directory); `nil` denotes a
  /// leaf, matching SwiftUI's distinction.
  public init<DataElement>(
    _ data: Data,
    id: KeyPath<DataElement, ID>,
    children: KeyPath<DataElement, Data?>,
    @ViewBuilder content: @escaping (DataElement) -> Leaf
  ) where DataElement == Data.Element, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    self.init(
      rootCount: data.count,
      rootElement: Self._positional(data),
      id: { $0[keyPath: id] },
      children: { element in element[keyPath: children].map { Array($0) } },
      childrenCount: { element in element[keyPath: children]?.count },
      content: content
    )
  }

  /// Target for the Embedded source-lowering pass. The public application
  /// spelling remains `OutlineGroup(data, children: \.children)`; the lowered
  /// spelling passes the children as a closure, which Embedded Swift can call
  /// without a runtime `KeyPath`.
  @_spi(Renderer)
  public init<Children: RandomAccessCollection>(
    _ data: Data,
    _embeddedChildren children: @escaping (Data.Element) -> Children?,
    @ViewBuilder content: @escaping (Data.Element) -> Leaf
  ) where Data.Element: Identifiable, ID == Data.Element.ID, Children.Element == Data.Element,
          Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    self.init(
      rootCount: data.count,
      rootElement: Self._positional(data),
      id: { $0.id },
      children: { element in children(element).map { Array($0) } },
      childrenCount: { element in children(element)?.count },
      content: content
    )
  }

  /// Binding form used by editable tree models.  The row builder receives a
  /// binding to the identified element, just like SwiftUI.  The renderer
  /// keeps a value snapshot for structural traversal while writes are routed
  /// back to the source collection by stable element identity.
  init<C: MutableCollection & RandomAccessCollection, E>(
    collection root: Binding<C>,
    id idPath: KeyPath<E, ID>,
    children childrenPath: WritableKeyPath<E, C?>,
    content: @escaping (Binding<E>) -> Leaf
  ) where Data == Binding<C>, C.Element == E, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    // Rows are read from a snapshot taken now, as SwiftUI's outline does, so a
    // row whose element was removed keeps its last value instead of indexing
    // the live collection. Every row still reads and writes by identity.
    let snapshot = root.wrappedValue
    let lookup = _OutlineLookup<C, C, E, ID>(currentRoots: { root.wrappedValue }, idPath: idPath, childrenPath: childrenPath)
    self.init(
      rootCount: snapshot.count,
      rootElement: { offset in
        _outlineCollectionElementBinding(
          snapshot[snapshot.index(snapshot.startIndex, offsetBy: offset)],
          in: root,
          lookup: lookup,
          id: idPath,
          children: childrenPath
        )
      },
      id: { $0.wrappedValue[keyPath: idPath] },
      children: { element in
        guard let values = element.wrappedValue[keyPath: childrenPath] else { return nil }
        return values.map { child in
          _outlineCollectionElementBinding(child, in: root, lookup: lookup, id: idPath, children: childrenPath)
        }
      },
      childrenCount: { element in element.wrappedValue[keyPath: childrenPath]?.count },
      content: content
    )
  }

  /// Binding form for a single root element; its children are edited in place.
  init<C: MutableCollection & RandomAccessCollection, E>(
    element root: Binding<E>,
    id idPath: KeyPath<E, ID>,
    children childrenPath: WritableKeyPath<E, C?>,
    content: @escaping (Binding<E>) -> Leaf
  ) where Data == Binding<C>, C.Element == E, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    let lookup = _OutlineLookup<[E], C, E, ID>(currentRoots: { [root.wrappedValue] }, idPath: idPath, childrenPath: childrenPath)
    self.init(
      rootCount: 1,
      rootElement: { _ in root },
      id: { $0.wrappedValue[keyPath: idPath] },
      children: { element in
        guard let values = element.wrappedValue[keyPath: childrenPath] else { return nil }
        return values.map { child in
          let childID = child[keyPath: idPath]
          return _outlineElementBinding(
            child,
            find: {
              lookup.find(childID) {
                _outlineFindInTree(root.wrappedValue, id: childID, idPath: idPath, childrenPath: childrenPath)
              }
            },
            write: { updated in
              var tree = root.wrappedValue
              guard _outlineReplaceInTree(&tree, id: childID, with: updated, idPath: idPath, childrenPath: childrenPath) else { return }
              lookup.invalidate()
              root.wrappedValue = tree
            }
          )
        }
      },
      childrenCount: { element in element.wrappedValue[keyPath: childrenPath]?.count },
      content: content
    )
  }
}

/// A row's binding: it reads the element as the tree currently holds it and
/// writes changes back through `write`. A removed row keeps its last snapshot.
private func _outlineElementBinding<E>(
  _ element: E,
  find: @escaping () -> E?,
  write: @escaping (E) -> Void
) -> Binding<E> {
  Binding<E>(_unchecked: { find() ?? element }, set: write)
}

/// A row binding for an element of the collection `root` holds, by identity.
private func _outlineCollectionElementBinding<C: MutableCollection & RandomAccessCollection, E, ID: Hashable>(
  _ element: E,
  in root: Binding<C>,
  lookup: _OutlineLookup<C, C, E, ID>,
  id idPath: KeyPath<E, ID>,
  children childrenPath: WritableKeyPath<E, C?>
) -> Binding<E> where C.Element == E {
  let elementID = element[keyPath: idPath]
  return _outlineElementBinding(
    element,
    find: {
      lookup.find(elementID) {
        _outlineFind(in: root.wrappedValue, id: elementID, idPath: idPath, childrenPath: childrenPath)
      }
    },
    write: { updated in
      var collection = root.wrappedValue
      guard _outlineReplace(in: &collection, id: elementID, with: updated, idPath: idPath, childrenPath: childrenPath) else { return }
      lookup.invalidate()
      root.wrappedValue = collection
    }
  )
}

/// Maps each identifier to the path of its first occurrence in the pre-order `_outlineFind` visits. The row bindings of
/// an editable outline look their element up on every read; with this index a lookup is a dictionary read plus one walk
/// instead of a search of the whole tree. The index grows only as far as the lookups need and is shared by the bindings
/// of one render. A write through those bindings drops it. A hit is checked against the tree (the element at the path must
/// still carry the identifier); any other lookup falls back to the search.
private final class _OutlineLookup<Roots: RandomAccessCollection, Children: RandomAccessCollection, E, ID: Hashable>
  where Roots.Element == E, Children.Element == E {
  private let currentRoots: () -> Roots
  private let idPath: KeyPath<E, ID>
  private let childrenPath: KeyPath<E, Children?>
  /// The pre-order walk, kept between reads: each node is its offset and its parent's node, so a path costs its depth
  /// and the index stays linear in the tree's size. The walk goes only as far as the identifiers asked for so far.
  private var nodes: [(parent: Int, offset: Int)] = []
  private var firstNode: [ID: Int] = .init()
  private var pending: [(node: Int, element: E)] = []
  private var started = false

  init(currentRoots: @escaping () -> Roots, idPath: KeyPath<E, ID>, childrenPath: KeyPath<E, Children?>) {
    self.currentRoots = currentRoots
    self.idPath = idPath
    self.childrenPath = childrenPath
  }

  func find(_ id: ID, search: () -> E?) -> E? {
    let roots = currentRoots()
    if !started {
      started = true
      for offset in (0..<roots.count).reversed() {
        if let element = _outlineOffset(roots, offset) { pending.append((node: push(parent: -1, offset: offset), element: element)) }
      }
    }
    // Visits in the order `_outlineFind` does, so the first occurrence recorded is the one a search returns.
    while firstNode[id] == nil, let entry = pending.popLast() {
      let found = entry.element[keyPath: idPath]
      if firstNode[found] == nil { firstNode[found] = entry.node }
      if let children = entry.element[keyPath: childrenPath] {
        for offset in (0..<children.count).reversed() {
          if let child = _outlineOffset(children, offset) { pending.append((node: push(parent: entry.node, offset: offset), element: child)) }
        }
      }
    }
    if let node = firstNode[id],
       let element = _outlineElement(at: path(to: node), roots: roots, childrenPath: childrenPath),
       element[keyPath: idPath] == id {
      return element
    }
    return search()
  }

  private func push(parent: Int, offset: Int) -> Int {
    nodes.append((parent: parent, offset: offset))
    return nodes.count - 1
  }

  /// The offsets from the roots down to `node`.
  private func path(to node: Int) -> [Int] {
    var offsets: [Int] = []
    var current = node
    while current >= 0 {
      offsets.append(nodes[current].offset)
      current = nodes[current].parent
    }
    return offsets.reversed()
  }

  func invalidate() {
    nodes.removeAll(keepingCapacity: true)
    firstNode.removeAll(keepingCapacity: true)
    pending.removeAll(keepingCapacity: true)
    started = false
  }
}

/// The element at `offset`, or nil when the offset is outside the collection.
private func _outlineOffset<C: RandomAccessCollection>(_ collection: C, _ offset: Int) -> C.Element? {
  guard offset >= 0, offset < collection.count else { return nil }
  return collection[collection.index(collection.startIndex, offsetBy: offset)]
}

/// The element at an offset path from the roots, or nil when the path no longer leads to an element.
private func _outlineElement<Roots: RandomAccessCollection, Children: RandomAccessCollection, E>(
  at path: [Int],
  roots: Roots,
  childrenPath: KeyPath<E, Children?>
) -> E? where Roots.Element == E, Children.Element == E {
  guard let first = path.first, var element = _outlineOffset(roots, first) else { return nil }
  for offset in path.dropFirst() {
    guard let children = element[keyPath: childrenPath], let child = _outlineOffset(children, offset) else { return nil }
    element = child
  }
  return element
}

/// Finds `id` in the tree rooted at `element`, searching `element` first.
private func _outlineFindInTree<E, C: RandomAccessCollection, ID: Hashable>(
  _ element: E,
  id: ID,
  idPath: KeyPath<E, ID>,
  childrenPath: KeyPath<E, C?>
) -> E? where C.Element == E {
  if element[keyPath: idPath] == id { return element }
  guard let children = element[keyPath: childrenPath] else { return nil }
  return _outlineFind(in: children, id: id, idPath: idPath, childrenPath: childrenPath)
}

/// Replaces `id` in the tree rooted at `element`; `false` when it is absent.
private func _outlineReplaceInTree<E, C: MutableCollection & RandomAccessCollection, ID: Hashable>(
  _ element: inout E,
  id: ID,
  with updated: E,
  idPath: KeyPath<E, ID>,
  childrenPath: WritableKeyPath<E, C?>
) -> Bool where C.Element == E {
  if element[keyPath: idPath] == id {
    element = updated
    return true
  }
  guard var children = element[keyPath: childrenPath] else { return false }
  guard _outlineReplace(in: &children, id: id, with: updated, idPath: idPath, childrenPath: childrenPath) else { return false }
  element[keyPath: childrenPath] = children
  return true
}

/// The row initializers SwiftUI declares for identified elements (`ID == Element.ID`).
public extension OutlineGroup where Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
  /// Creates an outline from a single root element.
  init<DataElement>(
    _ root: DataElement,
    children: KeyPath<DataElement, Data?>,
    @ViewBuilder content: @escaping (DataElement) -> Leaf
  ) where ID == DataElement.ID, DataElement: Identifiable, DataElement == Data.Element {
    self.init(
      rootCount: 1,
      rootElement: { _ in root },
      id: { $0.id },
      children: { element in element[keyPath: children].map { Array($0) } },
      childrenCount: { element in element[keyPath: children]?.count },
      content: content
    )
  }

  /// Creates an outline from identified elements and a recursive children collection.
  init<DataElement>(
    _ data: Data,
    children: KeyPath<DataElement, Data?>,
    @ViewBuilder content: @escaping (DataElement) -> Leaf
  ) where ID == DataElement.ID, DataElement: Identifiable, DataElement == Data.Element {
    self.init(
      rootCount: data.count,
      rootElement: Self._positional(data),
      id: { $0.id },
      children: { element in element[keyPath: children].map { Array($0) } },
      childrenCount: { element in element[keyPath: children]?.count },
      content: content
    )
  }

  /// Creates an outline of editable identified elements, given a binding to the elements' collection.
  init<C: MutableCollection & RandomAccessCollection, E: Identifiable>(
    _ data: Binding<C>,
    children: WritableKeyPath<E, C?>,
    @ViewBuilder content: @escaping (Binding<E>) -> Leaf
  ) where Data == Binding<C>, ID == E.ID, C.Element == E, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    self.init(collection: data, id: \E.id, children: children, content: content)
  }

  /// Creates an outline of an editable identified root element.
  init<C: MutableCollection & RandomAccessCollection, E: Identifiable>(
    _ root: Binding<E>,
    children: WritableKeyPath<E, C?>,
    @ViewBuilder content: @escaping (Binding<E>) -> Leaf
  ) where Data == Binding<C>, ID == E.ID, C.Element == E, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
    self.init(element: root, id: \E.id, children: children, content: content)
  }
}

public extension OutlineGroup where Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren> {
  /// Creates an outline from a single root element, identified by `id`.
  init<DataElement>(
    _ root: DataElement,
    id: KeyPath<DataElement, ID>,
    children: KeyPath<DataElement, Data?>,
    @ViewBuilder content: @escaping (DataElement) -> Leaf
  ) where DataElement == Data.Element {
    self.init(
      rootCount: 1,
      rootElement: { _ in root },
      id: { $0[keyPath: id] },
      children: { element in element[keyPath: children].map { Array($0) } },
      childrenCount: { element in element[keyPath: children]?.count },
      content: content
    )
  }

  /// Creates an outline of editable elements identified by `id`, given a binding to their collection.
  init<C: MutableCollection & RandomAccessCollection, E>(
    _ data: Binding<C>,
    id: KeyPath<E, ID>,
    children: WritableKeyPath<E, C?>,
    @ViewBuilder content: @escaping (Binding<E>) -> Leaf
  ) where Data == Binding<C>, C.Element == E {
    self.init(collection: data, id: id, children: children, content: content)
  }

  /// Creates an outline of an editable root element identified by `id`.
  init<C: MutableCollection & RandomAccessCollection, E>(
    _ root: Binding<E>,
    id: KeyPath<E, ID>,
    children: WritableKeyPath<E, C?>,
    @ViewBuilder content: @escaping (Binding<E>) -> Leaf
  ) where Data == Binding<C>, C.Element == E {
    self.init(element: root, id: id, children: children, content: content)
  }
}

extension OutlineGroup: View where Parent: View, Leaf: View, Subgroup: View {
  public typealias Body = AnyView

  @MainActor @preconcurrency public var body: AnyView {
    AnyView(_OutlineGroupBody(
      rootCount: rootCount,
      rootElement: rootElement,
      id: id,
      children: children,
      childrenCount: childrenCount,
      content: content
    ))
  }
}

/// The children of a parent row's `DisclosureGroup` in an `OutlineGroup`.
/// Outline rows are flattened into one visible projection, so this subgroup
/// renders nothing of its own; it exists so the `Subgroup` type matches SwiftUI.
public nonisolated struct OutlineSubgroupChildren: View {
  public typealias Body = Never
  public func _render(in context: _RenderContext) -> _RenderNode { .empty() }
}

// The walks below are loops over an explicit stack, not recursion: an outline's depth comes from its data. They visit
// the nodes in the same pre-order as the recursive walk did, so the first match is the same element.

private func _outlineFind<Data: RandomAccessCollection, ID: Hashable>(
  in collection: Data,
  id: ID,
  idPath: KeyPath<Data.Element, ID>,
  childrenPath: KeyPath<Data.Element, Data?>
) -> Data.Element? {
  var stack: [Data.Element] = Array(collection.reversed())
  while let element = stack.popLast() {
    if element[keyPath: idPath] == id { return element }
    if let children = element[keyPath: childrenPath] { stack.append(contentsOf: children.reversed()) }
  }
  return nil
}

/// The index path from `collection` to the first element with `id`, in pre-order; nil when it is absent.
private func _outlinePath<Data: RandomAccessCollection, ID: Hashable>(
  in collection: Data,
  id: ID,
  idPath: KeyPath<Data.Element, ID>,
  childrenPath: KeyPath<Data.Element, Data?>
) -> [Data.Index]? {
  // Each visited node keeps its index and its parent's node, so the walk is linear and only the match's path is built.
  var nodes: [(parent: Int, index: Data.Index)] = []
  var stack: [(node: Int, element: Data.Element)] = []
  for index in collection.indices.reversed() {
    nodes.append((parent: -1, index: index))
    stack.append((node: nodes.count - 1, element: collection[index]))
  }
  while let entry = stack.popLast() {
    if entry.element[keyPath: idPath] == id {
      var path: [Data.Index] = []
      var current = entry.node
      while current >= 0 { path.append(nodes[current].index); current = nodes[current].parent }
      return path.reversed()
    }
    if let children = entry.element[keyPath: childrenPath] {
      for index in children.indices.reversed() {
        nodes.append((parent: entry.node, index: index))
        stack.append((node: nodes.count - 1, element: children[index]))
      }
    }
  }
  return nil
}

private func _outlineReplace<Data: MutableCollection & RandomAccessCollection, ID: Hashable>(
  in collection: inout Data,
  id: ID,
  with updated: Data.Element,
  idPath: KeyPath<Data.Element, ID>,
  childrenPath: WritableKeyPath<Data.Element, Data?>
) -> Bool {
  guard let path = _outlinePath(in: collection, id: id, idPath: idPath, childrenPath: childrenPath) else { return false }
  // `levels[j]` is the collection at depth j along the path. The target is edited there, then each level is written
  // back into its parent, from the deepest to the root.
  var levels: [Data] = [collection]
  for index in path.dropLast() {
    guard let children = levels[levels.count - 1][index][keyPath: childrenPath] else { return false }
    levels.append(children)
  }
  levels[levels.count - 1][path[path.count - 1]] = updated
  var child = levels.removeLast()
  while !levels.isEmpty {
    var parent = levels.removeLast()
    parent[path[levels.count]][keyPath: childrenPath] = child
    child = parent
  }
  collection = child
  return true
}

private struct _OutlineEntry<Element> {
  let element: Element
  let identity: String
  let depth: Int
  let hasChildren: Bool
}

private nonisolated struct _OutlineGroupBody<Element, ID: Hashable, RowContent: View>: View {
  typealias Body = AnyView

  let rootCount: Int
  let rootElement: (Int) -> Element
  let id: (Element) -> ID
  let children: (Element) -> [Element]?
  let childrenCount: (Element) -> Int?
  let content: (Element) -> RowContent

  /// The set is owned by this stable view boundary, not by a transient row.
  /// Consequently an expanded branch survives data updates and row moves as
  /// long as the model identifier remains unchanged.
  @State(memberID: 3605264436) private var expandedPaths: Set<String> = []

  /// Reuse the same renderer policy as List/Table/ForEach so an outline joins
  /// the existing visible-range engine at the point where other large
  /// collections do.
  private let virtualizationThreshold = _lazyCollectionThreshold

  @MainActor var body: AnyView {
    let entries = visibleEntries()
    let shouldVirtualize = treeExceedsThreshold()
    let rows = makeRows(entries)
    let stack: AnyView

    if shouldVirtualize {
      stack = AnyView(LazyVStack(alignment: .leading, spacing: 0) { rows })
    } else {
      stack = AnyView(VStack(alignment: .leading, spacing: 0) { rows })
    }

    return AnyView(_OutlineRoot(content: stack, virtualized: shouldVirtualize))
  }

  @MainActor private func makeRows(_ entries: [_OutlineEntry<Element>]) -> some View {
    ForEach(entries, id: { $0.identity }) { entry in
      _OutlineRow(
        element: entry.element,
        depth: entry.depth,
        hasChildren: entry.hasChildren,
        expanded: entry.hasChildren ? expansionBinding(for: entry.identity) : nil,
        content: content
      )
    }
  }

  @MainActor private func expansionBinding(for identity: String) -> Binding<Bool> {
    Binding(
      get: { expandedPaths.contains(identity) },
      set: { value in
        if value {
          expandedPaths.insert(identity)
        } else {
          expandedPaths.remove(identity)
        }
      }
    )
  }

  /// Builds only the currently visible projection.  Children of collapsed
  /// rows are not traversed or evaluated, which is important for file trees
  /// and navigation models backed by large or lazily loaded branches.
  @MainActor private func visibleEntries() -> [_OutlineEntry<Element>] {
    var result: [_OutlineEntry<Element>] = []
    var pending: [(element: Element, identity: String, depth: Int)] = []

    // Roots are pushed last-to-first so the depth-first worklist pops them in order.
    var rootOffset = rootCount
    while rootOffset > 0 {
      rootOffset -= 1
      let element = rootElement(rootOffset)
      pending.append((element, identity: identity(for: element, parent: ""), depth: 0))
    }

    while let next = pending.popLast() {
      // A count probe distinguishes a leaf from an empty-but-expandable
      // parent without copying a large child collection. Materialize values
      // only after the branch is known to be expanded.
      let childCount = childrenCount(next.element)
      let hasChildren = childCount != nil
      result.append(_OutlineEntry(
        element: next.element,
        identity: next.identity,
        depth: next.depth,
        hasChildren: hasChildren
      ))

      guard expandedPaths.contains(next.identity),
            let childCollection = children(next.element),
            !childCollection.isEmpty else {
        continue
      }

      for child in childCollection.reversed() {
        pending.append((
          child,
          identity: identity(for: child, parent: next.identity),
          depth: next.depth + 1
        ))
      }
    }

    return result
  }

  /// Counts at most `threshold + 1` nodes.  This bounded probe keeps the
  /// small-tree path cheap while still detecting a deeply nested large tree
  /// without walking an entire 100,000-node model on every render.
  @MainActor private func treeExceedsThreshold() -> Bool {
    var count = 0
    if rootCount > virtualizationThreshold { return true }
    var pending: [[Element]] = [(0..<rootCount).map { rootElement($0) }]

    while let branch = pending.popLast() {
      for element in branch {
        count += 1
        if count > virtualizationThreshold { return true }
        if let childCount = childrenCount(element) {
          // Avoid materializing a potentially huge child collection when its
          // count alone proves that this outline belongs on the lazy path.
          if count + childCount > virtualizationThreshold { return true }
          if childCount > 0, let childCollection = children(element) {
            pending.append(childCollection)
          }
        }
      }
    }
    return false
  }

  @MainActor private func identity(for element: Element, parent: String) -> String {
    let key = _FiberKey(id(element))
    let component = fiberKeyDescription(key)
    // Length-prefixing avoids ambiguity when an application's identifiers
    // contain the separator and keeps the representation deterministic on
    // both native and Embedded builds.
    return parent + "\(component.utf8.count):\(component)/"
  }
}

private nonisolated struct _OutlineRow<Element, RowContent: View>: View {
  typealias Body = AnyView

  let element: Element
  let depth: Int
  let hasChildren: Bool
  let expanded: Binding<Bool>?
  let content: (Element) -> RowContent

  @MainActor var body: AnyView {
    let row: AnyView
    if hasChildren, let expanded {
      // Descendants are siblings in the owner's keyed visible projection. The
      // disclosure still owns the native affordance and binding, but keeping
      // its content empty avoids rendering a second copy of the child range;
      // expanding the binding causes the projection to insert those rows at
      // the correct depth (or through the lazy descriptor for large trees).
      row = AnyView(DisclosureGroup(
        isExpanded: expanded,
        content: { EmptyView() },
        label: { content(element) }
      ))
    } else {
      row = AnyView(content(element))
    }

    return AnyView(row
      ._modified(_OutlineRowMetadata(depth: depth, hasChildren: hasChildren, expanded: expanded))
      .padding(.leading, Double(depth * 16)))
  }
}

private nonisolated struct _OutlineRowMetadata: ViewModifier {
  let depth: Int
  let hasChildren: Bool
  let expanded: Binding<Bool>?

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["role"] = "treeitem"
    node.attributes["aria-level"] = String(depth + 1)
    if hasChildren {
      node.attributes["aria-expanded"] = expanded?.wrappedValue == true ? "true" : "false"
    }
  }
}

private nonisolated struct _OutlineRoot<Content: View>: View {
  typealias Body = Never

  let content: Content
  let virtualized: Bool

  @MainActor func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["outline-group"]
    node.attributes["role"] = "tree"
    node.attributes["data-outline-group"] = "true"
    node.attributes["data-outline-virtualized"] = virtualized ? "true" : "false"

    let rendered = content._render(in: context.child(_FiberKey("content")))
    if rendered.kind == .fragment {
      node.children = rendered.children
    } else if !rendered.isEmpty {
      node.children = [rendered]
    }
    return node
  }
}
