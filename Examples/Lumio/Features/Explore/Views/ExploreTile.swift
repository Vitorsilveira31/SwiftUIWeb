import SwiftUIWeb

/// A square of the Explore grid.
struct ExploreTile: View {
  let tile: LumioTile

  var body: some View {
    Image(tile.imageURL, alt: tile.title)
      .resizable()
      .scaledToFill()
      .frame(maxWidth: .infinity)
      .aspectRatio(1, contentMode: .fit)
      .clipped()
  }
}
