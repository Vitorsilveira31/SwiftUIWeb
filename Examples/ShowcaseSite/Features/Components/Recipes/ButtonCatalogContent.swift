import SwiftUIWeb

/// The `Button` itself, before a style is applied to it; each tap adds to the count the preview shows.
struct ButtonCatalogContent: View {
  let title: String
  let isDestructive: Bool
  let isDisabled: Bool
  @Binding var taps: Int

  var body: some View {
    Button(title, role: isDestructive ? .destructive : nil) { taps += 1 }.disabled(isDisabled)
  }
}
