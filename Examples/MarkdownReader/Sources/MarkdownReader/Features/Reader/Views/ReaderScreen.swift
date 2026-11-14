import SwiftUI

/// The reader: the Source editor above the rendered document when it is
/// shown, with the toolbar and the contents sheet.
struct ReaderScreen: View {
    @State private var viewModel = ReaderViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.showsSource {
                SourceEditor(text: Binding(
                    get: { viewModel.state.source },
                    set: { viewModel.send(.setSource($0)) }
                ))
                Divider()
            }
            DocumentView(
                document: viewModel.state.document,
                scrollRequest: viewModel.state.scrollRequest,
                textSize: viewModel.state.textSize
            )
        }
        .toolbar {
            ReaderToolbarContent(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showsContents },
            set: { viewModel.send(.setShowsContents($0)) }
        )) {
            ContentsSheet(headings: viewModel.state.document.headings) { blockID in
                viewModel.send(.jump(toBlock: blockID))
            }
        }
    }
}
