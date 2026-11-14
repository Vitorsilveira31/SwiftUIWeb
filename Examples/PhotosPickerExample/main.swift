import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebPhotosUI

private struct PhotosPickerExampleView: View {
  @State private var selection: PhotosPickerItem?
  @State private var selections: [PhotosPickerItem] = []
  @State private var status = "No media selected"

  var body: some View {
    VStack {
      Text("SwiftUIWebPhotosUI")
      Text("Choose an image or video; the browser reads its bytes asynchronously.")
        .foregroundColor(.secondary)

      PhotosPicker(selection: $selection, matching: .any(of: .images, .videos)) {
        Text("Choose media")
          .padding()
          .background(.blue)
          .foregroundColor(.white)
          .cornerRadius(8)
      }

      PhotosPicker(
        "Choose up to six",
        selection: $selections,
        maxSelectionCount: 6,
        selectionBehavior: .ordered,
        matching: .any(of: [.images, .videos])
      )
      .padding()

      Text("Selected \(selections.count) media item(s)")
        .task(id: selections) {
          guard !selections.isEmpty else { return }
          // Int64: the sum of file sizes can pass the 32-bit Int of the browser build.
          var bytes: Int64 = 0
          for item in selections {
            bytes += Int64((try? await item.loadDataRepresentation(forTypeIdentifier: ""))?.count ?? 0)
          }
          status = "Loaded \(bytes) bytes across \(selections.count) item(s)"
        }

      Text(status)
        .task(id: selection?.itemIdentifier) {
          guard let selection else { return }
          do {
            // (`loadTransferable` is generic, which Embedded Swift cannot specialize here: the data is read by type identifier.)
            let data = try await selection.loadDataRepresentation(forTypeIdentifier: "")
            status = "Loaded \(data?.count ?? 0) bytes from \(selection.suggestedFileName ?? "media")"
          } catch {
            // (An error cannot be interpolated into text in Embedded Swift.)
            status = "Unable to load media"
          }
        }
    }
    .padding()
  }
}

@main
private struct PhotosPickerExample: BrowserApp {
  var body: some View { WindowGroup { PhotosPickerExampleView() } }
}
