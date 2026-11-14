// The damped harmonic oscillator behind SwiftUI's springs, solved in closed form so that the browser can play it as a
// CSS `linear()` easing: the curve is sampled here, once per animation value, and the page interpolates between the
// samples. Pure arithmetic, no Foundation: the browser has no libm, so the few transcendental functions it needs are
// below.

/// A spring that carries a value from 0 to 1, as SwiftUI's `Spring` does: `response` is the period of the undamped
/// oscillation, `dampingRatio` 1 is critically damped (no overshoot), below 1 overshoots, above 1 creeps.
/// `initialVelocity` is in distances per second (1 = the whole distance in one second).
package struct _SpringMotion: Hashable, Sendable {
  package let response: Double
  package let dampingRatio: Double
  package let initialVelocity: Double

  package init(response: Double, dampingRatio: Double, initialVelocity: Double = 0) {
    self.response = response.isFinite ? max(response, 0.01) : 0.5
    self.dampingRatio = dampingRatio.isFinite ? max(dampingRatio, 0) : 1
    self.initialVelocity = initialVelocity.isFinite ? initialVelocity : 0
  }

  /// SwiftUI's duration/bounce spelling: bounce 0 is critically damped, a positive bounce overshoots, a negative one is
  /// overdamped.
  package init(duration: Double, bounce: Double, initialVelocity: Double = 0) {
    let bounce = bounce.isFinite ? min(max(bounce, -1), 1) : 0
    let ratio = bounce >= 0 ? 1 - bounce : 1 / max(1 + bounce, 0.01)
    self.init(response: duration, dampingRatio: ratio, initialVelocity: initialVelocity)
  }

  /// The physical spelling: a mass on a spring of `stiffness` with `damping`.
  package init(mass: Double, stiffness: Double, damping: Double, initialVelocity: Double = 0) {
    let mass = mass.isFinite ? max(mass, 0.0001) : 1
    let stiffness = stiffness.isFinite ? max(stiffness, 0.0001) : 100
    let damping = damping.isFinite ? max(damping, 0) : 10
    self.init(
      response: 2 * Double.pi * _squareRoot(mass / stiffness),
      dampingRatio: damping / (2 * _squareRoot(mass * stiffness)),
      initialVelocity: initialVelocity)
  }

  private var omega: Double { 2 * Double.pi / response }

  /// The progress at `time` seconds: 0 at the start, 1 at rest (a bouncy spring passes 1 on the way).
  package func value(at time: Double) -> Double {
    guard time > 0 else { return 0 }
    return 1 + displacement(at: time)
  }

  /// The distance from rest at `time`; -1 at the start.
  private func displacement(at time: Double) -> Double {
    let omega = self.omega, zeta = dampingRatio, velocity = initialVelocity
    if zeta < 1 {
      let damped = omega * _squareRoot(1 - zeta * zeta)
      let b = (velocity - zeta * omega) / damped
      let (sine, cosine) = _sineCosine(damped * time)
      return _exponential(-zeta * omega * time) * (-cosine + b * sine)
    }
    if zeta == 1 {
      return _exponential(-omega * time) * (-1 + (velocity - omega) * time)
    }
    let root = _squareRoot(zeta * zeta - 1)
    let slow = -omega * (zeta - root), fast = -omega * (zeta + root)
    let fastCoefficient = (velocity + slow) / (fast - slow)
    let slowCoefficient = -1 - fastCoefficient
    return slowCoefficient * _exponential(slow * time) + fastCoefficient * _exponential(fast * time)
  }

  /// The time after which the spring stays within `epsilon` of rest. That is how long the browser plays it; SwiftUI
  /// runs a spring until it settles the same way. An undamped spring never settles and is cut at ten seconds.
  package func settlingDuration(epsilon: Double = 0.001) -> Double {
    let limit = 10.0
    guard dampingRatio > 0 else { return limit }
    // The envelope that bounds the motion decays monotonically: find where it crosses epsilon, then step back to the
    // last sample that is still outside it, so a spring that is already close does not play for nothing.
    var low = 0.0, high = limit
    guard envelope(at: high) <= epsilon else { return limit }
    for _ in 0..<48 {
      let middle = (low + high) / 2
      if envelope(at: middle) > epsilon { low = middle } else { high = middle }
    }
    let step = 1.0 / 240
    var time = high
    while time > step, absolute(displacement(at: time - step)) <= epsilon, absolute(derivative(at: time - step)) <= epsilon * omega { time -= step }
    return max(time, 0.016)
  }

  /// An upper bound of |displacement| from `time` on.
  private func envelope(at time: Double) -> Double {
    let omega = self.omega, zeta = dampingRatio, velocity = initialVelocity
    if zeta < 1 {
      let damped = omega * _squareRoot(1 - zeta * zeta)
      let b = (velocity - zeta * omega) / damped
      return _exponential(-zeta * omega * time) * _squareRoot(1 + b * b)
    }
    if zeta == 1 {
      return _exponential(-omega * time) * (1 + absolute(velocity - omega) * time)
    }
    let root = _squareRoot(zeta * zeta - 1)
    let slow = -omega * (zeta - root), fast = -omega * (zeta + root)
    let fastCoefficient = (velocity + slow) / (fast - slow)
    let slowCoefficient = -1 - fastCoefficient
    return absolute(slowCoefficient) * _exponential(slow * time) + absolute(fastCoefficient) * _exponential(fast * time)
  }

  private func derivative(at time: Double) -> Double {
    let h = 1e-4
    return (displacement(at: time + h) - displacement(at: max(time - h, 0))) / (time > h ? 2 * h : time + h)
  }

  /// The spring played over `duration` seconds as a CSS easing: `linear()` with evenly spaced samples (60 a second,
  /// at least 20 and at most 120), rounded to a thousandth. Starts at 0 and ends at 1 exactly, so the last frame
  /// lands on the target value.
  package func cssEasing(duration: Double) -> String {
    let duration = duration > 0 && duration.isFinite ? duration : settlingDuration()
    let count = min(max(Int(min(duration * 60, 120)), 20), 120)
    var result = "linear(0"
    for index in 1..<count {
      let time = duration * Double(index) / Double(count)
      result += ","
      result += _easingNumber(value(at: time))
    }
    result += ",1)"
    return result
  }
}

