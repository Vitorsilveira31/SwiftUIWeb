import SwiftUIWeb

#if hasFeature(Embedded)
@Observable
@MainActor private final class EmbeddedReviewNavigationModel {
  var selectedTab = "overview"
}
#else
@MainActor private final class EmbeddedReviewNavigationModel: ObservableObject {
  @Published var selectedTab = "overview"
}
#endif

struct EmbeddedDeepReviewFixture: View {
  @State private var isSignedIn = false
  @State private var viewModel: EmbeddedReviewNavigationModel
  @State private var path = NavigationPath()
  private var reviewTargets: [String] { ["review"] }

  init() {
    _viewModel = State(wrappedValue: EmbeddedReviewNavigationModel())
  }

  var body: some View {
    ZStack {
      if isSignedIn {
        HStack {
          VStack {
            Text("Creative Studio")
            Button("Inbox") {}
          }
          Divider()
          VStack {
            Text("Review detail")
            NavigationStack(path: $path) {
              Button("Open review production") { path.append("review") }
                .navigationDestination(for: String.self) { _ in
                  ScrollView {
                    VStack {
                      Text("Production")
                      HStack {
                        VStack {
                          Text("A station")
                          Text("Waiting Human")
                        }
                        Spacer()
                        Text("Work 360")
                      }
                      HStack {
                        Button("Overview") { viewModel.selectedTab = "overview" }
                        Button("Open reviews") { viewModel.selectedTab = "reviews" }
                      }
                      switch viewModel.selectedTab {
                      case "reviews":
                        VStack {
                          Text("Workflow reviews")
                          if reviewTargets.isEmpty {
                            Text("No review tasks")
                          } else {
                            ForEach(reviewTargets, id: \.self) { _ in
                              AnyView(EmbeddedStatefulComparisonFixture())
                            }
                          }
                          Text("Review history")
                        }
                      default:
                        Text("Overview")
                      }
                    }
                  }
                  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
          }
        }
      } else {
        Button("Enter Studio") { isSignedIn = true }
      }
    }
  }
}
