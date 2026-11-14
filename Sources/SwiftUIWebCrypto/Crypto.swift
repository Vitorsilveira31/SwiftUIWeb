/// CryptoKit-compatible cryptographic primitives for SwiftUIWeb applications.
///
/// This module is deliberately optional and is not imported by
/// `SwiftUIWebCore` or the `SwiftUIWeb` façade. Its types are Swift Crypto's on
/// every host (the open-source CryptoKit API, backed by BoringSSL; on Apple
/// platforms Swift Crypto forwards to CryptoKit itself). Swift Crypto's API takes
/// the toolchain's Foundation `Data` and `DataProtocol`; byte arrays work on
/// every host. No browser or JavaScript type crosses this boundary.

import Crypto

private enum _SwiftUIWebCryptoBackend {
  static let identifier = "Swift Crypto"
}

public typealias HashFunction = Crypto.HashFunction
public typealias SHA256 = Crypto.SHA256
public typealias SHA384 = Crypto.SHA384
public typealias SHA512 = Crypto.SHA512
public typealias HMAC<Hash: HashFunction> = Crypto.HMAC<Hash>
public typealias SymmetricKey = Crypto.SymmetricKey
public typealias SymmetricKeySize = Crypto.SymmetricKeySize
public typealias AES = Crypto.AES
public typealias P256 = Crypto.P256
public typealias Curve25519 = Crypto.Curve25519


/// The selected implementation backend.
///
/// This is useful for diagnostics and support reports; callers should not
/// branch security behavior on this value. Swift Crypto exposes the
/// CryptoKit-compatible API and uses secure platform randomness.
public enum CryptoBackend {
  /// The backend name: `Swift Crypto`.
  public static var identifier: String { _SwiftUIWebCryptoBackend.identifier }

  /// SwiftUIWeb does not currently route operations through WebCrypto.
  /// Swift Crypto's WASI implementation provides the required primitives
  /// without introducing asynchronous JavaScript handles or browser-only key
  /// material. This remains explicit so a future browser provider can be
  /// added behind this module without changing application code.
  public static let usesWebCrypto = false
}

/// Secure random byte and key generation helpers.
///
/// `SystemRandomNumberGenerator` is the standard library's cryptographically
/// secure generator. It uses the platform's secure entropy source (including
/// WASI `random_get`); this module never falls back to timestamps, counters,
/// or pseudo-random generators. `SymmetricKey(size:)` and `AES.GCM.Nonce()`
/// likewise use the selected CryptoKit-compatible backend's secure RNG.
public enum SecureRandom {
  /// Returns `count` cryptographically secure random bytes.
  ///
  /// - Precondition: `count` is non-negative.
  public static func bytes(count: Int) -> [UInt8] {
    precondition(count >= 0, "Random byte count cannot be negative")

    var generator = SystemRandomNumberGenerator()
    var output = [UInt8]()
    output.reserveCapacity(count)
    for _ in 0..<count {
      output.append(UInt8.random(in: UInt8.min...UInt8.max, using: &generator))
    }
    return output
  }

  /// Generates a cryptographically secure symmetric key.
  public static func symmetricKey(size: SymmetricKeySize = .bits256) -> SymmetricKey {
    SymmetricKey(size: size)
  }

  /// Generates a fresh 96-bit AES-GCM nonce using the backend's secure RNG.
  ///
  /// Never reuse the returned nonce with the same key.
  public static func aesGCMNonce() -> AES.GCM.Nonce {
    AES.GCM.Nonce()
  }
}