private func absolute(_ value: Double) -> Double { value < 0 ? -value : value }

/// A thousandth-rounded decimal without trailing zeros: "0.5", "1.032", "-0.01", "0".
func _easingNumber(_ value: Double) -> String {
  // Bounded: a spring's initial velocity can come from a drag or a model value, and its overshoot is of that order.
  guard value.isFinite else { return "0" }
  let scaled = Int64((min(max(value, -1e12), 1e12) * 1000).rounded())
  if scaled == 0 { return "0" }
  let negative = scaled < 0
  let magnitude = negative ? -scaled : scaled
  let whole = magnitude / 1000
  var fraction = magnitude % 1000
  var text = (negative ? "-" : "") + String(whole)
  if fraction != 0 {
    var digits = 3
    while fraction % 10 == 0 { fraction /= 10; digits -= 1 }
    var fractionText = String(fraction)
    while fractionText.count < digits { fractionText = "0" + fractionText }
    text += "." + fractionText
  }
  return text
}

// MARK: Math without libm

package func _squareRoot(_ value: Double) -> Double { value > 0 ? value.squareRoot() : 0 }

func _exponential(_ value: Double) -> Double {
  guard value.isFinite else { return value > 0 ? .infinity : (value < 0 ? 0 : .nan) }
  if value > 709 { return .infinity }
  if value < -745 { return 0 }
  let ln2 = 0.693_147_180_559_945_3
  let steps = (value / ln2).rounded()
  let reduced = value - steps * ln2
  var term = 1.0, sum = 1.0, index = 1.0
  while index < 20 {
    term *= reduced / index
    sum += term
    index += 1
  }
  return sum * Double(sign: .plus, exponent: Int(steps), significand: 1)
}

func _sineCosine(_ value: Double) -> (sine: Double, cosine: Double) {
  guard value.isFinite else { return (.nan, .nan) }
  let pi = Double.pi
  var x = value.truncatingRemainder(dividingBy: 2 * pi)
  if x > pi { x -= 2 * pi }
  if x < -pi { x += 2 * pi }
  var cosineSign = 1.0
  if x > pi / 2 { x = pi - x; cosineSign = -1 }
  if x < -pi / 2 { x = -pi - x; cosineSign = -1 }
  var sine = x, sineTerm = x, cosine = 1.0, cosineTerm = 1.0
  for n in 1...9 {
    sineTerm *= -x * x / Double((2 * n) * (2 * n + 1))
    cosineTerm *= -x * x / Double((2 * n - 1) * (2 * n))
    sine += sineTerm; cosine += cosineTerm
  }
  return (sine, cosine * cosineSign)
}
