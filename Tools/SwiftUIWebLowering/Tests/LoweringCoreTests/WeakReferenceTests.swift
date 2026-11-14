import Testing

@testable import LoweringCore

@Suite struct WeakReferenceTests {
  private func weakened(_ source: String) -> LoweringResult { lower(source, rules: ["weak"]) }

  @Test func aWeakSelfClosureAtTheEndOfAFileIsLoweredWithoutReadingPastIt() {
    let result = weakened("let task = { [weak self] in self?.load() }\n")
    #expect(result.counts["weak-self"] == 1)
    #expect(result.text == "let task = { [self] in self.load() }\n")
  }

  @Test func aWeakSelfClosureFollowedByMultibyteTextIsNotSplit() {
    let result = weakened("{ [weak self] in self?.a() }aéé\n")
    #expect(result.counts["weak-self"] == 1)
    #expect(result.text == "{ [self] in self.a() }aéé\n")
  }

  @Test func weakSelfCapturesBecomeStrongAndDropTheirUnwrappingGuard() {
    let result = weakened(
      """
      final class Loader {
        var value = 0
        func start() {
          run { [weak self] in
            guard let self else { return }
            self.value += 1
          }
          run { [ weak self ] result in
            guard let self = self else {
              return
            }
            self?.value = result
            self?[0] = 1
          }
        }
      }

      """
    )
    #expect(result.counts["weak-self"] == 2)
    #expect(!result.text.contains("weak"))
    #expect(!result.text.contains("guard let self"))
    #expect(result.text.contains("run { [self] in\n            self.value += 1\n"))
    #expect(result.text.contains("run { [self] result in\n            self.value = result\n      self[0] = 1\n"))
  }

  @Test func aCaptureListWithNoEnclosingClosureIsStillMadeStrong() {
    let result = weakened("let capture = [weak self]")
    #expect(result.text == "let capture = [self]")
    #expect(result.counts["weak-self"] == 1)
  }

  @Test func theLineAndIndentationAroundADroppedGuardAreKept() {
    let result = weakened(
      """
      run { [weak self] in
        guard let self else { return }; self?.go()
        guard let self = self else { return } // note
        self?.stop()
      }

      """
    )
    #expect(result.text == "run { [self] in\n  ; self.go()\n   // note\n  self.stop()\n}\n")
  }

  @Test func otherWeakCapturesKeepTheObjectAliveAsAnOptional() {
    let result = weakened(
      """
      let handler = { [weak model, weak view] in model?.refresh() }
      let both = { [weak self, weak delegate] in self?.go() }
      let named = { [weak owner = store.owner] in owner?.go() }
      let spaced = { [
        weak first,
        unowned second
      ] in first?.go() }

      """
    )
    #expect(result.text.contains("[model = Optional(model), view = Optional(view)] in model?.refresh()"))
    #expect(result.text.contains("[self = Optional(self), delegate = Optional(delegate)] in self?.go()"))
    #expect(result.text.contains("[owner = Optional(store.owner)] in"))
    #expect(result.text.contains("[\n  first = Optional(first),\n  unowned second\n]"))
    #expect(result.counts["weak-capture"] == 6)
    #expect(result.counts["weak-self"] == nil)
  }

  @Test func weakPropertiesBecomeOrdinaryOnes() {
    let result = weakened(
      """
      final class Node {
        weak var parent: Node?
        private weak var owner: Owner?
        weak public var shown: Node?
        weak
          var spread: Node?
        @IBOutlet weak var label: Label!
        unowned var kept: Node
      }

      """
    )
    #expect(result.text.contains("final class Node {\n  var parent: Node?\n"))
    #expect(result.text.contains("  private var owner: Owner?\n"))
    #expect(result.text.contains("  public var shown: Node?\n"))
    #expect(result.text.contains("  var spread: Node?\n"))
    #expect(result.text.contains("  @IBOutlet var label: Label!\n"))
    #expect(result.text.contains("  unowned var kept: Node\n"))
    #expect(result.counts["weak-property"] == 5)
  }

  @Test func theWholePipelineLowersWeakReferencesOnceAndLeavesTheirNeighboursAlone() {
    let source = """
      let handler = { [weak model, weak view] in model?.refresh() }
      final class Node { weak var parent: Node? }
      struct Library: View {
        @Query(sort: \\Item.timestamp) var items: [Item]
      }

      """
    let result = lower(source)
    #expect(result.text.contains("[model = Optional(model), view = Optional(view)]"))
    #expect(result.text.contains("final class Node { var parent: Node? }"))
    #expect(result.text.contains("@Query(sort: { (model: Item) in model.timestamp }) var items: [Item]"))
    #expect(result.counts["weak-capture"] == 2)
    #expect(result.counts["weak-property"] == 1)
    #expect(result.counts["query-sort-key-path"] == 1)
    let again = lower(result.text)
    #expect(again.text == result.text)
  }

  @Test func theTreeReadsCaptureListsClosuresAndOptionalChainsNotText() {
    let result = weakened(
      """
      let text = "Use [weak self] and weak var here"
      // run { [weak self] in self?.go() }
      let word = "weak"
      run { [weak self] in
        let myself: Thing? = nil
        _ = myself?.value
        run { [weak self] in
          guard let self else { return }
          self?.inner()
        }
        _ = self?.outer
        _ = other?.name
      }

      """
    )
    #expect(result.text.contains("\"Use [weak self] and weak var here\""))
    #expect(result.text.contains("// run { [weak self] in self?.go() }"))
    #expect(result.text.contains("let word = \"weak\""))
    #expect(result.text.contains("_ = myself?.value"))
    #expect(result.text.contains("_ = other?.name"))
    #expect(result.text.contains("\n  run { [self] in\n        self.inner()\n"))
    #expect(result.text.contains("_ = self.outer"))
    #expect(result.counts["weak-self"] == 2)
  }

  @Test func aClosureWhoseBodyIsNotClosedStillLosesItsWeakCapture() {
    let result = weakened("run { [weak self] in\n  self?.go()\n")
    #expect(result.text == "run { [self] in\n  self?.go()\n")
    #expect(result.counts["weak-self"] == 1)
  }

  @Test func theFrameworkKeepsItsWeakReferences() {
    let source = "final class Box { weak var owner: Owner?; let run = { [weak self] in self?.go() } }\n"
    let pipeline = LoweringPipeline.standard.selecting(["weak"])!
    #expect(lower(pipeline, source, options: LoweringOptions(lowerCodable: false)).text == source)
  }
}
