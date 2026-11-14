// The one geometry the framework and applications share, on every host. These values are not foreign structs: FFI
// uses fixed-width scalars, never MemoryLayout of public types.
public typealias CGFloat = Double
public struct CGPoint: Hashable, Sendable {
  public var x: Double
  public var y: Double
  public init() { x = 0; y = 0 }
  public init(x: Double, y: Double) { self.x = x; self.y = y }
  public init(x: Int, y: Int) { self.x = Double(x); self.y = Double(y) }
  public static let zero = CGPoint()
}
public struct CGSize: Hashable, Sendable {
  public var width: Double
  public var height: Double
  public init() { width = 0; height = 0 }
  public init(width: Double, height: Double) { self.width = width; self.height = height }
  public init(width: Int, height: Int) { self.width = Double(width); self.height = Double(height) }
  public static let zero = CGSize()
}
public struct CGRect: Hashable, Sendable {
  public var origin: CGPoint
  public var size: CGSize
  public init(origin: CGPoint, size: CGSize) { self.origin = origin; self.size = size }
  public init() { origin = CGPoint(); size = CGSize() }
  public init(x: Double, y: Double, width: Double, height: Double) {
    origin = CGPoint(x: x, y: y); size = CGSize(width: width, height: height)
  }
  public init(x: Int, y: Int, width: Int, height: Int) {
    origin = CGPoint(x: x, y: y); size = CGSize(width: width, height: height)
  }
  public static let zero = CGRect()
  public var minX: Double { min(origin.x, origin.x + size.width) }
  public var minY: Double { min(origin.y, origin.y + size.height) }
  public var maxX: Double { max(origin.x, origin.x + size.width) }
  public var maxY: Double { max(origin.y, origin.y + size.height) }
  public var midX: Double { origin.x + size.width / 2 }
  public var midY: Double { origin.y + size.height / 2 }
  public var width: Double { abs(size.width) }
  public var height: Double { abs(size.height) }
}

// Default-argument expressions are type-checked in the declaring source file.
// Keep construction behind Core-owned symbols so users of SwiftUIWebCore do not
// need to import Foundation/CoreGraphics merely because these aliases resolve to
// platform geometry on that target.
public enum _SwiftUIWebGeometryDefaults {
  public static var zeroPoint: CGPoint { CGPoint(x: 0, y: 0) }
  public static var zeroSize: CGSize { CGSize(width: 0, height: 0) }
  public static var zeroRect: CGRect { CGRect(origin: zeroPoint, size: zeroSize) }
  public static var defaultUnspecifiedSize: CGSize { CGSize(width: 10, height: 10) }
  public static var unitRect: CGRect { CGRect(origin: zeroPoint, size: CGSize(width: 1, height: 1)) }
}

/// The affine transform on every host. It performs the math itself: Path consumes the result before any browser is
/// involved.
public struct CGAffineTransform: Hashable, Sendable {
  public var a: Double
  public var b: Double
  public var c: Double
  public var d: Double
  public var tx: Double
  public var ty: Double
  public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
    self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
  }
  public static let identity = Self()
  public init(translationX tx: Double, y ty: Double) { self.init(tx: tx, ty: ty) }
  public init(scaleX sx: Double, y sy: Double) { self.init(a: sx, d: sy) }
  public init(rotationAngle angle: Double) { self = Self.identity.rotated(by: angle) }
  public func translatedBy(x: Double, y: Double) -> Self {
    Self(a: a, b: b, c: c, d: d, tx: tx + a * x + c * y, ty: ty + b * x + d * y)
  }
  public func scaledBy(x: Double, y: Double) -> Self {
    Self(a: a * x, b: b * x, c: c * y, d: d * y, tx: tx, ty: ty)
  }
  public func rotated(by angle: Double) -> Self {
    let (sine, cosine) = Self.sineCosine(angle)
    return Self(a: a * cosine + c * sine, b: b * cosine + d * sine,
                c: c * cosine - a * sine, d: d * cosine - b * sine, tx: tx, ty: ty)
  }
  public func inverted() -> Self {
    let determinant = a * d - b * c
    // Preserve the historical singular-transform policy.
    guard determinant != 0 else { return .identity }
    return Self(a: d / determinant, b: -b / determinant, c: -c / determinant, d: a / determinant,
                tx: (c * ty - d * tx) / determinant, ty: (b * tx - a * ty) / determinant)
  }
  private static func sineCosine(_ value: Double) -> (Double, Double) {
    guard value.isFinite else { return (.nan, .nan) }
    let pi = Double.pi
    var x = value.truncatingRemainder(dividingBy: 2 * pi)
    if x > pi { x -= 2 * pi }
    if x < -pi { x += 2 * pi }
    var cosineSign = 1.0
    if x > pi / 2 { x = pi - x; cosineSign = -1 }
    if x < -pi / 2 { x = -pi - x; cosineSign = -1 }
    // Reduced to [-pi/2, pi/2]; bounded work also for huge finite angles.
    var sine = x, sineTerm = x, cosine = 1.0, cosineTerm = 1.0
    for n in 1...9 {
      sineTerm *= -x * x / Double((2 * n) * (2 * n + 1))
      cosineTerm *= -x * x / Double((2 * n - 1) * (2 * n))
      sine += sineTerm; cosine += cosineTerm
    }
    return (sine, cosine * cosineSign)
  }
}

/// Line cap and join of `StrokeStyle`. The raw values are CoreGraphics' (`kCGLineCap*`, `kCGLineJoin*`).
public enum CGLineCap: Int32, Hashable, Sendable {
  case butt = 0
  case round = 1
  case square = 2
}
public enum CGLineJoin: Int32, Hashable, Sendable {
  case miter = 0
  case round = 1
  case bevel = 2
}

/// A two-dimensional vector, as Core Graphics spells one.
public struct CGVector: Hashable, Sendable {
  public var dx: Double
  public var dy: Double
  public init() { dx = 0; dy = 0 }
  public init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
  public init(dx: Int, dy: Int) { self.dx = Double(dx); self.dy = Double(dy) }
  public static var zero: CGVector { CGVector() }
}
