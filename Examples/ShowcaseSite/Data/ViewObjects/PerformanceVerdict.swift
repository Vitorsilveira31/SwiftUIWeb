/// What the comparison concluded about one metric, from React's side.
enum PerformanceVerdict {
  /// React took less than SwiftUIWeb, beyond the noise of the machine.
  case reactLower
  /// React took more than SwiftUIWeb, beyond the noise of the machine.
  case reactHigher
  case same
  case tooFewSamples
}
