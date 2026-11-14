import SwiftUI

extension View {
    // The shared look of the screen's cards: a soft fill that reads in both schemes.
    func cardStyle() -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.gray.opacity(0.12)))
    }
}
