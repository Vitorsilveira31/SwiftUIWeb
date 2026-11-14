import SwiftUIWeb

/// The person's albums as round highlights, each with the first letter of its title.
struct ProfileHighlights: View {
  let titles: [String]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 16) {
        ForEach(titles, id: \.self) { title in
          VStack(spacing: 6) {
            Text(String(title.prefix(1)).uppercased())
              .font(.title3)
              .fontWeight(.semibold)
              .foregroundStyle(.white)
              .frame(width: 60, height: 60)
              .background(LumioPalette.brand)
              .clipShape(Circle())
            Text(title).font(.caption).lineLimit(1).frame(width: 76)
          }
        }
      }
      .padding(.horizontal, 12)
    }
  }
}
