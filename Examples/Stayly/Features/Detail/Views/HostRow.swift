import SwiftUIWeb

/// Who hosts the stay: the picture, the name, the city and the host's line.
struct HostRow: View {
  let host: StayHost

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(host.avatarURL, alt: host.name)
        .resizable()
        .scaledToFill()
        .frame(width: 56, height: 56)
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(DetailStrings.hostedBy(host.name)).font(.headline)
        Text(DetailStrings.livesIn(host.city)).foregroundStyle(.secondary)
        Text(host.bio).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
