import SwiftUI

// The grid every page uses: adaptive 120-point columns, one tile per fixture.
struct FixtureGrid<Content: View>: View {
    @ViewBuilder var content: Content

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            content
        }
    }
}
