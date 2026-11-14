import Testing
@testable import Neighborly

@MainActor
struct ContactsViewModelTests {
  @Test func theCitiesOfThePeopleAreEachOnceAndInOrder() async {
    let model = ContactsViewModel(load: StubPeople())
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.cities == ["Lisbon", "Porto"])
  }

  @Test func aFailureSaysSoAndHasNoCities() async {
    let stub = StubPeople()
    stub.fails = true
    let model = ContactsViewModel(load: stub)
    await model.load()
    #expect(model.state == .failed(FailureText.unreachable))
    #expect(model.cities.isEmpty)
  }
}
