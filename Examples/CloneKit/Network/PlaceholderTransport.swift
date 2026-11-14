import SwiftUIWeb

/// The edge of the network: what the client sends and what comes back. The app uses `URLSessionTransport`; a test uses a double.
public protocol PlaceholderTransport: Sendable {
  /// Sends `method` to `path` (`/api/posts?_limit=10`) with an optional JSON body and returns the body of a 2xx answer.
  func send(_ method: String, _ path: String, body: Data?) async throws -> Data
}

public enum PlaceholderError: Error, CustomStringConvertible {
  case invalidPath(String)
  case status(Int)

  public var description: String {
    switch self {
    case .invalidPath(let path): return "The address \(path) is not valid."
    case .status(let code): return "The service answered \(code)."
    }
  }
}

/// `URLSession` in the browser: the request goes through `fetch`, to the page's own origin.
public struct URLSessionTransport: PlaceholderTransport {
  public init() {}

  public func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
    guard let url = URL(string: path) else { throw PlaceholderError.invalidPath(path) }
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status >= 200 && status < 300 else { throw PlaceholderError.status(status) }
    return data
  }
}
