import SwiftUI

// A guide at y 40 and four "Ab" labels, each placed by a different baseline rule.
struct FxBaselines: View {
    private let ink = Color(hex: 0x1E293B)

    var body: some View {
        FixtureTile(name: "fx-baselines") {
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 40))
                    path.addLine(to: CGPoint(x: 120, y: 40))
                }
                .stroke(Color(hex: 0xFDA4AF), lineWidth: 1)
                AnchoredLabel("Ab", x: 4, y: 40, size: 14, color: ink)
                AnchoredLabel("Ab", x: 32, y: 40, size: 14, color: ink, vertical: .middle)
                AnchoredLabel("Ab", x: 60, y: 40, size: 14, color: ink, vertical: .middle)
                AnchoredLabel("Ab", x: 88, y: 40, size: 14, color: ink, vertical: .hanging)
            }
        }
    }
}
