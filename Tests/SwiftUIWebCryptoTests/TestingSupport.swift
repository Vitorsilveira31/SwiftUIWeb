import Testing

// Assertion-shaped helpers keep mechanical test expressions readable while
// routing every check through Swift Testing macros. This file is test-target-only.

@inline(__always)
func _expectTrue(
  _ value: @autoclosure () -> Bool,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(value())
}

@inline(__always)
func _expectFalse(
  _ value: @autoclosure () -> Bool,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(!value())
}

@inline(__always)
func _expectEqual<T: Equatable>(
  _ lhs: @autoclosure () throws -> T,
  _ rhs: @autoclosure () throws -> T,
  _ message: String = "",
  accuracy: T? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    let left = try lhs()
    let right = try rhs()
    #expect(left == right)
  } catch {
    #expect(Bool(false))
  }
}

@inline(__always)
func _expectNotEqual<T: Equatable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() != rhs())
}

@inline(__always)
func _expectNil<T>(
  _ value: @autoclosure () -> T?,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(value() == nil)
}

@inline(__always)
func _expectNotNil<T>(
  _ value: @autoclosure () -> T?,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(value() != nil)
}

@inline(__always)
func _expectGreaterThan<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() > rhs())
}

@inline(__always)
func _expectGreaterThanOrEqual<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() >= rhs())
}

@inline(__always)
func _expectLessThan<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() < rhs())
}

@inline(__always)
func _expectLessThanOrEqual<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() <= rhs())
}

@inline(__always)
func _expectThrows<T>(
  _ expression: @autoclosure () throws -> T,
  _ handler: ((any Error) -> Void)? = nil,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    _ = try expression()
    #expect(Bool(false))
  } catch {
    handler?(error)
  }
}

@inline(__always)
func _expectNoThrow<T>(
  _ expression: @autoclosure () throws -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    _ = try expression()
  } catch {
    #expect(Bool(false))
  }
}

@inline(__always)
func _fail(
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(Bool(false))
}

@inline(__always)
func _require<T>(
  _ expression: @autoclosure () throws -> T?,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> T {
  try #require(try expression())
}
