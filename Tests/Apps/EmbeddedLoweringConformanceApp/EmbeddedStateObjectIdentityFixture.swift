import SwiftUIWeb

#if hasFeature(Embedded)
@Observable
@MainActor private final class EmbeddedStateObjectIdentityModel {
  let id: String
  var count = 0

  init(id: String) { self.id = id }

  func increment() { count += 1 }
}
#else
@MainActor private final class EmbeddedStateObjectIdentityModel: ObservableObject {
  let id: String
  @Published var count = 0

  init(id: String) { self.id = id }

  func increment() { count += 1 }
}
#endif

private struct EmbeddedStateObjectIdentityRow: View {
  let id: String
  @State private var viewModel: EmbeddedStateObjectIdentityModel

  init(id: String) {
    self.id = id
    _viewModel = State(wrappedValue: EmbeddedStateObjectIdentityModel(id: id))
  }

  var body: some View {
    Button("\(viewModel.id):\(viewModel.count)") { viewModel.increment() }
  }
}

struct EmbeddedStateObjectIdentityFixture: View {
  let onExit: @MainActor () -> Void
  @State private var showsLeadingRow = false

  var body: some View {
    VStack {
      Button("Return to conformance app", action: onExit)
      Button(showsLeadingRow ? "Remove leading row" : "Insert leading row") {
        showsLeadingRow.toggle()
      }
      if showsLeadingRow { EmbeddedStateObjectIdentityRow(id: "X") }
      EmbeddedStateObjectIdentityRow(id: "A")
    }
  }
}
