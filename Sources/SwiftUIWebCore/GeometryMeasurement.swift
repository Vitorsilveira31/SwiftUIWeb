// Host geometry measurement and coordinate-space resolution for
// `GeometryReader`, `GeometryProxy` and `onGeometryChange`.
//
// The browser host (Tools/geometry-host.js) only measures DOM boxes. It
// reports the measured view's window (viewport) frame plus the frames of the
// ancestor coordinate spaces it can see. The SwiftUI semantics — `.local`,
// `.global`, `.named`, `.scrollView` and `bounds(of:)` — are resolved here,
// in Swift, so every host and the unit tests share one implementation.
//
// This file depends only on Geometry.swift and the standard library so
// `make geometry-test` can compile it in isolation, including Embedded.
//
// Wire format (UTF-8):
//
//   "x,y,width,height[,localWidth,localHeight[,a,b,c,d]]"   window frame of the measured view
//   ( RS kind US name US "x,y,width,height[,localWidth,localHeight[,a,b,c,d]]" )*   ancestor spaces, nearest first
//
// The frame is the box in the window (viewport) pixels, which a scale above the view makes larger or smaller than the box the
// view lays out at. The page adds that layout size (`localWidth,localHeight`) only when the two differ: `GeometryProxy.size`,
// the local frame and the sizes in a named space are in the view's own points, while the global frame stays in the window's.
// How many window pixels a point is comes from the two sizes, except under a rotation or a mirror, which the sizes do not
// show: the page then adds where the view's axes go in the window (`a,b,c,d`: a point along x lands a across and b down, one
// along y lands c across and d down), which gives the scale of each axis and takes points from one view's space to another's.
//
// RS is U+001E, US is U+001F. `kind` is `n` for a named coordinate space
// (`name` is the coordinate-space key) or `s` for an enclosing scroll view's
// visible rectangle (`name` is `vertical`, `horizontal` or `both`). The legacy
// compact forms "width,height" and "x,y,width,height" remain accepted.

/// A backend-neutral rectangle in window coordinates.
struct _GeometryBox: Equatable, Sendable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  static let zero = _GeometryBox(x: 0, y: 0, width: 0, height: 0)

  var rect: CGRect { _geometryMakeRect(x: x, y: y, width: width, height: height) }
}

func _geometryMakeRect(x: Double, y: Double, width: Double, height: Double) -> CGRect {
  CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
}

/// One ancestor coordinate space seen by the host, in window coordinates.
struct _GeometrySpaceFrame: Equatable, Sendable {
  enum Kind: Equatable, Sendable { case named, scrollView }
  var kind: Kind
  /// Coordinate-space key for `.named`; scroll axes for `.scrollView`.
  var name: String
  var box: _GeometryBox
  /// The size the space lays out at, in its own points, when a scale above it makes that differ from the box's.
  var localWidth: Double?
  var localHeight: Double?
  /// Where the space's axes go in the window when the page reports it (under a rotation the two sizes do not say).
  var axes: _GeometryAxes?

  /// How many window pixels a point of this space is wide and high.
  var scaleX: Double { axes?.scaleX ?? _geometryScale(box.width, localWidth) }
  var scaleY: Double { axes?.scaleY ?? _geometryScale(box.height, localHeight) }

  /// The space's own coordinates in the window: its corner there and where its axes go.
  var placement: _GeometryPlacement {
    _GeometryPlacement(box: box, size: CGSize(width: localWidth ?? box.width, height: localHeight ?? box.height), axes: axes ?? _GeometryAxes(a: scaleX, b: 0, c: 0, d: scaleY))
  }
}

/// A view's own coordinates in the window: where its top-leading corner is and where its axes go, with the size it lays out
/// at. Takes points of the window to the view's and back, and a view's rectangle to the box it has in another's coordinates.
struct _GeometryPlacement: Equatable, Sendable {
  var corner: CGPoint
  var axes: _GeometryAxes
  var size: CGSize

  /// From the box in the window: the view's own corner is the box's unless its axes are turned or mirrored.
  init(box: _GeometryBox, size: CGSize, axes: _GeometryAxes) {
    self.axes = axes
    self.size = size
    corner = CGPoint(
      x: box.x - min(0, axes.a * size.width) - min(0, axes.c * size.height),
      y: box.y - min(0, axes.b * size.width) - min(0, axes.d * size.height))
  }

  func window(_ point: CGPoint) -> CGPoint {
    CGPoint(x: corner.x + axes.a * point.x + axes.c * point.y, y: corner.y + axes.b * point.x + axes.d * point.y)
  }

  func local(_ point: CGPoint) -> CGPoint {
    let dx = point.x - corner.x, dy = point.y - corner.y, determinant = axes.a * axes.d - axes.b * axes.c
    guard abs(determinant) > 1e-12 else { return CGPoint(x: dx, y: dy) }
    return CGPoint(x: (axes.d * dx - axes.c * dy) / determinant, y: (axes.a * dy - axes.b * dx) / determinant)
  }

