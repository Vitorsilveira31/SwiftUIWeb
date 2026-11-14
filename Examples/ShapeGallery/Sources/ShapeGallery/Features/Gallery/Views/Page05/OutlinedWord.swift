import SwiftUI

// SwiftUI's Text cannot stroke, so the outline is four offset copies in the stroke colour
// under the fill.
struct OutlinedWord: View {
    private static let outlineOffsets: [(CGFloat, CGFloat)] = [(-0.75, 0), (0.75, 0), (0, -0.75), (0, 0.75)]

    var body: some View {
        ZStack {
            ForEach(Self.outlineOffsets.indices, id: \.self) { index in
                Text("SVG")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xB45309))
                    .offset(x: Self.outlineOffsets[index].0, y: Self.outlineOffsets[index].1)
            }
            Text("SVG")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Color(hex: 0xFEF3C7))
        }
        .frame(width: 120)
    }
}
