// Web adapter, not part of Apple's sample.
//
// Apple's App.swift is the `@main` of the Xcode target: it owns the model and the account store and puts ContentView
// in a window. This is that scene's content, public so the browser entry point (Web/) can use it.
import FoodTruckKit
import SwiftUI

public struct FoodTruckWebRoot: View {
    @StateObject private var model = FoodTruckModel()
    @State private var accountStore = AccountStore()

    public init() {}

    public var body: some View {
        ContentView(model: model, accountStore: accountStore)
    }
}
