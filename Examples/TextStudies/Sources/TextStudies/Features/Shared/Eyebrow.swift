import SwiftUI

/// Small label above each study.
struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(2)
            .foregroundStyle(.secondary)
    }
}
