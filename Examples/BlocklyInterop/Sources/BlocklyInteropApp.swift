import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebWeb

@main
struct BlocklyInteropApp: BrowserApp {
  var body: some View {
    WindowGroup { BlocklyInteropScreen() }
  }
}

private struct BlocklyInteropScreen: View {
  @State private var updatedFromSwift = false
  @State private var isEditorVisible = true
  @State private var changeCount = 0
  @State private var lastSerializedWorkspace = "Nenhuma alteração recebida ainda."

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Blockly integrado ao DOM do SwiftUIWeb")
        .font(.title2)
      Text("O workspace vive nesta página, sem URL externa e sem iframe.")
      HStack {
        Button(updatedFromSwift ? "Atualizar para estado A" : "Atualizar para estado B") {
          updatedFromSwift.toggle()
        }
        Button(isEditorVisible ? "Remover componente" : "Montar novamente") {
          isEditorVisible.toggle()
        }
      }
      Text("Alterações serializadas do Blockly: \(changeCount)")
      Text(lastSerializedWorkspace)
        .font(.caption)
        .lineLimit(2)
      if isEditorVisible {
        BlocklyView(
          status: updatedFromSwift ? "Atualizado pelo Swift: estado B" : "Blockly montado uma vez",
          onWorkspaceChange: { serialized in
            changeCount += 1
            lastSerializedWorkspace = String(serialized.prefix(180))
          }
        )
        .frame(maxWidth: .infinity)
        .frame(height: 520, alignment: .topLeading)
      } else {
        Text("O componente Blockly foi removido; seus listeners e workspace foram descartados.")
          .frame(height: 160)
      }
    }
    .padding(24)
    .frame(maxWidth: 1100)
  }
}

private struct BlocklyView: DOMViewRepresentable {
  let status: String
  let onWorkspaceChange: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onWorkspaceChange: onWorkspaceChange)
  }

  func makeDOMView(context: Context) -> DOMView {
    let domView = DOMView(component: "blockly", state: status)
    let coordinator = context.coordinator
    domView.onMessage = { message in
      coordinator.onWorkspaceChange(message)
    }
    return domView
  }

  func updateDOMView(_ domView: DOMView, context: Context) {
    context.coordinator.onWorkspaceChange = onWorkspaceChange
    domView.state = status
  }

  static func dismantleDOMView(_ domView: DOMView, coordinator: Coordinator) {
    coordinator.didDismantle = true
  }

  final class Coordinator {
    var onWorkspaceChange: (String) -> Void
    var didDismantle = false
    init(onWorkspaceChange: @escaping (String) -> Void) {
      self.onWorkspaceChange = onWorkspaceChange
    }
  }
}
