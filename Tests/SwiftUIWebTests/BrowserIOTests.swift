import Testing
import SwiftUIWeb
import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebHTML
import SwiftUIWebBrowserIO
import CSwiftUIWebBrowserIO

/// A view whose every level is an erased boundary, so each one passes through the render depth meter.
@MainActor private func nestedBoundaries(_ depth: Int) -> AnyView {
  depth == 0 ? AnyView(Text("leaf")) : AnyView(VStack { nestedBoundaries(depth - 1) })
}

private func browserIOCTestCallback(
  _ identifier: UInt32,
  _ status: Int32,
  _ bytes: UnsafePointer<UInt8>?,
  _ length: UInt32
) {
  _ = (identifier, status, bytes, length)
}

@Suite(.processGlobalState)
@MainActor
final class BrowserIOTests {
  @Test
  func testNativeCAdapterGuardsAndDeliveryOwnership() {
    _swiftUIWebInstallConcurrencyHooks(nil, nil, nil)
    browser_io_set_callback(browserIOCTestCallback)

    let empty = browser_io_alloc(0)
    #expect(empty != nil)
    browser_io_free(empty)
    #expect(browser_io_alloc(67_108_865) == nil)

    let payload = browser_io_alloc(2)!.assumingMemoryBound(to: UInt8.self)
    payload[0] = 0x61
    payload[1] = 0x62
    browser_io_deliver(1, 200, payload, 2)
    browser_io_deliver(2, 200, nil, 0)
    // A bounded non-zero payload without an owned pointer must be rejected;
    // the native bridge must also tolerate delivery after the callback is
    // removed without dereferencing a stale function pointer.
    browser_io_deliver(4, 200, nil, 1)
    browser_io_deliver(3, 200, nil, 67_108_865)
    browser_io_set_callback(nil)
    browser_io_deliver(5, 200, nil, 0)

    #expect(browser_io_request(1, 1, nil, 0) == -7)
    browser_io_cancel_request(1)
    #expect(browser_io_sync_request(1, nil, 0) == 0)
    #expect(browser_io_result_length(0) == 0)
    #expect(browser_io_result_copy(0, nil, 0) == -7)
    browser_io_result_release(0)
    // A native host has no shared binary atom table: it writes none and reports none, whatever the buffer.
    var atoms = [UInt8](repeating: 0xAB, count: 4)
    #expect(atoms.withUnsafeMutableBufferPointer { browser_io_binary_atoms($0.baseAddress, 4) } == 0)
    #expect(atoms == [0xAB, 0xAB, 0xAB, 0xAB])
    #expect(browser_io_binary_atoms(nil, 0) == 0)
  }

  @Test
  func renderDepthSamplesReachTheStackHeadroomHookWhileTheTreeRenders() {
    // Native hosts measure no call stack: the hook accepts every sample and the render is unaffected.
    var sampled: [Int] = []
    let wasEnabled = _RenderDepthMeter.enabled
    _RenderDepthMeter.observer = { depth in
      sampled.append(depth)
      browser_io_stack_headroom(UInt32(truncatingIfNeeded: depth))
    }
    _RenderDepthMeter.enabled = true
    defer {
      _RenderDepthMeter.enabled = wasEnabled
      _RenderDepthMeter.observer = nil
    }

    let html = StaticHTMLFiberRenderer().render(nestedBoundaries(6))
    #expect(html.contains("leaf"))
    #expect((sampled.max() ?? 0) >= 6, "every nested boundary is sampled at its depth")
    #expect(_RenderDepthMeter.depth == 0, "entering and leaving each boundary is balanced")
  }

