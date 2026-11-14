@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@MainActor @preconcurrency public protocol PreviewProvider {
  associatedtype Previews: View
  @MainActor @preconcurrency @ViewBuilder static var previews: Previews { get }
}
