@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

@MainActor @preconcurrency public protocol Scene: View {}

public nonisolated struct WindowGroup<Content: View>: Scene {
  public typealias Body = Never
  package let content: Content
  public nonisolated init(@ViewBuilder content: () -> Content) { self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode { content._render(in: context) }
}

package struct EmptyScene: Scene {
  package typealias Body = Never
  package init() {}
  package func _render(in context: _RenderContext) -> _RenderNode { .empty() }
}

public struct _AppConfiguration {
  public enum Reconciler: Sendable { case fiber(useDynamicLayout: Bool = false) }
  public let reconciler: Reconciler
  public let rootEnvironment: EnvironmentValues
  public init(reconciler: Reconciler = .fiber(), rootEnvironment: EnvironmentValues = .init()) { self.reconciler = reconciler; self.rootEnvironment = rootEnvironment }
}

/// Host-neutral application title storage. Browser hosts mirror this value to
/// `document.title`; native/WASI hosts can consume it when they provide a
/// window or shell integration. Keeping the value in Core removes the former
/// silent no-op from the default `App` implementation.
package enum AppTitleRuntime {
  @MainActor package static var current: String?

  @MainActor package static func set(_ title: String) {
    current = title
  }
}

/// SwiftUIWeb applications always launch through Fiber. Renderer selection is
/// intentionally absent from this API because Fiber is the canonical runtime.
@MainActor @preconcurrency
public protocol App {
  associatedtype Body: View
  @MainActor @preconcurrency var body: Body { get }
  static var _configuration: _AppConfiguration { get }
  static func _launch(_ app: Self, with configuration: _AppConfiguration)
  static func _setTitle(_ title: String)
  @MainActor @preconcurrency init()
}
