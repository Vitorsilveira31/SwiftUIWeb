// Browser implementation for SwiftUI-shaped PhaseAnimator and
// KeyframeAnimator metadata.  The Core renderer owns the timeline and emits
// semantic style frames; this file is the only place that knows how to hand
// those frames to a browser animation engine.

@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@_spi(Renderer) import SwiftUIWebFeatures

/// Native/WASI hosts retain semantic attributes but have no browser animation
/// engine. Keeping this no-op type makes BrowserSession's feature wiring
/// conditional without leaking platform details into Core.
final class BrowserAdvancedAnimationBackend {
  func synchronize(document: Any) { _ = document }
  func dispose() {}
}
