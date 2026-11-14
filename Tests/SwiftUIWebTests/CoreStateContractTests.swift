import Testing
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite(.serialized)
@MainActor
struct CoreStateContractTests {
  private final class BindingCapture {
    var binding: Binding<Int>?
  }

  private final class Model: ObservableObject {
    var title: String

    init(title: String) { self.title = title }

    func rename(_ title: String) {
      self.title = title
      objectWillChange.send()
    }
  }

  @Test
  func stateObjectRetainsAndObservesItsModelAndProjectsWritableMembers() async {
    struct ModelView: View {
      @StateObject private var model: Model

      init(model: Model) { _model = StateObject(wrappedValue: model) }

      var body: some View { Text(model.title) }
    }

    let model = Model(title: "Draft")
    let tree = FiberTree(ModelView(model: model))
    #expect(tree.renderNode.htmlDescription.contains("Draft"))

    model.rename("Published")
    await _settleObservedRefreshes()
    #expect(tree.renderNode.htmlDescription.contains("Published"))

    let stateObject = StateObject(wrappedValue: model)
    #expect(stateObject.wrappedValue === model)
    let title = stateObject.projectedValue[dynamicMember: \.title]
    #expect(title.wrappedValue == "Published")
    title.wrappedValue = "Edited"
    #expect(model.title == "Edited")
  }

  @Test
  func stateObjectCreatedDuringBodyEvaluationIsRetainedByItsViewIdentity() {
    final class CreationCounter {
      var count = 0
    }
    final class ScopedModel {
      let title: String
      init(_ title: String) { self.title = title }
    }
    struct ScopedModelView: View {
      let creations: CreationCounter

      var body: some View {
        let model = StateObject(wrappedValue: {
          creations.count += 1
          return ScopedModel("Retained model")
        }())
        return Text(model.wrappedValue.title)
      }
    }

    let creations = CreationCounter()
    let view = ScopedModelView(creations: creations)
    let tree = FiberTree(view)
    #expect(tree.renderNode.htmlDescription.contains("Retained model"))
    #expect(creations.count == 1)

    _ = tree.update(view)
    #expect(tree.renderNode.htmlDescription.contains("Retained model"))
    #expect(creations.count == 1)
  }

  @Test
  func gestureStateKeepsItsFiberSlotWhenReadFromAViewBody() {
    struct GestureStateView: View {
      @GestureState var progress = 4
      var body: some View { Text("Progress: \(progress)") }
    }

    let view = GestureStateView()
    let tree = FiberTree(view)
    #expect(tree.renderNode.htmlDescription.contains("Progress: 4"))
    _ = tree.update(view)
    #expect(tree.renderNode.htmlDescription.contains("Progress: 4"))
  }

  @Test
  func gestureStateSupportsExplicitInitializationMutationAndReset() {
    var state = GestureState(wrappedValue: 2)
    #expect(state.wrappedValue == 2)
    state.wrappedValue = 7
    #expect(state.wrappedValue == 7)
    state.wrappedValue = 4
    #expect(state.wrappedValue == 4)
  }

  @Test
  func observedObjectAndBindableExposeWritableMemberBindings() {
    let model = Model(title: "Before")

    var observed = ObservedObject(wrappedValue: model)
    #expect(observed.wrappedValue === model)
    let observedTitle = observed.projectedValue[dynamicMember: \.title]
    #expect(observedTitle.wrappedValue == "Before")
    observedTitle.wrappedValue = "Observed edit"
    #expect(model.title == "Observed edit")
    let replacement = Model(title: "Replacement")
    observed.wrappedValue = replacement
    #expect(observed.wrappedValue === replacement)

    let bindable = Bindable(wrappedValue: model)
    #expect(bindable.projectedValue.wrappedValue === model)
    let bindableTitle = bindable[dynamicMember: \.title]
    #expect(bindableTitle.wrappedValue == "Observed edit")
    bindableTitle.wrappedValue = "Bindable edit"
    #expect(model.title == "Bindable edit")

    bindable.wrappedValue = replacement
    #expect(bindable.wrappedValue === replacement)
    bindable[dynamicMember: \.title].wrappedValue = "Replacement edit"
    #expect(replacement.title == "Replacement edit")
  }

  @Test
  func focusStateProvidesBooleanAndOptionalDefaultsAndWritableProjectedBindings() {
    let booleanFocus = FocusState<Bool>()
    #expect(booleanFocus.wrappedValue == false)
    booleanFocus.wrappedValue = true
    #expect(booleanFocus.projectedValue.wrappedValue)
    booleanFocus.projectedValue.wrappedValue = false
    #expect(!booleanFocus.wrappedValue)

    let optionalFocus = FocusState<Int?>()
    #expect(optionalFocus.wrappedValue == nil)
    optionalFocus.wrappedValue = 7
    #expect(optionalFocus.projectedValue.wrappedValue == 7)
    optionalFocus.projectedValue.wrappedValue = nil
    #expect(optionalFocus.wrappedValue == nil)
  }

