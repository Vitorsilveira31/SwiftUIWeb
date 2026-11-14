import Foundation
import MapKit

/// A zoom-like level for the map. MapKit has no zoom level, so the level is derived from the visible
/// longitude span: each level halves the span, and level 0 spans the whole globe (360 degrees).
struct MapZoom: Equatable, Sendable {
    static let range: ClosedRange<Double> = 3...19
    static let start = MapZoom(level: 15)

    let level: Double

    /// Clamped to the map's range; a NaN level falls back to the start level.
    init(level: Double) {
        self.level = level.isNaN ? Self.start.level : min(max(level, Self.range.lowerBound), Self.range.upperBound)
    }

    /// A zero span gives +inf from log2, which the clamp turns into the closest zoom.
    init(longitudeDelta: Double) {
        self.init(level: longitudeDelta.isNaN ? Self.start.level : log2(360 / max(longitudeDelta, .leastNonzeroMagnitude)))
    }

    var displayLevel: Int {
        Int(level.rounded())
    }

    var canZoomOut: Bool {
        level > Self.range.lowerBound
    }

    var canZoomIn: Bool {
        level < Self.range.upperBound
    }

    /// One whole level in `delta` direction from the current level, kept inside `range`.
    func stepped(by delta: Double) -> MapZoom {
        let next = min(max(level.rounded() + delta, Self.range.lowerBound), Self.range.upperBound)
        return MapZoom(level: next)
    }

    /// The region that shows this level centred on `center`; the inverse of `init(longitudeDelta:)`.
    func region(center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let delta = 360 / pow(2, level)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta))
    }
}
