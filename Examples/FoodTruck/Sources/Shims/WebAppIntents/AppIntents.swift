// Apple's Food Truck imports AppIntents where it offers Siri and Shortcuts, behind `#if os(iOS)`. A browser has neither:
// the module gives the iPad version's views what they show, the Siri tip below Top 5 included.
import SwiftUIWeb

/// The Siri tip under Top 5 Donuts on iPad: a capsule with the Siri glyph that suggests the intent's phrase. A browser
/// has no Siri, so the tip shows the intent's title as the suggestion and dismisses like the native one.
public struct SiriTipView<Intent: SiriTipTitled>: View {
  let intent: Intent
  @Binding var isVisible: Bool

  public init(intent: Intent, isVisible: Binding<Bool> = .constant(true)) {
    self.intent = intent
    _isVisible = isVisible
  }

  public var body: some View {
    if isVisible {
      HStack(spacing: 10) {
        Circle()
          .fill(AngularGradient(colors: [.pink, .purple, .blue, .cyan, .pink], center: .center))
          .frame(width: 22, height: 22)
        Text(intent.siriTipTitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
}

/// An intent that names the suggestion its Siri tip shows (the web adapter of Food Truck's Top 5 intent).
public protocol SiriTipTitled {
  var siriTipTitle: String { get }
}
