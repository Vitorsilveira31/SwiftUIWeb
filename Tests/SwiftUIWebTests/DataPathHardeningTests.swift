import Testing
@testable import SwiftUIWebNetworking
import SwiftUIWebBrowserIO

/// Requests and storage that read data from outside the app: the browser cache mode a request names must follow its
/// cache policy, and the default request must keep the browser's own cache behaviour.
@Suite
struct DataPathHardeningTests {
  @Test func browser_request_defaults_to_the_browser_cache_mode() {
    let request = BrowserHTTPRequest(url: "https://example.test/data")
    #expect(request.cache == .default)
    #expect(BrowserHTTPRequest.Cache.noStore.rawValue == "no-store")
    #expect(BrowserHTTPRequest.Cache.noCache.rawValue == "no-cache")
    #expect(BrowserHTTPRequest.Cache.reload.rawValue == "reload")
  }

  @Test func reload_policies_bypass_the_cache_and_the_others_keep_the_default() {
    var request = URLRequest(url: URL("https://example.test/data"))
    #expect(request.browserCacheMode == "default")
    request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
    #expect(request.browserCacheMode == "no-store")
    request.cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData
    #expect(request.browserCacheMode == "no-store")
    request.cachePolicy = URLRequest.CachePolicy.reloadRevalidatingCacheData
    #expect(request.browserCacheMode == "no-cache")
    request.cachePolicy = URLRequest.CachePolicy.returnCacheDataElseLoad
    #expect(request.browserCacheMode == "default")
  }
}
