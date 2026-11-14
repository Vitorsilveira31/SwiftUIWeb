// Foundation-shaped `URLError` for every error that the URLSession façade
// throws. Hosts still report failures with the package `NetworkError`
// vocabulary; `_urlError(_:failingURL:)` converts those values at the public
// boundary so application code sees the same typed error on every platform.
//
// Raw values are Foundation's `NSURLError*` constants, so an `NSURLError`
// produced by the native URLSession keeps its code when it is re-wrapped.

/// The error thrown by ``URLSession`` and ``URLSessionWebSocketTask`` when a
/// request fails, matching Foundation's `URLError`.
///
/// Foundation's `userInfo` dictionary is not provided: it is `[String: Any]`,
/// which Embedded Swift cannot represent. `failingURL` and `failureURLString`
/// carry the URL that the request used.
public struct URLError: Error, Hashable, Sendable {
  /// Foundation's `URLError.Code`, with Foundation's raw values.
  public struct Code: Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let unknown = Code(rawValue: -1)
    public static let cancelled = Code(rawValue: -999)
    public static let badURL = Code(rawValue: -1000)
    public static let timedOut = Code(rawValue: -1001)
    public static let unsupportedURL = Code(rawValue: -1002)
    public static let cannotFindHost = Code(rawValue: -1003)
    public static let cannotConnectToHost = Code(rawValue: -1004)
    public static let networkConnectionLost = Code(rawValue: -1005)
    public static let dnsLookupFailed = Code(rawValue: -1006)
    public static let httpTooManyRedirects = Code(rawValue: -1007)
    public static let resourceUnavailable = Code(rawValue: -1008)
    public static let notConnectedToInternet = Code(rawValue: -1009)
    public static let redirectToNonExistentLocation = Code(rawValue: -1010)
    public static let badServerResponse = Code(rawValue: -1011)
    public static let userCancelledAuthentication = Code(rawValue: -1012)
    public static let userAuthenticationRequired = Code(rawValue: -1013)
    public static let zeroByteResource = Code(rawValue: -1014)
    public static let cannotDecodeRawData = Code(rawValue: -1015)
    public static let cannotDecodeContentData = Code(rawValue: -1016)
    public static let cannotParseResponse = Code(rawValue: -1017)
    public static let internationalRoamingOff = Code(rawValue: -1018)
    public static let callIsActive = Code(rawValue: -1019)
    public static let dataNotAllowed = Code(rawValue: -1020)
    public static let requestBodyStreamExhausted = Code(rawValue: -1021)
    public static let appTransportSecurityRequiresSecureConnection = Code(rawValue: -1022)
    public static let fileDoesNotExist = Code(rawValue: -1100)
    public static let fileIsDirectory = Code(rawValue: -1101)
    public static let noPermissionsToReadFile = Code(rawValue: -1102)
    public static let dataLengthExceedsMaximum = Code(rawValue: -1103)
    public static let secureConnectionFailed = Code(rawValue: -1200)
    public static let serverCertificateHasBadDate = Code(rawValue: -1201)
    public static let serverCertificateUntrusted = Code(rawValue: -1202)
    public static let serverCertificateHasUnknownRoot = Code(rawValue: -1203)
    public static let serverCertificateNotYetValid = Code(rawValue: -1204)
    public static let clientCertificateRejected = Code(rawValue: -1205)
    public static let clientCertificateRequired = Code(rawValue: -1206)
    public static let cannotLoadFromNetwork = Code(rawValue: -2000)
    public static let cannotCreateFile = Code(rawValue: -3000)
    public static let cannotOpenFile = Code(rawValue: -3001)
    public static let cannotCloseFile = Code(rawValue: -3002)
    public static let cannotWriteToFile = Code(rawValue: -3003)
    public static let cannotRemoveFile = Code(rawValue: -3004)
    public static let cannotMoveFile = Code(rawValue: -3005)
    public static let downloadDecodingFailedMidStream = Code(rawValue: -3006)
    public static let downloadDecodingFailedToComplete = Code(rawValue: -3007)
    public static let backgroundSessionRequiresSharedContainer = Code(rawValue: -995)
    public static let backgroundSessionInUseByAnotherProcess = Code(rawValue: -996)
    public static let backgroundSessionWasDisconnected = Code(rawValue: -997)
  }

  /// The failure category. Compare with `URLError.Code` constants.
  public let code: Code
  /// The URL of the request that failed, when the failure is tied to one.
  public let failingURL: URL?
  /// The string form of ``failingURL``, when it is available.
  public let failureURLString: String?

  /// Foundation's `errorCode`: the raw value of ``code``.
  public var errorCode: Int { code.rawValue }

  public init(_ code: Code) {
    self.init(code, failingURL: nil, reason: nil)
  }

  /// Creates an error for a request that failed at `failingURL`.
  package init(_ code: Code, failingURL: URL?, reason: String? = nil) {
    self.code = code
    self.failingURL = failingURL
    failureURLString = failingURL?.absoluteString
    self.reason = reason
  }

  /// A diagnostic from the layer that failed. It is not part of Foundation's
  /// public surface and never includes credentials, cookies or request bodies.
  package let reason: String?
}

/// Converts a failure from the host or transport layer into the public
/// ``URLError`` that URLSession throws.
package func _urlError(_ error: any Error, failingURL: URL? = nil) -> URLError {
  if let urlError = error as? URLError {
    return urlError
  }
  if error is CancellationError {
    return URLError(.cancelled, failingURL: failingURL)
  }
  guard let networkError = error as? NetworkError else {
    return URLError(.unknown, failingURL: failingURL)
  }
  return URLError(
    _urlErrorCode(networkError),
    failingURL: failingURL,
    reason: networkError.description
  )
}

/// Runs a URLSession operation and rethrows its failure as a ``URLError``.
@inline(__always)
package func _urlOperation<T>(
  _ request: URLRequest?,
  _ operation: () async throws -> T
) async throws -> T {
  do {
    return try await operation()
  } catch {
    throw _urlError(error, failingURL: request?.url)
  }
}

/// The Foundation code for each host failure. Keep this total: a new
/// `NetworkError` case must choose its code here.
package func _urlErrorCode(_ error: NetworkError) -> URLError.Code {
  switch error {
  case .unavailable: return .resourceUnavailable
  case .invalidRequest: return .unknown
  case .badURL: return .badURL
  case .forbiddenHeader: return .unknown
  case .unsupported: return .unsupportedURL
  case .webSocketClosed: return .networkConnectionLost
  case .transport: return .unknown
  case .cancelled: return .cancelled
  case .timedOut: return .timedOut
  case .connectionFailed: return .cannotConnectToHost
  case .offline: return .notConnectedToInternet
  case .connectionLost: return .networkConnectionLost
  case .responseTooLarge: return .dataLengthExceedsMaximum
  case .insecureRequest: return .appTransportSecurityRequiresSecureConnection
  }
}
