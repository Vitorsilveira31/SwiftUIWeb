import SwiftUIWeb

/// Embedded compile + browser fixture for SwiftUI spellings that must type
/// check and render the same as on iOS: value background/overlay forms,
/// contextual shape styles and shapes, uneven rounded rectangles, trimmed
/// shapes, containerRelativeFrame, accessibility elements and date texts.
struct EmbeddedSwiftUIParityFixture: View {
  let onExit: @MainActor () -> Void
  @State private var progress = 0.25
  private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Button("Return from parity fixture", action: onExit)
        ParityLayerRow()
        ParityShapeRow(progress: progress)
        Button("Advance progress") {
          withAnimation(.linear(duration: 0.2)) { progress = 0.75 }
        }
        ParityAccessibilityRow()
        ParityContainerRelativeRow()
        ParityDateRow(fixedDate: fixedDate)
        ParityModifierRow()
      }
      .padding()
    }
  }
}

private struct ParityLayerRow: View {
  var body: some View {
    HStack(spacing: 12) {
      Text("Color value").padding(8).background(Color.red).accessibilityIdentifier("parity-bg-color")
      Text("Style member").padding(8).background(.blue).accessibilityIdentifier("parity-bg-member")
      Text("Gradient")
        .padding(8)
        .background(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
        .accessibilityIdentifier("parity-bg-gradient")
      Color.green
        .frame(width: 80, height: 40)
        .overlay(Text("B").accessibilityIdentifier("parity-badge"), alignment: .topTrailing)
        .accessibilityIdentifier("parity-overlay-base")
      Text("Dim").padding(8).overlay(Color.black.opacity(0.5)).accessibilityIdentifier("parity-overlay-paint")
      Text("Outlined")
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 1))
        .accessibilityIdentifier("parity-bg-view")
      Text("Pill").padding(8).background(.yellow, in: .capsule).accessibilityIdentifier("parity-bg-capsule")
    }
  }
}

private struct ParityShapeRow: View {
  let progress: Double

  var body: some View {
    HStack(spacing: 12) {
      UnevenRoundedRectangle(topLeadingRadius: 16, bottomTrailingRadius: 4)
        .fill(.orange)
        .frame(width: 80, height: 40)
        .accessibilityIdentifier("parity-uneven-fill")
      Color.purple
        .frame(width: 80, height: 40)
        .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
        .accessibilityIdentifier("parity-uneven-clip")
      Text("Card")
        .padding(8)
        .background(.white, in: .rect(cornerRadius: 8))
        .accessibilityIdentifier("parity-rect-card")
      Circle()
        .trim(from: 0, to: progress)
        .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: 48, height: 48)
        .accessibilityIdentifier("parity-trim-ring")
      Circle().fill(.tint).frame(width: 12, height: 12)
      Text("Tertiary").foregroundStyle(.tertiary)
    }
  }
}

private struct ParityAccessibilityRow: View {
  var body: some View {
    HStack {
      HStack {
        Text("Rating")
        Text("4 stars")
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("parity-a11y-combine")
      HStack {
        Text("Decorative")
        Text("parts")
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Summary")
      .accessibilityIdentifier("parity-a11y-ignore")
      VStack {
        Text("Inside")
        Button("Act") {}
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Group")
      .accessibilityIdentifier("parity-a11y-contain")
    }
  }
}

private struct ParityContainerRelativeRow: View {
  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 10) {
        ForEach(0..<5, id: \.self) { index in
          Color.teal
            .frame(height: 30)
            .containerRelativeFrame(.horizontal, count: 3, spacing: 10)
            .accessibilityIdentifier("parity-relative-card-\(index)")
        }
      }
    }
    .frame(width: 320)
    .accessibilityIdentifier("parity-relative-scroll")
  }
}

private struct ParityDateRow: View {
  let fixedDate: Date

  var body: some View {
    VStack(alignment: .leading) {
      Text(fixedDate, format: .dateTime.year().month(.wide).day()).accessibilityIdentifier("parity-date-format")
      Text("Formatted: " + fixedDate.formatted(date: .abbreviated, time: .omitted)).accessibilityIdentifier("parity-date-formatted")
      Text(fixedDate, style: .date).accessibilityIdentifier("parity-date-style")
      Text(Date().addingTimeInterval(7_500), style: .relative).accessibilityIdentifier("parity-date-relative")
      Text(timerInterval: Date()...Date().addingTimeInterval(600)).accessibilityIdentifier("parity-date-timer")
      Text(fixedDate...fixedDate.addingTimeInterval(5_400)).accessibilityIdentifier("parity-date-range")
    }
  }
}

private struct ParityModifierRow: View {
  @State private var lastMenuAction = "none"
  @ScaledMetric private var iconSize: Double = 20

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Z").zIndex(2).accessibilityIdentifier("parity-zindex")
        Label("Settings", systemImage: "gear").labelStyle(.iconOnly).accessibilityIdentifier("parity-label-icon-only")
        Label("Title only", systemImage: "star").labelStyle(.titleOnly).accessibilityIdentifier("parity-label-title-only")
        ControlGroup {
          Button("Undo") {}
          Button("Redo") {}
        }
        .accessibilityIdentifier("parity-control-group")
        Text("Scaled \(Int(iconSize))").accessibilityIdentifier("parity-scaled-metric")
      }
      Text("Menu: \(lastMenuAction)")
        .padding(8)
        .contextMenu {
          Button("Copy") { lastMenuAction = "copy" }
          Button("Share") { lastMenuAction = "share" }
        }
        .accessibilityIdentifier("parity-context-menu")
      Color.gray.opacity(0.2)
        .frame(width: 120, height: 60)
        .overlay(Circle().fill(.red).frame(width: 10, height: 10).position(x: 30, y: 20).accessibilityIdentifier("parity-position-dot"))
        .accessibilityIdentifier("parity-position-area")
      HStack {
        Image(systemName: "bell").symbolEffect(.bounce, value: lastMenuAction)
        Image(systemName: "wifi").symbolEffect(.pulse, isActive: true)
        Text("\(Int(iconSize))").contentTransition(.numericText(value: iconSize))
        Label("Styled", systemImage: "star").foregroundStyle(.blue, .gray)
      }
      ContentUnavailableView("No items", systemImage: "tray", description: Text("Add one to begin"))
        .accessibilityIdentifier("parity-content-unavailable")
      Text("A long sentence that is truncated at the tail")
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: 120)
        .accessibilityIdentifier("parity-truncation")
    }
  }
}
