import SwiftUI

// The top strip of every screen after the lock screen: the time, then fixed connectivity
// symbols that follow the Settings switches.
struct StatusBar: View {
    @AppStorage("pocketos.airplane") private var airplane = false
    @AppStorage("pocketos.wifi") private var wifi = true

    var body: some View {
        HStack {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 17, weight: .semibold, design: .serif))
            }
            Spacer()
            HStack(spacing: 7) {
                if airplane {
                    Image(systemName: "airplane")
                } else if wifi {
                    Image(systemName: "wifi")
                }
                Image(systemName: "battery.75percent")
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 28)
        .frame(height: 34)
    }
}
