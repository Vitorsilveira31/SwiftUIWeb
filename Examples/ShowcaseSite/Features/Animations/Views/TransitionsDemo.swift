import SwiftUIWeb

/// A view that enters and leaves with the transition picked beside it.
struct TransitionsDemo: View {
  @State private var shown = true
  @State private var kind = 0

  private static let kinds: [(String, AnyTransition)] = [
    ("Opacity", .opacity),
    ("Scale", .scale),
    ("Slide", .slide),
    ("Move", .move(edge: .bottom)),
    ("Combined", AnyTransition.move(edge: .leading).combined(with: .opacity)),
  ]

  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        if shown {
          RoundedRectangle(cornerRadius: 14)
            .fill(SiteTheme.accentGradient)
            .frame(width: 132, height: 64)
            .transition(Self.kinds[kind].1)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 84)
      .clipped()
      HStack(spacing: 10) {
        // The kind is a menu drawn like the buttons around it. Its label has one width for every kind, and Hide and Show have
        // one width, so nothing on the line moves when either changes.
        Menu {
          ForEach(0..<Self.kinds.count, id: \.self) { index in
            Button(Self.kinds[index].0) { kind = index }
          }
        } label: {
          // One width for every kind, so the label does not change size with it. The menu and the button beside it are both 36 points tall.
          Text(Self.kinds[kind].0).frame(width: 72, height: 18, alignment: .leading)
        }
        .buttonStyle(.bordered)
        Button { withAnimation(.easeInOut(duration: 0.5)) { shown.toggle() } } label: {
          Text(shown ? "Hide" : "Show").frame(width: 40, height: 18)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }
}
