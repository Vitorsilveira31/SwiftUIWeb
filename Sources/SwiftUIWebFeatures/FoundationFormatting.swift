@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension CGRect {
  func intersects(_ other: CGRect) -> Bool {
    minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
  }

  func union(_ other: CGRect) -> CGRect {
    let left = min(minX, other.minX)
    let top = min(minY, other.minY)
    return CGRect(x: left, y: top, width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
  }

  func intersection(_ other: CGRect) -> CGRect {
    let left = max(minX, other.minX)
    let top = max(minY, other.minY)
    let right = min(maxX, other.maxX)
    let bottom = min(maxY, other.maxY)
    guard right > left, bottom > top else { return .zero }
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }
}
