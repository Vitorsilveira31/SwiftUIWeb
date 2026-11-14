import SwiftUI

/// The gallery screen: a segmented control over the two pages, the page in a scroll view, and Restart.
struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Picker(Strings.Gallery.pagePicker, selection: Binding(
                get: { viewModel.state.page },
                set: { viewModel.send(.selectPage($0)) }
            )) {
                Text(Strings.Gallery.fixtures).tag(GalleryPage.fixtures)
                Text(Strings.Gallery.shimmer).tag(GalleryPage.shimmer)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("gallery-page")

            ScrollView {
                Group {
                    switch viewModel.state.page {
                    case .fixtures:
                        FixturesPage()
                    case .shimmer:
                        ShimmerPage()
                    }
                }
                .id(viewModel.state.generation)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Strings.Gallery.restart, systemImage: "arrow.counterclockwise") {
                    viewModel.send(.restart)
                }
                .accessibilityIdentifier("restart")
            }
        }
    }
}
