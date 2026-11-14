import SwiftUI

/// The stage: the photo with its gestures, the crop overlay and the four corner handles. The live gesture values
/// stay here, and each gesture sends one action when it ends.
struct EditorStage: View {
    let viewModel: EditorViewModel
    let size: CGSize

    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveRotation: Angle = .zero
    @GestureState private var livePan: CGSize = .zero
    /// The crop while a corner is dragged; nil when the committed crop is the one to show.
    @State private var cropPreview: Crop?

    var body: some View {
        let edit = viewModel.state.edit
        let shown = edit.previewing(
            magnification: liveMagnification,
            rotation: liveRotation,
            pan: livePan,
            stage: size
        )
        let crop = cropPreview ?? edit.crop

        ZStack(alignment: .topLeading) {
            // The gestures sit on the photo's layer, not on the handles, so a corner drag never pans the photo.
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.18))
                EditorPhoto(source: viewModel.state.source, edit: shown, stage: size)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(turnGesture)
            .simultaneousGesture(panGesture)

            CropOverlay(crop: crop)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

            ForEach(Corner.allCases, id: \.self) { corner in
                CornerHandle(
                    corner: corner,
                    crop: crop,
                    stage: size,
                    viewModel: viewModel,
                    cropPreview: $cropPreview
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($liveMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                viewModel.send(.commitGesture(.zoom(Double(value.magnification))))
            }
    }

    private var turnGesture: some Gesture {
        RotateGesture()
            .updating($liveRotation) { value, state, _ in
                state = value.rotation
            }
            .onEnded { value in
                viewModel.send(.commitGesture(.turn(value.rotation.radians)))
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($livePan) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                viewModel.send(.commitGesture(.pan(
                    dx: Edit.fraction(value.translation.width, of: size.width),
                    dy: Edit.fraction(value.translation.height, of: size.height)
                )))
            }
    }
}
