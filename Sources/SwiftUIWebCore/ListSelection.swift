@_spi(Renderer) import SwiftUIWebTransferable
/// Selection-capable `List` initializers.
///
/// SwiftUI lists identify rows by their data identity and select rows by that
/// identity. Each row is wrapped in a selectable cell that reflects the
/// binding (`aria-selected`) and writes it when the row is activated, so the
/// same source drives single (`Binding<ID?>`) and multiple
/// (`Binding<Set<ID>>`) selection on every platform.
public extension List {
  /// `List(items, selection: $id) { item in ... }`: each row selects its element's `id`.
  nonisolated init<Data: RandomAccessCollection, SelectionValue: Hashable, RowContent: View>(
    _ data: Data,
    selection: Binding<SelectionValue?>?,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data.Element: Identifiable, SelectionValue == Data.Element.ID,
          Content == ForEach<Data, Data.Element.ID, _SelectableListRow<Data.Element.ID, RowContent>> {
    let sink = _ListSelectionSink(single: selection ?? Binding<Data.Element.ID?>.constant(nil))
    self.init {
      ForEach(data) { element in
        _SelectableListRow(id: element.id, sink: sink) { rowContent(element) }
      }
    }
  }

  nonisolated init<Data: RandomAccessCollection, SelectionValue: Hashable, RowContent: View>(
    _ data: Data,
    selection: Binding<Set<SelectionValue>>?,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data.Element: Identifiable, SelectionValue == Data.Element.ID,
          Content == ForEach<Data, Data.Element.ID, _SelectableListRow<Data.Element.ID, RowContent>> {
    let sink = _ListSelectionSink(multiple: selection ?? Binding<Set<Data.Element.ID>>.constant([]))
    self.init {
      ForEach(data) { element in
        _SelectableListRow(id: element.id, sink: sink) { rowContent(element) }
      }
    }
  }

  nonisolated init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    selection: Binding<ID?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Content == ForEach<Data, ID, _SelectableListRow<ID, RowContent>> {
    let sink = _ListSelectionSink(single: selection)
    self.init {
      ForEach(data, id: id) { element in
        _SelectableListRow(id: element[keyPath: id], sink: sink) { rowContent(element) }
      }
    }
  }

  nonisolated init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    selection: Binding<Set<ID>>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Content == ForEach<Data, ID, _SelectableListRow<ID, RowContent>> {
    let sink = _ListSelectionSink(multiple: selection)
    self.init {
      ForEach(data, id: id) { element in
        _SelectableListRow(id: element[keyPath: id], sink: sink) { rowContent(element) }
      }
    }
  }

  /// Embedded lowering target for `List(data, id: \.member)`.
  @_spi(Renderer) init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
    _ data: Data,
    id: @escaping (Data.Element) -> ID,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Content == ForEach<Data, ID, RowContent> {
    self.init { ForEach(data, id: id, content: rowContent) }
  }

  /// Embedded lowering target for `List(data, id: \.member, selection:)`.
  @_spi(Renderer) init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
    _ data: Data,
    id: @escaping (Data.Element) -> ID,
    selection: Binding<ID?>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Content == ForEach<Data, ID, _SelectableListRow<ID, RowContent>> {
    let sink = _ListSelectionSink(single: selection)
    self.init {
      ForEach(data, id: id) { element in
        _SelectableListRow(id: id(element), sink: sink) { rowContent(element) }
      }
    }
  }

  @_spi(Renderer) init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
    _ data: Data,
    id: @escaping (Data.Element) -> ID,
    selection: Binding<Set<ID>>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Content == ForEach<Data, ID, _SelectableListRow<ID, RowContent>> {
    let sink = _ListSelectionSink(multiple: selection)
    self.init {
      ForEach(data, id: id) { element in
        _SelectableListRow(id: id(element), sink: sink) { rowContent(element) }
      }
    }
  }
}

/// Reads and writes either selection shape through typed closures.
public nonisolated struct _ListSelectionSink<ID: Hashable> {
  let isSelected: (ID) -> Bool
  let select: (ID) -> Void

  package init(single binding: Binding<ID?>) {
    isSelected = { binding.wrappedValue == $0 }
    select = { binding.wrappedValue = $0 }
  }

  package init(multiple binding: Binding<Set<ID>>) {
    isSelected = { binding.wrappedValue.contains($0) }
    // A pointer activation selects the row, like a click in a macOS/iPadOS
    // list with a keyboard: the row becomes the single selected element.
    select = { binding.wrappedValue = [$0] }
  }
}

/// A list cell that participates in the enclosing list's selection.
public nonisolated struct _SelectableListRow<ID: Hashable, RowContent: View>: View {
  public typealias Body = Never
  // Not named `id`: a stored member would shadow `View.id(_:)` for chained calls.
  let rowID: ID
  let sink: _ListSelectionSink<ID>
  let row: RowContent

  init(id: ID, sink: _ListSelectionSink<ID>, @ViewBuilder row: () -> RowContent) {
    self.rowID = id
    self.sink = sink
    self.row = row()
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["list-view-row-selectable"]
    let selected = sink.isSelected(rowID)
    node.attributes["role"] = "option"
    node.attributes["aria-selected"] = selected ? "true" : "false"
    node.attributes["tabindex"] = "0"
    if selected { node.attributes["data-selected"] = "true" }
    let sink = self.sink
    let id = self.rowID
    node.events["click"] = _EventHandler(name: "click", action: { sink.select(id) })
    let child = row._render(in: context.child(_FiberKey("row")))
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}
