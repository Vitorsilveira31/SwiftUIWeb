import Observation

/// Owns the reader's state. The source text is the truth: the document is
/// always parsed from it, so editing the source re-renders live.
@Observable
@MainActor
final class ReaderViewModel {
    struct State: Equatable {
        var sample: Sample = .welcome
        var source = ""
        var document = Document()
        var scrollRequest: ScrollRequest?
        var textSize: TextSize = .standard
        var showsSource = false
        var showsContents = false
    }

    enum Action {
        case selectSample(Sample)
        case setSource(String)
        case setTextSize(TextSize)
        case setShowsSource(Bool)
        case setShowsContents(Bool)
        case jump(toBlock: Int)
    }

    private(set) var state: State
    private let repository: SampleRepository
    private var serial = 0

    /// An empty source means a fresh screen: it opens on the sample it names.
    init(initialState: State = .init(), repository: SampleRepository = BundledSampleRepository()) {
        self.repository = repository
        var loaded = initialState
        if loaded.source.isEmpty {
            loaded.source = repository.source(for: loaded.sample)
        }
        loaded.document = MarkdownParser.parse(loaded.source)
        state = loaded
    }

    func send(_ action: Action) {
        switch action {
        case let .selectSample(sample):
            state.sample = sample
            setSource(repository.source(for: sample))
        case let .setSource(source):
            setSource(source)
        case let .setTextSize(textSize):
            state.textSize = textSize
        case let .setShowsSource(shows):
            state.showsSource = shows
        case let .setShowsContents(shows):
            state.showsContents = shows
        case let .jump(blockID):
            serial += 1
            state.scrollRequest = ScrollRequest(blockID: blockID, serial: serial)
        }
    }

    private func setSource(_ source: String) {
        state.source = source
        state.document = MarkdownParser.parse(source)
    }
}