  /// This view's bounds as the box they have in the coordinates of `other`: a rotation between the two turns them.
  func bounds(in other: _GeometryPlacement) -> CGRect {
    let corners = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)].map { other.local(window($0)) }
    var minX = corners[0].x, maxX = minX, minY = corners[0].y, maxY = minY
    for point in corners { minX = min(minX, point.x); maxX = max(maxX, point.x); minY = min(minY, point.y); maxY = max(maxY, point.y) }
    return _geometryMakeRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }
}

/// Where a view's own x and y axes go in the window: a point along x lands `a` across and `b` down, one along y lands `c`
/// across and `d` down.
struct _GeometryAxes: Equatable, Sendable {
  var a: Double
  var b: Double
  var c: Double
  var d: Double

  var scaleX: Double { let length = (a * a + b * b).squareRoot(); return length > 0 ? length : 1 }
  var scaleY: Double { let length = (c * c + d * d).squareRoot(); return length > 0 ? length : 1 }

  init(a: Double, b: Double, c: Double, d: Double) { self.a = a; self.b = b; self.c = c; self.d = d }

  /// The four numbers after a payload's sizes, when they are there and are a map that can be undone.
  init?(_ numbers: [Double]) {
    guard numbers.count >= 10, abs(numbers[6] * numbers[9] - numbers[7] * numbers[8]) > 1e-9 else { return nil }
    self.init(a: numbers[6], b: numbers[7], c: numbers[8], d: numbers[9])
  }
}

/// The window pixels a point is, from the box measured in the window and the size it lays out at (1 without one).
func _geometryScale(_ measured: Double, _ local: Double?) -> Double {
  guard let local, local > 0, measured > 0 else { return 1 }
  return measured / local
}

/// The coordinate spaces SwiftUI exposes to `GeometryProxy`.
enum _GeometrySpace: Equatable, Sendable {
  case local
  case global
  case named(String)
  /// The innermost enclosing scroll view. `horizontal`/`vertical` restrict
  /// the match to a scroll view that scrolls on that axis.
  case scrollView(horizontal: Bool, vertical: Bool)
}

/// Reserved coordinate-space keys. The record/unit separators never occur in
/// a host payload field, so these cannot collide with an application name.
package enum _GeometrySpaceKeys {
  static package let scrollView = "\u{1F}scrollView"
  static package let scrollViewHorizontal = "\u{1F}scrollView.horizontal"
  static package let scrollViewVertical = "\u{1F}scrollView.vertical"

  static func space(forNamedKey key: String) -> _GeometrySpace {
    switch key {
    case scrollView: return .scrollView(horizontal: false, vertical: false)
    case scrollViewHorizontal: return .scrollView(horizontal: true, vertical: false)
    case scrollViewVertical: return .scrollView(horizontal: false, vertical: true)
    default: return .named(key)
    }
  }
}

