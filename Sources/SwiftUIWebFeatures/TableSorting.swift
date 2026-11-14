@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

// Unsortable columns: `Sort` is `Never`, as in SwiftUI.
public extension TableColumn where Sort == Never, Label == Text {
  nonisolated init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping (RowValue) -> Content) {
    self.init(title: titleKey.resolved, cell: content)
  }

  nonisolated init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping (RowValue) -> Content) {
    self.init(title: String(title), cell: content)
  }
}

public extension TableColumn where Sort == Never, Content == Text, Label == Text {
  nonisolated init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>) {
    self.init(title: titleKey.resolved, cell: { Text(_swiftUIWebDescribe($0[keyPath: value])) })
  }

  nonisolated init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String>) {
    self.init(title: String(title), cell: { Text(_swiftUIWebDescribe($0[keyPath: value])) })
  }
}

// Columns sorted by a comparator the app supplies.
public extension TableColumn where Label == Text {
  nonisolated init(
    _ titleKey: LocalizedStringKey,
    sortUsing comparator: Sort,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) where Sort: SortComparator, RowValue == Sort.Compared {
    self.init(title: titleKey.resolved, cell: content)
    _sort = _TableColumnSort(comparator: comparator)
  }

  nonisolated init<S: StringProtocol>(
    _ title: S,
    sortUsing comparator: Sort,
    @ViewBuilder content: @escaping (RowValue) -> Content
  ) where Sort: SortComparator, RowValue == Sort.Compared {
    self.init(title: String(title), cell: content)
    _sort = _TableColumnSort(comparator: comparator)
  }
}

/// The rows of a `Table(data, columns:)`, one `TableRow` per element.
public nonisolated struct TableForEachContent<Data>: TableRowContent where Data: RandomAccessCollection, Data.Element: Identifiable {
  public typealias TableRowValue = Data.Element
  public typealias TableRowBody = Never
  let data: Data

  init(_ data: Data) { self.data = data }

  public func _renderTableRows(in context: _RenderContext) -> _RenderNode {
    // One fragment carries every row value. A marker node and a child context per
    // row would make each render of a large table proportional to its row count in
    // node allocations, even when the lazy table then renders only a window.
    let node = _RenderNode.fragment()
    node._tableRowValue = _RuntimeValue(Array(data))
    return node
  }
}

/// Makes the sortable headers of a `Table` interactive: a click makes the column
/// the primary sort key, or flips its direction when it already is.
@MainActor func _wireTableSortHeaders<Sort: SortComparator>(_ node: _RenderNode, _ binding: Binding<[Sort]>) {
  if let stored = node._tableColumnSort, let spec: _TableColumnSort<Sort> = stored.read() {
    let primary = binding.wrappedValue.first
    let active = primary.map { spec.matches($0) } ?? false
    let direction = active ? (primary?.order ?? .forward) : .forward
    node.attributes["aria-sort"] = active ? (direction == .forward ? "ascending" : "descending") : "none"
    node.attributes["data-sortable"] = "true"
    node.attributes["tabindex"] = "0"
    if active {
      let indicator = _RenderNode.element("span")
      indicator.classes = ["table-sort-indicator"]
      indicator.attributes["aria-hidden"] = "true"
      indicator.children = [.text(direction == .forward ? " \u{25B2}" : " \u{25BC}")]
      node.children.append(indicator)
    }
    node.events["click"] = _EventHandler(name: "click", action: {
      if let first = binding.wrappedValue.first, spec.matches(first) {
        binding.wrappedValue = [spec.make(first.order == .forward ? .reverse : .forward)]
      } else {
        binding.wrappedValue = [spec.make(.forward)]
      }
    })
  }
  for child in node.children { _wireTableSortHeaders(child, binding) }
}

public extension Table {
  nonisolated init<Data>(
    _ data: Data,
    @TableColumnBuilder<Value, Never> columns: () -> Columns
  ) where Rows == TableForEachContent<Data>, Data: RandomAccessCollection, Columns.TableRowValue == Data.Element {
    self.init(rows: TableForEachContent(data), columns: columns())
  }

