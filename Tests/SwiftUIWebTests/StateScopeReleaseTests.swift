import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@testable @_spi(Renderer) import SwiftUIWebFeatures

/// A Fiber subtree that leaves the tree releases the state of all its scopes in one pass over the store
/// (`StateStore._releaseStateScopes`). A key belongs to scope `P` exactly when it starts with `P#`, as it did when each
/// scope was released on its own.
@Suite(.serialized)
@MainActor
struct StateScopeReleaseTests {
  private func survivors(after release: (StateStore) -> Void) -> [String] {
    let store = StateStore()
    let keys = ["root/a#count", "root/a#geometry-change.1", "root/a/b#count", "root/ab#count", "root/c#x#y", "p#q/r#s", "root/d#count"]
    for key in keys { store.box(key, default: 1).value = 2 }
    release(store)
    // A released key comes back as a fresh box holding the default.
    return keys.filter { store.box($0, default: 1).value == 2 }
  }

  @Test
  func oneScopeReleasesOnlyKeysThatStartWithItsPathAndAHash() {
    #expect(survivors { $0._releaseStateScope(atPathPrefix: "root/a") } == ["root/a/b#count", "root/ab#count", "root/c#x#y", "p#q/r#s", "root/d#count"])
  }

  @Test
  func motionCachesLeaveWithTheScopeTheyDescribe() {
    let store = StateStore()
    let layout = _MeasuredTextLayout(decoding: "0,0,10,10")!
    for key in ["abc#animation-value", "abc#text-layout", "abc#text-layout#origin", "abd#animation-value", "ab#anchor"] {
      store._animatorValues.set(1, for: key)
      store._windowFrames[key] = CGRect(x: 1, y: 2, width: 3, height: 4)
    }
    store._textLayouts["abc#text-layout"] = layout
    store._textLayouts["abd#text-layout"] = layout
    store._releaseStateScopes(atPathPrefixes: ["abc"])
    #expect(store._animatorValues.keys.sorted() == ["ab#anchor", "abd#animation-value"])
    #expect(store._windowFrames.keys.sorted() == ["ab#anchor", "abd#animation-value"])
    #expect(store._textLayouts.keys.sorted() == ["abd#text-layout"])
  }

  @Test
  func severalScopesReleaseInOnePassWhatEachWouldRelease() {
    let together = survivors { $0._releaseStateScopes(atPathPrefixes: ["root/a", "root/c", "p#q/r"]) }
    let oneByOne = survivors { store in for scope in ["root/a", "root/c", "p#q/r"] { store._releaseStateScope(atPathPrefix: scope) } }
    #expect(together == ["root/a/b#count", "root/ab#count", "root/d#count"])
    #expect(together == oneByOne)
    #expect(survivors { $0._releaseStateScopes(atPathPrefixes: []) }.count == 7)
  }
}
