@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension Shape where Self == Capsule {
  static var capsule: Capsule { Capsule() }

  static func capsule(style: RoundedCornerStyle) -> Capsule { Capsule(style: style) }
}

public extension Shape where Self == ContainerRelativeShape {
  static var containerRelative: ContainerRelativeShape { ContainerRelativeShape() }
}
