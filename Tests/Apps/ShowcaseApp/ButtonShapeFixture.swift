import SwiftUIWeb

/// Shape fixture for `Tools/test-button-highlight-browser.mjs`.
///
/// Each control is a button whose highlight, focus ring and hit area must follow
/// the visible shape its label declares (capsule, circle, rounded rectangle,
/// content shape, bordered capsule, custom style), or stay a plain rectangle
/// with no fill when no shape is declared. The route is hidden from the sidebar
/// and reached by path (`/buttonShape`) only.
struct ButtonShapeFixture: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("Plain buttons with a declared shape")
      HStack(spacing: 16) {
        Button {
        } label: {
          Text("Capsule")
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(Capsule().fill(Color.gray.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shape-capsule-plain")

        Button {
        } label: {
          Image(systemName: "play.fill")
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.gray.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shape-circle-plain")
      }
      Button {
      } label: {
        VStack(alignment: .leading) {
          Text("Rounded card")
          Text("Detail")
        }
        .frame(width: 240, height: 80, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.25)))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("shape-rounded-plain")

      Button {
      } label: {
        Text("Content shape")
          .padding(.horizontal, 18)
          .frame(height: 40)
          .background(Color.gray.opacity(0.25))
          .contentShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("shape-content-rounded")

      Text("Buttons without a declared shape")
      Button("Plain text") {}
        .buttonStyle(.plain)
        .accessibilityIdentifier("shape-plain-text")

      ShareLink(item: "Sample+") {
        Text("Share")
          .padding(.horizontal, 22)
          .frame(height: 44)
          .background(Capsule().fill(Color.gray.opacity(0.25)))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("shape-share-capsule")

      Text("Custom style and system styles")
      HStack(spacing: 16) {
        Button("Custom capsule") {}
          .buttonStyle(ShapeCapsuleStyle())
          .accessibilityIdentifier("shape-custom-capsule")
        Button("Bordered capsule") {}
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .accessibilityIdentifier("shape-bordered-capsule")
      }
      Button("Disabled capsule") {}
        .buttonStyle(ShapeCapsuleStyle())
        .disabled(true)
        .accessibilityIdentifier("shape-disabled-capsule")
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A custom style that draws its own capsule and pressed dimming, as an app does.
struct ShapeCapsuleStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 22)
      .frame(height: 44)
      .background(Capsule().fill(Color.blue.opacity(0.85)))
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}