  @Test
  func testAsyncBrowserOperationsExposeUnavailableHostErrors() async {
    let request = BrowserHTTPRequest(
      url: "https://example.test/data",
      method: "POST",
      headers: ["x-test": "one"],
      body: [1, 2, 3],
      timeoutMilliseconds: 10,
      maximumResponseBytes: 100,
      credentials: .include,
      redirect: .manual
    )

    let callbackOperation = BrowserHTTPClient.send(request) { result in
      guard case .failure(let error) = result else {
        Issue.record("native stub unexpectedly returned a response")
        return
      }
      #expect(error.code == -7)
    }
    callbackOperation.cancel()
    callbackOperation.cancel()
    #expect(callbackOperation.isCancelled)

    do {
      _ = try await BrowserHTTPClient.send(request)
      Issue.record("expected unavailable BrowserIO host")
    } catch let error as BrowserIOError {
      #expect(error.code == -7)
    } catch {
      Issue.record("unexpected error: \(error)")
    }

    let timer = BrowserTimer.schedule(after: .nan) {}
    timer.cancel()
    do {
      try await BrowserTimer.sleep(for: .infinity)
      Issue.record("expected unavailable BrowserIO host")
    } catch let error as BrowserIOError {
      #expect(error.code == -7)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }

  @Test
  func testBrowserStreamStorageConnectivityIntlAndDOMFallbacks() async {
    let request = BrowserHTTPRequest(url: "https://example.test/stream")
    var events: [String] = []
    let operation = BrowserHTTPClient.stream(request) { event in
      if case .failure(let error) = event {
        events.append("failure:\(error.code)")
      }
    }
    operation.cancel()
    #expect(events == ["failure:-7"])

    do {
      _ = try await BrowserHTTPClient.stream(request)
      Issue.record("expected unavailable BrowserIO host")
    } catch let error as BrowserIOError {
      #expect(error.code == -7)
    } catch {
      Issue.record("unexpected error: \(error)")
    }

    let storage = BrowserWebStorage(.session, namespace: "test")
    #expect((try? storage.get("missing")) == nil)
    #expect((try? storage.set("value", forKey: "key")) == nil)
    #expect((try? storage.remove("key")) == nil)
    #expect((try? storage.removeAll()) == nil)
    #expect((try? storage.keys()) == nil)
    #expect((try? storage.revision()) == nil)
    #expect((try? storage.transaction([.set(key: "key", value: "value")])) == nil)
    #expect(BrowserConnectivity.isOnline() == nil)
    let storageObserver = BrowserWebStorage.observeChanges { _ in }
    storageObserver.cancel()
    let connectivityObserver = BrowserConnectivity.observe { _ in }
    connectivityObserver.cancel()

    #expect(BrowserIntl.format(epochSeconds: .nan, style: 0) == nil)
    #expect(BrowserIntl.format(epochSeconds: 0, style: 0) == nil)
    #expect(BrowserIntl.format(epochSeconds: 0, style: 0, offsetSeconds: Int.max) == nil)
    #expect(BrowserText.formatNumber("1", options: "") == nil)
    #expect(BrowserText.fold("é", diacritics: true, case: true) == nil)

    let element = BrowserDOMElement(identifier: 1)
    #expect(!BrowserDOMBridge.isConnected(element))
    #expect(BrowserDOMBridge.attribute("title", of: element) == nil)
    BrowserDOMBridge.setAttribute("title", value: "value", on: element)
    BrowserDOMBridge.removeAttribute("title", from: element)
    #expect(BrowserDOMBridge.value(of: element) == nil)
    BrowserDOMBridge.setValue("value", on: element)
    #expect(BrowserDOMBridge.textContent(of: element) == nil)
    BrowserDOMBridge.setTextContent("value", on: element)
    #expect(BrowserDOMBridge.isSameNode(element, BrowserDOMElement(identifier: 1)))
    #expect((try? BrowserDOMBridge.mounts()) == nil)

    #expect(BrowserMediaBridge.currentTime(element) == 0)
    BrowserMediaBridge.setCurrentTime(3, element)
    #expect(BrowserMediaBridge.duration(element).isNaN)
    #expect(BrowserMediaBridge.rate(element) == 1)
    BrowserMediaBridge.setRate(2, element)
    #expect(BrowserMediaBridge.volume(element) == 1)
    BrowserMediaBridge.setVolume(0.5, element)
    #expect(!BrowserMediaBridge.muted(element))
    BrowserMediaBridge.setMuted(true, element)
    BrowserMediaBridge.play(element)
    BrowserMediaBridge.pause(element)
    BrowserMediaBridge.setSource("media", element)
    #expect(!BrowserMediaBridge.canPlay("video/mp4", element))
    #expect(BrowserMediaBridge.readyState(element) == 0)
    #expect(BrowserMediaBridge.networkState(element) == 0)
    #expect(BrowserMediaBridge.buffered(element).isEmpty)
    #expect(BrowserMediaBridge.seekable(element).isEmpty)
    BrowserMediaBridge.requestFullscreen(element)
    BrowserMediaBridge.exitFullscreen(element)
    #expect(!BrowserMediaBridge.supportsPictureInPicture(element))
    BrowserMediaBridge.setPictureInPicture(true, element)
    BrowserMediaBridge.attachAdaptive("manifest", element)
    BrowserMediaBridge.detachAdaptive(element)
    let mediaObserver = BrowserMediaBridge.observe(element, event: "play") {}
    mediaObserver.cancel()
    let keyObserver = BrowserMediaBridge.observeKeydown(element) { _, _ in }
    keyObserver.cancel()

    let database = BrowserIndexedDB(databaseName: "test", version: 2)
    do {
      _ = try await database.get("missing")
      Issue.record("expected unavailable BrowserIO host")
    } catch let error as BrowserIOError {
      #expect(error.code == -7)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
    do {
      try await database.put([1], forKey: "key")
      Issue.record("expected unavailable BrowserIO host")
    } catch let error as BrowserIOError {
      #expect(error.code == -7)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
    do {
      try await database.transaction([.removeAll])
      Issue.record("expected unavailable BrowserIO host")
    } catch let error as BrowserIOError {
      #expect(error.code == -7)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }
}
