import SwiftUI

/// The marker of a list item: a bullet glyph that changes with depth, the
/// number, or a task's checkbox.
struct ListMarkerView: View {
    let marker: ListMarker
    let depth: Int

    var body: some View {
        switch marker {
        case .bullet:
            Text(bulletGlyph)
                .foregroundStyle(.secondary)
        case let .number(number):
            Text("\(number).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case let .task(checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }

    private var bulletGlyph: String {
        depth == 0 ? "\u{2022}" : depth == 1 ? "\u{25E6}" : "\u{25AA}"
    }
}
