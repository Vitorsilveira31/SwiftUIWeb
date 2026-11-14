// Foundation's registration API of `NSItemProvider`, which returns a `Progress` (SwiftUIWebNetworking), so it lives here
// beside the other Foundation names rather than in SwiftUIWebCore, which declares the provider.
import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebLocking
import SwiftUIWebNetworking

/// Who may see a representation registered on an item provider, as Foundation declares it. The browser has one
/// process and no teams or app groups, so every visibility is visible to the page.
public enum NSItemProviderRepresentationVisibility: Int, Sendable {
  case all = 0
  case team = 1
  case group = 2
  case ownProcess = 3
}

extension NSItemProvider {
  /// Registers a representation of `typeIdentifier` whose data `loadHandler` supplies when it is asked for, as
  /// Foundation's `registerDataRepresentation(forTypeIdentifier:visibility:loadHandler:)` does.
  ///
  /// A drag asks for it when it starts, and the browser needs the data at that moment: the handler is called then, and
  /// the data it gives before it returns is the representation. Data given later, from another task, is not delivered.
  public func registerDataRepresentation(
    forTypeIdentifier typeIdentifier: String,
    visibility: NSItemProviderRepresentationVisibility,
    loadHandler: @escaping @Sendable (@escaping @Sendable (Data?, (any Error)?) -> Void) -> Progress?
  ) {
    _registerDataRepresentation(forTypeIdentifier: typeIdentifier) {
      let result = _LoadedRepresentation()
      _ = loadHandler { data, error in result.set(error == nil ? data : nil) }
      return result.data
    }
  }
}

/// The data a load handler gave, written from its completion.
private final class _LoadedRepresentation: @unchecked Sendable {
  private let lock = _RuntimeLock()
  private var value: Data?

  func set(_ data: Data?) { lock.withLock { value = data } }
  var data: Data? { lock.withLock { value } }
}
