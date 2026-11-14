import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebBrowser

@Suite
@MainActor
final class LayoutPhaseInstrumentationTests {
  @Test
  func testReadAfterWriteIsDetectedOnlyInsideWritePhase() {
    let phases = _BrowserLayoutPhaseCoordinator()
    phases.beginFrame()
    phases.beginWrite()
    phases.recordWrite(.style)
    phases.recordRead(.geometry)
    _expectEqual(phases.metrics.readAfterWriteHazards, 1)

    phases.beginMeasurement()
    phases.recordRead(.geometry)
    _expectEqual(phases.metrics.readAfterWriteHazards, 1)

    phases.beginCorrection()
    phases.recordWrite(.scroll)
    _expectEqual(phases.metrics.corrections, 1)
    _expectEqual(phases.metrics.writesDuringMeasurement, 0)
    phases.endFrame()
    _expectEqual(phases.phase, .idle)
  }

  @Test
  func testMeasurementInstrumentationTracksDeferredCorrections() {
    let phases = _BrowserLayoutPhaseCoordinator()
    phases.beginFrame()
    phases.beginMeasurement()
    phases.recordRead(.geometry)
    phases.deferMeasurement()
    phases.beginCorrection()
    phases.recordWrite(.scroll)
    _expectEqual(phases.metrics.frames, 1)
    _expectEqual(phases.metrics.reads, 1)
    _expectEqual(phases.metrics.deferredMeasurements, 1)
    _expectEqual(phases.metrics.writesDuringMeasurement, 0)
    _expectEqual(phases.metrics.corrections, 1)
  }
}
