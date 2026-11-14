import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite(.serialized)
@MainActor
struct CoreRuntimeMemoryMetricsTests {
  @Test
  func browserAndEnvironmentCountersClampClearAndIgnoreDisabledUpdates() {
    _RuntimeMemoryMetrics.start()
    defer {
      _RuntimeMemoryMetrics.stop()
      _RuntimeMemoryMetrics.reset()
    }

    _RuntimeMemoryMetrics.recordEnvironmentEntries(9)
    _RuntimeMemoryMetrics.recordEnvironmentEntries(4)
    _RuntimeMemoryMetrics.recordWebMounts(-2)
    _RuntimeMemoryMetrics.recordBrowserHandleSlots(5)
    _RuntimeMemoryMetrics.recordBrowserHandleSlots(8)
    _RuntimeMemoryMetrics.recordBrowserHandleSlots(-1)
    _RuntimeMemoryMetrics.recordBrowserIndexEntries(13)
    _RuntimeMemoryMetrics.recordScratchBuffer(bytes: 21)
    _RuntimeMemoryMetrics.recordStateStoreShape(
      entries: 3,
      subscribers: 2,
      observedKeys: 4,
      observedObjects: 1,
      dependencyOwnerEdges: 6
    )

    let active = _RuntimeMemoryMetrics.snapshot()
    #expect(active.enabled)
    #expect(active.environmentEntries == 4)
    #expect(active.peakEnvironmentEntries == 9)
    #expect(active.webMountsLive == 0)
    #expect(active.browserHandleSlots == 0)
    #expect(active.peakBrowserHandleSlots == 8)
    #expect(active.browserIndexEntries == 13)
    #expect(active.scratchBufferBytes == 21)
    #expect(active.stateStoreEntries == 3)
    #expect(active.stateStoreSubscribers == 2)
    #expect(active.stateStoreObservedKeys == 4)
    #expect(active.stateStoreObservedObjects == 1)
    #expect(active.dependencyOwnerEdges == 6)

    _RuntimeMemoryMetrics.recordBrowserHandleSlots(7)
    _RuntimeMemoryMetrics.clearBrowserHandleSlots()
    _RuntimeMemoryMetrics.clearBrowserIndexEntries()
    _RuntimeMemoryMetrics.clearScratchBuffer()
    _RuntimeMemoryMetrics.clearStateStoreShape()
    let cleared = _RuntimeMemoryMetrics.snapshot()
    #expect(cleared.browserHandleSlots == 0)
    #expect(cleared.browserIndexEntries == 0)
    #expect(cleared.scratchBufferBytes == 0)
    #expect(cleared.stateStoreEntries == 0)
    #expect(cleared.peakBrowserHandleSlots == 8)

    _RuntimeMemoryMetrics.stop()
    _RuntimeMemoryMetrics.recordEnvironmentEntries(99)
    _RuntimeMemoryMetrics.recordWebMounts(99)
    _RuntimeMemoryMetrics.recordBrowserHandleSlots(99)
    _RuntimeMemoryMetrics.recordBrowserIndexEntries(99)
    _RuntimeMemoryMetrics.recordScratchBuffer(bytes: 99)
    let disabled = _RuntimeMemoryMetrics.snapshot()
    #expect(!disabled.enabled)
    #expect(disabled.environmentEntries == 4)
    #expect(disabled.webMountsLive == 0)
    #expect(disabled.browserHandleSlots == 0)
    #expect(disabled.browserIndexEntries == 0)
    #expect(disabled.scratchBufferBytes == 0)
  }
}
