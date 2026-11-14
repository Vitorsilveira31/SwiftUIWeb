import SwiftUIWeb

/// What the stay offers, one line each.
struct AmenityList: View {
  let amenities: [StayAmenity]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(DetailStrings.offers).font(.headline)
      ForEach(amenities, id: \.self) { amenity in
        Label(DetailStrings.amenity(amenity), systemImage: "checkmark.circle")
      }
    }
  }
}
