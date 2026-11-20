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
