// Written against the public API only: no SPI import. It is the SwiftUIWeb half of the
// probe that must also type-check against Apple's SwiftUI and CoreTransferable.
import SwiftUIWeb
import Testing

private struct ProbeTagged: Transferable, Equatable {
  var text: String

  static var transferRepresentation: some TransferRepresentation {
    ProbeTaggedRepresentation()
  }
}

private struct ProbeTaggedRepresentation: TransferRepresentation {
  typealias Item = ProbeTagged

  var body: some TransferRepresentation<ProbeTagged> {
    DataRepresentation(
      contentType: .plainText,
      exporting: { (item: ProbeTagged) -> Data in Data(item.text.utf8) },
      importing: { (data: Data) -> ProbeTagged in ProbeTagged(text: String(decoding: data, as: UTF8.self)) }
    )
    ProxyRepresentation(exporting: { (item: ProbeTagged) -> String in item.text })
  }
}

@Suite
struct CustomTransferRepresentationTests {
  @Test func customBodyRepresentationAdvertisesItsContentTypes() {
    #expect(ProbeTagged.exportedContentTypes().first == .plainText)
    #expect(ProbeTagged.importedContentTypes() == [.plainText])
  }

  @Test func customBodyRepresentationRoundTripsThroughRuntime() async throws {
    let runtime = _AnyTransferRepresentation<ProbeTagged>(ProbeTaggedRepresentation())
    #expect(runtime.exportedContentTypes.first == .plainText)
    #expect(runtime.importedContentTypes == [.plainText])

    let imported = try await runtime._roundTrip(ProbeTagged(text: "round trip"))
    #expect(imported == ProbeTagged(text: "round trip"))
  }
}
