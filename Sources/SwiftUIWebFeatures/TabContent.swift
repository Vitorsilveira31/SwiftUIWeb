@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension TabContent {
  package nonisolated func customizationID(_ identifier: String) -> some TabContent<TabValue> {
    _TabModifiedContent(content: self, modifier: TabCustomizationIDModifier(identifier: identifier))
  }
}
