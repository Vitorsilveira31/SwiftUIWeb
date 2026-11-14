# Skip Lite Test Harness

This reference applies to transpiled Lite targets, not native Fuse tests.

## Swift Testing


```swift
import Testing

@Suite struct MathTests {
    @Test func addition() { #expect(1 + 1 == 2) }
    @Test func inequality() { #expect(3 != 5) }
    @Test func comparisons() {
        #expect(10 > 5)
        #expect(3 < 8)
        #expect(5 >= 5)
    }
    @Test func unwrap() throws {
        let v: Int? = 42
        let _ = try #require(v)
    }
}

// Freestanding @Test functions also supported
@Test func standalone() { #expect(true) }
```

**Supported**: `@Test`, `@Suite`, `#expect` (==, !=, >, <, >=, <=, bool), `#require`.
**Not supported**: Parameterized tests, traits, tags.


## Platform-Specific Tests


```swift
func testIOSOnly() throws {
    #if SKIP
    throw XCTSkip("Not supported on Android")
    #endif
    // iOS-only test
}
```

## Custom Test Harness

Create `XCSkipTests.swift` to override the auto-generated harness:

```swift
#if os(macOS)
import SkipTest

@available(macOS 13, *)
final class XCSkipTests: XCTestCase, XCGradleHarness {
    public func testSkipModule() async throws {
        try await runGradleTests()
    }
}
#endif
```

## Failure Behavior

- **Swift XCTest**: Assertion failure noted, test continues
- **Kotlin JUnit**: Assertion throws exception, test stops

This can cause different failure counts per platform.

## Diagnosing Failures

Kotlin compilation errors appear in `testSkipModule()` output with `.kt` file paths and line numbers. Cross-reference with Swift source.

Under Robolectric, `#if os(Android)` is false; use `#if os(Android) || ROBOLECTRIC` for code shared with that environment. Treat listed macro support as version-dependent and verify it against the installed Skip version.
