// An application that imports Foundation and SwiftUI together: `ObservableObject` and `@Published` resolve to one set
// of types (SwiftUIWeb's, with Foundation aliased to WebFoundation), and a model write re-renders the observing view after the current turn.
import Foundation
import SwiftUI

final class CrossCounterModel: ObservableObject {
  @Published var count = 0
}

struct CrossObservedView: View {
  @StateObject private var model = CrossCounterModel()

  var body: some View {
    VStack {
      Text("Count \(model.count)")
      Button("Increment") { model.count += 1 }
    }
  }
}
