import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures


/// Browser implementation of SwiftUIWeb's neutral history boundary.
///
/// The adapter records the typed `NavigationPath` alongside each URL so
/// browser back/forward can restore the same SwiftUI navigation state. URL
/// and JavaScript details remain entirely inside this module.
@MainActor public final class BrowserHistoryAdapter: @MainActor _TabHistoryAdapter {
  /// BrowserSession installs this host callback so a browser-originated
  /// back/forward event commits the updated NavigationPath through Fiber.
  /// NavigationPath itself remains the single logical source of truth.
  public var onPopstate: (() -> Void)?
  private var knownPaths: [String: NavigationPath] = ["/": NavigationPath()]
  /// The path represented by the current browser history entry.  Navigation
  /// mutations call `update` before `apply`, so keep this separately from the
  /// pending snapshot to calculate how many history entries a pop-to-root
  /// operation must traverse.
  private var currentPath = NavigationPath()
  private var pendingPath: NavigationPath?
  private var observer: ((NavigationPath) -> Void)?
  private var tabObservers: [String: (String) -> Void] = [:]
  private var tabTags: [String: String] = [:]
  private var tabDefaults: [String: String] = [:]
  /// The tab each namespace shows, as its history URL names it (namespace token to tag token): the last one Swift
  /// pushed or a location applied. The page reports the location after every tab URL Swift pushed.
  private var shownTabs: [String: String] = [:]
  private var pendingURLTab: (namespace: String, tag: String)?


  #if hasFeature(Embedded)
  private let embeddedID: UInt32
  private var entries: [String: NavigationPath] = [:]
  private static var adapters: [UInt32: BrowserHistoryAdapter] = [:]
  private static var nextAdapter: UInt32 = 0
  private static var sequence: UInt32 = 0
  /// Operations queued for the host, in order. Mutations made during one
  /// action are coalesced before the host sees them (see `coalesceUndrained`).
  private static var operations: [HistoryOperationRecord] = []
  /// Highest sequence already handed to the host; only later operations may merge.
  private static var drainedThrough: UInt32 = 0
  /// The operations the last publication carried. Once the host has acknowledged them they stay on the root: the host
  /// skips sequences it applied, and a publication that only dropped the attribute cost a whole commit (on a large app's
  /// navigation, the publication that answered the GeometryReaders differed from the page in nothing else).
  private static var lastPublished: String?
  private var embeddedParentID: UInt32?
  #endif

  public init() {
    #if hasFeature(Embedded)
    Self.nextAdapter += 1
    embeddedID = Self.nextAdapter
    entries["\(embeddedID):root"] = NavigationPath()
    Self.adapters[embeddedID] = self
    #endif
  }

  private var scopes: [String: BrowserHistoryAdapter] = [:]
  package func _scope(_ identity: String) -> NavigationHistoryAdapter {
    #if hasFeature(Embedded)
    if let adapter = scopes[identity] { return adapter }
    let adapter = BrowserHistoryAdapter()
    // Embedded Swift does not support weak references. Keep the parent link as
    // a scalar adapter ID instead of capturing `self` in a closure. This also
    // avoids a parent -> child -> closure -> parent retain cycle.
    adapter.embeddedParentID = embeddedID
    scopes[identity] = adapter
    return adapter
    #else
    return self
    #endif
  }

  public func update(_ navigationPath: NavigationPath) {
    let snapshot = navigationPath._historySnapshot()
    knownPaths[path(for: snapshot)] = snapshot
    pendingPath = snapshot
  }

  public func path(for navigationPath: NavigationPath) -> String {
    if let tab = _tabHistoryComponents(navigationPath) {
      return "/?tab-selection=\(tab.namespace)%3A\(tab.tag)"
    }
    let raw = navigationPath._historyPathDescription()
    guard raw != "/" else { return "/" }
    return "/" + raw.split(separator: "/").map { Self.escapePathSegment(String($0)) }.joined(separator: "/")
  }

  public func observe(_ callback: @escaping (NavigationPath) -> Void) {
    observer = callback
  }

  @_spi(Renderer) public func _updateTab(namespace: String, tag: String) {
    let token = _tabHistoryNamespaceToken(namespace)
    let tagToken = _tabHistoryNamespaceToken("\(namespace)|\(tag)")
    tabTags["\(token)|\(tagToken)"] = tag
    shownTabs[token] = tagToken
    var path = NavigationPath()
    path.append("__tab:\(token)")
    path.append(tagToken)
    update(path)
    apply(.push(path: self.path(for: path)))
  }

