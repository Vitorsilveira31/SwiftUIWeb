import Observation
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

@Observable
final class CorePrimitiveObservationModel {
  var title = "Before"
}

@Suite(.serialized)
@MainActor
struct CoreStateSurfaceTests {
  private final class BindingCapture {
    var value: Binding<Int>?
  }

  private final class ObjectCapture {
    var value: PublishedModel?
  }

  private final class FocusCapture {
    var value: Binding<Bool>?
  }

  private final class PublishedModel: ObservableObject {
    @Published var title = "Before"
  }

  @Test
  func nativePublishedPropertyInvalidatesAnObservedObjectConsumer() async {
    struct ModelView: View {
      @ObservedObject var model: PublishedModel
      var body: some View { Text(model.title) }
    }

    let model = PublishedModel()
    let tree = FiberTree(ModelView(model: model))
    #expect(tree.renderNode.htmlDescription.contains("Before"))
    model.title = "After publication"
    await Task.yield()
    #expect(tree.renderNode.htmlDescription.contains("After publication"))
  }

  @Test
  func publishedPropertyCanBeInitializedByItsOwningModelInitializer() {
    final class Model: ObservableObject {
      @Published var value: Int
      init(value: Int) { self.value = value }
    }

    let model = Model(value: 4)
    var updates: [Int] = []
    model.$value.subscribe { updates.append($0) }

    #expect(model.value == 4)
    model.value = 5
    #expect(updates == [5])
  }


  @Test
  func primitiveErasedOwnerRetainsAndReestablishesNativeObservation() {
    struct PrimitiveReader: View {
      typealias Body = Never
      let model: CorePrimitiveObservationModel
      func _render(in context: _RenderContext) -> _RenderNode {
        Text(model.title)._render(in: context)
      }
    }
    struct Root: View {
      let model: CorePrimitiveObservationModel
      var body: some View { AnyView(PrimitiveReader(model: model)) }
    }

    let model = CorePrimitiveObservationModel()
    let tree = FiberTree(Root(model: model), deferLazyCollections: false, startLifecycle: false)
    var invalidations = 0
    tree.setExternalInvalidationHandler({ invalidations += 1 }, deferUpdates: true)

    model.title = "After first render"
    #expect(invalidations == 1)
    #expect(tree._hasPendingSubtreeInvalidation)
    _ = tree.renderNode
    #expect(tree.root.renderNode.htmlDescription.contains("After first render"))

    model.title = "After retained rerender"
    #expect(invalidations == 2)
    _ = tree.renderNode
    #expect(tree.root.renderNode.htmlDescription.contains("After retained rerender"))
  }

  @Test
  func retainedPrimitiveOwnerRegistersAFreshObservationCallback() throws {
    struct PrimitiveReader: View {
      typealias Body = Never
      let model: CorePrimitiveObservationModel
      func _render(in context: _RenderContext) -> _RenderNode {
        Text(model.title)._render(in: context)
      }
    }

    let model = CorePrimitiveObservationModel()
    let store = StateStore()
    let registry = _RenderOwnerRegistry()
    var invalidations = 0
    store.setInvalidationHandler { invalidations += 1 }
    var context = _RenderContext(stateStore: store)
    context._renderOwnerRegistry = registry

    let initial = AnyView(PrimitiveReader(model: model))._render(in: context)
    let owner = try #require(initial._renderOwnerToken)
    #expect(registry._contains(owner))

    model.title = "Initial observer"
    #expect(invalidations == 1)
    #expect(registry._render(owner)?.htmlDescription.contains("Initial observer") == true)

    model.title = "Retained observer"
    #expect(invalidations == 2)
    #expect(store._observationOwnerTokens() == [owner])
  }

  @Test
  func stateSlotCollisionPreservesBothBoxesUnderDeterministicKeys() {
    let store = StateStore()
    let first = store.register(StateBox("wifi"), key: "settings")
    let secondCandidate = StateBox("bluetooth")

    let second = store.register(secondCandidate, key: "settings")
    let collisionSlot = store.box("settings@state1", default: "unexpected")

    #expect(first.value == "wifi")
    #expect(second.value == "bluetooth")
    #expect(collisionSlot === second)
  }

