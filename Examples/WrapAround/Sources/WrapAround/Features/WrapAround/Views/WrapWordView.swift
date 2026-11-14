import SwiftUI

/// One word of prose, or a paragraph break (zero-size) that the layout reads as a line change.
struct WrapWordView: View {
    let word: WrapWord

    var body: some View {
        if word.isBreak {
            Color.clear
                .frame(width: 0, height: 0)
                .layoutValue(key: WrapBreakKey.self, value: true)
        } else {
            Text(word.text)
        }
    }
}
