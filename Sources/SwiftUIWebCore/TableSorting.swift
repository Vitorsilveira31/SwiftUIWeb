// SwiftUI-shaped `Table` selection, sorting, `TableRow` and style APIs.
@_spi(Renderer) import SwiftUIWebTransferable

/// How a sortable `TableColumn` names and orders its comparator without
/// reflection. `matches` identifies the comparator that belongs to the column;
/// `make` builds the comparator written into the table's `sortOrder`.
package struct _TableColumnSort<Sort> {
  package let matches: (Sort) -> Bool
  package let make: (SortOrder) -> Sort
}

extension _TableColumnSort where Sort: SortComparator {
  /// Two comparators name the same column when they are equal apart from their
  /// order (`SortComparator` is `Hashable`), so a click on the active column
  /// toggles its direction and the header reports it in `aria-sort`.
  package init(comparator: Sort) {
    var forward = comparator
    forward.order = .forward
    matches = { [forward] candidate in
      var candidate = candidate
      candidate.order = .forward
      return candidate == forward
    }
    make = { order in
      var comparator = comparator
      comparator.order = order
      return comparator
    }
  }
}

// MARK: Table columns

// `Sort` is `Never` for unsortable columns; SwiftUIWeb does not make `Never` a
// `SortComparator` (Apple's `Never` members would be unmatched API), so the
// comparator requirement appears only where a comparator is used.

#if !hasFeature(Embedded)
/// Apple's `TableColumn(value:)` takes a plain `KeyPath`, which Swift does not mark `Sendable`, while `KeyPathComparator`
/// takes `any KeyPath & Sendable`.
/// SAFETY: a `KeyPath` is immutable once created and holds no mutable state, so sharing the reference is safe. Both
/// views are one class reference (`Sendable` is a marker protocol with no witness table).
private func _sendableKeyPath<Row, Value>(_ keyPath: KeyPath<Row, Value>) -> any KeyPath<Row, Value> & Sendable {
  unsafeBitCast(keyPath, to: (any KeyPath<Row, Value> & Sendable).self)
}

/// The column sort for a key path: its comparator in `sortOrder` is the one with the same key path.
func _keyPathSort<Row, Value: Comparable>(_ keyPath: KeyPath<Row, Value>) -> _TableColumnSort<KeyPathComparator<Row>> {
  let partial: PartialKeyPath<Row> = keyPath
  let sendable = _sendableKeyPath(keyPath)
  return _TableColumnSort(matches: { ($0.keyPath as PartialKeyPath<Row>) == partial }, make: { KeyPathComparator(sendable, order: $0) })
}

func _keyPathSort<Row, Value, Comparator: SortComparator>(
  _ keyPath: KeyPath<Row, Value>,
  comparator: Comparator
) -> _TableColumnSort<KeyPathComparator<Row>> where Comparator.Compared == Value {
  let partial: PartialKeyPath<Row> = keyPath
  let sendable = _sendableKeyPath(keyPath)
  return _TableColumnSort(
    matches: { ($0.keyPath as PartialKeyPath<Row>) == partial },
    make: { KeyPathComparator(sendable, comparator: comparator, order: $0) }
  )
}

// Columns sorted by a key path, as in `TableColumn("Name", value: \.name) { ... }`.
public extension TableColumn where Sort == KeyPathComparator<RowValue>, Label == Text {
  nonisolated init<Value: Comparable>(
    _ titleKey: LocalizedStringKey,
    value: KeyPath<RowValue, Value>,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) {
    self.init(title: titleKey.resolved, cell: content)
    _sort = _keyPathSort(value)
  }

  @_disfavoredOverload nonisolated init<S: StringProtocol, Value: Comparable>(
    _ title: S,
    value: KeyPath<RowValue, Value>,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) {
    self.init(title: String(title), cell: content)
    _sort = _keyPathSort(value)
  }

  nonisolated init<Value, Comparator: SortComparator>(
    _ titleKey: LocalizedStringKey,
    value: KeyPath<RowValue, Value>,
    comparator: Comparator,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) where Value == Comparator.Compared {
    self.init(title: titleKey.resolved, cell: content)
    _sort = _keyPathSort(value, comparator: comparator)
  }

  @_disfavoredOverload nonisolated init<S: StringProtocol, Value, Comparator: SortComparator>(
    _ title: S,
    value: KeyPath<RowValue, Value>,
    comparator: Comparator,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) where Value == Comparator.Compared {
    self.init(title: String(title), cell: content)
    _sort = _keyPathSort(value, comparator: comparator)
  }
}
#else
// Embedded lowering target for `TableColumn(title, value: \.member) { ... }`:
// the lowerer names the member and supplies a getter, since there are no key paths.
public extension TableColumn where Sort == KeyPathComparator<RowValue>, Label == Text {
  nonisolated init<S: StringProtocol, Value: Comparable & SendableMetatype>(
    _ title: S,
    _embeddedMember member: String,
    _embeddedValue value: @escaping @Sendable (RowValue) -> Value,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) {
    self.init(title: String(title), cell: content)
    _sort = _TableColumnSort(
      matches: { $0._identity == member },
      make: { KeyPathComparator(_embeddedMember: member, value, order: $0) }
    )
  }

  nonisolated init<S: StringProtocol, Value: SendableMetatype, Comparator: SortComparator>(
    _ title: S,
    _embeddedMember member: String,
    _embeddedValue value: @escaping @Sendable (RowValue) -> Value,
    comparator: Comparator,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) where Value == Comparator.Compared {
    self.init(title: String(title), cell: content)
    _sort = _TableColumnSort(
      matches: { $0._identity == member },
      make: { KeyPathComparator(_embeddedMember: member, value, comparator: comparator, order: $0) }
    )
  }
}
#endif

