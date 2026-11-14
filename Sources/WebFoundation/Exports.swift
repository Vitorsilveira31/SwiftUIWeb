/// What `import Foundation` means in the browser.
///
/// An application shared with Apple and Android writes `import Foundation` once; its browser build aliases that
/// name to this module (`-module-alias Foundation=WebFoundation`). It therefore re-exports every Foundation-shaped
/// type the runtime provides (`URL`, `Data`, `Date`, `URLRequest`, `URLSession`, formatting) next to the helpers
/// below. Core's view-layer names are deliberately not re-exported.
///
/// This target is intentionally Foundation-free. Native process/environment
/// access belongs to the application host; it must not leak into the browser
/// compatibility module through `ProcessInfo` or a conditional Foundation
/// import.
@_spi(Renderer) import SwiftUIWebTransferable
@_exported import SwiftUIWebTransferable
import SwiftUIWebCore
import SwiftUIWebFeatures
// Only the Foundation-shaped declarations of SwiftUIWebCore are re-exported. `import Foundation` must not bring in
// SwiftUI's own names (`List`, `Visibility`, `Text`, ...): they would be ambiguous with a package's types of the same
// name, exactly as they would not be with the real Foundation.
@_exported import struct SwiftUIWebCore.Bundle
@_exported import struct SwiftUIWebCore.Locale
@_exported import struct SwiftUIWebCore.TimeZone
@_exported import struct SwiftUIWebCore.DateComponents
@_exported import struct SwiftUIWebCore.Calendar
@_exported import struct SwiftUIWebFeatures.LocalizedStringResource
// The Foundation-shaped types that live in SwiftUIWebFeatures.
@_exported import struct SwiftUIWebFeatures.AttributedString
@_exported import typealias SwiftUIWebFeatures.UserDefaults
@_exported import struct SwiftUIWebFeatures.IndexSet
@_exported import enum SwiftUIWebCore.ComparisonResult
@_exported import typealias SwiftUIWebCore.CGFloat
@_exported import struct SwiftUIWebCore.CGPoint
@_exported import struct SwiftUIWebCore.CGSize
@_exported import struct SwiftUIWebCore.CGRect
@_exported import SwiftUIWebNetworking
@_exported import SwiftUIWebInternationalization

/// Runtime values exposed through one platform-neutral API. Browser and
/// Embedded hosts do not have a process environment, so the default provider
/// is intentionally empty. A native application can supply its own value at
/// the application boundary without making this module depend on Foundation.
package enum WebEnvironment {
  package typealias ValueProvider = @Sendable (String) -> String?
  /// Non-generic holder; see `SwiftUIWebDateRuntime` for why closures are not
  /// kept in a generic `_Locked` under Embedded Swift.
  private final class Storage: @unchecked Sendable {
    var provider: ValueProvider = { _ in nil }
  }
  private static let storage = Storage()

  /// Installs a host-owned environment provider. The native application
  /// boundary may bridge `ProcessInfo` here; browser and Embedded hosts can
  /// keep the default empty provider or install their own configuration.
  package static func install(provider: ValueProvider?) {
    storage.provider = provider ?? { _ in nil }
  }

  package static func value(forKey key: String) -> String? {
    storage.provider(key)
  }
}
