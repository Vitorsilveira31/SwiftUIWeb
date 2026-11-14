import SwiftUI

// Shows the last tapped element, in the grid's space beside the fixtures.
struct PickedLabel: View {
    let viewModel: HitTestViewModel

    var body: some View {
        Text(viewModel.state.picked.rawValue)
            .font(.system(size: 13))
            .accessibilityIdentifier("picked-label")
            .frame(width: 120, height: 80, alignment: .topLeading)
    }
}
