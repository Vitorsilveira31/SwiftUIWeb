@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// SwiftUI-shaped PasteButton support. Clipboard objects and permission
// prompts are deliberately kept in SwiftUIWebBrowser; Core only carries
// transfer metadata and browser-neutral item providers.

@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

/// Renderer-facing event names and compact result tokens. This enum is SPI so
/// browser hosts can translate Clipboard API results without exposing a DOM
/// event or JavaScript value through the SwiftUI-compatible surface.
@_spi(Browser) public enum PasteButtonRuntime {
  public static let event = "pasteButton"
  public static let successPrefix = "success:"
  public static let cancelled = "cancelled"
  public static let failurePrefix = "failure:"
}

private func _pasteButtonContentTypes<T: Transferable>(_ type: T.Type) -> [UTType] {
  let imported = T.importedContentTypes()
  return imported.isEmpty ? [.data] : imported
}

private func _pasteButtonAccept(_ types: [UTType]) -> String? {
  var values: [String] = []
  values.reserveCapacity(types.count * 2)
  for type in types {
    if let mime = type.preferredMIMEType, !mime.isEmpty { values.append(mime) }
    if let ext = type.preferredFilenameExtension, !ext.isEmpty { values.append("." + ext) }
  }
  var seen = Set<String>()
  let unique = values.filter { seen.insert($0.lowercased()).inserted }
  return unique.isEmpty ? nil : unique.joined(separator: ",")
}

/// Owns one asynchronous import operation. The explicit unchecked Sendable
/// box is the same host-boundary pattern used by dropDestination: a
/// Transferable value is not required to promise that its callback is safe to
/// move between executors, while the operation itself is retained by the
/// browser event until all providers have been consumed.
@MainActor private final class _PasteButtonOperation<Item: Transferable> {
  let type: Item.Type
  nonisolated(unsafe) let action: ([Item]) -> Void

  nonisolated init(type: Item.Type, action: @escaping ([Item]) -> Void) {
    self.type = type
    self.action = action
  }

  func start(_ providers: [NSItemProvider]) {
    // Native providers are not Sendable; the paste's task is their only reader, on the main actor.
    Task { @MainActor [self] in
      var values: [Item] = []
      values.reserveCapacity(providers.count)
      for provider in providers {
        if let value = try? await provider.loadTransferable(type: self.type) {
          values.append(value)
        }
      }
      guard !values.isEmpty else { return }
      self.action(values)
    }
  }
}

/// A SwiftUI-compatible paste control.
///
/// ``PasteButton`` is intentionally a regular Swift value. The browser host
/// attaches a private click listener to the rendered button and translates
/// Clipboard API items into ``NSItemProvider`` values. This means custom
/// ``Transferable`` types use the same representation/import path as drag and
/// drop and do not need a Web-specific decoder.
public nonisolated struct PasteButton: View {
  public typealias Body = Never

  private let acceptedTypes: [UTType]
  private let perform: @MainActor ([NSItemProvider]) -> Void

  /// Creates a paste button for a ``Transferable`` payload type.
  public nonisolated init<T: Transferable>(payloadType: T.Type, onPaste: @escaping ([T]) -> Void) {
    acceptedTypes = _pasteButtonContentTypes(payloadType)
    let operation = _PasteButtonOperation(type: payloadType, action: onPaste)
    perform = { providers in operation.start(providers) }
  }

  /// Creates a paste button for the item providers of the listed content types.
  public nonisolated init(supportedContentTypes: [UTType], payloadAction: @escaping ([NSItemProvider]) -> Void) {
    acceptedTypes = supportedContentTypes.isEmpty ? [.data] : supportedContentTypes
    perform = _mainActor(payloadAction)
  }

  /// Creates a paste button that turns the providers into a payload with `validator`
  /// and passes the payload to `payloadAction` only when `validator` returns one.
  public nonisolated init<Payload>(supportedContentTypes: [UTType], validator: @escaping ([NSItemProvider]) -> Payload?, payloadAction: @escaping (Payload) -> Void) {
    acceptedTypes = supportedContentTypes.isEmpty ? [.data] : supportedContentTypes
    // SAFETY: the callbacks were handed over from the main actor and only run there.
    nonisolated(unsafe) let validator = validator
    nonisolated(unsafe) let payloadAction = payloadAction
    perform = { providers in
      if let payload = validator(providers) { payloadAction(payload) }
    }
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("button")
    let styleClass = context.environment.buttonStyleIsCustom
      ? "button-custom"
      : "button-" + context.environment.buttonStyle.rawValue
    node.classes = [
      "paste-button",
      styleClass,
      "control-\(context.environment.controlSize.rawValue)"
    ]
    node.attributes["data-control-kind"] = "paste-button"
    node.attributes["data-button-style"] = context.environment.buttonStyle.rawValue
    if context.environment.buttonStyleIsCustom {
      node.attributes["data-button-style-custom"] = "true"
    }
    node.attributes["data-control-size"] = context.environment.controlSize.rawValue
    node.attributes["type"] = "button"
    node.attributes["data-paste-button"] = "true"
    node.attributes["data-paste-types"] = acceptedTypes.map { $0.identifier }.joined(separator: ",")
    if let accept = _pasteButtonAccept(acceptedTypes) {
      node.attributes["data-paste-accept"] = accept
    }
    if let tint = context.environment.tint {
      node.attributes["data-tint"] = tint.cssValue
      node.styles["--tint-color"] = tint.cssValue
    }
    if context.environment.isEnabled {
      node.events[PasteButtonRuntime.event] = _EventHandler(name: PasteButtonRuntime.event) { encoded in
        var normalized = encoded
        if encoded.hasPrefix("inline-text:"), let bytes = Data(base64Encoded: String(encoded.dropFirst("inline-text:".count))) {
          let id = _EmbeddedTransferIDs.shared.next("embedded-paste-")
          SwiftUIWebTransferRuntime._registerTransient(identifier: id, payload: SwiftUIWebTransferPayload(data: bytes, contentType: .utf8PlainText))
          normalized = PasteButtonRuntime.successPrefix + id
        }
        guard normalized.hasPrefix(PasteButtonRuntime.successPrefix) else { return }
        let ids = String(normalized.dropFirst(PasteButtonRuntime.successPrefix.count))
          .split(separator: ",", omittingEmptySubsequences: true)
          .map(String.init)
        guard !ids.isEmpty else { return }
        var providers: [NSItemProvider] = []
        providers.reserveCapacity(ids.count)
        for identifier in ids {
          guard let metadata = SwiftUIWebTransferRuntime.metadata(for: identifier) else { continue }
          providers.append(NSItemProvider(
            identifier: identifier,
            metadata: metadata,
            lease: SwiftUIWebTransferLease(identifier: identifier)
          ))
        }
        guard !providers.isEmpty else { return }
        perform(providers)
      }
    } else {
      node.attributes["disabled"] = "disabled"
      node.attributes["aria-disabled"] = "true"
    }
    // SwiftUI's PasteButton has a fixed, localized title; it has no label parameter.
    let label = Text("Paste")
    let child: _RenderNode
    if let styleRenderer = context.environment.buttonStyleRenderer {
      let configuration = ButtonStyleConfiguration(
        role: nil,
        label: .init(body: AnyView(label)),
        isPressed: false,
        action: {}
      )
      child = styleRenderer.render(configuration)._render(in: context.child(_FiberKey("styled-label")))
    } else {
      child = label._render(in: context)
    }
    _applyButtonVisibleShape(child, to: node)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}
