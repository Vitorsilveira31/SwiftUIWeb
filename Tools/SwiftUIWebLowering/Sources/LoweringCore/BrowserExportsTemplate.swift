import Foundation

/// The entry points appended to a `@main` `BrowserApp`, byte for byte as the previous lowerer writes them: the browser host
/// calls these `@_cdecl` functions by name, so the wording is part of the contract with the JavaScript runtime.
/// `__APP__` stands for the application type.
enum BrowserExportsTemplate {
  static func exports(for appType: String) -> String {
    "\n\n" + body.replacingOccurrences(of: "__APP__", with: appType) + "\n"
  }

  /// The entry point of a `--live-literals` build.
  static let liveLiterals = "@_expose(wasm, \"embedded_browser_live_literals\")\n@_cdecl(\"embedded_browser_live_literals\")\n@MainActor public func swiftuiwebEmbeddedBrowserLiveLiterals() -> UInt32 { BrowserAppLauncher.embeddedBrowserLiveLiterals() }\n"

  /// The entry point of a `--development-exports` build: the page calls it before a reload of the development loop.
  static let stateSave = "@_expose(wasm, \"embedded_browser_state_save\")\n@_cdecl(\"embedded_browser_state_save\")\n@MainActor public func swiftuiwebEmbeddedBrowserStateSave() -> UInt32 { BrowserAppLauncher.embeddedBrowserStateSave() }\n"

