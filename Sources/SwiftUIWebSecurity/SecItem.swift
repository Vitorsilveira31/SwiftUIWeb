// Security.framework's item functions with Apple's argument shapes: a dictionary, and an optional
// pointer that receives the result, so `SecItemCopyMatching(query as CFDictionary, &item)` and
// `SecItemAdd(attributes as CFDictionary, nil)` read the same. They answer synchronously from the
// store `WebSecurity.unlock()` decrypted; until it has, they return `errSecInteractionNotAllowed`.

public func SecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
  let (status, value) = WebSecurity.keychain.add(attributes)
  result?.pointee = value
  return status
}

public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
  let (status, value) = WebSecurity.keychain.copyMatching(query)
  result?.pointee = value
  return status
}

public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
  WebSecurity.keychain.update(query, attributesToUpdate)
}

public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
  WebSecurity.keychain.delete(query)
}
