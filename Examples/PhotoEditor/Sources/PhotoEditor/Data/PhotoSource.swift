import SwiftUI

/// Where the photo comes from: the bundled picture, or one the person chose.
enum PhotoSource {
    case sample
    case picked(Image)
}
