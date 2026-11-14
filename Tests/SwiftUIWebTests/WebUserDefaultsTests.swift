import Testing
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures

/// `UserDefaults` in the browser is the app scope of `StorageRuntime` (`localStorage`): typed values
/// round-trip as the same strings `@AppStorage` writes, suites keep their keys apart, and `nil`
/// removes a key.
@Suite(.serialized, .processGlobalState)
@MainActor
final class WebUserDefaultsTests {
  private var values: [String: String] = [:]

  deinit { StorageRuntime.install(nil) }

  private func install() {
    StorageRuntime.install(StorageAdapter(
      read: { [unowned self] in values[$0] },
      write: { [unowned self] in values[$0] = $1 },
      remove: { [unowned self] in values[$0] = nil }
    ))
  }

  @Test func typedValuesRoundTripThroughTheAppScope() {
    install()
    let defaults = _WebUserDefaults.standard
    defaults.set("pt-BR", forKey: "language")
    defaults.set(true, forKey: "onboarded")
    defaults.set(42, forKey: "count")
    defaults.set(1.5, forKey: "ratio")

    #expect(defaults.string(forKey: "language") == "pt-BR")
    #expect(defaults.bool(forKey: "onboarded"))
    #expect(defaults.integer(forKey: "count") == 42)
    #expect(defaults.double(forKey: "ratio") == 1.5)
    #expect(values["onboarded"] == "true", "the same encoding AppStorage uses")
    #expect(!defaults.bool(forKey: "missing") && defaults.integer(forKey: "missing") == 0)
  }

  @Test func appStorageSeesWhatUserDefaultsWrote() {
    install()
    _WebUserDefaults.standard.set("dark", forKey: "theme")
    let theme = AppStorage(wrappedValue: "light", "theme")
    #expect(theme.wrappedValue == "dark")
    theme.wrappedValue = "light"
    #expect(_WebUserDefaults.standard.string(forKey: "theme") == "light")
  }

  @Test func suitesKeepTheirKeysApartAndNilRemoves() {
    install()
    let suite = _WebUserDefaults(suiteName: "studio")
    suite?.set("a", forKey: "key")
    _WebUserDefaults.standard.set("b", forKey: "key")
    #expect(suite?.string(forKey: "key") == "a")
    #expect(_WebUserDefaults.standard.string(forKey: "key") == "b")

    _WebUserDefaults.standard.set(nil as String?, forKey: "key")
    #expect(_WebUserDefaults.standard.string(forKey: "key") == nil)
    #expect(values["key"] == nil)
  }
}
