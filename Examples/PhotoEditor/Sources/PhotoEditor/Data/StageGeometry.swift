import SwiftUI

/// The stage's geometry, shared by the screen and the export so both frame the picture the same way.
enum StageGeometry {
    /// The stage keeps this aspect, so a fraction of it means the same on screen and in the export.
    static let aspect = 1.5
    /// The export's size; the stage's pan and crop are fractions, so any size renders the same picture.
    static let exportSize = CGSize(width: 1200, height: 800)
}
