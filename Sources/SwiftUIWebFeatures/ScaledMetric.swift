@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// SwiftUI's `@ScaledMetric`: a dimension that scales with Dynamic Type.
///
/// The value is scaled by the environment's `dynamicTypeSize` using the
/// iOS body text-style ratios (`.large` = 1). Browsers expose no Dynamic Type
/// setting, so the default environment keeps the authored value; hosts or
/// applications that set a dynamic type size get the same scaling as iOS.
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty {
  private let baseValue: Value
  private let textStyle: Font.TextStyle

  public init(wrappedValue: Value) {
    baseValue = wrappedValue
    textStyle = .body
  }

  public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) {
    baseValue = wrappedValue
    self.textStyle = textStyle
  }

  public var wrappedValue: Value {
    baseValue * Value(_scaledMetricFactor(EnvironmentRuntime.current.dynamicTypeSize))
  }
}

/// iOS body point sizes per content size category divided by `.large` (17pt).
func _scaledMetricFactor(_ size: DynamicTypeSize) -> Double {
  let points: Double
  switch size {
  case .xSmall: points = 14
  case .small: points = 15
  case .medium: points = 16
  case .xLarge: points = 19
  case .xxLarge: points = 21
  case .xxxLarge: points = 23
  case .accessibility1: points = 28
  case .accessibility2: points = 33
  case .accessibility3: points = 40
  case .accessibility4: points = 47
  case .accessibility5: points = 53
  default: points = 17
  }
  return points / 17
}
