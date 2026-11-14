import SwiftUI

// The gallery screen: a segmented control picks one of ten pages of fixtures.
struct GalleryView: View {
    @State private var page: GalleryPage = .one

    var body: some View {
        VStack(spacing: 12) {
            Picker(Strings.Gallery.pageLabel, selection: $page) {
                ForEach(GalleryPage.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("gallery-page-picker")

            ScrollView {
                GalleryPageContent(page: page)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
            }
        }
        .padding(.top, 8)
        .accessibilityIdentifier("gallery")
    }
}
