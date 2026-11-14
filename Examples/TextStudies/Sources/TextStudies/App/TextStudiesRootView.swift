import SwiftUI

/// The text studies: a menu picks one of seven studies, and the toolbar pauses the clock
/// the animated studies read. Both hosts load this view.
public struct TextStudiesRootView: View {
    @State private var viewModel = TextStudiesViewModel(repository: SampleTextRepository())

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(Strings.Root.studyPicker, selection: Binding(
                    get: { viewModel.state.study },
                    set: { viewModel.send(.select($0)) })
                ) {
                    ForEach(TextStudy.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("scene-picker")
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
                switch viewModel.state.study {
                case .balls:
                    BallsStudyView(clock: viewModel.state.clock, words: viewModel.state.prose.ballWords)
                case .dragon:
                    DragonStudyView(
                        words: viewModel.state.prose.dragonWords,
                        dropCap: viewModel.state.prose.dropCapLetter)
                case .masonry:
                    MasonryStudyView(repository: SampleTextRepository())
                case .magazine:
                    MagazineStudyView(
                        words: viewModel.state.prose.articleWords,
                        breaks: viewModel.state.prose.articleBreaks)
                case .ascii:
                    AsciiStudyView(clock: viewModel.state.clock)
                case .wall:
                    WallStudyView(cards: viewModel.state.wallCards)
                case .spread:
                    SpreadStudyView(prose: viewModel.state.prose)
                }
            }
            .navigationTitle(Strings.Root.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(viewModel.state.clock.isRunning ? Strings.Root.pause : Strings.Root.play) {
                        viewModel.send(.togglePlayback)
                    }
                    .accessibilityIdentifier("pause")
                }
            }
        }
    }
}
