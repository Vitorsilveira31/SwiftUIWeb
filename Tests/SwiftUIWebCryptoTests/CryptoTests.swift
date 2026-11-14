import Testing
import Foundation
import SwiftUIWebCrypto


@Suite
@MainActor
final class CryptoTests {
  @Test
  func testSHA2KnownAnswers() {
    let input = Array("abc".utf8)

    _expectEqual(hex(SHA256.hash(data: input)),
                   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    _expectEqual(hex(SHA384.hash(data: input)),
                   "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a"
                   + "43ff5bed8086072ba1e7cc2358baeca134c825a7")
    _expectEqual(hex(SHA512.hash(data: input)),
                   "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                   + "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
  }

  @Test
  func testHMACSHA2KnownAnswers() {
    let key = Array(repeating: UInt8(0x0b), count: 20)
    let message = Array("Hi There".utf8)
    let symmetricKey = SymmetricKey(data: key)

    _expectEqual(hex(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey)),
                   "b0344c61d8db38535ca8afceaf0bf12b"
                   + "881dc200c9833da726e9376c2e32cff7")
    _expectEqual(hex(HMAC<SHA384>.authenticationCode(for: message, using: symmetricKey)),
                   "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59c"
                   + "faea9ea9076ede7f4af152e8b2fa9cb6")
    _expectEqual(hex(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey)),
                   "87aa7cdea5ef619d4ff0b4241a1d6cb0"
                   + "2379f4e2ce4ec2787ad0b30545e17cde"
                   + "daa833b7d6b8a702038b274eaea3f4e4"
                   + "be9d914eeb61f1702e696c203a126854")
  }

  @Test
  func testAESGCMKnownAnswerAndTamperDetection() throws {
    let key = SymmetricKey(data: Array(repeating: UInt8(0), count: 16))
    let nonce = try AES.GCM.Nonce(data: Array(repeating: UInt8(0), count: 12))
    let plaintext = Array(repeating: UInt8(0), count: 16)

    let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
    _expectEqual(hex(sealed.ciphertext), "0388dace60b6a392f328c2b971b2fe78")
    _expectEqual(hex(sealed.tag), "ab6e47d42cec13bdf53a67b21257bddf")
    _expectEqual(Array(try AES.GCM.open(sealed, using: key)), plaintext)

    var tampered = Array(sealed.tag)
    tampered[0] ^= 1
    let invalid = try AES.GCM.SealedBox(nonce: nonce, ciphertext: sealed.ciphertext, tag: tampered)
    _expectThrows(try AES.GCM.open(invalid, using: key))
  }

  @Test
  func testP256KnownGeneratorAndSignatureRoundTrip() throws {
    let scalar = [UInt8](repeating: 0, count: 31) + [1]
    let privateKey = try P256.Signing.PrivateKey(rawRepresentation: scalar)
    _expectEqual(
      hex(privateKey.publicKey.rawRepresentation),
      "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
        + "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"
    )

    let message = Array("SwiftUIWeb".utf8)
    let signature = try privateKey.signature(for: message)
    _expectTrue(privateKey.publicKey.isValidSignature(signature, for: message))
    _expectFalse(privateKey.publicKey.isValidSignature(signature, for: message + [0]))
  }

  @Test
  func testCurve25519KeyAgreementRoundTrip() throws {
    let alice = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Array(repeating: 1, count: 32))
    let bob = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Array(repeating: 2, count: 32))

    let aliceSecret = try alice.sharedSecretFromKeyAgreement(with: bob.publicKey)
    let bobSecret = try bob.sharedSecretFromKeyAgreement(with: alice.publicKey)
    _expectEqual(
      Array(aliceSecret.withUnsafeBytes { Array($0) }),
      Array(bobSecret.withUnsafeBytes { Array($0) })
    )
  }

  @Test
  func testSecureRandomHelpersProduceSizedValues() {
    _expectFalse(CryptoBackend.identifier.isEmpty)
    _expectFalse(CryptoBackend.usesWebCrypto)
    _expectEqual(SecureRandom.bytes(count: 0).count, 0)
    _expectEqual(SecureRandom.bytes(count: 32).count, 32)
    _expectEqual(SecureRandom.symmetricKey().bitCount, 256)

    let first = SecureRandom.bytes(count: 32)
    let second = SecureRandom.bytes(count: 32)
    _expectNotEqual(first, second)
    _ = SecureRandom.aesGCMNonce()
  }

  private func hex<C: ContiguousBytes>(_ bytes: C) -> String {
    bytes.withUnsafeBytes { rawBuffer in
      rawBuffer.map { String(format: "%02x", $0) }.joined()
    }
  }
}
