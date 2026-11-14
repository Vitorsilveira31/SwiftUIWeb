import SwiftUIWeb

struct EmbeddedBuilderStatefulButton: View {
  let label: String
  @State private var count = 0

  var body: some View {
    Button("\(label):\(count)") { count += 1 }
  }
}
