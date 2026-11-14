import SwiftUIWebBrowserIO

extension WebSecurity {
  /// Whether the server's sign-in session is active, learned without touching its credential.
  ///
  /// The session is an `HttpOnly`, `Secure`, `SameSite` cookie the server sets at sign-in; the
  /// browser stores it and attaches it to requests on its own, and the browser host never passes a
  /// `Set-Cookie` header to Swift. The app works with the session's state: it asks an endpoint the
  /// server protects with that cookie, and a 2xx answer means signed in. The endpoint must answer itself: a redirect
  /// (to a sign-in page that answers 200, say) is refused and reads as `unknown`, never as `active`.
  public struct Session: Sendable {
    public enum State: Sendable, Equatable {
      /// The endpoint answered 2xx: the cookie is present and valid.
      case active
      /// 401 or 403: no session, or it expired.
      case signedOut
      /// The request failed, was redirected or answered something else; the state is not known.
      case unknown(status: Int)
    }

    public typealias Transport = @Sendable (BrowserHTTPRequest) async throws -> Int

    public let statusURL: String
    public let credentials: BrowserHTTPRequest.Credentials
    private let transport: Transport

    /// - Parameters:
    ///   - statusURL: an endpoint the session cookie authorizes, such as `/api/me`.
    ///   - credentials: `.sameOrigin` when the API shares the page's origin; `.include` for an API
    ///     on another origin that answers CORS with `Access-Control-Allow-Credentials`.
    public init(statusURL: String, credentials: BrowserHTTPRequest.Credentials = .sameOrigin, transport: Transport? = nil) {
      self.statusURL = statusURL
      self.credentials = credentials
      self.transport = transport ?? { request in try await BrowserHTTPClient.send(request).statusCode }
    }

    public func state() async -> State {
      let request = BrowserHTTPRequest(
        url: statusURL, headers: ["Accept": "application/json"], maximumResponseBytes: 65_536, credentials: credentials,
        redirect: .error, cache: .noStore
      )
      guard let status = try? await transport(request) else { return .unknown(status: 0) }
      switch status {
      case 200..<300: return .active
      case 401, 403: return .signedOut
      default: return .unknown(status: status)
      }
    }
  }
}
