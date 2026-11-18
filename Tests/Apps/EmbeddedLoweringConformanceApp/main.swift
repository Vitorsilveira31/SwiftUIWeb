import SwiftUIWeb
import SwiftUIWebBrowser
import WebOSLog

private struct LoweringRow: Identifiable, Hashable {
  let id: Int
  let name: String
  let visible: Bool
  let children: [LoweringRow]?
}

private enum LoweringRoute: String, CaseIterable, Hashable {
  case first
  case second
}

private struct LoweringMotion {
  var scale: Double = 1
}

// The browser fixture must also compile as a native macOS 13 host target.
// Swift's Observation macro is macOS 14-only, while SwiftUIWeb's own
// ObservableObject/Published bridge has the same invalidation semantics on
// Embedded and remains available on every supported host.
@MainActor final class LoweringObservationModel: ObservableObject {
  @Published var count = 0
}

// This paired declaration is an Embedded compiler fixture for the source
// lowerer's `@Observable` compatibility path. In particular, `count` has no
// declaration-site value and is initialized by `init`, as is common for view
// models that receive their initial state from a dependency.
#if hasFeature(Embedded)
@Observable @MainActor final class InitAssignedViewModel {
  private(set) var count: Int

  init(count: Int) {
    self.count = count
  }

  func increment() {
    count += 1
  }
}
#else
@MainActor final class InitAssignedViewModel: ObservableObject {
  @Published private(set) var count = 0

  init(count: Int) {
    self.count = count
  }

  func increment() {
    count += 1
  }
}
#endif

private struct LoweringRoot: View {
  @Environment(\.colorScheme) private var colorScheme
  private let rows: [LoweringRow] = [
    LoweringRow(id: 1, name: "One", visible: true, children: nil),
    LoweringRow(id: 2, name: "Two", visible: true, children: nil)
  ]
  @State private var trigger = 0
  @State private var model = LoweringObservationModel()
  @State private var viewModel = InitAssignedViewModel(count: 4)
  @State private var showsDeepReviewFixture = false
  @State private var showsStateObjectIdentityFixture = false
  @State private var showsGeometryFixture = false
  @State private var showsParityFixture = false
  @State private var showsCanvasFixture = false
  @State private var showsShapesFixture = false
  @State private var showsAspectFixture = false
  @State private var showsChromeFixture = false
  @State private var showsNetworkMediaFixture = false
  @State private var showsNavigationBarFixture = false
  @State private var showsRetainedOwnerFixture = false
  @State private var showsInsetFixture = false
  @State private var showsGridCellsFixture = false
  @State private var showsPlacementFixture = false
  @State private var showsLabeledFixture = false
  @State private var showsFitFixture = false
  @State private var showsPresentedFixture = false
  @State private var showsRelativeFixture = false
  @State private var showsScrollFixture = false
  @State private var showsScrollRootFixture = false
  @State private var showsTextFixture = false
  @State private var showsPrincipalFixture = false
  @State private var showsNavigationViewFixture = false
  @State private var showsLayerFixture = false
  @State private var showsLazyShelfFixture = false
  @State private var showsLayoutFixture = false
  @State private var showsControlsFixture = false
  @State private var hostRootsFixture: EmbeddedHostRootsKind?
  @State private var showsSplitFixture = false
  @State private var showsLayoutParityFixture = false

