import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebFiber
import SwiftUIWebHTML

/// Default application entry point supplied by the façade. Browser targets
/// override `_launch` with their DOM-backed runtime, while native and WASI
/// executables get deterministic Fiber HTML output.
public extension App {
  static var _configuration: _AppConfiguration { _AppConfiguration() }

  static func _setTitle(_ title: String) {
    AppTitleRuntime.set(title)
  }

  static func _launch(_ app: Self, with configuration: _AppConfiguration) {
    print(StaticHTMLFiberRenderer().render(app.body, environment: configuration.rootEnvironment))
  }

  @MainActor @preconcurrency static func main() { _launch(Self(), with: _configuration) }
}

package extension StaticHTMLFiberRenderer {
  @MainActor func renderTree<V: View>(_ view: V, environment: EnvironmentValues) -> FiberTree {
    FiberTree(view, environment: environment)
  }

  @MainActor func render<V: View>(_ view: V, environment: EnvironmentValues) -> String {
    StaticHTMLFiberRenderer().renderTree(view, environment: environment).root.renderNode.htmlDescription
  }

  @MainActor func render<A: App>(_ app: A) -> String {
    render(app.body, environment: A._configuration.rootEnvironment)
  }

  @MainActor func renderTree<A: App>(_ app: A) -> FiberTree {
    renderTree(app.body, environment: A._configuration.rootEnvironment)
  }
}
