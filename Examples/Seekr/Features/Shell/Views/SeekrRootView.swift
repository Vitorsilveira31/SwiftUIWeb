import SwiftUIWeb

/// Seekr: the home page with the search, or the results of a search. The view models are built here, from the dependencies.
struct SeekrRootView: View {
  @State private var shell: SeekrShellViewModel
  @State private var home: SeekrHomeViewModel

  init(dependencies: SeekrDependencies) {
    let results = SeekrResultsViewModel(searchWeb: dependencies.searchWeb, searchNews: dependencies.searchNews, loadQuestions: dependencies.loadQuestions)
    let images = SeekrImagesViewModel(searchPictures: dependencies.searchPictures)
    let suggestions = SeekrSuggestionsViewModel(load: dependencies.loadSuggestions)
    _shell = State(wrappedValue: SeekrShellViewModel(results: results, images: images, suggestions: suggestions))
    _home = State(wrappedValue: SeekrHomeViewModel(feelingLucky: dependencies.feelingLucky))
  }

  var body: some View {
    switch shell.route {
    case .home:
      SeekrHomeView(shell: shell, home: home)
    case .results:
      SeekrResultsView(shell: shell)
    }
  }
}