  nonisolated init<Data>(
    _ data: Data,
    selection: Binding<Value.ID?>,
    @TableColumnBuilder<Value, Never> columns: () -> Columns
  ) where Rows == TableForEachContent<Data>, Data: RandomAccessCollection, Columns.TableRowValue == Data.Element {
    self.init(rows: TableForEachContent(data), columns: columns())
    _selection = _ListSelectionSink(single: selection)
  }

  nonisolated init<Data>(
    _ data: Data,
    selection: Binding<Set<Value.ID>>,
    @TableColumnBuilder<Value, Never> columns: () -> Columns
  ) where Rows == TableForEachContent<Data>, Data: RandomAccessCollection, Columns.TableRowValue == Data.Element {
    self.init(rows: TableForEachContent(data), columns: columns())
    _selection = _ListSelectionSink(multiple: selection)
  }

  nonisolated init<Data, Sort>(
    _ data: Data,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns
  ) where Rows == TableForEachContent<Data>, Data: RandomAccessCollection, Sort: SortComparator,
    Columns.TableRowValue == Data.Element, Data.Element == Sort.Compared {
    self.init(rows: TableForEachContent(data), columns: columns())
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init<Data, Sort>(
    _ data: Data,
    selection: Binding<Value.ID?>,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns
  ) where Rows == TableForEachContent<Data>, Data: RandomAccessCollection, Sort: SortComparator,
    Columns.TableRowValue == Data.Element, Data.Element == Sort.Compared {
    self.init(rows: TableForEachContent(data), columns: columns())
    _selection = _ListSelectionSink(single: selection)
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init<Data, Sort>(
    _ data: Data,
    selection: Binding<Set<Value.ID>>,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns
  ) where Rows == TableForEachContent<Data>, Data: RandomAccessCollection, Sort: SortComparator,
    Columns.TableRowValue == Data.Element, Data.Element == Sort.Compared {
    self.init(rows: TableForEachContent(data), columns: columns())
    _selection = _ListSelectionSink(multiple: selection)
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init(
    of valueType: Value.Type,
    @TableColumnBuilder<Value, Never> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) {
    self.init(rows: rows(), columns: columns())
  }

  nonisolated init(
    of valueType: Value.Type,
    selection: Binding<Value.ID?>,
    @TableColumnBuilder<Value, Never> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) {
    self.init(rows: rows(), columns: columns())
    _selection = _ListSelectionSink(single: selection)
  }

  nonisolated init(
    of valueType: Value.Type,
    selection: Binding<Set<Value.ID>>,
    @TableColumnBuilder<Value, Never> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) {
    self.init(rows: rows(), columns: columns())
    _selection = _ListSelectionSink(multiple: selection)
  }

  nonisolated init<Sort>(
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) where Sort: SortComparator, Columns.TableRowValue == Sort.Compared {
    self.init(rows: rows(), columns: columns())
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init<Sort>(
    of valueType: Value.Type,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) where Sort: SortComparator, Columns.TableRowValue == Sort.Compared {
    self.init(rows: rows(), columns: columns())
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init<Sort>(
    selection: Binding<Value.ID?>,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) where Sort: SortComparator, Columns.TableRowValue == Sort.Compared {
    self.init(rows: rows(), columns: columns())
    _selection = _ListSelectionSink(single: selection)
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init<Sort>(
    of valueType: Value.Type,
    selection: Binding<Value.ID?>,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) where Sort: SortComparator, Columns.TableRowValue == Sort.Compared {
    self.init(rows: rows(), columns: columns())
    _selection = _ListSelectionSink(single: selection)
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init<Sort>(
    selection: Binding<Set<Value.ID>>,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) where Sort: SortComparator, Columns.TableRowValue == Sort.Compared {
    self.init(rows: rows(), columns: columns())
    _selection = _ListSelectionSink(multiple: selection)
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }

  nonisolated init<Sort>(
    of valueType: Value.Type,
    selection: Binding<Set<Value.ID>>,
    sortOrder: Binding<[Sort]>,
    @TableColumnBuilder<Value, Sort> columns: () -> Columns,
    @TableRowBuilder<Value> rows: () -> Rows
  ) where Sort: SortComparator, Columns.TableRowValue == Sort.Compared {
    self.init(rows: rows(), columns: columns())
    _selection = _ListSelectionSink(multiple: selection)
    _sortWiring = { node in _wireTableSortHeaders(node, sortOrder) }
  }
}

/// The bordered table look; see ``InsetTableStyle`` for `alternatesRowBackgrounds`.
public nonisolated struct BorderedTableStyle: TableStyle {
  public typealias Body = EmptyView
  public nonisolated init() {}
  public nonisolated init(alternatesRowBackgrounds: Bool) {}
  nonisolated public func makeBody(configuration: BorderedTableStyle.Configuration) -> EmptyView { EmptyView() }
  public nonisolated var _swiftUIWebTableStyle: String { "bordered" }
}

public extension TableStyle where Self == BorderedTableStyle {
  @MainActor @preconcurrency static var bordered: BorderedTableStyle { BorderedTableStyle() }

  @MainActor @preconcurrency static func bordered(alternatesRowBackgrounds: Bool) -> BorderedTableStyle { BorderedTableStyle(alternatesRowBackgrounds: alternatesRowBackgrounds) }
}

public extension View {
  nonisolated func tableStyle<S: TableStyle>(_ style: S) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_SemanticCompatibilityModifier(attributes: ["data-table-style": style._swiftUIWebTableStyle]))
  }

  nonisolated func tableColumnHeaders(_ visibility: Visibility) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_SemanticCompatibilityModifier(attributes: ["data-table-column-headers": visibility.rawValue]))
  }
}

/// The column content of a `TableColumnBuilder` block. Apple's `TupleTableColumnContent`.
public nonisolated struct TupleTableColumnContent<RowValue, Sort, T>: TableColumnContent
where RowValue: Identifiable {
  public typealias TableRowValue = RowValue
  public typealias TableColumnSortComparator = Sort
  public typealias TableColumnBody = Never
  public var value: T
  let renderer: @MainActor (T, _RenderContext) -> _RenderNode

  init(value: T, renderer: @escaping @MainActor (T, _RenderContext) -> _RenderNode) {
    self.value = value
    self.renderer = renderer
  }

  @MainActor public func _renderTableColumns(in context: _RenderContext) -> _RenderNode { renderer(value, context) }
}

/// The row content of a `TableRowBuilder` block. Apple's `TupleTableRowContent`.
public nonisolated struct TupleTableRowContent<Value, T>: TableRowContent where Value: Identifiable {
  public typealias TableRowValue = Value
  public typealias TableRowBody = Never
  public var value: T
  let renderer: @MainActor (T, _RenderContext) -> _RenderNode

  init(value: T, renderer: @escaping @MainActor (T, _RenderContext) -> _RenderNode) {
    self.value = value
    self.renderer = renderer
  }

  @MainActor public func _renderTableRows(in context: _RenderContext) -> _RenderNode { renderer(value, context) }
}

/// Groups the rendered children of a table builder block into one fragment.
func _tableFragment(_ parts: [_RenderNode]) -> _RenderNode {
  let node = _RenderNode.fragment()
  node.children = parts
  return node
}

/// Builds the `rows:` content of a `Table`. Apple's `TableRowBuilder`.
@resultBuilder public enum TableRowBuilder<Value> where Value: Identifiable {
  public static func buildExpression<Content: TableRowContent>(_ content: Content) -> Content
  where Value == Content.TableRowValue {
    content
  }

  public static func buildBlock<C: TableRowContent>(_ content: C) -> C where Value == C.TableRowValue {
    content
  }

 public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> TupleTableRowContent<Value, (C0, C1)>
  where C0: TableRowContent, C1: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1")))])
    })
  }

