import SwiftUIWeb

/// The Seekr name, each letter in a color of the brand: the wordmark of the home page and of the results bar.
struct SeekrWordmark: View {
  var size: CGFloat = 32

  var body: some View {
    HStack(spacing: 0) {
      Text("S").foregroundStyle(SeekrPalette.indigo)
      Text("e").foregroundStyle(SeekrPalette.coral)
      Text("e").foregroundStyle(SeekrPalette.amber)
      Text("k").foregroundStyle(SeekrPalette.teal)
      Text("r").foregroundStyle(SeekrPalette.indigo)
    }
    .font(.system(size: size, weight: .bold))
    .accessibilityLabel("Seekr")
  }
}
