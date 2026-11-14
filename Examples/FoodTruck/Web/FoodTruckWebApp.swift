import FoodTruck
import SwiftUIWeb
import SwiftUIWebBrowser

// Replaces Apple/App/App.swift, whose `@main` is the Apple host. The scene is the same: one window with ContentView
// (through FoodTruckWebRoot, which holds the model and the account store as App.swift does).
@main
struct FoodTruckWebApp: BrowserApp {
  var body: some View {
    WindowGroup {
      FoodTruckWebRoot()
    }
  }
}
