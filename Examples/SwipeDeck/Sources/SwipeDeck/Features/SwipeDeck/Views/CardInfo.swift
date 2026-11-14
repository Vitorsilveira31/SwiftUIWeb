import SwiftUI

/// The text block at the foot of a card: name, age, job, distance, bio and interest tags.
struct CardInfo: View {
    let profile: Profile
    let isTop: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(profile.name)
                    .font(.system(size: 32, weight: .heavy))
                    .accessibilityIdentifier(isTop ? "top-name" : "name-\(profile.id)")
                Text("\(profile.age)")
                    .font(.system(size: 26))
            }
            Label(profile.job, systemImage: "briefcase.fill")
                .font(.system(size: 15))
                .lineLimit(1)
            Label(Strings.Card.distance(profile.miles), systemImage: "location.fill")
                .font(.system(size: 15))
                .lineLimit(1)
            Text(profile.bio)
                .font(.system(size: 15))
                .lineLimit(2)
            HStack(spacing: 6) {
                ForEach(profile.interests, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 18, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(isTop ? "card-info" : "info-\(profile.id)")
    }
}
