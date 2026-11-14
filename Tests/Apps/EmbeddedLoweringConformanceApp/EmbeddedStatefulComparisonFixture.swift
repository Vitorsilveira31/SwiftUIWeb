import SwiftUIWeb

#if hasFeature(Embedded)
@Observable
// The Embedded browser fixture runs on one JavaScript event loop, the main actor.
@MainActor private final class EmbeddedComparisonModel {
  private(set) var isExpanded = false
  private(set) var isLoading = false

  func prepare() async {
    isExpanded = true
    isLoading = true
    await Task.yield()
    isLoading = false
  }

  func dismiss() {
    isExpanded = false
    isLoading = false
  }
}
#else
@MainActor private final class EmbeddedComparisonModel: ObservableObject {
  @Published private(set) var isExpanded = false
  @Published private(set) var isLoading = false

  func prepare() async {
    isExpanded = true
    isLoading = true
    await Task.yield()
    isLoading = false
  }

  func dismiss() {
    isExpanded = false
    isLoading = false
  }
}
#endif

struct EmbeddedStatefulComparisonFixture: View {
  @State private var viewModel: EmbeddedComparisonModel
  @State private var comment = ""

  init() {
    _viewModel = State(wrappedValue: EmbeddedComparisonModel())
  }

  var body: some View {
    VStack {
      Button(viewModel.isExpanded ? "Hide previous version" : "Load previous version") {
        if viewModel.isExpanded {
          viewModel.dismiss()
        } else {
          let model = viewModel
          Task { await model.prepare() }
        }
      }
      if viewModel.isExpanded {
        Text(viewModel.isLoading ? "Previous version loading" : "Previous version loaded")
      }
      TextField("Reviewer comment", text: $comment)
    }
  }
}
