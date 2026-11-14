import SwiftUIWeb

/// Overlays as tall as their content (a hairline at a row's bottom, a padded button in a card's top trailing corner, a
/// padded empty stack in the bottom trailing corner) and a menu Picker beside a flexible field in an HStack, which is as
/// wide as its selected label, and an HStack of three flexible views at the priorities -0.5, 0 and 0.5 (each a tier of
/// `flex-grow`). CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`), on WebKit too.
struct EmbeddedLayerFixture: View {
  let onDone: () -> Void
  @State private var query = ""
  @State private var genre = "All"

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      ForEach(["Episode 1", "Episode 2"], id: \.self) { title in
        HStack {
          Text(title)
          Spacer()
        }
        .frame(height: 56)
        .overlay(alignment: .bottom) {
          Rectangle().fill(.gray).frame(height: 0.5).padding(.leading, 20)
        }
      }
      VStack(alignment: .leading) {
        Text("A card")
        Spacer()
      }
      .frame(width: 320, height: 160, alignment: .topLeading)
      .background(.yellow)
      .overlay(alignment: .topTrailing) {
        Button("X") {}.frame(width: 40, height: 40).padding(12)
      }
      Color.blue.opacity(0.2)
        .frame(width: 320, height: 120)
        .overlay(alignment: .bottomTrailing) {
          VStack(spacing: 8) {}.padding(.horizontal, 24).padding(.bottom, 20)
        }
      HStack(spacing: 12) {
        TextField("Search works", text: $query).frame(minWidth: 220, maxWidth: .infinity)
        Picker("Genre", selection: $genre) {
          Text("All").tag("All")
          Text("Telenovela · Suspense and much more").tag("Telenovela")
          Text("Romance").tag("Romance")
        }
        .pickerStyle(.menu)
        .fixedSize()
      }
      .frame(width: 640)
      HStack(spacing: 0) {
        Color.red.frame(maxWidth: .infinity, maxHeight: 20).layoutPriority(-0.5)
        Color.green.frame(maxWidth: .infinity, maxHeight: 20)
        Color.blue.frame(maxWidth: 120, maxHeight: 20).layoutPriority(0.5)
      }
      .frame(width: 320)
    }
    .padding(16)
  }
}
