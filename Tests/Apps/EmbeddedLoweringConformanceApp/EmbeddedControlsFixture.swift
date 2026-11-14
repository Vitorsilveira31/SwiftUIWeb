import SwiftUIWeb

/// Divider, a linear ProgressView, Slider, a menu Picker, a linear Gauge, TextEditor and Canvas in a VStack, in an HStack, with a
/// frame and with none, each sized as SwiftUI sizes it: a Divider runs across its stack (vertically in an HStack) and is a point
/// thick, a progress bar, a slider and a gauge take the width they are offered, a menu Picker is as wide as its selected label, a
/// TextEditor takes what it is offered and a Canvas takes its frame. `Tools/test-css-layout-fixtures-browser.mjs`
/// checks the CSS boxes of the groups it sets apart (a `data-testid`) against Apple's frames of the same trees
/// (`Tests/LayoutConformance/apple-macos-css-extra.json`) as well. Every group has a frame of its own, so a difference in one does
/// not move the others.
struct EmbeddedControlsFixture: View {
  let onDone: () -> Void
  @State private var level = 0.4
  @State private var genre = "All"
  @State private var notes = "Notes"

  private var picker: some View {
    Picker("Genre", selection: $genre) {
      Text("All").tag("All")
      Text("Telenovela").tag("Telenovela")
    }
    .pickerStyle(.menu)
  }

  private func group<Content: View>(height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
    content().frame(width: 340, height: height, alignment: .topLeading)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Return to conformance app") { onDone() }
      // In a VStack of a fixed width: a Divider, a progress bar and a slider take the width.
      group(height: 80) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Stack")
          Divider()
          ProgressView(value: 0.4)
          Slider(value: $level, in: 0...1)
        }
        .frame(width: 320)
      }
      // In a VStack that centres, with a Divider that spans the stack.
      group(height: 70) {
        VStack(spacing: 8) {
          Text("Centred")
          Divider()
          Slider(value: $level, in: 0...1)
        }
        .frame(width: 320)
      }
      // Framed: the frame is the control's width.
      group(height: 90) {
        VStack(alignment: .leading, spacing: 8) {
          Divider().frame(width: 100)
          ProgressView(value: 0.4).frame(width: 200)
          Slider(value: $level, in: 0...1).frame(width: 200)
          Slider(value: $level, in: 0...1).frame(maxWidth: 240)
          ProgressView(value: 0.4).frame(maxWidth: .infinity)
        }
        .frame(width: 320)
      }
      // A Divider and a frame around it: the frame is as wide as the Divider's stack is long, a point thick.
      group(height: 50) {
        VStack(alignment: .leading, spacing: 8) {
          Divider().frame(height: 20)
          Divider().padding(.horizontal, 8)
        }
        .frame(width: 200)
      }
      // A TextEditor in a frame, in a frame of a fixed size and with a padding around it.
      group(height: 100) { TextEditor(text: $notes).frame(height: 90) }
      group(height: 100) { TextEditor(text: $notes).frame(width: 240, height: 90) }
      group(height: 110) { TextEditor(text: $notes).frame(width: 240, height: 90).padding(4) }
      // A Canvas as the frame says.
      group(height: 30) {
        Canvas { context, size in
          var fill = Path()
          fill.addRect(CGRect(origin: .zero, size: size))
          context.fill(fill, with: .color(.red))
        }
        .frame(width: 200, height: 12)
      }
      group(height: 30) {
        Canvas { context, size in
          var fill = Path()
          fill.addRect(CGRect(origin: .zero, size: size))
          context.fill(fill, with: .color(.blue))
        }
        .frame(height: 12)
      }
      // A spinner (an indeterminate ProgressView) and a ring (a determinate circular one) are 20 pt squares.
      group(height: 40) {
        HStack(spacing: 8) {
          ProgressView()
          ProgressView(value: 0.4).progressViewStyle(.circular)
          Text("Loading")
        }
      }
      // Where the browser layout differs from SwiftUI (see the test):
      // - a Canvas offered no height is its 10 pt ideal size, border and all;
      group(height: 50) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Canvas")
          Canvas { context, size in
            var fill = Path()
            fill.addRect(CGRect(origin: .zero, size: size))
            context.fill(fill, with: .color(.green))
          }
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityIdentifier("controls-canvas-ideal")
      // - a Divider in an HStack is a vertical rule as tall as the row;
      group(height: 60) {
        HStack(spacing: 8) {
          Text("Left")
          Divider()
          Text("Right")
        }
        .frame(width: 200, height: 40)
      }
      .accessibilityIdentifier("controls-divider-row")
      // - a Slider and a progress bar in an HStack take what their neighbours leave;
      group(height: 40) {
        HStack(spacing: 8) {
          Text("Volume")
          Slider(value: $level, in: 0...1)
          Text("100")
        }
        .frame(width: 320)
      }
      .accessibilityIdentifier("controls-slider-row")
      group(height: 40) {
        HStack(spacing: 8) {
          Text("Loading")
          ProgressView(value: 0.4)
        }
        .frame(width: 320)
      }
      .accessibilityIdentifier("controls-progress-row")
      // - a TextEditor in a stack of a fixed height takes the height the stack leaves;
      group(height: 150) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Notes")
          TextEditor(text: $notes)
        }
        .frame(width: 200, height: 150)
      }
      .accessibilityIdentifier("controls-editor-stack")
      // - the label of a Gauge is above its track with the stylesheet's gap;
      group(height: 60) {
        VStack(alignment: .leading, spacing: 8) {
          Gauge(value: 0.5, in: 0...1) { Text("Gauge") }
        }
        .frame(width: 320)
      }
      .accessibilityIdentifier("controls-gauge")
      // - a menu Picker is as wide as its selected label, also in a frame wider than it.
      group(height: 70) {
        VStack(alignment: .leading, spacing: 8) {
          picker
        }
        .frame(width: 320)
      }
      .accessibilityIdentifier("controls-picker")
      group(height: 70) {
        picker.frame(width: 200)
      }
      .accessibilityIdentifier("controls-picker-framed")
      // - with its label hidden (as in a shipping app), in a row and in a frame.
      group(height: 50) {
        HStack(spacing: 8) {
          Text("Genre")
          picker.labelsHidden()
          Spacer()
        }
        .frame(width: 320)
      }
      group(height: 50) { picker.labelsHidden().frame(width: 200) }
    }
    .padding(16)
  }
}
