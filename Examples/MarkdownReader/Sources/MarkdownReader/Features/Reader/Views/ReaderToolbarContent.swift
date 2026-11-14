import SwiftUI

/// The reader's toolbar: contents, the Source toggle, and the text size and
/// sample menus.
struct ReaderToolbarContent: ToolbarContent {
    let viewModel: ReaderViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                viewModel.send(.setShowsContents(true))
            } label: {
                Label(Strings.Reader.contents, systemImage: "list.bullet")
            }
            .accessibilityIdentifier("markdown-contents")

            Toggle(isOn: Binding(
                get: { viewModel.state.showsSource },
                set: { viewModel.send(.setShowsSource($0)) }
            )) {
                Label(Strings.Reader.source, systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("markdown-source-toggle")

            Menu {
                Picker(Strings.Reader.textSize, selection: Binding(
                    get: { viewModel.state.textSize },
                    set: { viewModel.send(.setTextSize($0)) }
                )) {
                    ForEach(TextSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
            } label: {
                Label(Strings.Reader.textSize, systemImage: "textformat.size")
            }
            .accessibilityIdentifier("markdown-text-size")

            Menu {
                Picker(Strings.Reader.sample, selection: Binding(
                    get: { viewModel.state.sample },
                    set: { viewModel.send(.selectSample($0)) }
                )) {
                    ForEach(Sample.allCases) { sample in
                        Text(sample.title).tag(sample)
                    }
                }
            } label: {
                Label(Strings.Reader.samples, systemImage: "doc.text")
            }
            .accessibilityIdentifier("markdown-samples")
        }
    }
}
