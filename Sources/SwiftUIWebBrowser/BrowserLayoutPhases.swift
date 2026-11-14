/// Lightweight browser layout-phase accounting.  The coordinator deliberately
/// contains no DOM types so the instrumentation can be exercised from the
/// host test suite and remains invisible to SwiftUI-facing APIs.
@_spi(Renderer) public enum _BrowserLayoutPhase: Equatable, Sendable {
  case idle
  case calculation
  case writing
  case measurement
  case correction
}

@_spi(Renderer) public enum _BrowserLayoutReadKind: Equatable, Sendable {
  case geometry
  case scroll
  case focus
  case viewport
  case animation
  case other
}

@_spi(Renderer) public enum _BrowserLayoutWriteKind: Equatable, Sendable {
  case dom
  case scroll
  case focus
  case style
  case animation
  case other
}

@_spi(Renderer) public struct _BrowserLayoutPhaseMetrics: Equatable, Sendable {
  public fileprivate(set) var frames = 0
  public fileprivate(set) var calculations = 0
  public fileprivate(set) var writes = 0
  public fileprivate(set) var reads = 0
  public fileprivate(set) var corrections = 0
  public fileprivate(set) var readAfterWriteHazards = 0
  public fileprivate(set) var writesDuringMeasurement = 0
  public fileprivate(set) var deferredMeasurements = 0

  public init() {}
}

/// Coordinates browser DOM work without introducing a second scheduler.  The
/// existing BrowserSession/RAF scheduler remains responsible for when work
/// runs; this object only makes the ordering explicit and detects accidental
/// read-after-write layout hazards in development and benchmarks.
@_spi(Renderer) public final class _BrowserLayoutPhaseCoordinator: @unchecked Sendable {
  @_spi(Renderer) public static let shared = _BrowserLayoutPhaseCoordinator()

  @_spi(Renderer) public private(set) var phase: _BrowserLayoutPhase = .idle
  @_spi(Renderer) public private(set) var metrics = _BrowserLayoutPhaseMetrics()

  private var lastOperationWasWrite = false
  private var lastWritePhase: _BrowserLayoutPhase = .idle

  @_spi(Renderer) public init() {}

  @_spi(Renderer) public func reset() {
    phase = .idle
    metrics = _BrowserLayoutPhaseMetrics()
    lastOperationWasWrite = false
    lastWritePhase = .idle
  }

  @_spi(Renderer) public func beginFrame() {
    metrics.frames += 1
    beginCalculation()
  }

  @_spi(Renderer) public func beginCalculation() {
    phase = .calculation
    metrics.calculations += 1
    lastOperationWasWrite = false
  }

  @_spi(Renderer) public func beginWrite() {
    phase = .writing
    lastOperationWasWrite = false
  }

  @_spi(Renderer) public func beginMeasurement() {
    phase = .measurement
    // A browser layout opportunity is expected between these phases.  A read
    // in measurement therefore does not count as a hazard from an earlier
    // write phase; a read that occurs while still writing does.
    lastOperationWasWrite = false
  }

  @_spi(Renderer) public func beginCorrection() {
    phase = .correction
    lastOperationWasWrite = false
  }

  @_spi(Renderer) public func endFrame() {
    phase = .idle
    lastOperationWasWrite = false
    lastWritePhase = .idle
  }

  @_spi(Renderer) public func deferMeasurement() {
    metrics.deferredMeasurements += 1
  }

  @_spi(Renderer) public func recordRead(_ kind: _BrowserLayoutReadKind = .other) {
    _ = kind
    metrics.reads += 1
    if lastOperationWasWrite && lastWritePhase == phase {
      metrics.readAfterWriteHazards += 1
    }
    lastOperationWasWrite = false
  }

  @_spi(Renderer) public func recordWrite(_ kind: _BrowserLayoutWriteKind = .other) {
    _ = kind
    metrics.writes += 1
    if phase == .measurement { metrics.writesDuringMeasurement += 1 }
    if phase == .correction { metrics.corrections += 1 }
    lastOperationWasWrite = true
    lastWritePhase = phase
  }
}
