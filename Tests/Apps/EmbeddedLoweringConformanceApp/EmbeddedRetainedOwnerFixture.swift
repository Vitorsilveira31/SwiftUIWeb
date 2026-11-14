import SwiftUIWeb

#if hasFeature(Embedded)
@Observable
@MainActor private final class RetainedOwnerRouter {
  var section = RetainedOwnerSection.catalog
  var detail = 0
}
#else
@MainActor private final class RetainedOwnerRouter: ObservableObject {
  @Published var section = RetainedOwnerSection.catalog
  @Published var detail = 0
}
#endif

private enum RetainedOwnerSection: String, CaseIterable, Hashable {
  case catalog
  case queue
  case settings
}

private enum RetainedOwnerField: Hashable {
  case email
  case password
}

/// The shape of an application shell that navigates by one shared model:
/// - the model is injected above a `TabView` whose tabs come from a `ForEach`, and each tab's screen reads it with
///   `@Environment(Model.self)` while building its title and body. Writing the model re-renders that tab's owner
///   on its own, outside any enclosing view's render, where the screen must still resolve the model and keep its
///   `@State`;
/// - a sign-in form with two fields bound to a `FocusState`: the person moves from one field to the next, and the
///   keystrokes that follow belong to the field they moved to;
/// - a screen that traps while it renders (a button writes the value it traps on): the page must report that once and
///   stop calling into the instance, which the trap left with a render pass open.
struct EmbeddedRetainedOwnerFixture: View {
  let onDone: () -> Void
  @State private var router = RetainedOwnerRouter()
  @State private var email = ""
  @State private var password = ""
  @FocusState private var field: RetainedOwnerField?

  var body: some View {
    VStack {
      Button("Return to conformance app") { onDone() }
      Button("Trap on purpose") { router.detail = -1 }
      RetainedOwnerShell()
        .environment(router)
      VStack {
        TextField("Retained e-mail", text: $email)
          .focused($field, equals: .email)
        SecureField("Retained password", text: $password)
          .focused($field, equals: .password)
        Text("Typed: \(email.count)/\(password.count)")
      }
    }
  }
}

private struct RetainedOwnerShell: View {
  @Environment(RetainedOwnerRouter.self) private var router

  var body: some View {
    VStack {
      Button("Write the model") { router.detail += 1 }
      TabView(selection: Binding(get: { router.section }, set: { router.section = $0 })) {
        ForEach(RetainedOwnerSection.allCases, id: \.self) { section in
          Tab(section.rawValue, systemImage: "circle", value: section) {
            RetainedOwnerScreen(section: section)
          }
          .badge(section == .queue && router.detail > 1 ? Text("\(router.detail)") : nil)
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    }
  }
}

private struct RetainedOwnerScreen: View {
  let section: RetainedOwnerSection
  @Environment(RetainedOwnerRouter.self) private var router
  @State private var taps = 0

  var body: some View {
    VStack {
      Text("Screen \(section.rawValue): detail \(title)")
      Button("Tap \(section.rawValue)") { taps += 1 }
      Text("Taps \(section.rawValue): \(taps)")
    }
    .navigationTitle(title)
  }

  private var title: String {
    // The model's value names a trap on purpose: it happens while the screen renders, with a render pass open.
    if router.detail < 0 { fatalError("deliberate trap in a render pass") }
    return "\(router.detail)"
  }
}
