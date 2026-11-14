// Web adapter, not part of Apple's sample.
//
// Apple's DetailedMapView wraps `MKMapView` in a UIKit/AppKit view controller, which has no counterpart in a browser.
// This is the same view (same parameters, same non-interactive map) drawn with the framework's MapKit `Map`.
import CoreLocation
import MapKit
import SwiftUI

struct DetailedMapView: View {
    var location: CLLocation
    var distance: Double = 1000
    var pitch: Double = 0
    var heading: Double = 0
    var topSafeAreaInset: Double

    var body: some View {
        Map(position: .constant(.camera(MapCamera(
            centerCoordinate: location.coordinate, distance: distance, heading: heading, pitch: pitch
        ))))
        .allowsHitTesting(false)
        .padding(.top, topSafeAreaInset)
    }
}
