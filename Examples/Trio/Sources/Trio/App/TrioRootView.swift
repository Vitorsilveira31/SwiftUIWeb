import SwiftUI

// The shared top-level view. Every host loads it: Darwin/Sources/Main.swift on iOS, the Skip-generated activity on
// Android (Android/app/src/main/kotlin/Main.kt) and Web/TrioWebApp.swift in the browser. Only how they start differs.
/* SKIP @bridge */ public struct TrioRootView: View {
    /* SKIP @bridge */ public init() {}

    public var body: some View {
        ContentView()
    }
}
