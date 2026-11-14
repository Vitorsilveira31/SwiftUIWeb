import SwiftUI

/// Marks a zero-size subview that ends a paragraph, so the flow starts a new line after the gap.
struct WrapBreakKey: LayoutValueKey {
    static let defaultValue = false
}