  @_spi(Renderer) public func _observeTab(namespace: String, callback: @escaping (String) -> Void) {
    let token = _tabHistoryNamespaceToken(namespace)
    tabObservers[token] = callback
    if let pending = pendingURLTab, pending.namespace == token {
      pendingURLTab = nil
      // Deliver the pending tab only when it is one of the registered tabs.
      if let tag = tabTags["\(pending.namespace)|\(pending.tag)"] { callback(tag) }
    }
  }

  @_spi(Renderer) public func _setTabDefault(namespace: String, tag: String) {
    tabDefaults[_tabHistoryNamespaceToken(namespace)] = tag
  }

  /// Records that a history URL names `tagToken` for `namespaceToken` and returns whether that is not the tab already
  /// shown there, so the selection (and a render) is owed.
  @_spi(Renderer) public func _locationShowsTab(namespaceToken: String, tagToken: String) -> Bool {
    guard shownTabs[namespaceToken] != tagToken else { return false }
    shownTabs[namespaceToken] = tagToken
    return true
  }

  package func apply(_ operation: NavigationHistoryOperation) {
    #if hasFeature(Embedded)
    // The browser host applies this neutral operation through History API.
    // Keep the typed snapshot in the adapter so popstate can restore the
    // NavigationPath without asking the application to know about JavaScript.
    Self.sequence += 1
    let sequence = Self.sequence
    let key = "\(embeddedID):\(sequence)"
    let operationName: String
    let logicalPath: String
    switch operation {
    case .push(let path):
      operationName = "push"
      logicalPath = path
    case .replace(let path):
      operationName = "replace"
      logicalPath = path
    case .back(let path):
      operationName = "back"
      logicalPath = path
    }

    let oldDepth = currentPath.count
    let snapshot = pendingPath ?? knownPaths[logicalPath] ?? currentPath
    entries[key] = snapshot._historySnapshot()
    currentPath = snapshot
    pendingPath = nil
    Self.operations.append(HistoryOperationRecord(
      sequence: sequence, adapter: embeddedID, key: key, kind: operationName,
      path: logicalPath, depth: snapshot.count, oldDepth: oldDepth))
    #else
    _ = operation
    #endif
  }

  private static func escapePathSegment(_ value: String) -> String {
    var output = ""
    for byte in value.utf8 {
      let allowed = (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) ||
        (byte >= 97 && byte <= 122) || byte == 45 || byte == 46 || byte == 95 || byte == 126
      if allowed { output.append(Character(UnicodeScalar(byte))) }
      else {
        let hex = String(byte, radix: 16, uppercase: true)
        output += "%" + (byte < 16 ? "0" : "") + hex
      }
    }
    return output
  }

  #if hasFeature(Embedded)
  /// A queued history operation, serialized for the browser host on demand.
  private struct HistoryOperationRecord {
    let sequence: UInt32
    let adapter: UInt32
    let key: String
    var kind: String
    let path: String
    let depth: Int
    var oldDepth: Int

    var json: String {
      "{\"sequence\":\(sequence),\"adapter\":\(adapter),\"key\":\(BrowserHistoryAdapter.quote(key)),\"rootKey\":\(BrowserHistoryAdapter.quote("\(adapter):root")),\"kind\":\(BrowserHistoryAdapter.quote(kind)),\"path\":\(BrowserHistoryAdapter.quote(path)),\"depth\":\(depth),\"oldDepth\":\(oldDepth)}"
    }
  }

