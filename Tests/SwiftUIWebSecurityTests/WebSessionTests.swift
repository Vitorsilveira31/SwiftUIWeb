import Testing
import SwiftUIWebBrowserIO
@testable import SwiftUIWebSecurity

/// The session is learned from the status of an endpoint its cookie authorizes; the request carries
/// the configured credentials mode and nothing about the cookie itself.
struct WebSessionTests {
  private actor Recorder {
    var requests: [BrowserHTTPRequest] = []
    func record(_ request: BrowserHTTPRequest) { requests.append(request) }
  }

  @Test func status_codes_map_to_session_states() async {
    for (status, expected) in [(200, WebSecurity.Session.State.active), (204, .active), (401, .signedOut),
                               (403, .signedOut), (500, .unknown(status: 500))] {
      let session = WebSecurity.Session(statusURL: "/api/me", transport: { _ in status })
      #expect(await session.state() == expected)
    }
    let offline = WebSecurity.Session(statusURL: "/api/me", transport: { _ in throw BrowserIOError(code: -3, message: "offline") })
    #expect(await offline.state() == .unknown(status: 0))
  }

  @Test func the_request_uses_the_credentials_mode() async {
    let recorder = Recorder()
    let session = WebSecurity.Session(statusURL: "https://api.example.com/me", credentials: .include, transport: { request in
      await recorder.record(request)
      return 200
    })
    _ = await session.state()
    let request = await recorder.requests.first
    #expect(request?.credentials == .include)
    #expect(request?.method == "GET")
    #expect(request?.headers["Cookie"] == nil)
    // A redirect is not the endpoint's answer: a sign-in page answering 200 must not read as signed in.
    #expect(request?.redirect == .error)
  }
}
