/// Security.framework's result codes, with the values Apple uses, so code that compares a status
/// against `errSecItemNotFound` behaves the same in the browser.
public typealias OSStatus = Int32

public let errSecSuccess: OSStatus = 0
/// The operation does not exist in the browser. Returned for session credentials
/// (`kSecClassInternetPassword`), which belong in the server's `HttpOnly` cookie, and for iCloud
/// synchronization.
public let errSecUnimplemented: OSStatus = -4
public let errSecParam: OSStatus = -50
public let errSecAllocate: OSStatus = -108
public let errSecNotAvailable: OSStatus = -25291
public let errSecDuplicateItem: OSStatus = -25299
public let errSecItemNotFound: OSStatus = -25300
/// The item store is still locked: `WebSecurity.unlock()` has not finished decrypting it. The
/// same status the Keychain returns while the device is locked.
public let errSecInteractionNotAllowed: OSStatus = -25308
public let errSecDecode: OSStatus = -26275

/// A readable explanation of `status`, as `SecCopyErrorMessageString` gives one. `reserved` is
/// accepted for source compatibility and must be `nil`.
public func SecCopyErrorMessageString(_ status: OSStatus, _ reserved: UnsafeMutableRawPointer?) -> String? {
  switch status {
  case errSecSuccess: return "No error."
  case errSecUnimplemented:
    return "Not available in the browser. Sign-in sessions belong in an HttpOnly cookie the server sets."
  case errSecParam: return "One or more parameters passed to a function were not valid."
  case errSecAllocate: return "Failed to allocate memory."
  case errSecNotAvailable: return "No keychain is available: this browser offers no Web Crypto (HTTPS is required)."
  case errSecDuplicateItem: return "The specified item already exists in the keychain."
  case errSecItemNotFound: return "The specified item could not be found in the keychain."
  case errSecInteractionNotAllowed: return "The keychain is locked until WebSecurity.unlock() finishes."
  case errSecDecode: return "Unable to decode the provided data."
  default: return nil
  }
}
