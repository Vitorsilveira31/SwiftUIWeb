// Keys and values of keychain dictionaries, spelled as in Security.framework. The raw strings are
// Apple's, so a query reads the same in either place.

public let kSecClass: CFString = "class"
public let kSecClassGenericPassword: SecValue = "genp"
/// Server credentials. In the browser a sign-in session lives in an `HttpOnly`, `Secure`,
/// `SameSite` cookie the server sets and the browser sends; no script, and so no Swift code in the
/// WASM, can read it. Every keychain operation on this class returns `errSecUnimplemented`; use
/// `WebSecurity.Session` to learn whether the session is active.
public let kSecClassInternetPassword: SecValue = "inet"

public let kSecAttrAccount: CFString = "acct"
public let kSecAttrService: CFString = "svce"
public let kSecAttrLabel: CFString = "labl"
public let kSecAttrDescription: CFString = "desc"
public let kSecAttrComment: CFString = "icmt"
public let kSecAttrGeneric: CFString = "gena"
public let kSecAttrServer: CFString = "srvr"
/// Accepted and stored. The browser has one protection level: items are readable while the page
/// runs, after `WebSecurity.unlock()`.
public let kSecAttrAccessible: CFString = "pdmn"
public let kSecAttrAccessibleWhenUnlocked: SecValue = "ak"
public let kSecAttrAccessibleAfterFirstUnlock: SecValue = "ck"
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly: SecValue = "aku"
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: SecValue = "cku"
public let kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: SecValue = "akpu"
/// Items never leave the browser profile; asking for synchronization returns `errSecUnimplemented`.
public let kSecAttrSynchronizable: CFString = "sync"
/// Accepted for source compatibility and ignored.
public let kSecUseDataProtectionKeychain: CFString = "nleg"

public let kSecValueData: CFString = "v_Data"
public let kSecReturnData: CFString = "r_Data"
public let kSecReturnAttributes: CFString = "r_Attributes"
public let kSecMatchLimit: CFString = "m_Limit"
public let kSecMatchLimitOne: SecValue = "m_LimitOne"
public let kSecMatchLimitAll: SecValue = "m_LimitAll"

/// Optional, as CoreFoundation's are, so `kSecReturnData as String: kCFBooleanTrue!` compiles.
public let kCFBooleanTrue: SecValue? = .bool(true)
public let kCFBooleanFalse: SecValue? = .bool(false)

/// The attributes an item keeps; anything else in an add or update is rejected with `errSecParam`.
let _secStoredAttributes: Set<String> = [
  kSecClass, kSecAttrAccount, kSecAttrService, kSecAttrLabel, kSecAttrDescription, kSecAttrComment,
  kSecAttrGeneric, kSecAttrServer, kSecAttrAccessible, kSecAttrSynchronizable,
]
/// Keys that shape a query or a result rather than describe an item.
let _secQueryControls: Set<String> = [
  kSecReturnData, kSecReturnAttributes, kSecMatchLimit, kSecUseDataProtectionKeychain,
]
