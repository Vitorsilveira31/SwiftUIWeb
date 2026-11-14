import Testing

@testable import LoweringCore

@Suite struct FinalClassTests {
  private func finalized(_ source: String) -> LoweringResult { lower(source, rules: ["final-class-generic-method"]) }

  @Test func genericMethodsMakeAClassFinalUnlessItIsSubclassed() {
    let result = finalized("""
      class Cache {
        func value<T>(for key: String) -> T? { nil }
      }
      @MainActor public class Store {
        static func load<T>(_ type: T.Type) {}
      }
      class Base {
        func map<T>(_ transform: () -> T) -> T { transform() }
      }
      class Derived: Base {}
      class Plain { func run() {} }

      """)
    #expect(result.text.contains("final class Cache {"))
    #expect(result.text.contains("@MainActor public final class Store {"))
    #expect(result.text.contains("\nclass Base {"))
    #expect(result.text.contains("class Plain { func run() {} }"))
    #expect(!result.text.contains("final class Plain"))
    #expect(result.counts["final-class-generic-method"] == 2)
    let again = finalized(result.text)
    #expect(again.text == result.text)
    #expect(again.counts.isEmpty)
  }

  @Test func anUnterminatedClassBodyIsLeftAlone() {
    let source = "class Open {\n  func f<T>(_ v: T) {}\n"
    let result = finalized(source)
    #expect(result.text == source)
    #expect(result.counts.isEmpty)
  }

  @Test func onlyClassesTheCompilerObjectsToAreCandidates() {
    let result = finalized("""
      final class Done { func f<T>(_ v: T) {} }
      open class Open {
        func f<T>(_ v: T) {}
      }
      private class Hidden {
        func f<T>(_ v: T) {}
      }
      class Marked {
        final func f<T>(_ v: T) {}
      }
      class Overriding {
        override func f<T>(_ v: T) {}
        func plain() {}
      }
      struct Value {
        func f<T>(_ v: T) {}
      }
      class Initialized {
        init<T>(_ value: T) {}
      }
      """)
    #expect(result.counts["final-class-generic-method"] == 1)
    #expect(result.text.contains("final class Overriding {"))
    #expect(result.text.contains("\nopen class Open {"))
    #expect(result.text.contains("\nprivate class Hidden {"))
    #expect(result.text.contains("\nclass Marked {"))
    #expect(result.text.contains("\nclass Initialized {"))
  }

  @Test func aGenericMethodOfANestedTypeCounts() {
    let result = finalized("""
      class Outer {
        struct Inner {
          func f<T>(_ v: T) {}
        }
      }
      """)
    #expect(result.text.hasPrefix("final class Outer {"))
  }

  @Test func subclassesAreFoundInTheInheritanceClauseOfAnyDeclaration() {
    let result = finalized("""
      class A { func f<T>(_ v: T) {} }
      class B { func f<T>(_ v: T) {} }
      class C { func f<T>(_ v: T) {} }
      enum Namespace {
        class Child: Foo, A {}
      }
      class Generic<Value>: B<Int> {}
      class Unrelated: Another {}
      """)
    #expect(result.text.hasPrefix("class A {"))
    #expect(result.text.contains("\nclass B {"))
    #expect(result.text.contains("\nfinal class C {"))
    #expect(result.counts["final-class-generic-method"] == 1)
  }

  @Test func commentsAndStringsAreNotDeclarations() {
    let source = #"""
      // class Fake { func f<T>(_ v: T) {} }
      let text = "class Fake { func f<T>(_ v: T) {} }"
      class Real {
        // func g<T>() {}
        let note = "func h<T>() {}"
      }
      """#
    let result = finalized(source)
    #expect(result.text == source)
  }

  @Test func theBodyMayOpenOnALineOfItsOwn() {
    let result = finalized("""
      class Split
      {
        func f<T>(_ v: T) {}
      }
      class Wrapped<Value>: Base where Value: Hashable {
        func f<T>(_ v: T) {}
      }
      """)
    #expect(result.text.contains("final class Split\n{"))
    #expect(result.text.contains("\nfinal class Wrapped<Value>: Base where Value: Hashable {"))
  }
}
