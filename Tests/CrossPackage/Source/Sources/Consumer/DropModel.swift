// An application that imports Foundation and SwiftUI together: `NSItemProvider` is Foundation's class in the drag,
// drop and paste API (as on Apple's platforms), and its registration API is the one the application calls.
import Foundation
import SwiftUI

struct CrossDragSource: View {
  var body: some View {
    Text("Drag me")
      .onDrag {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: "public.plain-text", visibility: .all) { completion in
          completion(Data("hello".utf8), nil)
          return nil
        }
        return provider
      }
  }
}

struct CrossDropTarget: View {
  @State private var isTargeted = false

  var body: some View {
    Text(isTargeted ? "Release" : "Drop here")
      .onDrop(of: [.plainText], isTargeted: $isTargeted) { (providers: [NSItemProvider], _: CGPoint) in
        providers.first?.hasItemConformingToTypeIdentifier("public.plain-text") ?? false
      }
  }
}
