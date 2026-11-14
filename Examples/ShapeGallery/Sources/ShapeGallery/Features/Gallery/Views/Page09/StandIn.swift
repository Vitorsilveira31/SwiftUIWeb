import SwiftUI

// The picture an image filter is applied to, standing in for a reference photo.
struct StandIn: View {
    var body: some View {
        Image(systemName: "tram.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color(hex: 0x1E40AF))
            .frame(width: 48, height: 18)
    }
}
