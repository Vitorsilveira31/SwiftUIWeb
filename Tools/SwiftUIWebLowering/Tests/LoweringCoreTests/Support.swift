import Testing

@testable import LoweringCore

/// A pipeline over one source. A source the lowerer refuses to rewrite is recorded as a failure of the test; the tests
/// of those refusals call `LoweringPipeline.lower` themselves.
func lower(_ pipeline: LoweringPipeline, _ source: String, options: LoweringOptions) -> LoweringResult {
  do {
    return try pipeline.lower(source, options: options)
  } catch {
    Issue.record("lowering failed: \(error)")
    return LoweringResult(text: source, counts: [:])
  }
}

/// The ported passes over one source, as an application (`--lower-codable`).
func lower(_ source: String, aliased: Bool = false, rules: [String]? = nil) -> LoweringResult {
  var pipeline = LoweringPipeline.standard
  if let rules { pipeline = pipeline.selecting(rules)! }
  return lower(pipeline, source, options: LoweringOptions(lowerCodable: true, moduleAliases: aliased))
}

func lowered(_ source: String, aliased: Bool = false, rules: [String]? = nil) -> String {
  lower(source, aliased: aliased, rules: rules).text
}
