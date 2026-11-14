/// One thing the comparison measured, with the median of each side.
///
/// `swiftUIWeb` is the app as it runs by default (its Swift in a Web Worker); `mainThread` is the same bundle with the Swift on the
/// main thread. `react` is React's plain list, and `reactVirtual` is React with a hand-written virtualized list. Each is compared
/// with `swiftUIWeb` (and `mainThread` with `react`), never with another one.
struct PerformanceMetricVO {
  let id: String
  let unit: String
  let swiftUIWeb: Double
  let mainThread: Double
  let react: Double
  let swiftUIWebSpread: Double
  let mainThreadSpread: Double
  let reactSpread: Double
  /// React against `swiftUIWeb`.
  let verdict: PerformanceVerdict
  /// React against `mainThread`.
  let mainThreadVerdict: PerformanceVerdict
  let reactVirtual: Double
  let reactVirtualSpread: Double
  /// React with a virtualized list against `swiftUIWeb`.
  let reactVirtualVerdict: PerformanceVerdict
}
