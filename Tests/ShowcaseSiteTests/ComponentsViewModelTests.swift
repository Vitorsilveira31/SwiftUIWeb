import Testing
@testable import ShowcaseSite

@MainActor
struct ComponentsViewModelTests {
  private func makeModel() -> ComponentsViewModel {
    ComponentsViewModel(
      load: DefaultLoadComponentCatalogUseCase(repository: LiveComponentCatalogRepository()),
      search: DefaultSearchComponentCatalogUseCase()
    )
  }

  @Test func theFirstEntryIsShownAtStart() {
    #expect(makeModel().selectedID == "text")
  }

  @Test func theEntriesAreGroupedInTheOrderOfTheCategories() {
    #expect(makeModel().groups(.en).map(\.category) == [.content, .controls, .layout, .collections])
  }

  @Test func searchingKeepsTheMatchesOfTheLanguageShown() {
    let model = makeModel()
    model.query = "slid"
    #expect(model.groups(.en).flatMap(\.recipes).map(\.id) == ["slider"])
    model.query = "booleano"
    #expect(model.groups(.pt).flatMap(\.recipes).map(\.id) == ["toggle"])
    #expect(model.groups(.en).isEmpty)
  }

  @Test func theWholeCatalogIsListedWhateverTheSearchHolds() {
    let model = makeModel()
    let everything = model.allGroups().flatMap(\.recipes).map(\.id)
    model.query = "nothing matches this"
    #expect(model.groups(.en).isEmpty)
    #expect(model.allGroups().flatMap(\.recipes).map(\.id) == everything)
    #expect(everything.contains("slider") && everything.contains("text"))
  }

  @Test func changingAKnobKeepsItUntilAnotherEntryIsShown() {
    let model = makeModel()
    model.set("bold", bool: true)
    #expect(model.values.bool("bold"))
    model.select("button")
    #expect(model.values.text("title") == "Save")
    model.select("text")
    #expect(!model.values.bool("bold"))
  }

  @Test func openingAnEntryByItsIdShowsItWithDefaultKnobs() {
    let model = makeModel()
    model.set("content", text: "changed")
    model.open(entry: "slider")
    #expect(model.selectedID == "slider")
    model.open(entry: "text")
    #expect(model.values.text("content") == "Hello, SwiftUIWeb")
  }

  @Test func anUnknownOrMissingEntryLeavesTheOneShown() {
    let model = makeModel()
    model.open(entry: "nothing")
    model.open(entry: nil)
    #expect(model.selectedID == "text")
  }

  @Test func openingTheEntryAlreadyShownKeepsTheKnobsAsTheyAre() {
    let model = makeModel()
    model.set("bold", bool: true)
    model.open(entry: "text")
    #expect(model.values.bool("bold"))
  }

  @Test func resettingPutsTheKnobsBackAtTheirDefaults() {
    let model = makeModel()
    model.set("content", text: "changed")
    model.resetKnobs()
    #expect(model.values.text("content") == "Hello, SwiftUIWeb")
  }
}