 public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleTableRowContent<Value, (C0, C1, C2)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleTableRowContent<Value, (C0, C1, C2, C3)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2, c3), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2"))), value.3._renderTableRows(in: context.child(_FiberKey("row_3")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue, C4.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2, c3, c4), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2"))), value.3._renderTableRows(in: context.child(_FiberKey("row_3"))), value.4._renderTableRows(in: context.child(_FiberKey("row_4")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue, C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2"))), value.3._renderTableRows(in: context.child(_FiberKey("row_3"))), value.4._renderTableRows(in: context.child(_FiberKey("row_4"))), value.5._renderTableRows(in: context.child(_FiberKey("row_5")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue, C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue, C6.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2"))), value.3._renderTableRows(in: context.child(_FiberKey("row_3"))), value.4._renderTableRows(in: context.child(_FiberKey("row_4"))), value.5._renderTableRows(in: context.child(_FiberKey("row_5"))), value.6._renderTableRows(in: context.child(_FiberKey("row_6")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent, C7: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue, C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue, C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6, c7), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2"))), value.3._renderTableRows(in: context.child(_FiberKey("row_3"))), value.4._renderTableRows(in: context.child(_FiberKey("row_4"))), value.5._renderTableRows(in: context.child(_FiberKey("row_5"))), value.6._renderTableRows(in: context.child(_FiberKey("row_6"))), value.7._renderTableRows(in: context.child(_FiberKey("row_7")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent, C7: TableRowContent, C8: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue, C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue, C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue, C8.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2"))), value.3._renderTableRows(in: context.child(_FiberKey("row_3"))), value.4._renderTableRows(in: context.child(_FiberKey("row_4"))), value.5._renderTableRows(in: context.child(_FiberKey("row_5"))), value.6._renderTableRows(in: context.child(_FiberKey("row_6"))), value.7._renderTableRows(in: context.child(_FiberKey("row_7"))), value.8._renderTableRows(in: context.child(_FiberKey("row_8")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleTableRowContent<Value, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
  where C0: TableRowContent, C1: TableRowContent, C2: TableRowContent, C3: TableRowContent, C4: TableRowContent, C5: TableRowContent, C6: TableRowContent, C7: TableRowContent, C8: TableRowContent, C9: TableRowContent, C0.TableRowValue == Value, C1.TableRowValue == C0.TableRowValue, C2.TableRowValue == C0.TableRowValue, C3.TableRowValue == C0.TableRowValue, C4.TableRowValue == C0.TableRowValue, C5.TableRowValue == C0.TableRowValue, C6.TableRowValue == C0.TableRowValue, C7.TableRowValue == C0.TableRowValue, C8.TableRowValue == C0.TableRowValue, C9.TableRowValue == C0.TableRowValue {
    TupleTableRowContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9), renderer: { value, context in
      _tableFragment([value.0._renderTableRows(in: context.child(_FiberKey("row_0"))), value.1._renderTableRows(in: context.child(_FiberKey("row_1"))), value.2._renderTableRows(in: context.child(_FiberKey("row_2"))), value.3._renderTableRows(in: context.child(_FiberKey("row_3"))), value.4._renderTableRows(in: context.child(_FiberKey("row_4"))), value.5._renderTableRows(in: context.child(_FiberKey("row_5"))), value.6._renderTableRows(in: context.child(_FiberKey("row_6"))), value.7._renderTableRows(in: context.child(_FiberKey("row_7"))), value.8._renderTableRows(in: context.child(_FiberKey("row_8"))), value.9._renderTableRows(in: context.child(_FiberKey("row_9")))])
    })
  }

  public static func buildIf<C: TableRowContent>(_ content: C?) -> C? where Value == C.TableRowValue {
    content
  }

  public static func buildEither<T: TableRowContent, F: TableRowContent>(first component: T) -> _ConditionalContent<T, F>
  where Value == T.TableRowValue, T.TableRowValue == F.TableRowValue {
    .trueContent(component)
  }

  public static func buildEither<T: TableRowContent, F: TableRowContent>(second component: F) -> _ConditionalContent<T, F>
  where Value == T.TableRowValue, T.TableRowValue == F.TableRowValue {
    .falseContent(component)
  }
}