  @Test
  func publishedIndexDiagnosticsPreserveTheirExplicitValues() {
    let index = _PublishedObservationIndexDiagnostics(sourceCount: 2, storeLinks: 3)
    #expect(index.sourceCount == 2)
    #expect(index.storeLinks == 3)
  }

  @Test
  func stateSourceAndObservationDiagnosticsPreserveTheirExplicitValues() {
    #expect(_StateSourceID(rawValue: 9) == _StateSourceID(rawValue: 9))
    #expect(_StateSourceID.environment.rawValue == UInt64.max)

    let diagnostics = _StateStoreObservationDiagnostics(
      accessCount: 4,
      invalidationCount: 3,
      coalescedInvalidationCount: 2,
      teardownCount: 1,
      isDisposed: true
    )
    #expect(diagnostics.accessCount == 4)
    #expect(diagnostics.invalidationCount == 3)
    #expect(diagnostics.coalescedInvalidationCount == 2)
    #expect(diagnostics.teardownCount == 1)
    #expect(diagnostics.isDisposed)
  }

  @Test
  func bindingsMapValuesProjectMembersAndMutateCollectionElements() {
    struct Settings { var retryCount: Int }

    var settings = Settings(retryCount: 2)
    let settingsBinding = Binding<Settings>(get: { settings }, set: { settings = $0 })
    let retryCount = settingsBinding[dynamicMember: \.retryCount]
    #expect(retryCount.wrappedValue == 2)
    retryCount.wrappedValue = 5
    #expect(settings.retryCount == 5)
    #expect(retryCount.projectedValue.wrappedValue == 5)

    let doubled = settingsBinding.map(
      get: { $0.retryCount * 2 },
      set: { value, newValue in
        var updated = value
        updated.retryCount = newValue / 2
        settings = updated
      }
    )
    #expect(doubled.wrappedValue == 10)
    doubled.wrappedValue = 14
    #expect(settings.retryCount == 7)

    var values = [3, 6, 9]
    let valuesBinding = Binding<[Int]>(get: { values }, set: { values = $0 })
    let middle = valuesBinding[1]
    #expect(middle.wrappedValue == 6)
    middle.wrappedValue = 8
    #expect(values == [3, 8, 9])

    let constant = Binding.constant("fixed")
    constant.wrappedValue = "ignored"
    #expect(constant.wrappedValue == "fixed")
  }

  @Test
  func stateSourceSubscriptionsFilterChangesCancelAndStopAtTeardown() {
    struct CounterView: View {
      @State private var count = 0
      let capture: BindingCapture

      var body: some View {
        ZStack {
          captureBinding($count)
          Text("Count: \(count)")
        }
      }

      private func captureBinding(_ binding: Binding<Int>) -> EmptyView {
        capture.binding = binding
        return EmptyView()
      }
    }

    let capture = BindingCapture()
    let view = CounterView(capture: capture)
    let tree = FiberTree(view)
    guard let binding = capture.binding else {
      Issue.record("The state view should expose its binding while rendering")
      return
    }
    guard let source = binding._sourceID, let store = binding._sourceStore else {
      Issue.record("A rendered @State binding must carry its source and owning store")
      return
    }

    let unrelatedSource = _StateSourceID(rawValue: source.rawValue &+ 1)
    var matchingCalls = 0
    var unrelatedCalls = 0
    let subscription = store._subscribe(source) { matchingCalls += 1 }
    let unrelated = store._subscribe(unrelatedSource) { unrelatedCalls += 1 }

    binding.wrappedValue = 1
    #expect(matchingCalls == 1)
    #expect(unrelatedCalls == 0)
    #expect(tree.renderNode.htmlDescription.contains("Count: 1"))

    subscription.cancel()
    subscription.cancel()
    binding.wrappedValue = 2
    #expect(matchingCalls == 1)
    #expect(unrelatedCalls == 0)

    unrelated.cancel()
    store._dispose()
    var callsAfterDispose = 0
    let afterDispose = store._subscribe(source) { callsAfterDispose += 1 }
    binding.wrappedValue = 3
    #expect(matchingCalls == 1)
    #expect(callsAfterDispose == 0)
    afterDispose.cancel()
    #expect(store._isDisposed)
    #expect(store._observationDiagnostics.teardownCount == 1)
  }
}
