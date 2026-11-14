import SwiftUIWeb

/// A person's initials in a colored circle. The color comes from the address, so a person keeps it everywhere.
struct MailoAvatar: View {
  let person: MailPerson
  var size: CGFloat = 36

  var body: some View {
    Text(person.initials)
      .font(.caption)
      .fontWeight(.bold)
      .foregroundStyle(Color.white)
      .frame(width: size, height: size)
      .background(MailoPalette.avatars[person.address.utf8.count % MailoPalette.avatars.count])
      .clipShape(Circle())
      .accessibilityHidden(true)
  }
}
