import SwiftUI

// The sun's arc from sunrise to sunset, with a dot at the selected hour's place on it.
struct SunTile: View {
    let sunrise: String
    let sunset: String
    let hour: Double

    var body: some View {
        let riseHour = WallTime.hour(of: sunrise)
        let setHour = WallTime.hour(of: sunset)
        let progress = min(max((hour - riseHour) / max(setHour - riseHour, 1), 0), 1)

        VStack(alignment: .leading, spacing: 10) {
            Label(Strings.Elements.sun, systemImage: "sunrise.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack {
                    SunArc()
                        .stroke(.secondary, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    Circle()
                        .fill(.orange)
                        .frame(width: 12, height: 12)
                        .position(SunArc.point(at: progress, in: geometry.size))
                }
            }
            .frame(height: 80)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.Elements.sunrise)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(WallTime.clock(sunrise))
                        .font(.system(.title3, design: .serif))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Strings.Elements.sunset)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(WallTime.clock(sunset))
                        .font(.system(.title3, design: .serif))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.10)))
    }
}
