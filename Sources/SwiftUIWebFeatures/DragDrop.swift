@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

/// Owns the asynchronous import launched by a `dropDestination` callback.
/// Transferable intentionally does not require `Sendable` (matching
/// CoreTransferable), so the box is an explicit host boundary rather than a
/// promise that application values are thread-safe.
@MainActor private final class _DropDestinationOperation<Item: Transferable> {
  let type: Item.Type
  let action: @MainActor ([Item], CGPoint) -> Bool

  nonisolated init(type: Item.Type, action: @escaping @MainActor ([Item], CGPoint) -> Bool) {
    self.type = type
    self.action = action
  }

  func start(_ providers: [NSItemProvider], location: CGPoint) {
    // Native providers are not Sendable; the drop's task is their only reader, on the main actor.
    Task { @MainActor [self] in
      var values: [Item] = []
      values.reserveCapacity(providers.count)
      for provider in providers {
        if let value = try? await provider.loadTransferable(type: self.type) { values.append(value) }
      }
      _ = self.action(values, location)
    }
  }
}

package nonisolated struct DropTargetModifier: ViewModifier {
  let descriptor: _DropTargetDescriptor
  package init(descriptor: _DropTargetDescriptor) { self.descriptor = descriptor }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard context.environment.isEnabled else { return }
    node.attributes["data-drop-target"] = "true"
    node.attributes["data-drop-types"] = descriptor.acceptedTypes.map { $0.identifier }.joined(separator: ",")
    #if hasFeature(Embedded)
    if descriptor.targeted != nil {
      node.events["embeddedDropTargeted"] = _EventHandler(name: "embeddedDropTargeted", action: { raw in descriptor.targeted?(raw == "true") })
    }
    node.events["embeddedDrop"] = _EventHandler(name: "embeddedDrop", action: { raw in
      var providers: [NSItemProvider] = []
      var types: [UTType] = []
      var location = CGPoint(x: 0, y: 0)
      if raw.hasPrefix("v2:") {
        let lines = raw.dropFirst(3).split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return }
        let coordinates = first.split(separator: ",", omittingEmptySubsequences: false)
        guard coordinates.count == 2, let x = Double(coordinates[0]), let y = Double(coordinates[1]), x.isFinite, y.isFinite else { return }
        location = CGPoint(x: x, y: y)
        for line in lines.dropFirst() {
          let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
          guard fields.count == 3,
                let mime = try? _embeddedBase64Decode(String(fields[0])),
                let filename = try? _embeddedBase64Decode(String(fields[1])),
                let bytes = try? _embeddedBase64Decode(String(fields[2])) else { continue }
          let type = UTType.from(mimeType: String(decoding: mime, as: UTF8.self))
          guard descriptor.acceptedTypes.isEmpty || descriptor.acceptedTypes.contains(where: { _swiftUIWebContentTypeMatches(type, requested: $0) }) else { continue }
          let name = String(decoding: filename, as: UTF8.self)
          types.append(type)
          providers.append(NSItemProvider(payload: SwiftUIWebTransferPayload(data: Data(bytes), contentType: type, suggestedFileName: name.isEmpty ? nil : name)))
        }
      } else {
        // Backward-compatible text envelope for older external browser hosts.
        let parts = raw.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let x = Double(parts[0]), let y = Double(parts[1]), x.isFinite, y.isFinite,
              let bytes = try? _embeddedBase64Decode(String(parts[2])) else { return }
        location = CGPoint(x: x, y: y)
        let type = UTType.plainText
        guard descriptor.acceptedTypes.isEmpty || descriptor.acceptedTypes.contains(where: { _swiftUIWebContentTypeMatches(type, requested: $0) }) else { return }
        types.append(type)
        providers.append(NSItemProvider(payload: SwiftUIWebTransferPayload(data: Data(bytes), contentType: type)))
      }
      guard !providers.isEmpty else { return }
      _ = descriptor.perform(providers, DropInfo(location: location, types: types, providers: providers))
    })
    #endif
    node._dropTarget = descriptor
  }
}

public extension View {
  /// Starts a drag whose item is the provider `data` returns.
  nonisolated func onDrag(_ data: @escaping () -> NSItemProvider) -> some View {
    modifier(_onDragModifier(_mainActorReturning(data)))
  }

  /// Starts a drag with a preview. Browser hosts draw their native drag image, so the SwiftUI `preview`
  /// closure is accepted for source compatibility and is not mounted.
  nonisolated func onDrag<Preview: View>(_ data: @escaping () -> NSItemProvider, @ViewBuilder preview: () -> Preview) -> some View {
    _ = preview
    return onDrag(data)
  }

  /// Transferable drag source with a Swift callback when the native drag
  /// begins. Embedded hosts still put the transferable value into the browser
  /// DataTransfer synchronously, then dispatch this callback for source UI
  /// such as highlighting compatible destinations.
  @_spi(Renderer) nonisolated func onDrag<T: Transferable>(_ value: T, onStarted: @escaping @MainActor () -> Void) -> some View {
    modifier(DragSourceModifier(descriptor: _DragSourceDescriptor(
      export: { try await value._swiftUIWebExportAll() },
      preferredTypes: T.exportedContentTypes(),
      embeddedText: _swiftUIWebDescribe(value),
      onStarted: onStarted
    )))
  }

  /// Accepts drops of the listed types. `action` receives the providers whose content matches.
  nonisolated func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?, perform action: @escaping ([NSItemProvider]) -> Bool) -> some View {
    nonisolated(unsafe) let action = action
    return modifier(_onDropModifier(of: supportedContentTypes, isTargeted: isTargeted, perform: { providers, _ in action(providers) }))
  }

  /// As ``onDrop(of:isTargeted:perform:)``, also reporting where the drop happened.
  nonisolated func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?, perform action: @escaping ([NSItemProvider], CGPoint) -> Bool) -> some View {
    modifier(_onDropModifier(of: supportedContentTypes, isTargeted: isTargeted, perform: _mainActorReturning(action)))
  }

  /// Modern Transferable destination.  Providers are loaded asynchronously at
  /// the Core boundary, while the SwiftUI-shaped action remains synchronous.
  @_disfavoredOverload nonisolated func dropDestination<T: Transferable>(for payloadType: T.Type = T.self, action: @escaping ([T], CGPoint) -> Bool, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
    nonisolated(unsafe) let isTargeted = isTargeted
    let importedTypes = T.importedContentTypes()
    let operation = _DropDestinationOperation(type: payloadType, action: _mainActorReturning(action))
    let descriptor = _DropTargetDescriptor(acceptedTypes: importedTypes, targeted: { value in isTargeted(value) }, perform: { providers, info in
      operation.start(providers, location: info.location)
      return true
    })
    return modifier(DropTargetModifier(descriptor: descriptor))
  }
}

/// Carries the delegate into the main-actor closures of a drop descriptor; only the main actor ever reads it.
private struct _DropDelegateBox: @unchecked Sendable {
  let delegate: any DropDelegate
}

public extension View {
  nonisolated func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View {
    let box = _DropDelegateBox(delegate: delegate)
    let descriptor = _DropTargetDescriptor(
      acceptedTypes: supportedContentTypes,
      targeted: { entered in
        if entered { box.delegate.dropEntered(info: DropInfo()) } else { box.delegate.dropExited(info: DropInfo()) }
      },
      perform: { _, info in box.delegate.validateDrop(info: info) && box.delegate.performDrop(info: info) })
    return ModifiedContent(content: self, modifier: DropTargetModifier(descriptor: descriptor))
  }
}
