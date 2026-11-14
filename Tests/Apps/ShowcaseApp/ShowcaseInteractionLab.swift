import SwiftUIWeb

/// Keyboard, control-style and presentation parity fixture used by the
/// Showcase browser checks (`Tools/test-controls-browser.mjs` and
/// `Tools/test-presentation-browser.mjs`). Everything here is ordinary SwiftUI
/// source: keyboard shortcuts, `onKeyPress`, segmented pickers, toggle
/// styles, `ButtonStyle.Configuration.isPressed`, sheet detents/`onDismiss`
/// and data-presenting alerts.
struct ShowcaseInteractionLab: View {
  @State private var shortcutCount = 0
  @State private var highlighted = 0
  @State private var containerKeys = 0
  @State private var period = "week"
  @State private var checked = false
  @State private var bold = false
  @State private var quiet = true
  @State private var showSheet = false
  @State private var dismissCount = 0
  @State private var sheetAction = "none"
  @State private var alertTarget: String?
  @State private var showAlert = false
  @State private var alertResult = "none"
  private let rows = ["Inbox", "Drafts", "Archive"]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Interaction lab").font(.headline)
      HStack(spacing: 8) {
        Button("Shortcut increment") { shortcutCount += 1 }
          .keyboardShortcut("k", modifiers: .command)
        Button("Disabled shortcut") { shortcutCount += 100 }
          .keyboardShortcut("j", modifiers: .command)
          .disabled(true)
        Text("Shortcut count: \(shortcutCount)").accessibilityIdentifier("lab-shortcut-count")
      }
      VStack(alignment: .leading, spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          Text(index == highlighted ? "▶ \(rows[index])" : rows[index])
        }
      }
      .focusable()
      .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, rows.count - 1); return .handled }
      .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
      .onKeyPress(.escape) { .ignored }
      .accessibilityIdentifier("lab-key-list")
      .padding(4)
      .onKeyPress(characters: .letters) { _ in containerKeys += 1; return .handled }
      Text("Highlighted: \(rows[highlighted]) · container keys: \(containerKeys)").accessibilityIdentifier("lab-key-state")
      Picker("Period", selection: $period) {
        Text("Day").tag("day")
        Text("Week").tag("week")
        Text("Month").tag("month")
      }
      .pickerStyle(.segmented)
      Text("Period: \(period)").accessibilityIdentifier("lab-period")
      Toggle("Checkbox option", isOn: $checked).toggleStyle(.checkbox)
      Toggle("Bold", isOn: $bold).toggleStyle(.button)
      Toggle("Quiet hours", isOn: $quiet).labelsHidden()
      Text("Toggles: \(checked ? "checked" : "unchecked") \(bold ? "bold" : "regular") \(quiet ? "quiet" : "loud")")
        .accessibilityIdentifier("lab-toggles")
      Button("Hold me") {}.buttonStyle(LabPressStyle())
      HStack(spacing: 8) {
        Button("Detent sheet") { showSheet = true }
        Button("Presenting alert") { alertTarget = "Report.pdf"; showAlert = true }
      }
      .alert("Delete file?", isPresented: $showAlert, presenting: alertTarget) { name in
        Button("Delete \(name)", role: .destructive) { alertResult = "deleted \(name)" }
        Button("Keep", role: .cancel) { alertResult = "kept" }
      } message: { name in
        Text("\(name) will be removed.")
      }
      Text("Sheet dismissals: \(dismissCount) · action: \(sheetAction) · alert: \(alertResult)")
        .accessibilityIdentifier("lab-presentation-state")
    }
    .sheet(isPresented: $showSheet, onDismiss: { dismissCount += 1 }) {
      LabSheet { sheetAction = $0 }
    }
  }
}

private struct LabSheet: View {
  @Environment(\.dismiss) private var dismiss
  let record: (String) -> Void

  var body: some View {
    VStack(spacing: 12) {
      Text("Detent sheet").font(.title)
      Button("Cancel sheet") { record("cancel"); dismiss() }.keyboardShortcut(.cancelAction)
      Button("Confirm sheet") { record("confirm"); dismiss() }.keyboardShortcut(.defaultAction)
    }
    .padding(16)
    .presentationDetents([.medium, .large])
  }
}

private struct LabPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.label
      Text(configuration.isPressed ? "Pressed" : "Idle")
    }
    .padding(8)
    .background(configuration.isPressed ? Color.blue.opacity(0.3) : Color.clear)
  }
}
