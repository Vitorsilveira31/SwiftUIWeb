/// A crop rectangle in the photo's own terms: fractions of the photo's frame.
struct Crop: Equatable, Sendable {
    var x = 0.0
    var y = 0.0
    var width = 1.0
    var height = 1.0

    /// Smallest side a crop may have, so a handle never closes on itself.
    static let minimumSide = 0.12

    /// The crop with one corner moved by `dx`, `dy` (fractions), kept inside the photo.
    func movingCorner(_ corner: Corner, dx: Double, dy: Double) -> Crop {
        var left = x, right = x + width, top = y, bottom = y + height
        if corner.isLeading {
            left = min(max(0, left + dx), right - Self.minimumSide)
        } else {
            right = max(min(1, right + dx), left + Self.minimumSide)
        }
        if corner.isTop {
            top = min(max(0, top + dy), bottom - Self.minimumSide)
        } else {
            bottom = max(min(1, bottom + dy), top + Self.minimumSide)
        }
        return Crop(x: left, y: top, width: right - left, height: bottom - top)
    }
}