/// A decoded host measurement. Equality covers every value a proxy can
/// expose, so callers can cheaply detect semantically visible changes.
package struct _GeometryMeasurement: Equatable, Sendable {
  var box: _GeometryBox
  var spaces: [_GeometrySpaceFrame]
  /// The size the view lays out at, in its own points, when a scale above it makes that differ from the box in the window.
  var localWidth: Double?
  var localHeight: Double?
  /// Where the view's axes go in the window when the page reports it (under a rotation the two sizes do not say).
  var axes: _GeometryAxes?

  static package let zero = _GeometryMeasurement(box: .zero, spaces: [])

  /// The view's size in its own points: what `GeometryProxy.size` is.
  var size: CGSize { CGSize(width: localWidth ?? box.width, height: localHeight ?? box.height) }

  /// How many window pixels one of the view's points is.
  var scaleX: Double { axes?.scaleX ?? _geometryScale(box.width, localWidth) }
  var scaleY: Double { axes?.scaleY ?? _geometryScale(box.height, localHeight) }

  /// Where the view's axes go in the window: what the page reported, or the plain scale the two sizes give.
  var resolvedAxes: _GeometryAxes { axes ?? _GeometryAxes(a: scaleX, b: 0, c: 0, d: scaleY) }

  /// The view's own coordinates in the window.
  var placement: _GeometryPlacement { _GeometryPlacement(box: box, size: size, axes: resolvedAxes) }

  /// Where the view's own top-leading corner is in the window: its box's corner unless its axes are turned or mirrored.
  var corner: CGPoint { placement.corner }

  init(box: _GeometryBox, spaces: [_GeometrySpaceFrame] = [], localWidth: Double? = nil, localHeight: Double? = nil) {
    self.box = box
    self.spaces = spaces
    self.localWidth = localWidth
    self.localHeight = localHeight
  }

  package init?(decoding raw: String) {
    var records = _geometrySplit(Array(raw.utf8), separator: 0x1E)
    guard !records.isEmpty else { return nil }
    let head = _geometryNumbers(records.removeFirst())
    switch head.count {
    case 2: box = _GeometryBox(x: 0, y: 0, width: head[0], height: head[1])
    case 4...: box = _GeometryBox(x: head[0], y: head[1], width: head[2], height: head[3])
    default: return nil
    }
    if head.count >= 6 { localWidth = head[4]; localHeight = head[5] }
    axes = _GeometryAxes(head)
    spaces = []
    for record in records {
      let fields = _geometrySplit(record, separator: 0x1F)
      guard fields.count == 3, fields[0].count == 1 else { continue }
      let kind: _GeometrySpaceFrame.Kind
      switch fields[0][0] {
      case UInt8(ascii: "n"): kind = .named
      case UInt8(ascii: "s"): kind = .scrollView
      default: continue
      }
      let numbers = _geometryNumbers(fields[2])
      guard numbers.count == 4 || numbers.count == 6 || numbers.count == 10 else { continue }
      let name = String(decoding: fields[1], as: UTF8.self)
      spaces.append(_GeometrySpaceFrame(
        kind: kind, name: name,
        box: _GeometryBox(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]),
        localWidth: numbers.count >= 6 ? numbers[4] : nil, localHeight: numbers.count >= 6 ? numbers[5] : nil,
        axes: _GeometryAxes(numbers)))
    }
  }

  /// The window-coordinate box of the requested space, or nil when the host
  /// did not see a matching ancestor.
  func spaceBox(for space: _GeometrySpace) -> _GeometryBox? { spaceFrame(for: space)?.box }

  /// The requested space as the host measured it, with the scale it has in the window.
  func spaceFrame(for space: _GeometrySpace) -> _GeometrySpaceFrame? {
    switch space {
    case .local: return _GeometrySpaceFrame(kind: .named, name: "", box: box, localWidth: localWidth, localHeight: localHeight, axes: axes)
    case .global: return nil
    case .named(let name):
      return spaces.first { $0.kind == .named && $0.name == name }
    case .scrollView(let horizontal, let vertical):
      return spaces.first { frame in
        guard frame.kind == .scrollView else { return false }
        if horizontal && frame.name == "vertical" { return false }
        if vertical && frame.name == "horizontal" { return false }
        return true
      }
    }
  }

  /// SwiftUI `GeometryProxy.frame(in:)`: `.local` has a zero origin, `.global`
  /// is the window frame, and a named or scroll-view space is relative to that
  /// space's origin. An unresolved space falls back to global coordinates.
  func frame(in space: _GeometrySpace) -> CGRect {
    if case .local = space { return _geometryMakeRect(x: 0, y: 0, width: size.width, height: size.height) }
    guard let frame = spaceFrame(for: space) else { return box.rect }
    // In the space's own points: the view's bounds through the window into the space, whatever scale or rotation each has.
    if axes != nil || frame.axes != nil { return placement.bounds(in: frame.placement) }
    // Without a rotation: a scale the space has is divided out of the offset and of the size.
    let origin = frame.box, sx = frame.scaleX, sy = frame.scaleY
    return _geometryMakeRect(x: (box.x - origin.x) / sx, y: (box.y - origin.y) / sy, width: box.width / sx, height: box.height / sy)
  }

  /// SwiftUI `GeometryProxy.bounds(of:)`: the space's bounds converted into
  /// the measured view's local coordinates, or nil when it is not in scope.
  func bounds(of space: _GeometrySpace) -> CGRect? {
    guard let target = spaceBox(for: space) else { return nil }
    // In the measured view's own points: through the window when either is turned.
    if let frame = spaceFrame(for: space), axes != nil || frame.axes != nil { return frame.placement.bounds(in: placement) }
    return _geometryMakeRect(x: (target.x - box.x) / scaleX, y: (target.y - box.y) / scaleY, width: target.width / scaleX, height: target.height / scaleY)
  }
}

private func _geometrySplit(_ bytes: [UInt8], separator: UInt8) -> [[UInt8]] {
  var result: [[UInt8]] = []
  var current: [UInt8] = []
  for byte in bytes {
    if byte == separator { result.append(current); current = [] } else { current.append(byte) }
  }
  result.append(current)
  return result
}

/// Parses comma-separated finite numbers; any malformed field rejects the list.
private func _geometryNumbers(_ bytes: [UInt8]) -> [Double] {
  var values: [Double] = []
  for field in _geometrySplit(bytes, separator: UInt8(ascii: ",")) {
    guard !field.isEmpty, let value = Double(String(decoding: field, as: UTF8.self)), value.isFinite else { return [] }
    values.append(value)
  }
  return values
}
