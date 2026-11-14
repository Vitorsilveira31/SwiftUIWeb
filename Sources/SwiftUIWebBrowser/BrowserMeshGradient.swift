#if !SWIFTUIWEB_RELEASE || SWIFTUIWEB_RELEASE_HAS_MESH_GRADIENT
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

final class BrowserMeshGradientBackend {
  func synchronize(document: Any) { _ = document }
  func dispose() {}
}
#endif
