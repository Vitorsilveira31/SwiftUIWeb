import SwiftUIWeb

/// A wrapper-owned description of an optional browser feature.  This is SPI,
/// not a SwiftUI-facing type: feature packages use it to describe the ESM
/// entry point and its sidecar assets without making Core or application code
/// aware of JavaScript package-manager or DOM concepts.
@_spi(Browser)
public struct _WebFeatureManifest: Hashable, Sendable {
  public let id: String
  public let entry: String
  public let styles: [String]
  public let workers: [String]
  public let routes: [String]
  public let viewportScope: String?

  public init(
    id: String,
    entry: String,
    styles: [String] = [],
    workers: [String] = [],
    routes: [String] = [],
    viewportScope: String? = nil
  ) {
    self.id = id
    self.entry = entry
    self.styles = styles
    self.workers = workers
    self.routes = routes
    self.viewportScope = viewportScope
  }

  /// Converts the manifest into the existing prefetch planner's compact
  /// resources.  Route/viewport hints are low-priority browser work and do
  /// not evaluate the ESM module; a wrapper still calls `load` at activation.
  @_spi(Browser)
  public var _prefetchResources: [_WebPrefetchResource] {
    guard !id.isEmpty, !entry.isEmpty else { return [] }
    let triggers: [_WebPrefetchTrigger]
    if !routes.isEmpty {
      triggers = routes.map { .route($0) }
    } else if let viewportScope {
      triggers = [.viewport(viewportScope)]
    } else {
      // An explicitly registered feature may be warmed after first paint,
      // while the initial application route remains free of provider bytes.
      triggers = [.idle]
    }

    var resources: [_WebPrefetchResource] = []
    for trigger in triggers {
      resources.append(_WebPrefetchResource(
        url: entry,
        kind: .module,
        trigger: trigger,
        priority: routes.isEmpty ? 80 : 12
      ))
      resources.append(contentsOf: styles.map {
        _WebPrefetchResource(
          url: $0,
          kind: .stylesheet,
          trigger: trigger,
          priority: routes.isEmpty ? 82 : 14
        )
      })
      resources.append(contentsOf: workers.map {
        _WebPrefetchResource(
          url: $0,
          kind: .worker,
          trigger: trigger,
          priority: routes.isEmpty ? 84 : 16
        )
      })
    }
    return resources
  }
}

@_spi(Browser)
public struct _WebFeatureLoadError: Error, Equatable, Sendable {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }
}

/// Internal runtime used by Web integration packages.  Registration feeds the
/// existing idle/route/viewport prefetch planner.  Loading is a separate,
/// demand-driven operation backed by the browser's cached dynamic `import()`;
/// no provider JavaScript is evaluated during SwiftUI tree construction.
@_spi(Browser)
@MainActor public enum WebFeatureRuntime {
  @discardableResult
  public static func register(_ manifest: _WebFeatureManifest) -> _WebPrefetchRegistration {
    WebPrefetchRuntime.register(manifest._prefetchResources)
  }

  @discardableResult
  public static func register<S: Sequence>(_ manifests: S) -> _WebPrefetchRegistration where S.Element == _WebFeatureManifest {
    var resources: [_WebPrefetchResource] = []
    for manifest in manifests {
      resources.append(contentsOf: manifest._prefetchResources)
    }
    return WebPrefetchRuntime.register(resources)
  }

  /// Embedded browser hosts use the JavaScript loader. Native hosts can
  /// still compile wrapper packages; their browser-only call is represented by
  /// a deterministic unsupported error rather than reaching into JavaScript.
  public static func load(_ manifest: _WebFeatureManifest) async throws -> Any {
    _ = manifest
    throw _WebFeatureLoadError("Web feature loading requires a browser WebAssembly host")
  }

  public static func loadFromManifest(id: String) async throws -> Any {
    _ = id
    throw _WebFeatureLoadError("Web feature loading requires a browser WebAssembly host")
  }

  public static func prefetch(_ manifest: _WebFeatureManifest) { _ = manifest }
  public static func prefetchRoute(_ route: String) { _ = route }
}
