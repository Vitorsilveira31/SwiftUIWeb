import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite(.serialized)
@MainActor
final class StateContractTests {
  // The next tests drive SwiftUIWeb's own `ObservableObjectPublisher`/`@Published` (Embedded and WASI); native builds use
  // Combine's types, which have no such subscribe/projection API.
  @Test
  func publisherFanoutAndObservableObjectPublisherIdentityAreStable() {
    final class Model: ObservableObject {}

    let model = Model()
    let first = model.objectWillChange
    let second = model.objectWillChange
    #expect(first === second)

    var firstCalls = 0
    var secondCalls = 0
    first.subscribe { firstCalls += 1 }
    first.subscribe { secondCalls += 1 }
    first.send()
    first.send()
    #expect(firstCalls == 2)
    #expect(secondCalls == 2)
  }


  @Test
  func retiredRenderOwnerRetainsOnlyItsStructuralPath() {
    let registry = _RenderOwnerRegistry()
    let path = [_FiberKey("canvas"), _FiberKey("node-7")]
    let context = _RenderContext(path: path, stateStore: StateStore())
    let token = registry._register(context: context) { _ in .empty() }

    registry._remove(token)

    #expect(registry._ownerPath(token)?.keys == path)
    #expect(!registry._contains(token))
    registry._removeAll(keepingCapacity: false)
    #expect(registry._ownerPath(token) == nil)
  }

  @Test
  func publishedValueEmitsOnlyAfterAWriteAndKeepsItsProjectedPublisher() {
    // `@Published` is only available on class properties, as in Combine.
    final class Model: ObservableObject {
      @Published var value = 1
    }
    let model = Model()
    var received: [Int] = []
    model.$value.subscribe { received.append($0) }

    #expect(model.value == 1)
    #expect(received.isEmpty)
    model.value = 2
    model.value = 3
    #expect(received == [2, 3])

    // Copies of the projected publisher share their observers.
    let copy = model.$value
    var copied: [Int] = []
    copy.subscribe { copied.append($0) }
    model.value = 4
    #expect(received == [2, 3, 4])
    #expect(copied == [4])
  }

  @Test
  func publishedMemberWithoutDeclarationValueCanBeInitializedByModelInit() {
    final class Model: ObservableObject {
      @Published(memberID: 1) private(set) var state: String

      init(state: String) {
        self.state = state
      }
    }

    #expect(Model(state: "ready").state == "ready")
  }


  @Test
  func stateSubscriptionCancelsAtMostOnceIncludingDeinit() {
    var cancellationCount = 0
    do {
      let subscription = _StateSubscription { cancellationCount += 1 }
      subscription.cancel()
      subscription.cancel()
      #expect(cancellationCount == 1)
    }
    #expect(cancellationCount == 1)

    do {
      _ = _StateSubscription { cancellationCount += 1 }
    }
    #expect(cancellationCount == 2)
  }

  @Test
  func stateStoreObservationDiagnosticsTrackAccessInvalidationAndDispose() {
    let store = StateStore()
    let source = _StateSourceID(rawValue: 7)
    store._beginRenderPass()
    store._recordPublishedObservation(source)
    store._endRenderPass(provenLeafSources: [])
    #expect(store._observationDiagnostics.accessCount == 1)

    store._ownerObservationDidChange(42)
    let pending = store._observationDiagnostics
    #expect(pending.invalidationCount == 1)
    #expect(pending.coalescedInvalidationCount == 0)
    #expect(store._hasPendingObservationInvalidation())
    #expect(store._observationOwnerTokens() == [42])

    store._ownerObservationDidChange(42)
    #expect(store._observationDiagnostics.coalescedInvalidationCount == 1)
    store._clearObservationInvalidation()
    #expect(!store._hasPendingObservationInvalidation())

    store._dispose()
    store._dispose()
    let disposed = store._observationDiagnostics
    #expect(disposed.isDisposed)
    #expect(disposed.teardownCount == 1)
    #expect(store._observationOwnerTokens().isEmpty)
  }

  @Test
  func sharedPublishedObservationFansOutSeparatelyFromStateInvalidation() {
    let store = StateStore()
    let observedSource = _StateSourceID(rawValue: 81)
    let secondObservedSource = _StateSourceID(rawValue: 83)
    let stateSource = _StateSourceID(rawValue: 82)
    store._dependencies.beginPass(.root)
    store._dependencies.observationAccess(observedSource, owner: 11)
    store._dependencies.observationAccess(observedSource, owner: 12)
    store._dependencies.observationAccess(secondObservedSource, owner: 13)
    store._dependencies.recordRead(stateSource, owner: 22)
    store._dependencies.endPass(provenLeafSources: [])

    store._publishedObservationDidChange(observedSource)
    store._publishedObservationDidChange(secondObservedSource)
    store._dependencies.markDirty(stateSource)

    #expect(store._dirtyPublishedObservationOwnerGroups() == [
      observedSource.rawValue: Set([11, 12]),
      secondObservedSource.rawValue: Set([13])
    ])
    #expect(store._dirtyPublishedObservationOwnerTokens() == Set([11, 12, 13]))
    #expect(store._dirtyStateSubtreeOwnerTokens() == Set([22]))
    store._clearDirtySources()
    #expect(store._dirtyPublishedObservationOwnerGroups() == [:])
    #expect(store._dirtyPublishedObservationOwnerTokens() == Set<UInt64>())
  }
}
