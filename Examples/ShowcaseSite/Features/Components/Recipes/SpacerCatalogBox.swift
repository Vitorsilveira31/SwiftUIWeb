import SwiftUIWeb

/// One of the two boxes the spacer pushes apart: a box that stretches, or a fixed one that keeps its ideal size.
struct SpacerCatalogBox: View {
  let isFixed: Bool

  var body: some View {
    if isFixed {
      RoundedRectangle(cornerRadius: 6).fill(Color.blue).frame(minWidth: 40, minHeight: 36).fixedSize()
    } else {
      RoundedRectangle(cornerRadius: 6).fill(Color.blue).frame(minWidth: 40, minHeight: 36)
    }
  }
}
