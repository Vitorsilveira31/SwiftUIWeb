import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures

private enum RuntimeOptionalKey: EnvironmentKey {
  static var defaultValue: String? { "fallback" }
}
private enum RuntimeArrayKey: EnvironmentKey {
  static var defaultValue: [Int] { [] }
}
private final class RuntimeEnvironmentModel { let number: Int; init(_ number: Int) { self.number = number } }
private enum RuntimeSumPreference: PreferenceKey {
  static var defaultValue: Int { 0 }
  static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}
private enum RuntimeOptionalPreference: PreferenceKey {
  static func reduce(value: inout String?, nextValue: () -> String?) {
    value = nextValue() ?? value
  }
}

@Suite
@MainActor
final class TypedRuntimeStorageTests {
  @Test
  func testOptionalEnvironmentValueCanOverrideNonNilDefaultWithNil() {
    var environment = EnvironmentValues()
    _expectEqual(environment[RuntimeOptionalKey.self], "fallback")
    environment[RuntimeOptionalKey.self] = nil
    _expectNil(environment[RuntimeOptionalKey.self])
  }

  @Test
  func testEnvironmentCopiesDoNotShareMutableSlots() {
    var first = EnvironmentValues()
    first[RuntimeArrayKey.self] = [1, 2]
    var second = first
    second[RuntimeArrayKey.self].append(3)
    _expectEqual(first[RuntimeArrayKey.self], [1, 2])
    _expectEqual(second[RuntimeArrayKey.self], [1, 2, 3])
    _expectEqual(second._revision, first._revision + 1)
  }

  @Test
  func testTypedEnvironmentModelKeepsIdentity() {
    let previous = EnvironmentRuntime.installed
    defer { EnvironmentRuntime.installed = previous }
    let model = RuntimeEnvironmentModel(8)
    var environment = EnvironmentValues()
    environment._setEnvironmentObject(model)
    EnvironmentRuntime.current = environment
    let wrapper = Environment(RuntimeEnvironmentModel.self)
    _expectTrue(wrapper.wrappedValue === model)
  }

  @Test
  func testOptionalOnChangeHistoryDistinguishesMissingAndNil() {
    let store = StateStore()
    let first = store.rememberChange("optional", value: Optional<Int>.none)
    let unchanged = store.rememberChange("optional", value: Optional<Int>.none)
    let changed = store.rememberChange("optional", value: Optional(3))
    _expectTrue(first.initial)
    _expectFalse(unchanged.initial)
    _expectFalse(unchanged.changed)
    _expectTrue(changed.changed)
    _expectNotNil(changed.previous as Any?)
    _expectNil(changed.previous!)
  }

  @Test
  func testPreferencePassesKeepIndependentSnapshots() {
    let store = _PreferenceStore()
    store.beginPass()
    for n in 1...1000 { store.write(n, for: RuntimeSumPreference.self) }
    _expectEqual(store.value(for: RuntimeSumPreference.self), 500500)
    store.beginPass()
    store.write(7, for: RuntimeSumPreference.self)
    _expectEqual(store.value(for: RuntimeSumPreference.self), 7)
    _expectEqual(store.previousValue(for: RuntimeSumPreference.self), 500500)
    _expectTrue(store.changed(for: RuntimeSumPreference.self))
  }

  @Test
  func testTypedSlotRejectsDifferentTypeAndReleasesObjects() {
    var values = _TypedValueStorage<Int>()
    weak var released: RuntimeEnvironmentModel?
    do {
      let model = RuntimeEnvironmentModel(9)
      released = model
      values.set(model, for: 1)
    }
    _expectNotNil(released)
    _expectNil(values.value(for: 1, as: Int.self))
    values.removeAll()
    _expectNil(released)
  }

  @Test
  func testTypedSlotTakeAndRemovalPreserveOptionalNilAsAStoredValue() {
    var values = _TypedValueStorage<String>()
    values.set(Optional<Int>.none, for: "optional")
    _expectTrue(values.contains("optional"))

    let stored: Int?? = values.value(for: "optional", as: Optional<Int>.self)
    _expectNotNil(stored)
    _expectNil(stored!)

    let mismatched: String? = values.takeValue(for: "optional", as: String.self)
    _expectNil(mismatched)
    _expectTrue(values.contains("optional"), "a mismatched read must not consume the slot")

    let taken: Int?? = values.takeValue(for: "optional", as: Optional<Int>.self)
    _expectNotNil(taken)
    _expectNil(taken!)
    _expectFalse(values.contains("optional"))
    _expectNil(values.takeValue(for: "missing", as: Int.self))

    values.set("first", for: "one")
    values.set("second", for: "two")
    values.removeValue(for: "one")
    _expectFalse(values.contains("one"))
    values.removeAll(keepingCapacity: true)
    _expectTrue(values.isEmpty)
    values.set("reused", for: "after-clear")
    values.removeAll()
    _expectTrue(values.isEmpty)
  }

  @Test
  func testOptionalNilPreferenceDefaultAndPassChangeAreObservable() {
    let store = _PreferenceStore()
    _expectNil(store.value(for: RuntimeOptionalPreference.self))
    store.write("selected", for: RuntimeOptionalPreference.self)
    _expectEqual(store.value(for: RuntimeOptionalPreference.self), "selected")
    store.beginPass()
    _expectNil(store.value(for: RuntimeOptionalPreference.self))
    _expectEqual(store.previousValue(for: RuntimeOptionalPreference.self), "selected")
    _expectTrue(store.changed(for: RuntimeOptionalPreference.self))
  }

  @Test
  func testTypedChangeHistoryResetStartsANewInitialObservation() {
    var history = _TypedChangeHistory<String>()
    let initial = history.remember("selection", value: Optional<Int>.none)
    let unchanged = history.remember("selection", value: Optional<Int>.none)
    let changed = history.remember("selection", value: Optional(4))
    _expectTrue(initial.initial)
    _expectFalse(unchanged.changed)
    _expectTrue(changed.changed)
    _expectNotNil(changed.previous as Any?)
    _expectNil(changed.previous!)

    history.removeValue(for: "selection")
    _expectTrue(history.remember("selection", value: 5).initial)
    history.removeAll(keepingCapacity: true)
    _expectTrue(history.remember("selection", value: 6).initial)
    history.removeAll()
    _expectTrue(history.remember("selection", value: 7).initial)
  }
}
