import SwiftUIWeb

/// Chooses the CPU rate whose measurements are shown.
struct PerformanceCpuPicker: View {
  let viewModel: PerformanceViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    HStack(spacing: 10) {
      Text(PerformanceStrings.cpuLabel(language)).foregroundStyle(.secondary)
      Picker(
        PerformanceStrings.cpuLabel(language),
        selection: Binding(get: { viewModel.cpu }, set: { viewModel.cpu = $0 })
      ) {
        ForEach(viewModel.rates, id: \.self) { rate in Text(PerformanceStrings.cpuOption(rate, language)).tag(rate) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
    }
  }
}
