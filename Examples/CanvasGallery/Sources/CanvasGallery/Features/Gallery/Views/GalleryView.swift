import SwiftUI

/// The gallery screen: the page picker, the step and backdrop controls, and the tiles of the page.
struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()

    var body: some View {
        VStack(spacing: 10) {
            Picker(Strings.Gallery.page, selection: pageBinding) {
                ForEach(GalleryPage.allCases) { page in
                    Text("\(page.rawValue)")
                        .accessibilityIdentifier("page-\(page.rawValue)")
                        .tag(page)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            GalleryControlRow(viewModel: viewModel)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(viewModel.state.page.fixtures) { fixture in
                        FixtureTile(
                            fixture: fixture,
                            step: viewModel.state.step,
                            backdrop: viewModel.state.backdrop
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .padding(.top, 8)
    }

    private var pageBinding: Binding<GalleryPage> {
        Binding(
            get: { viewModel.state.page },
            set: { viewModel.send(.selectPage($0)) }
        )
    }
}
