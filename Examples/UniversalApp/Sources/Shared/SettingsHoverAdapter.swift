// The shared Settings rows use the same system highlight API on both hosts.
#if WEB
import SwiftUIWeb
#else
import SwiftUI
#endif

extension View {
  func settingsDirectRowActionHoverEffect() -> some View {
    hoverEffect(.highlight)
  }
}
