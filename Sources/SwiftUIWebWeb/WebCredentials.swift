import SwiftUIWebNetworking

/// Whether the browser attaches cookies and HTTP credentials to a URLSession request.
///
/// The values match the browser `fetch` credentials modes. Foundation has no
/// equivalent, so this type exists only in SwiftUIWebWeb. The default is
/// ``sameOrigin``.
public enum WebCredentialsPolicy: String, Hashable, Sendable {
  /// Send no cookies or HTTP credentials (browser `credentials: "omit"`).
  case omit
  /// Send cookies and credentials only to the request's own origin. This is the browser default.
  case sameOrigin
  /// Send cookies and credentials to other origins too. The server must allow
  /// credentialed CORS (`Access-Control-Allow-Credentials: true` and a specific
  /// origin), and SameSite rules still apply.
  case include

  fileprivate var packagePolicy: URLSessionCredentialsPolicy {
    switch self {
    case .omit: return .omit
    case .sameOrigin: return .sameOrigin
    case .include: return .include
    }
  }

  fileprivate init(packagePolicy: URLSessionCredentialsPolicy) {
    switch packagePolicy {
    case .omit: self = .omit
    case .sameOrigin: self = .sameOrigin
    case .include: self = .include
    }
  }
}

extension URLSessionConfiguration {
  /// The credentials mode of every request made with this session. Setting
  /// `.include` lets cross-origin requests carry the browser's cookies, so use
  /// it only for an origin you control.
  public var webCredentialsPolicy: WebCredentialsPolicy {
    get { WebCredentialsPolicy(packagePolicy: credentialsPolicy) }
    set { credentialsPolicy = newValue.packagePolicy }
  }
}

extension URLRequest {
  /// The credentials mode for this request only. `nil` (the default) uses the
  /// session's ``URLSessionConfiguration/webCredentialsPolicy``.
  ///
  /// The cookie switches still apply: `httpShouldHandleCookies == false` sends
  /// the request with no credentials whatever this value is.
  public var webCredentialsPolicy: WebCredentialsPolicy? {
    get { credentialsPolicyOverride.map { WebCredentialsPolicy(packagePolicy: $0) } }
    set { credentialsPolicyOverride = newValue?.packagePolicy }
  }
}
