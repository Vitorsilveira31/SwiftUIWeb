import SwiftUI

/// The editing surface: a stage at the photo's aspect, filled by the stage that takes the gestures.
struct EditorSurface: View {
    let viewModel: EditorViewModel

    var body: some View {
        Color.clear
            .aspectRatio(StageGeometry.aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    EditorStage(viewModel: viewModel, size: proxy.size)
                }
            }
            .clipped()
    }
}
