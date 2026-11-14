@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

@inline(never)
func _onDragModifier(_ provider: @escaping @MainActor () -> NSItemProvider) -> DragSourceModifier {
  return DragSourceModifier(descriptor: _DragSourceDescriptor(export: { provider().payloads }, synchronousExport: { provider().payloads }))
}

@inline(never)
func _onDropModifier(of types: [UTType], isTargeted: Binding<Bool>?, perform action: @escaping @MainActor ([NSItemProvider], CGPoint) -> Bool) -> DropTargetModifier {
  var targeted: (@MainActor (Bool) -> Void)?
  if let isTargeted { targeted = { value in isTargeted.wrappedValue = value } }
  let descriptor = _DropTargetDescriptor(acceptedTypes: types, targeted: targeted, perform: { providers, info in action(providers, info.location) })
  return DropTargetModifier(descriptor: descriptor)
}
