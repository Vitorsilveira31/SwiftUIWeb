import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures

@Suite
struct CircularCurveTests {
  private static let circularCurves: [UnitCurve] = [.circularEaseIn, .circularEaseOut, .circularEaseInOut]
  private static let samples: [Double] = [0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1]

  @Test func inverseUndoesEachCircularCurve() {
    for curve in Self.circularCurves {
      for t in Self.samples {
        let roundTrip = curve.inverse.value(at: curve.value(at: t))
        #expect(abs(roundTrip - t) < 1e-6, "curve \(curve.rawValue) at \(t) round-tripped to \(roundTrip)")
      }
    }
  }

  @Test func inverseOfInverseCurveUndoesItToo() {
    for curve in Self.circularCurves {
      for t in Self.samples {
        let inverse = curve.inverse
        let back = inverse.inverse.value(at: inverse.value(at: t))
        #expect(abs(back - t) < 1e-6, "inverse of \(curve.rawValue) at \(t) round-tripped to \(back)")
      }
    }
  }

  @Test func doubleInverseIsTheOriginalCurve() {
    for curve in Self.circularCurves {
      #expect(curve.inverse.inverse == curve)
      for t in Self.samples {
        #expect(abs(curve.inverse.inverse.value(at: t) - curve.value(at: t)) < 1e-9)
      }
    }
  }

  @Test func circularEaseInOutInverseMatchesKnownPoint() {
    // Forward: y(0.25) = (1 - sqrt(1 - 4 * 0.25^2)) / 2 = (1 - sqrt(0.75)) / 2, so the inverse at that y is 0.25.
    let y = UnitCurve.circularEaseInOut.value(at: 0.25)
    #expect(abs(UnitCurve.circularEaseInOut.inverse.value(at: y) - 0.25) < 1e-9)
  }

  @Test func circularScrollTransitionPublishesLinearEasing() throws {
    for curve in Self.circularCurves {
      let configuration = ScrollTransitionConfiguration.interactive(timingCurve: curve)
      let easing = try #require(configuration.attributes["data-scroll-transition-curve"])
      #expect(easing.hasPrefix("linear("))
      #expect(!easing.contains("circular"))
    }
  }

  @Test func sampledEasingHasEvenlySpacedFourDecimalPointsFromZeroToOne() throws {
    for curve in Self.circularCurves {
      let easing = curve.cssEasing
      #expect(easing.hasPrefix("linear(") && easing.hasSuffix(")"))
      let body = easing.dropFirst("linear(".count).dropLast()
      let values = body.split(separator: ",").map { $0.trimmingWhitespace() }
      #expect(values.count == 33)
      #expect(values.first == "0")
      #expect(values.last == "1")
      for text in values {
        let number = try #require(Double(text))
        #expect(number >= 0 && number <= 1)
        let fraction = text.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first ?? ""
        #expect(fraction.count <= 4)
      }
    }
  }

  @Test func cssNativeCurvesKeepTheirExistingEasing() {
    #expect(UnitCurve.easeInOut.cssEasing == "ease-in-out")
    #expect(UnitCurve.linear.cssEasing == "linear")
    #expect(UnitCurve.easeIn.cssEasing == "ease-in")
    #expect(UnitCurve.cubicBezier(0.1, 0.2, 0.3, 0.4).cssEasing == "cubic-bezier(0.1,0.2,0.3,0.4)")
  }
}

private extension Substring {
  func trimmingWhitespace() -> String {
    String(self).filter { $0 != " " }
  }
}
