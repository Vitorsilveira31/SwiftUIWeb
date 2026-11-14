/// Where a screen's data is: being fetched, there, or not reachable (with the reason to show).
enum LoadState: Equatable {
  case loading
  case loaded
  case failed(String)
}
