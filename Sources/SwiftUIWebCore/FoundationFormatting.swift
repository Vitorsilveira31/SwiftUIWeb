// CoreGraphics' `CGRect` operations on every host. `String(format:)` lives in WebFoundation, which owns the printf engine.

public extension CGRect {
  var isEmpty: Bool { width == 0 || height == 0 }

  func insetBy(dx: Double, dy: Double) -> CGRect {
    let insetWidth = max(0, width - 2 * dx)
    let insetHeight = max(0, height - 2 * dy)
    return CGRect(x: minX + dx, y: minY + dy, width: insetWidth, height: insetHeight)
  }

  func offsetBy(dx: Double, dy: Double) -> CGRect {
    CGRect(x: minX + dx, y: minY + dy, width: width, height: height)
  }

  func contains(_ point: CGPoint) -> Bool {
    point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
  }

}
