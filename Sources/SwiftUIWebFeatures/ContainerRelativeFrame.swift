@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// SwiftUI's `containerRelativeFrame` family.
///
/// The frame's length along each selected axis is a function of the nearest
/// container's size — the enclosing scroll view's visible size, a navigation
/// column, or the window/presentation root. Only the layout knows
/// that size (the browser measures the root and propagates proposals), so
/// Swift describes the length function as a small piecewise-linear table:
///
/// - `count:span:spacing:` is exactly linear:
///   `((length - spacing * (count - 1)) / count) * span + spacing * (span - 1)`;
/// - the closure form is sampled at fixed container lengths and interpolated.
///   Linear and clamped (`min`/`max`) closures are reproduced exactly within
///   the sampled range; arbitrary curves are approximated between samples.
///
/// Along an unselected axis the view keeps its own size, like SwiftUI.
public extension View {
  nonisolated func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center) -> some View {
    modifier(ContainerRelativeFrameModifier(axes: axes, alignment: alignment, samples: { _ in [(0, 0), (1000, 1000)] }))
  }

  nonisolated func containerRelativeFrame(_ axes: Axis.Set, count: Int, span: Int = 1, spacing: CGFloat, alignment: Alignment = .center) -> some View {
    let count = Double(max(1, count))
    let span = Double(max(1, span))
    let spacing = Double(spacing)
    let length: (Double) -> Double = { container in
      ((container - spacing * (count - 1)) / count) * span + spacing * (span - 1)
    }
    return modifier(ContainerRelativeFrameModifier(axes: axes, alignment: alignment, samples: { _ in
      [(0, length(0)), (1000, length(1000))]
    }))
  }

  nonisolated func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center, _ length: @escaping (CGFloat, Axis) -> CGFloat) -> some View {
    modifier(ContainerRelativeFrameModifier(axes: axes, alignment: alignment, samples: { axis in
      _containerRelativeSampleLengths.map { ($0, Double(length(CGFloat($0), axis))) }
    }))
  }
}

/// Container lengths at which a closure-form length function is sampled.
/// They cover phone, tablet, desktop and wide-display surfaces.
private let _containerRelativeSampleLengths: [Double] = [0, 160, 320, 480, 640, 800, 1024, 1280, 1600, 2048, 2560, 3840]

package nonisolated struct ContainerRelativeFrameModifier: ViewModifier {
  let axes: Axis.Set
  let alignment: Alignment
  let samples: (Axis) -> [(Double, Double)]

  init(axes: Axis.Set, alignment: Alignment, samples: @escaping (Axis) -> [(Double, Double)]) {
    self.axes = axes
    self.alignment = alignment
    self.samples = samples
  }

  /// Semantic metadata consumed by the browser layout host.
  var _semanticAttributes: _NodeValues {
    var attributes = _semanticAlignment(alignment)
    attributes["data-layout-kind"] = "container-relative"
    if axes.contains(.horizontal) { attributes["data-relative-w"] = Self._encode(samples(.horizontal)) }
    if axes.contains(.vertical) { attributes["data-relative-h"] = Self._encode(samples(.vertical)) }
    return attributes
  }

  @MainActor package func _apply(to node: _RenderNode, context: inout _RenderContext) {
    StyleModifier(styles: .init(), semantic: _semanticAttributes)._apply(to: node, context: &context)
  }

  private static func _encode(_ samples: [(Double, Double)]) -> String {
    samples.map { sample in
      let value = sample.1.isFinite ? sample.1 : 0
      return _semanticNumber(sample.0) + ":" + _semanticNumber(value)
    }.joined(separator: ";")
  }
}