  private static let body = #"""
@_cdecl("embedded_browser_start")
@MainActor public func swiftuiwebEmbeddedBrowserStart() {
  BrowserAppLauncher.embeddedBrowserLaunch(__APP__(), configuration: __APP__._configuration)
}

@_cdecl("embedded_browser_dispatch")
@MainActor public func swiftuiwebEmbeddedBrowserDispatch(_ id: UInt32, _ eventCode: UInt32) {
  BrowserAppLauncher.embeddedBrowserDispatch(id, eventCode: eventCode)
}

@_cdecl("embedded_browser_dispatch_named")
@MainActor public func swiftuiwebEmbeddedBrowserDispatchNamed(_ id: UInt32, _ nameLength: UInt32) -> UInt32 {
  BrowserAppLauncher.embeddedBrowserDispatchNamed(id, nameLength: nameLength)
}

@_cdecl("embedded_browser_event_value_reset")
@MainActor public func swiftuiwebEmbeddedBrowserEventValueReset() { BrowserAppLauncher.embeddedBrowserEventValueReset() }

@_cdecl("embedded_browser_event_value_push")
@MainActor public func swiftuiwebEmbeddedBrowserEventValuePush(_ byte: UInt32) { BrowserAppLauncher.embeddedBrowserEventValuePush(byte) }

@_cdecl("embedded_browser_secure_value")
@MainActor public func swiftuiwebEmbeddedBrowserSecureValue() -> UInt32 { BrowserAppLauncher.embeddedBrowserSecureValue() }

@_cdecl("embedded_browser_secure_value_reset")
@MainActor public func swiftuiwebEmbeddedBrowserSecureValueReset() { BrowserAppLauncher.embeddedBrowserSecureValueReset() }

@_cdecl("embedded_browser_secure_value_byte")
@MainActor public func swiftuiwebEmbeddedBrowserSecureValueByte(_ index: UInt32) -> UInt32 {
  BrowserAppLauncher.embeddedBrowserSecureValueByte(index)
}

@_cdecl("embedded_browser_event_value_alloc")
@MainActor public func swiftuiwebEmbeddedBrowserEventValueAlloc(_ length: UInt32) -> UInt32 { BrowserAppLauncher.embeddedBrowserEventValueAlloc(length) }

@_cdecl("embedded_browser_event_value_commit")
@MainActor public func swiftuiwebEmbeddedBrowserEventValueCommit(_ length: UInt32) { BrowserAppLauncher.embeddedBrowserEventValueCommit(length) }

@_cdecl("embedded_browser_secure_value_pointer")
@MainActor public func swiftuiwebEmbeddedBrowserSecureValuePointer() -> UInt32 { BrowserAppLauncher.embeddedBrowserSecureValuePointer() }

@_cdecl("embedded_browser_secure_ids_length")
@MainActor public func swiftuiwebEmbeddedBrowserSecureIDsLength() -> UInt32 { BrowserAppLauncher.embeddedBrowserSecureIDsLength() }

@_cdecl("embedded_browser_secure_ids_pointer")
@MainActor public func swiftuiwebEmbeddedBrowserSecureIDsPointer() -> UInt32 { BrowserAppLauncher.embeddedBrowserSecureIDsPointer() }

@_cdecl("embedded_browser_timeline_tick")
@MainActor public func swiftuiwebEmbeddedBrowserTimelineTick() { BrowserAppLauncher.embeddedBrowserTimelineTick() }

@_cdecl("embedded_browser_batch_begin")
@MainActor public func swiftuiwebEmbeddedBrowserBatchBegin() { BrowserAppLauncher.embeddedBrowserBatchBegin() }

@_cdecl("embedded_browser_batch_end")
@MainActor public func swiftuiwebEmbeddedBrowserBatchEnd() { BrowserAppLauncher.embeddedBrowserBatchEnd() }

@_cdecl("embedded_browser_lazy_collection_count")
@MainActor public func swiftuiwebEmbeddedBrowserLazyCollectionCount() -> UInt32 { BrowserAppLauncher.embeddedBrowserLazyCollectionCount() }

@_cdecl("embedded_browser_lazy_item_count")
@MainActor public func swiftuiwebEmbeddedBrowserLazyItemCount(_ collection: UInt32) -> UInt32 { BrowserAppLauncher.embeddedBrowserLazyItemCount(collection) }

@_cdecl("embedded_browser_lazy_estimated_extent")
@MainActor public func swiftuiwebEmbeddedBrowserLazyEstimatedExtent(_ collection: UInt32) -> Double { BrowserAppLauncher.embeddedBrowserLazyEstimatedExtent(collection) }

@_cdecl("embedded_browser_lazy_window")
@MainActor public func swiftuiwebEmbeddedBrowserLazyWindow(_ collection: UInt32, _ start: UInt32, _ count: UInt32, _ before: Double, _ after: Double) { BrowserAppLauncher.embeddedBrowserLazyWindow(collection, start: start, count: count, before: before, after: after) }

@_cdecl("embedded_browser_webmount_reconcile")
@MainActor public func swiftuiwebEmbeddedBrowserWebMountReconcile() { BrowserAppLauncher.embeddedBrowserWebMountReconcile() }

@_cdecl("embedded_browser_html_length")
@MainActor public func swiftuiwebEmbeddedBrowserHTMLLength() -> UInt32 {
  BrowserAppLauncher.embeddedBrowserHTMLLength()
}

@_cdecl("embedded_browser_publish_seq")
@MainActor public func swiftuiwebEmbeddedBrowserPublishSequence() -> UInt32 { BrowserAppLauncher.embeddedBrowserPublishSequence() }

@_cdecl("embedded_browser_publish_ack")
@MainActor public func swiftuiwebEmbeddedBrowserPublishAck(_ sequence: UInt32) { BrowserAppLauncher.embeddedBrowserPublishAcknowledge(sequence) }

@_cdecl("embedded_browser_publish_full")
@MainActor public func swiftuiwebEmbeddedBrowserPublishFull() { BrowserAppLauncher.embeddedBrowserPublishFull() }

@_cdecl("embedded_browser_fiber_metric")
@MainActor public func swiftuiwebEmbeddedBrowserFiberMetric(_ index: UInt32) -> UInt32 {
  BrowserAppLauncher.embeddedBrowserFiberMetric(index)
}

@_cdecl("embedded_browser_html_pointer")
@MainActor public func swiftuiwebEmbeddedBrowserHTMLPointer() -> UInt32 { BrowserAppLauncher.embeddedBrowserHTMLPointer() }

@_cdecl("embedded_browser_html_byte")
@MainActor public func swiftuiwebEmbeddedBrowserHTMLByte(_ index: UInt32) -> UInt32 {
  BrowserAppLauncher.embeddedBrowserHTMLByte(index)
}

@_cdecl("embedded_browser_drain_tasks")
@MainActor public func swiftuiwebEmbeddedBrowserDrainTasks() -> UInt32 { BrowserAppLauncher.embeddedBrowserDrainTasks() }

@_cdecl("embedded_browser_set_initial_preferences")
@MainActor public func swiftuiwebEmbeddedBrowserSetInitialPreferences(_ dark: UInt32, _ reducedMotion: UInt32) {
  BrowserAppLauncher.embeddedBrowserSetInitialPreferences(dark: dark, reducedMotion: reducedMotion)
}

@_cdecl("browser_io_receive")
@MainActor public func swiftuiwebIOReceive(_ id: UInt32, _ status: Int32, _ pointer: UnsafePointer<UInt8>?, _ count: UInt32) { BrowserAppLauncher.embeddedBrowserIOReceive(id, status: status, pointer, count: count) }

@_cdecl("embedded_browser_viewport")
@MainActor public func swiftuiwebEmbeddedBrowserViewport(_ width: Double, _ height: Double, _ dark: UInt32, _ reducedMotion: UInt32) { BrowserAppLauncher.embeddedBrowserViewport(width, height: height, dark: dark, reducedMotion: reducedMotion) }
@_cdecl("embedded_browser_scroll_ack")
@MainActor public func swiftuiwebEmbeddedBrowserScrollAck(_ sequence: UInt32) { BrowserAppLauncher.embeddedBrowserAcknowledgeScroll(sequence) }
@_cdecl("embedded_browser_scroll_prepare")
@MainActor public func swiftuiwebEmbeddedBrowserScrollPrepare() -> UInt32 { BrowserAppLauncher.embeddedBrowserPrepareScrollTarget() }

@_cdecl("embedded_browser_history_ack")
@MainActor public func swiftuiwebEmbeddedHistoryAck(_ sequence: UInt32) { BrowserAppLauncher.embeddedBrowserHistoryAcknowledge(sequence) }
@_cdecl("embedded_browser_history_restore")
@MainActor public func swiftuiwebEmbeddedHistoryRestore() { BrowserAppLauncher.embeddedBrowserHistoryRestore() }
@_cdecl("embedded_browser_cookies_changed")
@MainActor public func swiftuiwebEmbeddedBrowserCookiesChanged() { BrowserAppLauncher.embeddedBrowserCookiesChanged() }
@_cdecl("embedded_browser_history_location")
@MainActor public func swiftuiwebEmbeddedHistoryLocation() { BrowserAppLauncher.embeddedBrowserHistoryLocation() }
"""#
}
