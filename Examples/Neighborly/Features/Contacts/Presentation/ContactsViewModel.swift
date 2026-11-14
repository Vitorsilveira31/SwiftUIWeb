import SwiftUIWeb

/// The people of Neighborly, as the contacts column and the Photos picker show them, and the cities they are grouped by.
@MainActor @Observable
final class ContactsViewModel {
  private(set) var people: [NeighborlyUser] = []
  private(set) var state: LoadState = .loading
  private let loadPeople: any LoadPeopleUseCase

  init(load: any LoadPeopleUseCase) { loadPeople = load }

  /// The cities of the people, each once and in order: one group per city.
  var cities: [String] { Array(Set(people.map(\.city))).sorted() }

  func load() async {
    state = .loading
    do {
      people = try await loadPeople.execute()
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }
}
