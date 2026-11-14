import SwiftUI

/// The one spring every deck move uses: throws, undo, and a card springing back to rest.
enum DeckMotion {
    static var spring: Animation { .spring(duration: 0.42, bounce: 0.12) }
}
