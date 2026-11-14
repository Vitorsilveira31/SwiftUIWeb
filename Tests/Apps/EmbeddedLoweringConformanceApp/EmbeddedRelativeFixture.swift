import SwiftUIWeb

/// `containerRelativeFrame`: cards a third of a horizontal ScrollView's width (`count:spacing:`), and frames of the window
/// root's and of a vertical ScrollView's size (the closure form, sampled by Swift), one of them clamped. The last
/// ScrollView follows the window, so a resize changes what it proposes. CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
/// - Variants of the exact form: `span`, a vertical axis and both axes (`count:span:spacing:`).
/// - Closures that decrease, bend, fall and rise again, and that go negative (the length is at least 0).
/// - Frames with a frame, a padding and a background around and inside them, in a ScrollView and at the window root.
/// A vertical ScrollView whose content is narrower than it hugs that content on the CSS path, and `updateContainers` reads the
/// container's length from its box, so the content of each ScrollView here fills its width.
struct EmbeddedRelativeFixture: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(0..<5, id: \.self) { _ in
            Color.teal.frame(height: 30).containerRelativeFrame(.horizontal, count: 3, spacing: 10)
          }
        }
      }
      .frame(width: 320, height: 30)
      Text("A quarter of the window")
        .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in length / 4 }
        .background(Color.gray.opacity(0.15))
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          Color.orange
            .containerRelativeFrame([.horizontal, .vertical]) { length, axis in axis == .horizontal ? min(length, 300) : length / 4 }
          Text("Half of the scroll view")
            .containerRelativeFrame(.horizontal) { length, _ in length / 2 }
            .background(Color.blue.opacity(0.2))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 200)
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          Color.pink.frame(height: 20).containerRelativeFrame(.horizontal, count: 4, span: 2, spacing: 8)
          Color.purple.frame(height: 20).containerRelativeFrame(.horizontal, count: 4, span: 1, spacing: 8)
          Color.mint.frame(height: 20).containerRelativeFrame(.horizontal, count: 1, spacing: 8)
        }
      }
      .frame(width: 320, height: 20)
      HStack(alignment: .top, spacing: 8) {
        ScrollView {
          VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
              Color.indigo.containerRelativeFrame(.vertical, count: 3, spacing: 6)
            }
          }
          .frame(width: 60)
        }
        .frame(width: 60, height: 120)
        ScrollView {
          Color.brown.containerRelativeFrame([.horizontal, .vertical], count: 2, span: 1, spacing: 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 100, height: 80)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          Color.red.frame(height: 10)
            .containerRelativeFrame(.horizontal) { length, _ in max(0, 600 - length) }
          Color.red.frame(height: 10)
            .containerRelativeFrame(.horizontal) { length, _ in length < 400 ? length : 400 + (length - 400) / 4 }
          Color.red.frame(height: 10)
            .containerRelativeFrame(.horizontal) { length, _ in abs(length - 500) }
          Color.red.frame(height: 10)
            .containerRelativeFrame(.horizontal) { length, _ in length - 700 }
          Color.red.frame(height: 10)
            .containerRelativeFrame(.horizontal) { length, _ in length < 480 ? 120 : 240 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(width: 360, height: 90)
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          Color.green.frame(height: 10)
            .containerRelativeFrame(.horizontal, count: 2, spacing: 0)
            .padding(8)
          Color.green.frame(height: 10)
            .padding(.horizontal, 8)
            .containerRelativeFrame(.horizontal, count: 3, spacing: 0, alignment: .trailing)
            .background(Color.gray.opacity(0.15))
          Text("Framed")
            .containerRelativeFrame(.horizontal) { length, _ in length / 2 }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 12)
          Text("Fixed")
            .frame(width: 200, alignment: .leading)
            .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in length / 4 }
            .background(Color.blue.opacity(0.2))
          Color.orange
            .containerRelativeFrame(.horizontal) { length, _ in length / 3 }
            .frame(height: 12)
            .frame(minWidth: 300)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(width: 360, height: 110)
      Color.cyan.frame(height: 14)
        .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: 10)
        .padding(.leading, 20)
    }
    .padding(16)
  }
}
