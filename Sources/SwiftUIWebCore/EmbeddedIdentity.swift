@_spi(Renderer) import SwiftUIWebTransferable
#if hasFeature(Embedded)
/// Canonical identity for non-scalar Hashable values (enum routes, struct IDs).
/// The renderer is single-threaded. The registry contains NON-owning references;
/// entries remove themselves in deinit, so a removed route does not leak forever.
/// Exact type + equality decide identity. Hash collisions never alias values.
final class _EmbeddedOpaqueIdentity {
  let serial: UInt64
  let fingerprint: Int
  let typeID: ObjectIdentifier
  let payload: _RuntimeValue
  let equals: (_RuntimeValue) -> Bool

  init(payload: _RuntimeValue, serial: UInt64, fingerprint: Int, equals: @escaping (_RuntimeValue) -> Bool) {
    self.serial = serial
    self.fingerprint = fingerprint
    self.typeID = payload.typeID
    self.payload = payload
    self.equals = equals
  }

  deinit { _EmbeddedIdentityRegistry.remove(serial: serial, fingerprint: fingerprint) }
}

private enum _EmbeddedIdentityRegistry {
  private struct Entry { let serial: UInt64; let reference: Unmanaged<_EmbeddedOpaqueIdentity> }
  private struct State {
    /// By the fingerprint's bits: a `UInt64`-keyed table of arrays shares its code with the renderer's (Embedded Swift
    /// emits the hashed-collection code once per key type and value layout).
    var entries: [UInt64: [Entry]] = .init()
    var next: UInt64 = 1
  }
  private static let state = _Locked(State())

  static func intern<Value: Hashable>(_ value: Value) -> _EmbeddedOpaqueIdentity {
    var hasher = Hasher()
    hasher.combine(_storedTypeID(Value.self))
    hasher.combine(value)
    let fingerprint = hasher.finalize()
    let payload = _RuntimeValue(value)
    return state.withLock { state in
      for entry in state.entries[UInt64(UInt(bitPattern: fingerprint))] ?? [] {
        // All access is serialized by the same UI runtime. An entry exists only
        // while at least one _FiberKey owns its payload; deinit removes it before
        // its storage is reclaimed. No raw reference is returned to a caller.
        let candidate = entry.reference.takeUnretainedValue()
        if candidate.typeID == payload.typeID && candidate.equals(payload) { return candidate }
      }
      precondition(state.next < UInt64.max, "Embedded identity space exhausted")
      let result = _EmbeddedOpaqueIdentity(payload: payload, serial: state.next, fingerprint: fingerprint) { other in
        guard let candidate: Value = other.read() else { return false }
        return value == candidate
      }
      state.next += 1
      state.entries[UInt64(UInt(bitPattern: fingerprint)), default: []].append(Entry(serial: result.serial, reference: .passUnretained(result)))
      return result
    }
  }

  static func remove(serial: UInt64, fingerprint: Int) {
    state.withLock { state in
      let slot = UInt64(UInt(bitPattern: fingerprint))
      state.entries[slot]?.removeAll { $0.serial == serial }
      if state.entries[slot]?.isEmpty == true { state.entries.removeValue(forKey: slot) }
    }
  }
}

extension _EmbeddedOpaqueIdentity {
  static func intern<Value: Hashable>(_ value: Value) -> _EmbeddedOpaqueIdentity {
    _EmbeddedIdentityRegistry.intern(value)
  }
}
#endif
