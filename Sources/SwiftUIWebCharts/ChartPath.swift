// Foundation-free path construction for line and area marks. A `_ChartCurve`
// is a polyline or a chain of cubic Béziers through the data points; the
// interpolation methods follow the definitions used by d3-shape (cardinal,
// centripetal Catmull-Rom, monotone-X and the three step variants).

struct _ChartPoint {
  var x: Double
  var y: Double
}

struct _ChartCurve {
  struct Segment {
    var c1x: Double, c1y: Double, c2x: Double, c2y: Double
    var x: Double, y: Double
    var isCurve: Bool
  }

  var startX: Double
  var startY: Double
  var segments: [Segment] = []

  /// `command` is `M` for a new subpath or `L` to continue an existing one.
  func pathData(command: String = "M") -> String {
    var text = "\(command) \(_chartNumber(startX)) \(_chartNumber(startY))"
    for segment in segments {
      if segment.isCurve {
        text += " C \(_chartNumber(segment.c1x)) \(_chartNumber(segment.c1y)) \(_chartNumber(segment.c2x)) \(_chartNumber(segment.c2y)) \(_chartNumber(segment.x)) \(_chartNumber(segment.y))"
      } else {
        text += " L \(_chartNumber(segment.x)) \(_chartNumber(segment.y))"
      }
    }
    return text
  }

  func reversed() -> _ChartCurve {
    guard let last = segments.last else { return self }
    var result = _ChartCurve(startX: last.x, startY: last.y)
    var index = segments.count - 1
    while index >= 0 {
      let segment = segments[index]
      let previousX = index == 0 ? startX : segments[index - 1].x
      let previousY = index == 0 ? startY : segments[index - 1].y
      result.segments.append(Segment(c1x: segment.c2x, c1y: segment.c2y, c2x: segment.c1x, c2y: segment.c1y, x: previousX, y: previousY, isCurve: segment.isCurve))
      index -= 1
    }
    return result
  }

  static func make(_ points: [_ChartPoint], method: ChartInterpolationMethod) -> _ChartCurve? {
    guard let first = points.first else { return nil }
    var curve = _ChartCurve(startX: first.x, startY: first.y)
    guard points.count > 1 else { return curve }
    switch method.kind {
    case .linear:
      for point in points.dropFirst() { curve.line(point.x, point.y) }
    case .stepStart:
      for index in 1..<points.count { curve.line(points[index - 1].x, points[index].y); curve.line(points[index].x, points[index].y) }
    case .stepEnd:
      for index in 1..<points.count { curve.line(points[index].x, points[index - 1].y); curve.line(points[index].x, points[index].y) }
    case .stepCenter:
      for index in 1..<points.count {
        let middle = (points[index - 1].x + points[index].x) / 2
        curve.line(middle, points[index - 1].y); curve.line(middle, points[index].y); curve.line(points[index].x, points[index].y)
      }
    case .cardinal:
      curve.addCardinal(points, tension: method.parameter)
    case .catmullRom:
      curve.addCatmullRom(points, alpha: method.parameter)
    case .monotone:
      curve.addMonotone(points)
    }
    return curve
  }

  private mutating func line(_ x: Double, _ y: Double) {
    segments.append(Segment(c1x: x, c1y: y, c2x: x, c2y: y, x: x, y: y, isCurve: false))
  }

  private mutating func cubic(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
    segments.append(Segment(c1x: c1x, c1y: c1y, c2x: c2x, c2y: c2y, x: x, y: y, isCurve: true))
  }

  /// The end points are duplicated so the first and last segments have a
  /// neighbour, as d3 does.
  private func neighbour(_ points: [_ChartPoint], _ index: Int) -> _ChartPoint {
    points[min(max(index, 0), points.count - 1)]
  }

  private mutating func addCardinal(_ points: [_ChartPoint], tension: Double) {
    let k = (1 - tension) / 6
    for index in 0..<(points.count - 1) {
      let p0 = neighbour(points, index - 1), p1 = points[index], p2 = points[index + 1], p3 = neighbour(points, index + 2)
      cubic(p1.x + k * (p2.x - p0.x), p1.y + k * (p2.y - p0.y), p2.x + k * (p1.x - p3.x), p2.y + k * (p1.y - p3.y), p2.x, p2.y)
    }
  }

  private mutating func addCatmullRom(_ points: [_ChartPoint], alpha: Double) {
    let epsilon = 1e-12
    for index in 0..<(points.count - 1) {
      let p0 = neighbour(points, index - 1), p1 = points[index], p2 = points[index + 1], p3 = neighbour(points, index + 2)
      let d01 = (p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y)
      let d12 = (p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y)
      let d23 = (p3.x - p2.x) * (p3.x - p2.x) + (p3.y - p2.y) * (p3.y - p2.y)
      let l01_2a = _chartPower(d01, alpha), l12_2a = _chartPower(d12, alpha), l23_2a = _chartPower(d23, alpha)
      let l01_a = l01_2a.squareRoot(), l12_a = l12_2a.squareRoot(), l23_a = l23_2a.squareRoot()
      var c1x = p1.x, c1y = p1.y, c2x = p2.x, c2y = p2.y
      if l01_a > epsilon {
        let a = 2 * l01_2a + 3 * l01_a * l12_a + l12_2a
        let n = 3 * l01_a * (l01_a + l12_a)
        c1x = (p1.x * a - p0.x * l12_2a + p2.x * l01_2a) / n
        c1y = (p1.y * a - p0.y * l12_2a + p2.y * l01_2a) / n
      }
      if l23_a > epsilon {
        let b = 2 * l23_2a + 3 * l23_a * l12_a + l12_2a
        let m = 3 * l23_a * (l23_a + l12_a)
        c2x = (p2.x * b + p1.x * l23_2a - p3.x * l12_2a) / m
        c2y = (p2.y * b + p1.y * l23_2a - p3.y * l12_2a) / m
      }
      cubic(c1x, c1y, c2x, c2y, p2.x, p2.y)
    }
  }