  @Test
  func supplementalAndSubtreePassesPreserveSourceClassificationAndDisposeGuards() {
    let store = StateStore()
    let structural = _StateSourceID(rawValue: 80)
    let supplemental = _StateSourceID(rawValue: 81)
    let leaf = _StateSourceID(rawValue: 82)

    store._beginRenderPass()
    store._recordRead(structural)
    store._endRenderPass(provenLeafSources: [])
    #expect(store._isStructural(structural))

    store._beginSupplementalRenderPass()
    store._recordRead(supplemental)
    store._endSupplementalRenderPass(provenLeafSources: [])
    #expect(store._isStructural(supplemental))

    store._beginSubtreeRenderPass(replacing: [])
    store._creditLeafRead(leaf)
    store._recordRead(leaf)
    store._endSubtreeRenderPass(provenLeafSources: [leaf])
    #expect(store._isStructural(leaf) == false)
    #expect(store._hasStateStorage() == false)

    store._dispose()
    store._beginRenderPass()
    store._beginSupplementalRenderPass()
    store._beginSubtreeRenderPass(replacing: [1])
    store._recordRead(structural)
    store._recordPublishedObservation(supplemental)
    store._recordEnvironmentRead()
    store._creditLeafRead(leaf)
    store._endRenderPass(provenLeafSources: [])
    store._endSupplementalRenderPass(provenLeafSources: [])
    store._endSubtreeRenderPass(provenLeafSources: [])
    store._clearObservationInvalidation()
    store._clearDirtySources()
    #expect(store._observationDiagnostics.accessCount == 0)
    #expect(store._observationDiagnostics.teardownCount == 1)
  }

  @Test
  func aFreshWrapperReusesItsExistingFiberSlotWithoutReplacingTheStoredValue() {
    let store = StateStore()
    let registered = store.box("settings.mode", default: "compact")
    let freshWrapper = StateBox("wide")

    let restored = store.register(freshWrapper, key: "settings.mode", reuseMatchingSlot: true)

    #expect(restored === registered)
    #expect(restored.value == "compact")
  }

  @Test
  func registeringTheSameStateBoxAtAnotherPathKeepsItsOriginalIdentity() {
    let store = StateStore()
    let box = StateBox("enabled")
    let first = store.register(box, key: "settings.wifi")
    let reused = store.register(box, key: "settings.bluetooth")

    #expect(reused === first)
    #expect(reused.value == "enabled")
    #expect(store._hasStateStorage())
    #expect(store.box("settings.bluetooth", default: "off").value == "off")
  }

  @Test
  func stateMutationCarriesAndDrainsTheActiveAnimationTransaction() throws {
    struct Counter: View {
      @State var value = 0
      let capture: BindingCapture
      var body: some View {
        capture.value = $value
        return Text("Value \(value)")
      }
    }

    let capture = BindingCapture()
    let view = Counter(capture: capture)
    let tree = FiberTree(view)
    let binding = try #require(capture.value)
    let store = try #require(binding._sourceStore)

    withAnimation(.linear(duration: 0.4)) {
      binding.wrappedValue = 1
    }
    let first = try #require(store._takeAnimationTransactionCSS())
    #expect(!first.isEmpty)
    #expect(store._takeAnimationTransactionCSS() == nil)
    #expect(tree.renderNode.htmlDescription.contains("Value 1"))

    withAnimation(nil) {
      binding.wrappedValue = 2
    }
    #expect(store._takeAnimationTransactionCSS() == "none")
    #expect(tree.renderNode.htmlDescription.contains("Value 2"))
  }

  @Test
  func environmentObjectPublisherAndProjectionShareTheProvidedInstance() async {
    struct Reader: View {
      @EnvironmentObject var model: PublishedModel
      let capture: ObjectCapture
      var body: some View {
        capture.value = $model
        return Text(model.title)
      }
    }

    let model = PublishedModel()
    let capture = ObjectCapture()
    let tree = FiberTree(Reader(capture: capture).environmentObject(model))
    #expect(tree.renderNode.htmlDescription.contains("Before"))
    #expect(capture.value === model)
    model.title = "Shared environment model"
    await Task.yield()
    #expect(tree.renderNode.htmlDescription.contains("Shared environment model"))
  }

  @Test
  func focusStateCreatedDuringBodyUsesAndInvalidatesItsOwningStore() throws {
    struct FocusReader: View {
      let capture: FocusCapture

      var body: some View {
        let focus = FocusState<Bool>()
        capture.value = focus.projectedValue.binding
        return Text(focus.wrappedValue ? "Focused" : "Not focused")
          .focused(focus.projectedValue)
      }
    }

    let capture = FocusCapture()
    let tree = FiberTree(FocusReader(capture: capture))
    let binding = try #require(capture.value)
    #expect(binding._sourceStore != nil)
    #expect(tree.renderNode.htmlDescription.contains("Not focused"))

    binding.wrappedValue = true

    #expect(tree.renderNode.htmlDescription.contains("Focused"))
  }
}
