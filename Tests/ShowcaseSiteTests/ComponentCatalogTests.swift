import Testing
@testable import ShowcaseSite

@MainActor
struct ComponentCatalogTests {
  private let recipes = LiveComponentCatalogRepository().recipes()

  @Test func everyEntryHasItsOwnId() {
    let ids = recipes.map(\.id)
    #expect(Set(ids).count == ids.count)
  }

  @Test func everyKnobOfAnEntryHasItsOwnId() {
    for recipe in recipes {
      let ids = recipe.knobs.map(\.id)
      #expect(Set(ids).count == ids.count, "\(recipe.id)")
    }
  }

  @Test func everyEntryHasCodeAtItsDefaults() {
    for recipe in recipes {
      let code = recipe.code(CatalogKnobValues(defaults: recipe.knobs))
      #expect(!code.isEmpty, "\(recipe.id)")
    }
  }

  /// The code the page shows and the view it draws come from the same values, so a knob that changes nothing in the code
  /// is a knob the code does not tell the truth about.
  @Test func everyKnobChangesTheCode() {
    for recipe in recipes {
      let defaults = CatalogKnobValues(defaults: recipe.knobs)
      let before = recipe.code(defaults)
      for knob in recipe.knobs {
        var changed = defaults
        switch knob.kind {
        case .toggle(let value): changed.set(knob.id, bool: !value)
        case .choice(let options, let index): changed.set(knob.id, choiceIndex: (index + 1) % options.count)
        case .number(let range, _, let value): changed.set(knob.id, number: value == range.upperBound ? range.lowerBound : range.upperBound)
        case .text: changed.set(knob.id, text: "changed")
        }
        #expect(recipe.code(changed) != before, "\(recipe.id).\(knob.id)")
      }
    }
  }

  @Test func theDefaultsStayInsideTheRangeOfEveryNumberKnob() {
    for recipe in recipes {
      for knob in recipe.knobs {
        if case .number(let range, _, let value) = knob.kind { #expect(range.contains(value), "\(recipe.id).\(knob.id)") }
      }
    }
  }

  @Test func everyEntryIsExplainedInBothLanguages() {
    for recipe in recipes {
      #expect(!recipe.summary.pt.isEmpty && !recipe.summary.en.isEmpty, "\(recipe.id)")
      for knob in recipe.knobs { #expect(!knob.label.pt.isEmpty && !knob.label.en.isEmpty, "\(recipe.id).\(knob.id)") }
    }
  }
}