/// Builds the column content of a `Table`. Apple's `TableColumnBuilder`.
@resultBuilder public enum TableColumnBuilder<RowValue, Sort>
where RowValue: Identifiable {
  public static func buildExpression<Column: TableColumnContent>(_ column: Column) -> Column
  where RowValue == Column.TableRowValue {
    column
  }

  public static func buildBlock<Column: TableColumnContent>(_ column: Column) -> Column
  where RowValue == Column.TableRowValue {
    column
  }

 public static func buildBlock<C0, C1>(_ c0: C0, _ c1: C1) -> TupleTableColumnContent<RowValue, Sort, (C0, C1)>
  where C0: TableColumnContent, C1: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1")))])
    })
  }

 public static func buildBlock<C0, C1, C2>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2, c3), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2"))), value.3._renderTableColumns(in: context.child(_FiberKey("column_3")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue, C4.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2, c3, c4), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2"))), value.3._renderTableColumns(in: context.child(_FiberKey("column_3"))), value.4._renderTableColumns(in: context.child(_FiberKey("column_4")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue, C4.TableRowValue == RowValue, C5.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2"))), value.3._renderTableColumns(in: context.child(_FiberKey("column_3"))), value.4._renderTableColumns(in: context.child(_FiberKey("column_4"))), value.5._renderTableColumns(in: context.child(_FiberKey("column_5")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue, C4.TableRowValue == RowValue, C5.TableRowValue == RowValue, C6.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2"))), value.3._renderTableColumns(in: context.child(_FiberKey("column_3"))), value.4._renderTableColumns(in: context.child(_FiberKey("column_4"))), value.5._renderTableColumns(in: context.child(_FiberKey("column_5"))), value.6._renderTableColumns(in: context.child(_FiberKey("column_6")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent, C7: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue, C4.TableRowValue == RowValue, C5.TableRowValue == RowValue, C6.TableRowValue == RowValue, C7.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6, c7), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2"))), value.3._renderTableColumns(in: context.child(_FiberKey("column_3"))), value.4._renderTableColumns(in: context.child(_FiberKey("column_4"))), value.5._renderTableColumns(in: context.child(_FiberKey("column_5"))), value.6._renderTableColumns(in: context.child(_FiberKey("column_6"))), value.7._renderTableColumns(in: context.child(_FiberKey("column_7")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue, C4.TableRowValue == RowValue, C5.TableRowValue == RowValue, C6.TableRowValue == RowValue, C7.TableRowValue == RowValue, C8.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2"))), value.3._renderTableColumns(in: context.child(_FiberKey("column_3"))), value.4._renderTableColumns(in: context.child(_FiberKey("column_4"))), value.5._renderTableColumns(in: context.child(_FiberKey("column_5"))), value.6._renderTableColumns(in: context.child(_FiberKey("column_6"))), value.7._renderTableColumns(in: context.child(_FiberKey("column_7"))), value.8._renderTableColumns(in: context.child(_FiberKey("column_8")))])
    })
  }

 public static func buildBlock<C0, C1, C2, C3, C4, C5, C6, C7, C8, C9>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)>
  where C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent, C5: TableColumnContent, C6: TableColumnContent, C7: TableColumnContent, C8: TableColumnContent, C9: TableColumnContent, C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue, C4.TableRowValue == RowValue, C5.TableRowValue == RowValue, C6.TableRowValue == RowValue, C7.TableRowValue == RowValue, C8.TableRowValue == RowValue, C9.TableRowValue == RowValue {
    TupleTableColumnContent(value: (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9), renderer: { value, context in
      _tableFragment([value.0._renderTableColumns(in: context.child(_FiberKey("column_0"))), value.1._renderTableColumns(in: context.child(_FiberKey("column_1"))), value.2._renderTableColumns(in: context.child(_FiberKey("column_2"))), value.3._renderTableColumns(in: context.child(_FiberKey("column_3"))), value.4._renderTableColumns(in: context.child(_FiberKey("column_4"))), value.5._renderTableColumns(in: context.child(_FiberKey("column_5"))), value.6._renderTableColumns(in: context.child(_FiberKey("column_6"))), value.7._renderTableColumns(in: context.child(_FiberKey("column_7"))), value.8._renderTableColumns(in: context.child(_FiberKey("column_8"))), value.9._renderTableColumns(in: context.child(_FiberKey("column_9")))])
    })
  }

  public static func buildIf<C: TableColumnContent>(_ content: C?) -> C?
  where RowValue == C.TableRowValue {
    content
  }

  public static func buildEither<T: TableColumnContent, F: TableColumnContent>(first component: T) -> _ConditionalContent<T, F>
  where RowValue == T.TableRowValue, F.TableRowValue == RowValue {
    .trueContent(component)
  }

  public static func buildEither<T: TableColumnContent, F: TableColumnContent>(second component: F) -> _ConditionalContent<T, F>
  where RowValue == T.TableRowValue, F.TableRowValue == RowValue {
    .falseContent(component)
  }
}
