import SwiftUI

/// One button per store that has one; a tap selects the store and centres the map on it.
struct StorePickRow: View {
    let viewModel: StoreMapViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.state.stores.filter(\.hasPickButton)) { store in
                Button(store.title) {
                    viewModel.send(.choose(store.id))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pick-\(store.id)")
            }
        }
    }
}
