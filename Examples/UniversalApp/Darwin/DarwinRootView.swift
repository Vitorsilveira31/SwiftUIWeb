import SwiftUI

/// Darwin-only chrome stays at the platform boundary. The navigation and state
/// remain in `Sources/Shared/SharedViews.swift`.
struct DarwinRootView: View {
  var body: some View {
    SharedRootView()
  }
}