  var body: some View {
    if showsDeepReviewFixture {
      EmbeddedDeepReviewFixture()
    } else if showsGeometryFixture {
      EmbeddedGeometryFixture {
        showsGeometryFixture = false
      }
    } else if showsChromeFixture {
      EmbeddedChromeFixture { showsChromeFixture = false }
    } else if showsLabeledFixture {
      EmbeddedLabeledFixture { showsLabeledFixture = false }
    } else if showsFitFixture {
      EmbeddedFitFixture { showsFitFixture = false }
    } else if showsPresentedFixture {
      EmbeddedPresentedFixture { showsPresentedFixture = false }
    } else if showsRelativeFixture {
      EmbeddedRelativeFixture { showsRelativeFixture = false }
    } else if showsScrollFixture {
      EmbeddedScrollFixture { showsScrollFixture = false }
    } else if showsScrollRootFixture {
      EmbeddedScrollRootFixture { showsScrollRootFixture = false }
    } else if showsTextFixture {
      EmbeddedTextFixture { showsTextFixture = false }
    } else if showsPrincipalFixture {
      EmbeddedPrincipalFixture { showsPrincipalFixture = false }
    } else if showsNavigationViewFixture {
      EmbeddedNavigationViewFixture { showsNavigationViewFixture = false }
    } else if showsLayerFixture {
      EmbeddedLayerFixture { showsLayerFixture = false }
    } else if showsLazyShelfFixture {
      EmbeddedLazyShelfFixture { showsLazyShelfFixture = false }
    } else if showsLayoutFixture {
      EmbeddedLayoutFixture { showsLayoutFixture = false }
    } else if showsLayoutParityFixture {
      EmbeddedLayoutParityFixture { showsLayoutParityFixture = false }
    } else if showsControlsFixture {
      EmbeddedControlsFixture { showsControlsFixture = false }
    } else if let kind = hostRootsFixture {
      EmbeddedHostRootsFixture(kind: kind) { hostRootsFixture = nil }
    } else if showsSplitFixture {
      EmbeddedSplitFixture { showsSplitFixture = false }
    } else if showsPlacementFixture {
      EmbeddedPlacementFixture { showsPlacementFixture = false }
    } else if showsInsetFixture {
      EmbeddedInsetFixture { showsInsetFixture = false }
    } else if showsGridCellsFixture {
      EmbeddedGridCellsFixture { showsGridCellsFixture = false }
    } else if showsRetainedOwnerFixture {
      EmbeddedRetainedOwnerFixture { showsRetainedOwnerFixture = false }
    } else if showsNavigationBarFixture {
      EmbeddedNavigationBarFixture { showsNavigationBarFixture = false }
    } else if showsCanvasFixture {
      EmbeddedCanvasFixture { showsCanvasFixture = false }
    } else if showsShapesFixture {
      EmbeddedShapesFixture { showsShapesFixture = false }
    } else if showsAspectFixture {
      EmbeddedAspectFixture { showsAspectFixture = false }
    } else if showsParityFixture {
      EmbeddedSwiftUIParityFixture { showsParityFixture = false }
    } else if showsNetworkMediaFixture {
      EmbeddedNetworkMediaFixtureView { showsNetworkMediaFixture = false }
    } else if showsStateObjectIdentityFixture {
      EmbeddedStateObjectIdentityFixture {
        showsStateObjectIdentityFixture = false
      }
    } else {
      VStack {
        Text(
          (colorScheme == .dark ? "dark" : "light") + ": "
            + "alpha::beta".components(separatedBy: "::").joined(separator: " | ")
        )
        ForEach(rows, id: \.id) { row in Text(row.name) }
        ForEach(rows, id: \.self) { row in Text(row.name) }
        ForEach(LoweringRoute.allCases) { route in Text(route.rawValue) }
        OutlineGroup(rows, children: \.children) { row in Text(row.name) }
        Table(rows) {
          TableColumn("Name", value: \.name)
        }
        Text(rows.map(\.name).filter(\.isEmpty).joined(separator: ","))
        Text("Animated")
          .keyframeAnimator(initialValue: LoweringMotion(), trigger: trigger) { content, value in
            content.scaleEffect(value.scale)
          } keyframes: { _ in
            KeyframeTrack(\.scale) {
              LinearKeyframe(1.1, duration: 0.1)
              LinearKeyframe(1.0, duration: 0.1)
            }
          }
        Button("Run") { trigger += 1 }
        VStack {
          Text("Observed: \(model.count)")
          Button("Update observer") { model.count += 1 }
          Text("Init-assigned: \(viewModel.count)")
          Button("Update init-assigned") { viewModel.increment() }
          ContentBuilderProbe()
          SwitchProbe()
          // `.id` is generic, so these reach _FiberKey's generic initializer; the
          // scalars must keep their own text as the DOM identity.
          Text("Fiber key string id").id("lowering-fiber-key")
          Text("Fiber key integer id").id(42)
          EmbeddedCodableFixtureView()
          EmbeddedPredicateFixtureView()
          EmbeddedBuilderArityFixture()
          EmbeddedBuilderIdentityFixture()
          EmbeddedTabViewFixture()
          EmbeddedMeasurementFixtureView()
          EmbeddedUnicodeFixtureView()
          EmbeddedJSONStreamFixtureView()
          EmbeddedJSONCorpusFixtureView()
          Button("Open deep review fixture") { showsDeepReviewFixture = true }
          Button("Open StateObject identity fixture") { showsStateObjectIdentityFixture = true }
          Button("Open geometry fixture") { showsGeometryFixture = true }
          Button("Open SwiftUI parity fixture") { showsParityFixture = true }
          Button("Open canvas fixture") { showsCanvasFixture = true }
          Button("Open shapes fixture") { showsShapesFixture = true }
          Button("Open aspect fixture") { showsAspectFixture = true }
          Button("Open chrome fixture") { showsChromeFixture = true }
          Button("Open navigation bar fixture") { showsNavigationBarFixture = true }
          Button("Open retained owner fixture") { showsRetainedOwnerFixture = true }
          Button("Open inset fixture") { showsInsetFixture = true }
          Button("Open grid cells fixture") { showsGridCellsFixture = true }
          Button("Open placement fixture") { showsPlacementFixture = true }
          Button("Open labeled fixture") { showsLabeledFixture = true }
          Button("Open fit fixture") { showsFitFixture = true }
          Button("Open presented fixture") { showsPresentedFixture = true }
          Button("Open relative fixture") { showsRelativeFixture = true }
          Button("Open scroll fixture") { showsScrollFixture = true }
          Button("Open scroll root fixture") { showsScrollRootFixture = true }
          Button("Open text fixture") { showsTextFixture = true }
          Button("Open principal fixture") { showsPrincipalFixture = true }
          Button("Open navigation view fixture") { showsNavigationViewFixture = true }
          Button("Open layer fixture") { showsLayerFixture = true }
          Button("Open lazy shelf fixture") { showsLazyShelfFixture = true }
          Button("Open layout fixture") { showsLayoutFixture = true }
          Button("Open controls fixture") { showsControlsFixture = true }
          Button("Open alert fixture") { hostRootsFixture = .alert }
          Button("Open confirmation fixture") { hostRootsFixture = .confirmation }
          Button("Open table fixture") { hostRootsFixture = .table }
          Button("Open chart fixture") { hostRootsFixture = .chart }
          Button("Open form fixture") { hostRootsFixture = .form }
          Button("Open split fixture") { showsSplitFixture = true }
          Button("Open layout parity fixture") { showsLayoutParityFixture = true }
          // OSLog's Logger in the browser: one line per level (`Tools/test-oslog-browser.mjs` reads the console).
          Button("Write log lines") {
            let logger = Logger(subsystem: "conformance", category: "oslog")
            let user = "Ana", items = 3
            logger.debug("debug \(items)")
            logger.info("info \(user)")
            logger.notice("notice \(user, privacy: .public)")
            logger.warning("warning \(items, privacy: .private)")
            logger.error("error \(user)")
            logger.fault("fault")
          }
          Button("Open network media fixture") { showsNetworkMediaFixture = true }
        }
      }
    }
  }
}

/// A switch-style Toggle is a fixed-size layout leaf; it must still take the pointer.
private struct SwitchProbe: View {
  @State private var isOn = false
  var body: some View {
    Toggle("Lowering switch", isOn: $isOn)
    Text(isOn ? "Lowering switch: on" : "Lowering switch: off")
  }
}

private struct ContentBuilderProbe: View {
  @ContentBuilder
  var body: some View {
    Text("ContentBuilder lowered")
    if true {
      Text("ContentBuilder conditional")
    }
  }
}

@main
struct EmbeddedLoweringConformanceApp: BrowserApp {
  var body: some View { WindowGroup { LoweringRoot() } }
}
