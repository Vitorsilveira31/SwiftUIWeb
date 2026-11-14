import Testing

@testable import LoweringCore

/// The `embedded-feature-condition` pass alone.
private func fullSwift(_ source: String, enabled: Bool = true) -> LoweringResult {
  let pipeline = LoweringPipeline.standard.selecting(["embedded-feature-condition"])!
  return lower(pipeline, source, options: LoweringOptions(fullSwift: enabled))
}

@Suite struct EmbeddedConditionTests {
  @Test func anEmbeddedConditionBecomesTrue() {
    let result = fullSwift("#if hasFeature(Embedded)\nlet a = 1\n#else\nlet a = 2\n#endif\n")
    #expect(result.text == "#if true\nlet a = 1\n#else\nlet a = 2\n#endif\n")
    #expect(result.counts["embedded-feature-condition"] == 1)
  }

  @Test func theRestOfACompoundConditionIsKept() {
    #expect(fullSwift("#if arch(wasm32) && hasFeature(Embedded)\n#endif\n").text == "#if arch(wasm32) && true\n#endif\n")
    #expect(fullSwift("#if canImport(Observation) && !hasFeature(Embedded)\n#endif\n").text == "#if canImport(Observation) && !true\n#endif\n")
    #expect(
      fullSwift("#if hasFeature(Embedded) || os(WASI) || !(canImport(Darwin) || canImport(Glibc))\n#endif\n").text
        == "#if true || os(WASI) || !(canImport(Darwin) || canImport(Glibc))\n#endif\n")
  }

  @Test func anElseifConditionAndANestedBlockAreRewritten() {
    let source = "#if os(macOS)\n#elseif hasFeature(Embedded)\n#if !hasFeature(Embedded)\n#endif\n#endif\n"
    let result = fullSwift(source)
    #expect(result.text == "#if os(macOS)\n#elseif true\n#if !true\n#endif\n#endif\n")
    #expect(result.counts["embedded-feature-condition"] == 2)
  }

  @Test func anotherFeatureAndCodeOutsideAConditionAreLeftAlone() {
    let source = "#if hasFeature(StrictConcurrency)\n#endif\n// hasFeature(Embedded)\nlet text = \"hasFeature(Embedded)\"\n"
    #expect(fullSwift(source).text == source)
  }

  @Test func withoutTheOptionNothingChanges() {
    let source = "#if hasFeature(Embedded)\n#endif\n"
    #expect(fullSwift(source, enabled: false).text == source)
  }
}
