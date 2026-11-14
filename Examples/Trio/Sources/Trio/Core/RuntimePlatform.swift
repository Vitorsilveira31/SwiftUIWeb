// The one place that asks which host is running, only so the demo can say it on screen. Nothing else in the app
// branches on the platform.
enum RuntimePlatform {
    static var name: String {
        #if WEB
            "Web"
        #elseif os(Android)
            "Android"
        #else
            "iOS"
        #endif
    }

    static var engine: String {
        #if WEB
            "SwiftUIWeb · Embedded Swift/WebAssembly"
        #elseif os(Android)
            "Skip Fuse · Jetpack Compose"
        #else
            "SwiftUI"
        #endif
    }
}
