import SwiftUI

/// One corner handle of the crop. Dragging it previews the crop; the drag's end commits it as one edit.
struct CornerHandle: View {
    let corner: Corner
    /// The crop being shown, which places the handle.
    let crop: Crop
    let stage: CGSize
    let viewModel: EditorViewModel
    @Binding var cropPreview: Crop?

    var body: some View {
        let x = (corner.isLeading ? crop.x : crop.x + crop.width) * stage.width
        let y = (corner.isTop ? crop.y : crop.y + crop.height) * stage.height

        Color.clear
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .offset(x: x - 22, y: y - 22)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let movement = movement(value)
                        cropPreview = viewModel.state.edit.crop.movingCorner(corner, dx: movement.dx, dy: movement.dy)
                    }
                    .onEnded { value in
                        let movement = movement(value)
                        cropPreview = nil
                        viewModel.send(.commitGesture(.corner(corner, dx: movement.dx, dy: movement.dy)))
                    }
            )
            .accessibilityLabel(Strings.Editor.cropCorner)
            .accessibilityIdentifier("crop-\(corner)")
    }

    /// The drag so far as fractions of the stage, so the crop moves the same on any size.
    private func movement(_ value: DragGesture.Value) -> (dx: Double, dy: Double) {
        (
            Edit.fraction(value.translation.width, of: stage.width),
            Edit.fraction(value.translation.height, of: stage.height)
        )
    }
}
