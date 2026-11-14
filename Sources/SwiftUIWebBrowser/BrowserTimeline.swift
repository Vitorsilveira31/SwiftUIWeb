// Browser realization of SwiftUI-shaped TimelineView schedules.  The core
// module emits only a renderer-neutral descriptor; this file is the sole place
// that knows about requestAnimationFrame, timeout handles and DOM connectivity.

@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

