/// One page of results and how many results the search has in all.
struct SeekrResultPage: Equatable {
  let results: [SeekrResult]
  let total: Int
}
