import Foundation
import SkipFuse

// Skip-only (the web build excludes this file): the lifecycle callbacks the iOS and Android hosts forward.
let logger = Logger(subsystem: "dev.swiftuiweb.trio", category: "Trio")

/* SKIP @bridge */ public final class TrioAppDelegate: Sendable {
    /* SKIP @bridge */ public static let shared = TrioAppDelegate()

    private init() {}

    /* SKIP @bridge */ public func onInit() { logger.debug("onInit") }
    /* SKIP @bridge */ public func onLaunch() { logger.debug("onLaunch") }
    /* SKIP @bridge */ public func onResume() { logger.debug("onResume") }
    /* SKIP @bridge */ public func onPause() { logger.debug("onPause") }
    /* SKIP @bridge */ public func onStop() { logger.debug("onStop") }
    /* SKIP @bridge */ public func onDestroy() { logger.debug("onDestroy") }
    /* SKIP @bridge */ public func onLowMemory() { logger.debug("onLowMemory") }
}
