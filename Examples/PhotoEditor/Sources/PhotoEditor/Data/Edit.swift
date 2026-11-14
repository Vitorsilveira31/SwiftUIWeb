import SwiftUI

/// The whole state of an edit. A value, so undo is a stack of these and every change goes through one commit.
struct Edit: Equatable, Sendable {
    var scale = 1.0
    /// Radians, clockwise on screen: the gestures and the Rotate 90° button add to it.
    var rotation = 0.0
    /// The pan as fractions of the stage.
    var panX = 0.0
    var panY = 0.0
    var crop = Crop()
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    /// Degrees.
    var hue = 0.0
    var blur = 0.0
    var grayscale = 0.0

    static let scaleRange = 0.5...8.0
    static let panLimit = 0.5

    static func clampedScale(_ value: Double) -> Double {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func clampedPan(_ value: Double) -> Double {
        min(max(value, -panLimit), panLimit)
    }

    /// A distance on the stage as a fraction of it; zero before the stage has a size.
    static func fraction(_ points: CGFloat, of total: CGFloat) -> Double {
        total > 0 ? Double(points / total) : 0
    }

    /// The rotation in degrees, [0, 360), to one decimal place.
    var rotationDegrees: Double {
        let degrees = rotation * 180 / .pi
        let turned = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return ((turned * 10).rounded() / 10).truncatingRemainder(dividingBy: 360)
    }

    /// The edit as a gesture in flight would leave it, so the surface can show it before the gesture ends.
    func previewing(magnification: CGFloat, rotation delta: Angle, pan: CGSize, stage: CGSize) -> Edit {
        var edit = self
        edit.scale = Self.clampedScale(scale * Double(magnification))
        edit.rotation += delta.radians
        edit.panX = Self.clampedPan(panX + Self.fraction(pan.width, of: stage.width))
        edit.panY = Self.clampedPan(panY + Self.fraction(pan.height, of: stage.height))
        return edit
    }

    /// Sets the six filters of a look and leaves the geometry alone.
    mutating func applyLook(_ look: Edit) {
        brightness = look.brightness
        contrast = look.contrast
        saturation = look.saturation
        hue = look.hue
        blur = look.blur
        grayscale = look.grayscale
    }
}
