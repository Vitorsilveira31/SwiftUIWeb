@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

// `chartPlotStyle`, `chartOverlay` and `chartBackground`. A chart reads the
// plot-style closure from the environment and renders its plot through it, so
// the modifier works on a `Chart` or on any view that contains one.

/// The chart's plot, handed to the `chartPlotStyle` closure to be styled with
/// ordinary view modifiers. Without a layout engine for the plot rectangle,
/// the modifiers apply to the whole rendered chart (plot, axes and legend).
public struct ChartPlotContent: View {
  public typealias Body = Never
  let rendered: _RenderNode
  public func _render(in context: _RenderContext) -> _RenderNode { rendered }
}

/// Handed to `chartOverlay` and `chartBackground` content. The browser
/// realization draws marks directly, so there are no scale lookups to offer.
public struct ChartProxy {}

struct _ChartPlotStyleBox {
  let apply: (@MainActor (ChartPlotContent) -> AnyView)?
}

enum _ChartPlotStyleKey: EnvironmentKey {
  static let defaultValue = _ChartPlotStyleBox(apply: nil)
}

extension View {
  /// Styles the plot area of every chart in this view.
  nonisolated public func chartPlotStyle<Content: View>(@ViewBuilder content: @escaping (ChartPlotContent) -> Content) -> some View {
    nonisolated(unsafe) let content = content
    return _environment(_ChartPlotStyleKey.self, _ChartPlotStyleBox(apply: { AnyView(content($0)) }))
  }

  /// Layers a view over the chart.
  nonisolated public func chartOverlay<Overlay: View>(alignment: Alignment = .center, @ViewBuilder content: @escaping (ChartProxy) -> Overlay) -> some View {
    overlay(alignment: alignment) { content(ChartProxy()) }
  }

  /// Layers a view behind the chart.
  nonisolated public func chartBackground<Background: View>(alignment: Alignment = .center, @ViewBuilder content: @escaping (ChartProxy) -> Background) -> some View {
    background(alignment: alignment) { content(ChartProxy()) }
  }
}
