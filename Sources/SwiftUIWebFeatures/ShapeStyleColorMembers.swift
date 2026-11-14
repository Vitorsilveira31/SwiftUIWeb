@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
/// SwiftUI exposes the standard colors as `ShapeStyle` members so implicit
/// member syntax works wherever a generic shape style is expected, e.g.
/// `Circle().fill(.red)` or `Capsule().stroke(.blue, lineWidth: 2)`.
/// Each member is the same unresolved value as its `Color` counterpart.
public extension ShapeStyle where Self == Color {
  static var black: Color { Color.black }
  static var blue: Color { Color.blue }
  static var brown: Color { Color.brown }
  static var clear: Color { Color.clear }
  static var cyan: Color { Color.cyan }
  static var gray: Color { Color.gray }
  static var green: Color { Color.green }
  static var indigo: Color { Color.indigo }
  static var mint: Color { Color.mint }
  static var orange: Color { Color.orange }
  static var pink: Color { Color.pink }
  static var purple: Color { Color.purple }
  static var red: Color { Color.red }
  static var teal: Color { Color.teal }
  static var white: Color { Color.white }
  static var yellow: Color { Color.yellow }
}
