import SwiftUI

struct CounterScreen: View {
    @State var viewModel = CounterViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Text("\(viewModel.state.count)")
                .font(.system(size: 72, weight: .bold))
                .accessibilityIdentifier("counter-value")

            HStack(spacing: 16) {
                Button("−") { viewModel.send(.decrement) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("counter-decrement")
                Button("+") { viewModel.send(.increment) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("counter-increment")
            }
            .font(.title)

            Stepper(
                "Step: \(viewModel.state.step)",
                value: Binding(get: { viewModel.state.step }, set: { viewModel.send(.setStep($0)) }),
                in: 1...10
            )
            .frame(maxWidth: 280)

            Button("Reset", role: .destructive) { viewModel.send(.reset) }
                .disabled(viewModel.state.count == 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Counter")
    }
}
