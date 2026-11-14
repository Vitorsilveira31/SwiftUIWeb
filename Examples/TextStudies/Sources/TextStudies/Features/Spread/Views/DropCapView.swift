import SwiftUI

/// The drop cap: a large initial the words flow around.
struct DropCapView: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(.system(size: 60, weight: .bold))
            .foregroundStyle(Color(red: 0.71, green: 0.27, blue: 0.18))
            .frame(width: 62, height: 72, alignment: .topLeading)
    }
}
