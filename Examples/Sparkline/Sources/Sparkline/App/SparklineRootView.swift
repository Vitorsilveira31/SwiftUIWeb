import SwiftUI

/// The app's entry view. Both hosts load it; the NavigationStack and the
/// title are what the old demo's host provided.
public struct SparklineRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            MarketsView()
                .navigationTitle(Strings.Markets.title)
        }
    }
}
