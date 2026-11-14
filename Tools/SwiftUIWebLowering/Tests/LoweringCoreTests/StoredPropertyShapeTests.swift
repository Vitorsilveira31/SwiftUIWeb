import Testing

@testable import LoweringCore

/// What makes a `var` stored or computed, as the observable class and the view comparison both read it.
@Suite struct StoredPropertyShapeTests {
  private static let source = """
    @Observable final class Model {
      var a = (array[0])
      var b: Int;
      var c: Int
        { 3 }
      var d: Int
        { get { 4 } set { } }
      var e = 1
      var callback: (Int) -> [Int] = { value in [value] }
      var typed: (Int) -> [Int] = make()
      var model: Model {
        storage = make()
      }
      var last: Int
    }
    struct Card: View {
      var a = (array[0])
      var c: Int
        { 3 }
      var callback: (Int) -> [Int] = make()
      var model: Model {
        storage = make()
      }
      var trailing: Int
      var body: some View { Text("") }
    }

    """

  @Test func anObservableClassPublishesTheStoredVarsAndOnlyThose() {
    let output = lowered(Self.source)
    for published in [
      "@Published(memberID: 1) var a = (array[0])", "@Published(memberID: 2) var b: Int;", "@Published(memberID: 3) var e = 1",
      "@Published(memberID: 4) var callback: (Int) -> [Int] = { value in [value] }",
      "@Published(memberID: 5) var typed: (Int) -> [Int] = make()", "@Published(memberID: 6) var last: Int\n",
    ] {
      #expect(output.contains(published), "\(published)")
    }
    // A brace on the next line, a getter and an assignment inside an accessor make a property computed.
    #expect(output.contains("  var c: Int\n    { 3 }\n"))
    #expect(output.contains("  var d: Int\n    { get { 4 } set { } }\n"))
    #expect(output.contains("  var model: Model {\n    storage = make()\n  }\n"))
    #expect(output.components(separatedBy: "@Published").count - 1 == 6)
  }

  @Test func aViewComparesItsStoredVarsAndNotTheComputedOnes() {
    let output = lowered(Self.source)
    #expect(output.contains("_swiftUIWebSame(lhs.a, rhs.a) && _swiftUIWebSame(lhs.callback, rhs.callback) && _swiftUIWebSame(lhs.trailing, rhs.trailing) }"))
    #expect(!output.contains("lhs.c,"))
    #expect(!output.contains("lhs.model"))
  }
}
