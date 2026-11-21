@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

public extension List {
  /// `List(selection: $selection) { NavigationLink(value: ...) ... }`: a sidebar. Links select their value.
  nonisolated init<SelectionValue: Hashable>(
    selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content
  ) {
    self.init(content: content)
    guard let selection else { return }
    _selection = _ListSelection(
      select: { value in if let selected: SelectionValue = value.read() { selection.wrappedValue = selected } },
      isSelected: { value in
        guard let selected: SelectionValue = value.read(), let current = selection.wrappedValue else { return false }
        return selected == current
      }
    )
  }

  nonisolated init<SelectionValue: Hashable>(
    selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content
  ) {
    self.init(content: content)
    guard let selection else { return }
    _selection = _ListSelection(
      select: { value in
        guard let selected: SelectionValue = value.read() else { return }
        if selection.wrappedValue.contains(selected) { selection.wrappedValue.remove(selected) } else { selection.wrappedValue.insert(selected) }
      },
      isSelected: { value in
        guard let selected: SelectionValue = value.read() else { return false }
        return selection.wrappedValue.contains(selected)
      }
    )
  }
}

/// A row that selects `value` when clicked, inside a `List(selection:)`.
public nonisolated struct _ListSelectionRow<Value: Hashable, Content: View>: View {
  public typealias Body = Never
  let value: Value
  let content: Content

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["list-view-row"]
    node.attributes["role"] = "option"
    let runtime = _RuntimeValue(value)
    if let selection = context.environment[_ListSelectionKey.self] {
      node.events["click"] = _EventHandler(name: "click", action: { selection.select(runtime) })
      if selection.isSelected(runtime) {
        node.attributes["aria-selected"] = "true"
        node.attributes["data-selected"] = "true"
        node.classes.append("item-selected")
      }
    }
    let child = content._render(in: context)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

public extension Section where Header == EmptyView, Footer == EmptyView {
  /// `Section { rows }`: no header, no footer.
  init(@ViewBuilder content: () -> Content) {
    self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
  }
}

public extension ShapeStyle {
  var tertiary: some ShapeStyle { opacity(0.3) }

  var quaternary: some ShapeStyle { opacity(0.18) }

  var quinary: some ShapeStyle { opacity(0.1) }
}

/// A shape style that also casts a shadow. The paint is the base style; the shadow is not drawn in the browser.
public struct _ShadowShapeStyle<Base: ShapeStyle>: ShapeStyle {
  let base: Base
  // Not named `shadow`: a stored member would shadow `ShapeStyle.shadow(_:)` for chained calls.
  let shadowStyle: ShadowStyle

  public var _swiftUIWebCSSValue: String { base._swiftUIWebCSSValue }
  public var _swiftUIWebSolidColor: Color? { base._swiftUIWebSolidColor }
  public var _swiftUIWebShadow: ShadowStyle? { shadowStyle }
}

public extension ShapeStyle {
  func shadow(_ shadow: ShadowStyle) -> _ShadowShapeStyle<Self> { _ShadowShapeStyle(base: self, shadowStyle: shadow) }
}

public extension ShapeStyle where Self == _ShadowShapeStyle<Color> {
  /// `.background(.shadow(.drop(...)), in: shape)`: the shape is painted in the page's own background color, so the
  /// only thing that shows is the shadow it casts.
  static func shadow(_ shadow: ShadowStyle) -> _ShadowShapeStyle<Color> {
    _ShadowShapeStyle(base: Color(css: "Canvas"), shadowStyle: shadow)
  }
}

public enum Prominence: Hashable, Sendable {
  case standard, increased
}

public extension View {
  /// The tint of a list row's icon, over the app's tint (`--list-item-tint`): Food Truck's city rows in the sidebar,
  /// `.listItemTint(.secondary)`, have grey icons, as on iPad. nil leaves the row's icon in the app's tint.
  nonisolated func listItemTint(_ tint: Color?) -> some View {
    modifier(_SemanticCompatibilityModifier(styles: tint.map { ["--list-item-tint": $0.cssValue] } ?? .init()))
  }

  nonisolated func headerProminence(_ prominence: Prominence) -> Self { self }

  /// The number of grid columns the cell spans. The grid's placement widens the spanned columns (see `_gridColumnWidths`).
  nonisolated func gridCellColumns(_ count: Int) -> some View {
    // At most 1 000 columns: a count from data would otherwise overflow the column arithmetic (Int is 32 bits in the
    // browser build) or ask for a grid of a billion tracks.
    modifier(GridCellModifier(name: "data-grid-cell-columns", value: String(min(max(1, count), 1_000))))
  }

  /// Where a grid cell anchors itself in its slot. The grid places cells itself and reads this attribute.
  nonisolated func gridCellAnchor(_ anchor: UnitPoint) -> some View {
    modifier(GridCellModifier(name: "data-grid-cell-anchor", value: "\(anchor.x),\(anchor.y)"))
  }

  /// The axes on which the cell does not contribute to its column or row size; it fills the slot on them instead.
  nonisolated func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View {
    modifier(GridCellModifier(name: "data-grid-unsized-axes", value: String(axes.rawValue)))
  }

  /// The horizontal alignment of the whole column this cell belongs to, overriding the grid's alignment.
  nonisolated func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
    modifier(GridCellModifier(name: "data-grid-column-alignment", value: guide.cssValue))
  }

  /// The style `.background()` and `background(in:)` paint inside this view: a custom property the views inside inherit,
  /// as they inherit the environment value in SwiftUI (`BackgroundStyle`).
  nonisolated func backgroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    modifier(_SemanticCompatibilityModifier(attributes: [:], styles: ["--swu-background-style": style._swiftUIWebCSSValue]))
  }
}

/// Writes one grid attribute onto the cell. Kept as a modifier so the value flows through nested views to the grid row
/// that places the cell.
package nonisolated struct GridCellModifier: ViewModifier {
  package let name: String
  package let value: String
  package init(name: String, value: String) { self.name = name; self.value = value }
  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes[name] = value
  }
}

/// The menu a title opens (`.toolbar { ToolbarTitleMenu { ... } }`), shown next to the title.
public nonisolated struct ToolbarTitleMenu<Content: View>: CustomizableToolbarContent {
  public typealias Body = Never
  let content: Content

  public nonisolated init(@ViewBuilder content: () -> Content) { self.content = content() }
  public nonisolated init() where Content == EmptyView { content = EmptyView() }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    ToolbarItem(placement: .principal) {
      Menu {
        content
      } label: {
        Image(systemName: "chevron.down")
      }
      .buttonStyle(.plain)
    }
    ._render(in: context)
  }
}

public nonisolated struct BorderlessButtonMenuStyle: MenuStyle {
  public nonisolated init() {}
  public var _swiftUIWebMenuStyle: String { "borderlessButton" }
}

public extension MenuStyle where Self == BorderlessButtonMenuStyle {
  static nonisolated var borderlessButton: BorderlessButtonMenuStyle { BorderlessButtonMenuStyle() }
}

public extension View {
  nonisolated func menuStyle<S: MenuStyle>(_ style: S) -> some View { self }
}

public extension View {
  /// `menuIndicator(_:)`: whether a menu draws its disclosure arrow; the browser menus draw their own.
  nonisolated func menuIndicator(_ visibility: Visibility) -> some View { self }
}
