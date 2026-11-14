import SwiftUI

// Shows the fixtures of the chosen page.
struct GalleryPageContent: View {
    let page: GalleryPage

    var body: some View {
        switch page {
        case .one: Page01View()
        case .two: Page02View()
        case .three: Page03View()
        case .four: Page04View()
        case .five: Page05View()
        case .six: Page06View()
        case .seven: Page07View()
        case .eight: Page08View()
        case .nine: Page09View()
        case .ten: Page10View()
        }
    }
}
