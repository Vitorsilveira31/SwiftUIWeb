import CloneKit

/// What Seekr needs from the outside, in one place: a test builds it with doubles, the app with `live`.
struct SeekrDependencies {
  let loadSuggestions: any LoadSuggestionsUseCase
  let searchWeb: any SearchWebUseCase
  let searchNews: any SearchNewsUseCase
  let loadQuestions: any LoadQuestionsUseCase
  let searchPictures: any SearchPicturesUseCase
  let feelingLucky: any FeelingLuckyUseCase

  static var live: SeekrDependencies {
    let client = PlaceholderClient()
    let web = LiveWebRepository(client: client)
    return SeekrDependencies(
      loadSuggestions: DefaultLoadSuggestionsUseCase(repository: LiveSuggestionRepository(client: client)),
      searchWeb: DefaultSearchWebUseCase(repository: web),
      searchNews: DefaultSearchNewsUseCase(repository: web),
      loadQuestions: DefaultLoadQuestionsUseCase(repository: web),
      searchPictures: DefaultSearchPicturesUseCase(repository: LivePictureRepository(client: client)),
      feelingLucky: DefaultFeelingLuckyUseCase(repository: web)
    )
  }
}
