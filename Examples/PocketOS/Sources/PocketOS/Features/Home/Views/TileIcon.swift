import SwiftUI

// An app's icon: the symbol on a neutral tile. Grid tiles add the zoom to it;
// the dock uses it as it is.
struct TileIcon: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Color.gray.opacity(0.32), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}
