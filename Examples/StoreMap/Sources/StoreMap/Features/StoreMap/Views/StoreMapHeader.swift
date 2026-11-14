import SwiftUI

struct StoreMapHeader: View {
    let selectedID: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Strings.Stores.title)
                .font(.title3.weight(.semibold))
            Spacer()
            Text(selectionStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("selected")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var selectionStatus: String {
        selectedID.map { Strings.Stores.selected($0) } ?? Strings.Stores.noStoreSelected
    }
}