public extension TableColumn {
  /// A fixed column width (`nil` leaves the column flexible).
  nonisolated func width(_ width: CGFloat? = nil) -> TableColumn<RowValue, Sort, Content, Label> {
    var copy = self
    copy._widthStyles = width.map { ["width": "\(_swiftUIWebDescribe($0))px"] } ?? [:]
    return copy
  }

  nonisolated func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> TableColumn<RowValue, Sort, Content, Label> {
    var copy = self
    var styles: _NodeValues = [:]
    if let min { styles["min-width"] = "\(_swiftUIWebDescribe(min))px" }
    if let ideal { styles["width"] = "\(_swiftUIWebDescribe(ideal))px" }
    if let max { styles["max-width"] = "\(_swiftUIWebDescribe(max))px" }
    copy._widthStyles = styles
    return copy
  }
}

// MARK: Table rows

/// A row of a `Table`. Rows render as table markup themselves, so the content has no view body.
@MainActor @preconcurrency
public protocol TableRowContent<TableRowValue> {
  associatedtype TableRowValue: Identifiable
  associatedtype TableRowBody

  /// SwiftUIWeb's renderer hook. Rows render as hidden `tr` markers that carry
  /// their row value; the table collects the values from them.
  func _renderTableRows(in context: _RenderContext) -> _RenderNode
}

/// Marks the data value behind one row of a `Table`.
public nonisolated struct TableRow<Value>: TableRowContent where Value: Identifiable {
  public typealias TableRowValue = Value
  public typealias TableRowBody = Never
  let value: Value
  public nonisolated init(_ value: Value) { self.value = value }

  public func _renderTableRows(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("tr")
    node.attributes["hidden"] = "true"
    node._tableRowValue = _RuntimeValue(value)
    return node
  }
}

// Optional builder results (`if` without `else`) keep the table content of their wrapped value.
extension Optional: TableRowContent where Wrapped: TableRowContent {
  public typealias TableRowValue = Wrapped.TableRowValue
  public typealias TableRowBody = Never

  public func _renderTableRows(in context: _RenderContext) -> _RenderNode {
    switch self {
    case .some(let wrapped): return wrapped._renderTableRows(in: context)
    case .none: return _RenderNode.fragment()
    }
  }
}

extension Optional: TableColumnContent where Wrapped: TableColumnContent {
  public typealias TableRowValue = Wrapped.TableRowValue
  public typealias TableColumnSortComparator = Wrapped.TableColumnSortComparator
  public typealias TableColumnBody = Never

  public func _renderTableColumns(in context: _RenderContext) -> _RenderNode {
    switch self {
    case .some(let wrapped): return wrapped._renderTableColumns(in: context)
    case .none: return _RenderNode.fragment()
    }
  }
}

@MainActor func _collectTableRows<Value>(_ node: _RenderNode, into rows: inout [Value]) {
  if let stored = node._tableRowValue {
    if let row: Value = stored.read() { rows.append(row) }
    else if let batch: [Value] = stored.read() { rows.append(contentsOf: batch) }
  }
  for child in node.children { _collectTableRows(child, into: &rows) }
}

// MARK: Table initializers

// MARK: Table styling

/// SwiftUI's table style. The browser draws the built-in looks from the attribute each style
/// reports (`data-table-style`); a custom style's `makeBody` is not invoked, so it renders with the
/// automatic look, as it did before these styles were SwiftUI-shaped.
@MainActor @preconcurrency
public protocol TableStyle {
  associatedtype Body: View
  typealias Configuration = TableStyleConfiguration
  @MainActor @preconcurrency @ViewBuilder func makeBody(configuration: Self.Configuration) -> Body
  nonisolated var _swiftUIWebTableStyle: String { get }
}

public extension TableStyle {
  nonisolated var _swiftUIWebTableStyle: String { "automatic" }
}

/// The configuration the browser hands a table style. Only the built-in look is carried.
public struct TableStyleConfiguration {
  package let look: String
  package init(look: String) { self.look = look }
}

public nonisolated struct AutomaticTableStyle: TableStyle {
  public typealias Body = EmptyView
  // Apple exposes no public initializer for the automatic style; the static member is the way to spell it.
  package let look: String
  package init(look: String) { self.look = look }
  nonisolated public func makeBody(configuration: AutomaticTableStyle.Configuration) -> EmptyView { EmptyView() }
  public nonisolated var _swiftUIWebTableStyle: String { look }
}

/// The inset table look. The browser's table draws its own row backgrounds, so
/// `alternatesRowBackgrounds` is accepted for source compatibility and has no effect.
public nonisolated struct InsetTableStyle: TableStyle {
  public typealias Body = EmptyView
  public nonisolated init() {}
  public nonisolated init(alternatesRowBackgrounds: Bool) {}
  nonisolated public func makeBody(configuration: InsetTableStyle.Configuration) -> EmptyView { EmptyView() }
  public nonisolated var _swiftUIWebTableStyle: String { "inset" }
}

public extension TableStyle where Self == AutomaticTableStyle {
  @MainActor @preconcurrency static var automatic: AutomaticTableStyle { AutomaticTableStyle(look: "automatic") }
}

public extension TableStyle where Self == InsetTableStyle {
  @MainActor @preconcurrency static var inset: InsetTableStyle { InsetTableStyle() }
  @MainActor @preconcurrency static func inset(alternatesRowBackgrounds: Bool) -> InsetTableStyle { InsetTableStyle(alternatesRowBackgrounds: alternatesRowBackgrounds) }
}

