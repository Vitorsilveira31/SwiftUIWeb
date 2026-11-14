import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

// SwiftUI declares `Binding`, `State`, `Environment`, `AnyView` and the modifiers nonisolated, so code outside
// the main actor may form and read them. These tests are deliberately not `@MainActor`: they fail to compile
// (or trap, if the wrappers asserted the executor) when the API regains main-actor isolation.
@Suite
struct NonisolatedStateAPITests {
  private nonisolated func readAndWrite(_ binding: Binding<Int>) -> Int {
    binding.wrappedValue += 1
    return binding.wrappedValue
  }

  private final class Model: @unchecked Sendable { var count = 0 }

  @Test
  func bindingsAreUsableFromNonisolatedCode() {
    let model = Model()
    let binding = Binding<Int>(get: { model.count }, set: { model.count = $0 })
    #expect(readAndWrite(binding) == 1)
    #expect(model.count == 1)
    #expect(readAndWrite(.constant(41)) == 41)
  }

  @Test
  func bindingProjectionsAndMemberBindingsKeepTheirSource() {
    struct Point { var x = 1; var y = 2 }
    var point = Point()
    let binding = Binding<Point>(get: { point }, set: { point = $0 })
    let x = binding.x
    x.wrappedValue = 7
    #expect(point.x == 7)
    #expect(binding.projectedValue.y.wrappedValue == 2)
  }

  @Test
  func stateAndFocusStateInitializeWithoutAnActor() {
    @State var count = 3
    #expect(count == 3)
    count += 1
    #expect($count.wrappedValue == 4)
    @FocusState var focused: Bool
    #expect(focused == false)
    focused = true
    #expect($focused.wrappedValue == true)
  }

  @Test
  func anyViewAndModifiersBuildWithoutAnActor() {
    let erased = AnyView(Text("hello"))
    let modified = Text("hello").padding().opacity(0.5).frame(width: 10)
    _ = erased
    _ = modified
  }

  @Test
  func environmentWrapperReadsItsDefaultOutsideARender() {
    let environment = Environment(\.isEnabled)
    #expect(environment.wrappedValue == true)
  }
}