  private mutating func addMonotone(_ points: [_ChartPoint]) {
    let count = points.count
    guard count > 2 else { for point in points.dropFirst() { line(point.x, point.y) }; return }
    var slopes: [Double] = []
    var widths: [Double] = []
    for index in 0..<(count - 1) {
      let width = points[index + 1].x - points[index].x
      widths.append(width)
      slopes.append(width == 0 ? 0 : (points[index + 1].y - points[index].y) / width)
    }
    var tangents = [Double](repeating: 0, count: count)
    for index in 1..<(count - 1) {
      let s0 = slopes[index - 1], s1 = slopes[index]
      let h0 = widths[index - 1], h1 = widths[index]
      let p = (h0 + h1) == 0 ? 0 : (s0 * h1 + s1 * h0) / (h0 + h1)
      let sign0: Double = s0 < 0 ? -1 : (s0 > 0 ? 1 : 0)
      let sign1: Double = s1 < 0 ? -1 : (s1 > 0 ? 1 : 0)
      let magnitude = min(abs(s0), abs(s1), 0.5 * abs(p))
      tangents[index] = (sign0 + sign1) * magnitude
    }
    tangents[0] = (3 * slopes[0] - tangents[1]) / 2
    tangents[count - 1] = (3 * slopes[count - 2] - tangents[count - 2]) / 2
    for index in 0..<(count - 1) {
      let p0 = points[index], p1 = points[index + 1]
      let dx = (p1.x - p0.x) / 3
      cubic(p0.x + dx, p0.y + dx * tangents[index], p1.x - dx, p1.y - dx * tangents[index + 1], p1.x, p1.y)
    }
  }
}

/// `value ^ alpha` for alpha in 0...1 without a math library: exact at 0,
/// 0.5 and 1 and linearly blended in between, which is all Catmull-Rom's
/// parameterization needs.
func _chartPower(_ value: Double, _ alpha: Double) -> Double {
  guard value > 0 else { return value == 0 ? (alpha == 0 ? 1 : 0) : 0 }
  let clamped = min(max(alpha, 0), 1)
  if clamped <= 0.5 { let t = clamped / 0.5; return 1 + (value.squareRoot() - 1) * t }
  let t = (clamped - 0.5) / 0.5
  return value.squareRoot() + (value - value.squareRoot()) * t
}

/// Marker outlines for `.symbol(...)`, as SVG path data centered at the origin.
func _chartSymbolPath(_ shape: BasicChartSymbolShape, radius r: Double) -> String? {
  let d = r * 0.7071
  switch shape.kind {
  case .circle: return nil
  case .square: return "M \(_chartNumber(-r)) \(_chartNumber(-r)) h \(_chartNumber(2 * r)) v \(_chartNumber(2 * r)) h \(_chartNumber(-2 * r)) Z"
  case .triangle: return "M 0 \(_chartNumber(-r)) L \(_chartNumber(r * 0.866)) \(_chartNumber(r * 0.5)) L \(_chartNumber(-r * 0.866)) \(_chartNumber(r * 0.5)) Z"
  case .diamond: return "M 0 \(_chartNumber(-r)) L \(_chartNumber(r)) 0 L 0 \(_chartNumber(r)) L \(_chartNumber(-r)) 0 Z"
  case .pentagon:
    return "M 0 \(_chartNumber(-r)) L \(_chartNumber(r * 0.951)) \(_chartNumber(-r * 0.309)) L \(_chartNumber(r * 0.588)) \(_chartNumber(r * 0.809)) L \(_chartNumber(-r * 0.588)) \(_chartNumber(r * 0.809)) L \(_chartNumber(-r * 0.951)) \(_chartNumber(-r * 0.309)) Z"
  case .plus: return "M 0 \(_chartNumber(-r)) V \(_chartNumber(r)) M \(_chartNumber(-r)) 0 H \(_chartNumber(r))"
  case .cross: return "M \(_chartNumber(-d)) \(_chartNumber(-d)) L \(_chartNumber(d)) \(_chartNumber(d)) M \(_chartNumber(d)) \(_chartNumber(-d)) L \(_chartNumber(-d)) \(_chartNumber(d))"
  case .asterisk:
    return "M 0 \(_chartNumber(-r)) V \(_chartNumber(r)) M \(_chartNumber(-d)) \(_chartNumber(-d)) L \(_chartNumber(d)) \(_chartNumber(d)) M \(_chartNumber(d)) \(_chartNumber(-d)) L \(_chartNumber(-d)) \(_chartNumber(d))"
  }
}

func _chartSymbolIsStroked(_ shape: BasicChartSymbolShape) -> Bool {
  switch shape.kind { case .plus, .cross, .asterisk: return true; default: return false }
}
