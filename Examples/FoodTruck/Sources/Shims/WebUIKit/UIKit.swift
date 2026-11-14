// Apple's Food Truck chooses its system colors with `#if canImport(UIKit)`; the UIKit names it uses (`UIColor`,
// `Color(uiColor:)`) are part of SwiftUI there, so they live in SwiftUIWeb. This module only has to exist for
// `canImport(UIKit)` to be true.
import SwiftUIWeb
