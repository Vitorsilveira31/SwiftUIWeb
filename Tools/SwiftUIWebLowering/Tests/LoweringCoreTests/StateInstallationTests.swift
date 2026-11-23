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
