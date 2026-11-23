import Testing

@testable import LoweringCore

@Suite struct StateInstallationTests {
  private func installations(_ source: String) -> LoweringResult { lower(source, rules: ["state-installation"]) }

  @Test func aViewInstallsItsStateInDeclarationOrder() {
    let source = """
      struct Player: View {
        @State var model: PlayerModel
        let title: String
        @State private var engine: Engine
        @StateObject var store = Store()
        @State(memberID: 7) var hovered = false
        @Environment(\\.dismiss) var dismiss
        static var shared = 0

        init(engine: Engine) {
          title = ""
          _engine = State(wrappedValue: engine)
          _model = State(wrappedValue: PlayerModel(engine: engine))
        }

        var body: some View { Text(title) }
      }

      public struct Badge: View {
        @SwiftUI.State var count = 0
        public var body: some View { Text("\\(count)") }
      }

      struct Plain: View {
        let value: Int
        var body: some View { Text("\\(value)") }
      }

      struct Holder {
        private struct Hidden: View {
          @State var on = false
          var body: some View { Text("h") }
        }
        struct Row: View {
          @State var on = false
          var body: some View { Text("r") }
        }
      }

      """
    let result = installations(source)
    #expect(result.counts["state-installation"] == 3)
    #expect(result.text.contains(
      "extension Player {\n  func _installState() { _model._install(); _engine._install(); _store._install(); _hovered._install() }\n}"
    ))
    #expect(result.text.contains("extension Badge {\n  public func _installState() { _count._install() }\n}"))
    #expect(result.text.contains("extension Holder.Row {\n  func _installState() { _on._install() }\n}"))
    #expect(!result.text.contains("extension Plain"))
    #expect(!result.text.contains("Hidden {"))
    let again = installations(result.text)
    #expect(again.counts["state-installation"] == nil)
    #expect(again.text == result.text)
  }

  /// The passes that run after this one write into the installation: `export-interface` marks the function and
  /// `stable-source-locations` puts a directive above it. Lowering that output must still find the installation.
  @Test func anInstallationALaterPassWroteIntoIsNotWrittenAgain() {
    let source = "struct V: View {\n  @State var on = false\n}\n"
    // The debug development loop: a framework file without and with its source locations, and an application file.
    let developmentLoops = [
      LoweringOptions(exportInterface: true),
      LoweringOptions(exportInterface: true, stableSourceLocations: true, sourcePath: "Sources/V.swift"),
      LoweringOptions(
        lowerCodable: true, exportInterface: true, exportInterfaceApplication: true, stableSourceLocations: true, sourcePath: "Web/V.swift"),
    ]
    for options in developmentLoops {
      let once = lower(.standard, source, options: options)
      #expect(once.counts["state-installation"] == 1)
      #expect(once.text.contains("  @export(interface) func _installState() { _on._install() }\n"))
      let again = lower(.standard, once.text, options: options)
      #expect(again.counts["state-installation"] == nil)
      #expect(again.text == once.text)
    }
  }

  @Test func anInstallationIsFoundByItsDeclarationWhateverIsWrittenBeforeIt() {
    let views = "struct V: View {\n  @State var on = false\n}\n\nstruct Holder {\n  struct Row: View {\n    @State var on = false\n  }\n}\n\n"
    let marked = "@export(interface) func _installState() { _on._install() }"
    let written = [
      "extension V {\n  \(marked)\n}\n\nextension Holder.Row {\n  \(marked)\n}\n",
      "extension V {\n  @export(interface)\n  public func _installState() { _on._install() }\n}\n\nextension Holder.Row {\n  \(marked)\n}\n",
      "extension V {\n  #sourceLocation(file: \"Web/V.swift|ext.V.func._installState()\", line: 1)\n  \(marked)\n}\n\nextension Holder.Row {\n  \(marked)\n}\n#sourceLocation()\n",
    ]
    for installation in written {
      let result = installations(views + installation)
      #expect(result.counts["state-installation"] == nil)
      #expect(result.text == views + installation)
    }
  }

  @Test func aFunctionOfAnotherTypeStaticOrWithParametersIsNotTheInstallation() {
    let source = "struct V: View {\n  @State var on = false\n}\n\nextension W {\n  func _installState() {}\n}\n\nextension V {\n  func _installState(in scope: Int) {}\n  static func _installState() {}\n}\n"
    let result = installations(source)
    #expect(result.counts["state-installation"] == 1)
    #expect(result.text.contains("extension V {\n  func _installState() { _on._install() }\n}"))
  }

  // What a method written by hand counts for is what its text counted for before the passes wrote into that text: the
  // member of an extension is the view's installation wherever the extension stands, and a method inside a conditional
  // block of the extension is not.
  @Test func aMethodInAConditionalBlockOfTheExtensionIsNotTheInstallation() {
    // A configuration without `DEBUG` compiles the view and no such method, so the pass still writes its own.
    let source = "struct V: View {\n  @State var on = false\n}\n\nextension V {\n  #if DEBUG\n  func _installState() {}\n  #endif\n}\n"
    let result = installations(source)
    #expect(result.counts["state-installation"] == 1)
    #expect(result.text.contains("extension V {\n  func _installState() { _on._install() }\n}"))
    #expect(installations(result.text).text == result.text)
  }

  @Test func anInstallationInAnExtensionInsideAConditionalBlockIsKept() {
    // A second installation would be declared twice wherever `DEBUG` is set.
    let source = "struct V: View {\n  @State var on = false\n}\n\n#if DEBUG\nextension V {\n  func _installState() {}\n}\n#endif\n"
    let result = installations(source)
    #expect(result.counts["state-installation"] == nil)
    #expect(result.text == source)
  }

  @Test func anotherDeclarationOfTheNameIsNotTheInstallation() {
    // None of these is the method the pass writes, and the written one can be declared beside each of them.
    let view = "struct Box<T>: View {\n  @State var on = false\n}\n\n"
    let others = [
      "extension Box {\n  @inline(__always) func _installState() where T: Equatable {}\n}\n",
      "extension Box {\n  func _installState() async {}\n}\n",
      "extension Box {\n  func _installState<U>() -> U? { nil }\n}\n",
      "extension Box {\n  func _installState() -> Int { 0 }\n}\n",
    ]
    for other in others {
      let result = installations(view + other)
      #expect(result.counts["state-installation"] == 1)
      #expect(result.text.contains("extension Box {\n  func _installState() { _on._install() }\n}"))
      #expect(installations(result.text).text == result.text)
    }
  }

  @Test func anotherSpellingOfTheMethodIsTheSameDeclaration() {
    // The compiler takes `func _installState()` beside any of these for a second declaration, so the view is left alone.
    let view = "struct V: View {\n  @State var on = false\n}\n\n"
    let spellings = [
      "func _installState() throws {}", "mutating func _installState() {}", "nonisolated func _installState() {}",
      "func _installState() -> Void {}", "func _installState() -> (Void) {}", "func _installState() -> Swift.Void {}",
      "func _installState() -> (()) {}", "func `_installState`() {}",
    ]
    for method in spellings {
      let source = view + "extension V {\n  \(method)\n}\n"
      let result = installations(source)
      #expect(result.counts["state-installation"] == nil, "\(method)")
      #expect(result.text == source)
    }
  }

  @Test func aViewThatDeclaresTheMethodInItsBodyIsLeftAlone() {
    // An extension with the method would declare it a second time.
    let source = "struct V: View {\n  @State var on = false\n  func _installState() { _on._install() }\n}\n"
    let result = installations(source)
    #expect(result.counts["state-installation"] == nil)
    #expect(result.text == source)
    // A method inside a conditional block of the body is not the view's: without the block the view has none, so the
    // pass writes its own, as it does for a conditional block of an extension.
    let conditional = "struct W: View {\n  @State var on = false\n  #if DEBUG\n  func _installState() {}\n  #endif\n}\n"
    #expect(installations(conditional).counts["state-installation"] == 1)
  }

  @Test func theInstallationOfAViewInAConditionalBlockIsFoundInThatBlock() {
    let once = installations("#if WEB\nstruct V: View {\n  @State var on = false\n}\n#endif\n")
    #expect(once.text == "#if WEB\nstruct V: View {\n  @State var on = false\n}\n\nextension V {\n  func _installState() { _on._install() }\n}\n#endif\n")
    let again = installations(once.text)
    #expect(again.counts["state-installation"] == nil)
    #expect(again.text == once.text)
  }

  @Test func anExtensionOfSomeOfAGenericViewIsNotItsInstallation() {
    // Neither extends every `Box`, so the view still needs the installation this pass writes for all of them.
    let source = "struct Box<T>: View {\n  @State var on = false\n}\n\nextension Box where T: Equatable {\n  func _installState() {}\n}\n\nextension Box<Int> {\n  func _installState() {}\n}\n"
    let result = installations(source)
    #expect(result.counts["state-installation"] == 1)
    #expect(result.text.contains("extension Box {\n  func _installState() { _on._install() }\n}"))
    #expect(installations(result.text).text == result.text)
  }

  @Test func aViewInAnotherBranchThanItsDeclarationIsLeftAlone() {
    let source = """
      struct Outer {
        #if WEB
        struct Inner: View {
          @State var on = false
          var body: some View { Text("i") }
        }
        #endif
      }

      """
    #expect(installations(source).counts["state-installation"] == nil)
  }

  @Test func itRunsAfterObservableStateAndBeforeTheRendererSPI() {
    let names = LoweringPipeline.ported.map(\.name)
    let index = { (name: String) in names.firstIndex(of: name)! }
    #expect(index("observable-state") < index("state-installation"))
    #expect(index("state-installation") < index("renderer-spi"))
  }
}
