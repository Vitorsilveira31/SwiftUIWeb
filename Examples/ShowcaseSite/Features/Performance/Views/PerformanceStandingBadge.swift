import SwiftUIWeb

/// Where SwiftUIWeb stands on one measurement, in a word and a symbol, so the color is never the only signal.
struct PerformanceStandingBadge: View {
  let standing: PerformanceVerdict
  @Environment(\.siteLanguage) private var language

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
      Text(PerformanceStrings.standing(standing, language)).fontWeight(.semibold)
    }
    .font(.caption)
    .foregroundStyle(tint)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(tint.opacity(0.14))
    .clipShape(Capsule())
  }

  /// `standing` is React's verdict: React higher means SwiftUIWeb is ahead.
  private var tint: Color {
    switch standing {
    case .reactHigher: return SiteTheme.positive
    case .reactLower: return SiteTheme.negative
    case .same, .tooFewSamples: return .secondary
    }
  }

  private var symbol: String {
    switch standing {
    case .reactHigher: return "checkmark.circle"
    case .reactLower, .same, .tooFewSamples: return "info.circle"
    }
  }
}
