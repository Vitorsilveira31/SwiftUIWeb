#if !SWIFTUIWEB_RELEASE || SWIFTUIWEB_RELEASE_HAS_DRAGDROP
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

final class BrowserDragDropController {
  func synchronize(document: Any, resolveNode: @escaping (String) -> _RenderNode?, requestRefresh: @escaping () -> Void) { _ = document; _ = resolveNode; _ = requestRefresh }
  func releaseAll() {}
}
#endif