  nonisolated private static func quote(_ text: String) -> String {
    var result = "\""
    // Scalars, not Characters: "\r\n" is one Character, and each control scalar in it must be escaped.
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      default:
        if scalar.value < 0x20 || scalar.value == 0x7F {
          let hex = String(scalar.value, radix: 16)
          result += "\\u00" + (scalar.value < 16 ? "0" : "") + hex
        } else {
          result.unicodeScalars.append(scalar)
        }
      }
    }
    return result + "\""
  }
  static func embeddedOperations() -> String? {
    coalesceUndrained()
    guard let last = operations.last else { return lastPublished }
    drainedThrough = last.sequence
    let published = "[" + operations.map { $0.json }.joined(separator: ",") + "]"
    lastPublished = published
    return published
  }
  static func embeddedAcknowledge(_ sequence: UInt32) { operations.removeAll { $0.sequence <= sequence } }

  /// One SwiftUI action can mutate a NavigationPath several times (for example
  /// `removeLast()` followed by `append(_:)`). SwiftUI shows that as one
  /// navigation change, so the operations that have not reached the host yet
  /// collapse into a single operation measured from the depth before the first
  /// one: push when the stack grew, back when it shrank, replace when the depth
  /// is unchanged. The merged operation keeps the last sequence and key so the
  /// host's sequence bookkeeping and popstate restoration stay valid.
  private static func coalesceUndrained() {
    var index = 0
    while index < operations.count {
      guard operations[index].sequence > drainedThrough else { index += 1; continue }
      var end = index + 1
      while end < operations.count, operations[end].adapter == operations[index].adapter,
            operations[end].sequence > drainedThrough {
        end += 1
      }
      if end - index > 1 {
        var merged = operations[end - 1]
        let start = operations[index].oldDepth
        merged.oldDepth = start
        if merged.depth > start { merged.kind = "push" }
        else if merged.depth < start { merged.kind = "back" }
        else { merged.kind = "replace" }
        operations.replaceSubrange(index..<end, with: [merged])
      }
      index += 1
    }
  }
  static func embeddedReset() {
    adapters.removeAll(keepingCapacity: false)
    operations.removeAll(keepingCapacity: false)
    drainedThrough = 0
    lastPublished = nil
    nextAdapter = 0
    sequence = 0
  }
  /// Applies the tab selection the page's location names. Returns whether it selected another tab: the page reports the
  /// location after each tab URL Swift pushed, which names the tab Swift already shows.
  @discardableResult static func embeddedLocation(_ rawURL: String) -> Bool {
    guard let queryStart = rawURL.firstIndex(of: "?") else { return false }
    let query = rawURL[rawURL.index(after: queryStart)...].split(separator: "#", maxSplits: 1).first ?? ""
    guard let item = query.split(separator: "&").first(where: { $0.hasPrefix("tab-selection=") }) else { return false }
    let value = decodeTabValue(String(item.dropFirst("tab-selection=".count)))
    let pieces = value.split(separator: ":", maxSplits: 1).map(String.init)
    guard pieces.count == 2 else { return false }
    if let adapter = adapters.values.first(where: { $0.tabObservers[pieces[0]] != nil }) {
      // Only a tag one of the tabs registered is selected; an unknown raw tag from the URL is ignored.
      guard let tag = adapter.tabTags["\(pieces[0])|\(pieces[1])"] else { return false }
      guard adapter._locationShowsTab(namespaceToken: pieces[0], tagToken: pieces[1]) else { return false }
      adapter.tabObservers[pieces[0]]?(tag)
      return true
    } else if let adapter = adapters.values.first {
      adapter.pendingURLTab = (pieces[0], pieces[1])
      return true
    }
    return false
  }

  private static func decodeTabValue(_ value: String) -> String {
    // Tab paths are emitted by `path(for:)` above and only need the encoded
    // colon decoded here. Keep this parser Foundation-free for Embedded Swift.
    var output = ""
    var index = value.startIndex
    while index < value.endIndex {
      let character = value[index]
      if character == "%" {
        let next = value.index(after: index)
        if next < value.endIndex {
          let after = value.index(after: next)
          if after < value.endIndex {
            let pair = String(value[next..<after])
            if pair == "3A" || pair == "3a" { output.append(":"); index = after; continue }
          }
        }
      }
      output.append(character)
      index = value.index(after: index)
    }
    return output
  }
  static func embeddedRestore(_ key: String) {
    guard let id = UInt32(key.split(separator: ":").first ?? ""), let adapter = adapters[id], let path = adapter.entries[key] else { return }
    adapter.currentPath = path; adapter.pendingPath = nil
    if let components = _tabHistoryComponents(path) {
      let tag = adapter.tabTags["\(components.namespace)|\(components.tag)"] ?? components.tag
      adapter.shownTabs[components.namespace] = components.tag
      adapter.tabObservers[components.namespace]?(tag)
    } else {
      // The root history entry has no tab component. Restore each tab view's
      // declared default so Back from a tab URL returns to the same landing
      // screen as a fresh native SwiftUI scene.
      adapter.shownTabs.removeAll()
      for (namespace, callback) in adapter.tabObservers {
        if let tag = adapter.tabDefaults[namespace] { callback(tag) }
      }
      adapter.observer?(path)
    }
    adapter.notifyEmbeddedPopstate()
  }

  private func notifyEmbeddedPopstate() {
    onPopstate?()
    if let parentID = embeddedParentID, let parent = Self.adapters[parentID] {
      parent.notifyEmbeddedPopstate()
    }
  }
  #endif

  /// `history.pushState` accepts the logical path emitted by SwiftUIWeb, but
  /// the browser serializes reserved characters (for example quotes in a
  /// typed route) in `location.pathname`. Keep that canonical browser form
  /// alongside the logical key so a later back/forward traversal can resolve
  /// the same typed path instead of silently leaving the previous Fiber view
  /// on screen.

}
