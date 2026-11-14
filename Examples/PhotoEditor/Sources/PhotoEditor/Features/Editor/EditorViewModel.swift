import Foundation
import Observation
import PhotosUI
import SwiftUI

/// The editor's state and its history. Views read `state` and send actions; nothing else changes it.
@Observable
@MainActor
final class EditorViewModel {
    struct State {
        var source: PhotoSource = .sample
        var edit = Edit()
        /// Earlier edits; Undo restores the last one.
        var history: [Edit] = []
        /// Edits the person has made, counted as each one ends.
        var edits = 0
        /// The export of the current edit; nil once the edit changes, because it no longer shows it.
        var exported: Image?
        /// Counts the photos chosen, so the screen can close the sheet a photo was picked from.
        var picks = 0

        var canUndo: Bool { !history.isEmpty }

        /// The state reported when an edit ends, in the reference's words.
        var summary: String {
            String(format: "scale %.2f× · rotation %.1f° · pan x %.2f y %.2f · crop x %.2f y %.2f w %.2f h %.2f",
                   edit.scale, edit.rotationDegrees, edit.panX, edit.panY,
                   edit.crop.x, edit.crop.y, edit.crop.width, edit.crop.height)
        }

        /// The same edit in the photo's own terms: the angle, and the crop as fractions of the photo.
        var photoTerms: String {
            String(format: "{\"rotate\":%.1f,\"crop\":{\"x\":%.2f,\"y\":%.2f,\"width\":%.2f,\"height\":%.2f}}",
                   edit.rotationDegrees, edit.crop.x, edit.crop.y, edit.crop.width, edit.crop.height)
        }
    }

    /// How a gesture ended, as the edit needs it. The live values stay in the surface until then.
    enum GestureEnd {
        case zoom(Double)
        case turn(Double)
        case pan(dx: Double, dy: Double)
        case corner(Corner, dx: Double, dy: Double)
    }

    enum Action {
        case commitGesture(GestureEnd)
        case rotateQuarterTurn
        case reset
        case undo
        case applyPreset(Preset)
        case beginSliderDrag
        case changeAdjustment(Adjustment, Double)
        case endSliderDrag
        case pickPhoto(PhotosPickerItem)
        case export
    }

    private(set) var state: State
    /// The edit a slider drag started from, so one drag is one history entry.
    private var sliderBase: Edit?
    /// Counts the photo loads started; a load that finishes after a newer one started is dropped.
    private var loadSerial = 0

    init(initialState: State = .init()) {
        state = initialState
    }

    func send(_ action: Action) {
        switch action {
        case .commitGesture(let end):
            commitGesture(end)
        case .rotateQuarterTurn:
            commit { $0.rotation += .pi / 2 }
        case .reset:
            commit { $0 = Edit() }
        case .undo:
            guard let previous = state.history.popLast() else { return }
            apply(previous)
        case .applyPreset(let preset):
            commit { $0.applyLook(preset.look) }
        case .beginSliderDrag:
            sliderBase = sliderBase ?? state.edit
        case .changeAdjustment(let adjustment, let value):
            var next = state.edit
            adjustment.set(value, in: &next)
            apply(next)
        case .endSliderDrag:
            endSliderDrag()
        case .pickPhoto(let item):
            loadPhoto(item)
        case .export:
            state.exported = PhotoExporter.render(state.source, edit: state.edit)
        }
    }

    private func commitGesture(_ end: GestureEnd) {
        switch end {
        case .zoom(let factor):
            commit { $0.scale = Edit.clampedScale($0.scale * factor) }
        case .turn(let radians):
            commit { $0.rotation += radians }
        case .pan(let dx, let dy):
            commit {
                $0.panX = Edit.clampedPan($0.panX + dx)
                $0.panY = Edit.clampedPan($0.panY + dy)
            }
        case .corner(let corner, let dx, let dy):
            commit { $0.crop = $0.crop.movingCorner(corner, dx: dx, dy: dy) }
        }
    }

    /// Applies one change as one history entry, and nothing when it changes nothing (a tap is no edit).
    private func commit(_ change: (inout Edit) -> Void) {
        var next = state.edit
        change(&next)
        guard next != state.edit else { return }
        state.history.append(state.edit)
        state.edits += 1
        apply(next)
    }

    /// Replaces the edit. The export shows the previous one, so it goes.
    private func apply(_ next: Edit) {
        guard next != state.edit else { return }
        state.edit = next
        state.exported = nil
    }

    /// A slider drag is recorded when it ends, as one entry, from the edit it started on.
    private func endSliderDrag() {
        guard let base = sliderBase else { return }
        sliderBase = nil
        guard base != state.edit else { return }
        state.history.append(base)
        state.edits += 1
    }

    /// A new photo starts a new edit: the history belongs to the photo it was made on.
    private func choose(_ image: Image) {
        state.source = .picked(image)
        state.edit = Edit()
        state.history = []
        state.edits = 0
        state.exported = nil
        sliderBase = nil
        state.picks += 1
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        loadSerial += 1
        let current = loadSerial
        Task {
            guard let image = try? await item.loadTransferable(type: Image.self), current == loadSerial else { return }
            choose(image)
        }
    }
}
