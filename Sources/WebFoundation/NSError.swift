// Foundation's `NSError` and the error pointer Objective-C style APIs fill in, on every host.
// The stored properties avoid `_domain`/`_code`: full Swift's `Error` has hidden requirements with those names.
//
// Embedded Swift has no `AutoreleasingUnsafeMutablePointer`, the pointer type Apple's `NSErrorPointer` names, so
// `NSErrorPointer` is a plain `UnsafeMutablePointer<NSError?>?`. `&error` converts to it exactly as it does on Apple.

public let NSCocoaErrorDomain: String = "NSCocoaErrorDomain"
public let NSPOSIXErrorDomain: String = "NSPOSIXErrorDomain"

/// Foundation's error class: a domain, a code and a user-info dictionary.
open class NSError: NSObject, Error, @unchecked Sendable {
  private let storedDomain: String
  private let storedCode: Int
  private let storedUserInfo: [String: Any]

  public init(domain: String, code: Int, userInfo dict: [String: Any]? = nil) {
    storedDomain = domain
    storedCode = code
    storedUserInfo = dict ?? .init()
  }

  open var domain: String { storedDomain }
  open var code: Int { storedCode }
  open var userInfo: [String: Any] { storedUserInfo }

  /// The `NSLocalizedDescription` entry when there is one, otherwise Foundation's sentence for the codes this
  /// runtime produces (a stream's POSIX errors, a failed file write, malformed JSON).
  open var localizedDescription: String {
    if let text = storedUserInfo["NSLocalizedDescription"] as? String { return text }
    if storedDomain == NSCocoaErrorDomain {
      switch storedCode {
      case 512: return "The file couldn’t be saved."
      case 3840: return "The data couldn’t be read because it isn’t in the correct format."
      default: break
      }
    }
    if storedDomain == NSPOSIXErrorDomain {
      switch storedCode {
      case 2: return "The operation couldn’t be completed. No such file or directory"
      case 12: return "The operation couldn’t be completed. Cannot allocate memory"
      default: break
      }
    }
    return "The operation couldn’t be completed. (\(storedDomain) error \(storedCode).)"
  }
}

/// What an Objective-C style method fills with the error it ran into.
public typealias NSErrorPointer = UnsafeMutablePointer<NSError?>?

