import SwiftUI

/// Text drawn inside an exclusion rectangle.
enum WrapCaption: Sendable {
    /// A drop cap: its letter and font size.
    case dropCap(String, CGFloat)
    /// An inset quotation: its text and font size.
    case quote(String, CGFloat)
}
