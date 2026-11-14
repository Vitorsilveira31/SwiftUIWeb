import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures
@_spi(Renderer) @testable import SwiftUIWebFiber

private final class OwnerLifetimeMarker {}
private struct OwnerLifetimeView: View {
  let marker: OwnerLifetimeMarker
  var body: some View { Text("Owner") }
}

@MainActor private final class RetainedEnvironmentModel {
  var label = "resolved model"
}

private struct RetainedEnvironmentReader: View {
  @Environment(RetainedEnvironmentModel.self) private var model
  var body: some View { Text(model.label) }
}

@Suite
@MainActor
final class RenderOwnerLifecycleTests {
  /// A boundary that is not an erased view (a tab's `ForEach` element, a modifier or a reader) builds the views
  /// below it itself. Rendered again on its own, outside any enclosing view's render, they must still resolve an
  /// environment object from the context the owner registered with (this used to trap, and left the layout pass open).
  @Test
  func testRetainedRenderOfABoundaryResolvesEnvironmentObjectsOfItsContext() {
    let registry = _RenderOwnerRegistry()
    var context = _RenderContext()
    context.environment._setEnvironmentObject(RetainedEnvironmentModel())
    context._renderOwnerRegistry = registry
    let token = registry._register(context: context) { active in RetainedEnvironmentReader()._render(in: active) }
    _expectNil(StateRuntime.scope)
    let node = registry._render(token)
    _expectNotNil(node)
    _expectTrue(node?.htmlDescription.contains("resolved model") == true)
    // The scope and environment installed for the render are gone again.
    _expectNil(StateRuntime.scope)
    _expectNil(EnvironmentRuntime.installed)
  }

  @Test
  func testRegistryDoesNotRetainItselfThroughStoredRenderContexts() {
    weak var releasedRegistry: _RenderOwnerRegistry?
    func install() {
      let registry = _RenderOwnerRegistry()
      releasedRegistry = registry
      var context = _RenderContext()
      context._renderOwnerRegistry = registry
      _ = registry._register(context: context) { _ in .empty() }
    }
    install()
    _expectNil(releasedRegistry)
  }

  @Test
  func testRetainedRenderRestoresRegistryForNestedViews() {
    let registry = _RenderOwnerRegistry()
    var context = _RenderContext()
    context._renderOwnerRegistry = registry
    var restored = false
    let token = registry._register(context: context) { [weak registry] active in
      restored = active._renderOwnerRegistry === registry
      return .empty()
    }
    _expectNotNil(registry._render(token))
    _expectTrue(restored)
    registry._removeAll()
    _expectNil(registry._render(token))
  }

  @Test
  func testTreeDisposalReleasesModelCapturedByOwnerRenderers() {
    weak var releasedMarker: OwnerLifetimeMarker?
    func mountAndDispose() {
      let marker = OwnerLifetimeMarker()
      releasedMarker = marker
      let tree = FiberTree(OwnerLifetimeView(marker: marker))
      _expectTrue(tree.renderNode.htmlDescription.contains("Owner"))
    }
    mountAndDispose()
    _expectNil(releasedMarker)
  }
}
