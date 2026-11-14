// A browser stand-in for the part of AuthenticationServices Apple's Food Truck account screens read: the
// `authorizationController` environment value they hand to the account store. Passkeys against the sample's
// example.com relying party cannot run in a browser; the web account adapter signs in locally instead.
import SwiftUIWeb

public struct AuthorizationController: Sendable {
  public init() {}
}

private enum AuthorizationControllerKey: EnvironmentKey {
  static let defaultValue = AuthorizationController()
}

public extension EnvironmentValues {
  var authorizationController: AuthorizationController {
    get { self[AuthorizationControllerKey.self] }
    set { self[AuthorizationControllerKey.self] = newValue }
  }
}

public enum ASAuthorizationController {
  public struct RequestOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let preferImmediatelyAvailableCredentials = RequestOptions(rawValue: 1)
  }
}
