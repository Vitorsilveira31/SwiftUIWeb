import SwiftUI

/// One fixture: a canvas on white or black, captioned with its identifier.
struct FixtureTile: View {
    let fixture: Fixture
    let step: Int
    let backdrop: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                fixture.draw(into: &context, size: size, step: step)
            }
            .frame(width: fixture.width(step: step), height: TileMetrics.height)
            .background(backdrop ? Color.black : Color.white)
            .foregroundStyle(fixture.foreground)
            .accessibilityIdentifier(fixture.identifier)

            Text(fixture.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
