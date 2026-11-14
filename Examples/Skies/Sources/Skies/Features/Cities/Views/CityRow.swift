import SwiftUI

// One city in the picker, with a check mark on the one the forecast shows.
struct CityRow: View {
    let city: CityVO
    let selected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(.body)
                Text(city.region)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
