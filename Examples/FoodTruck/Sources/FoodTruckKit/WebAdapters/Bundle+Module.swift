// Web adapter, not part of Apple's sample.
//
// SwiftPM generates `Bundle.module` for a target that has resources. This package excludes FoodTruckKit's resources
// (the web build serves them next to the page), so the accessor the sample's `bundle: .module` arguments name is
// declared here.
import Foundation

extension Bundle {
  static let module = Bundle.main
}
