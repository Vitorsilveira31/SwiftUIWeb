import SwiftUI

// Runs: a line made of three styled pieces, and a stroked word.
struct FxRuns: View {
    var body: some View {
        FixtureTile(name: "fx-runs") {
            ZStack(alignment: .topLeading) {
                RunLine()
                    .offset(x: 6, y: 30 - 13 * 0.8)
                OutlinedWord()
                    .offset(x: 0, y: 66 - 28 * 0.8)
            }
        }
    }
}
