import SwiftUIWebCore

/// Compile-time platform information used by the runtime boundary. Application
/// views do not need to inspect this value; it exists for bootstrappers,
/// diagnostics, and platform adapters.
package enum SwiftUIWebPlatform: String, Sendable {
  #if os(WASI)
  case wasi
  #elseif arch(wasm32)
  case webAssembly
  #else
  case native
  #endif
}

package struct SwiftUIWebRuntimeCapabilities: OptionSet, Sendable {
  package let rawValue: UInt16
  package init(rawValue: UInt16) { self.rawValue = rawValue }

  package static let browserDOM = Self(rawValue: 1 << 0)
  package static let browserEvents = Self(rawValue: 1 << 1)
  package static let history = Self(rawValue: 1 << 2)
  package static let persistentStorage = Self(rawValue: 1 << 3)
  package static let wasiIO = Self(rawValue: 1 << 4)
}

package enum SwiftUIWebRuntime {
  package static let platform: SwiftUIWebPlatform = {
    #if os(WASI)
    return .wasi
    #elseif arch(wasm32)
    return .webAssembly
    #else
    return .native
    #endif
  }()

  #if hasFeature(Embedded)
  package static let isEmbedded = true
  #else
  package static let isEmbedded = false
  #endif

  /// The neutral core advertises only capabilities it can provide without a
  /// platform adapter. A browser adapter can add DOM/events/history/storage
  /// bits when it is linked by an application.
  package static let capabilities: SwiftUIWebRuntimeCapabilities = {
    #if os(WASI)
    return [.wasiIO]
    #else
    return []
    #endif
  }()
}

/// Platform adapters consume this neutral commit boundary. Fiber and views do
/// not import JavaScript interop, DOM objects, or WASI APIs.
package protocol FiberRuntimeAdapter {
  func mount(root: _RenderNode)
  /// Compatibility boundary. Browser hosts use FiberTree's renderer SPI
  /// packed mutation stream and therefore do not require this array on their
  /// hot path; custom/native adapters keep the original source contract.
  func apply(_ mutations: [Mutation])
}
