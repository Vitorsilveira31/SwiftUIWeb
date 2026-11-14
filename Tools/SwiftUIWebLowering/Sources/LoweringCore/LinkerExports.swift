import Foundation
import SwiftParser
import SwiftSyntax

/// The browser host calls the application's `@_cdecl` entry points through the WebAssembly module's exports, which the
/// linker keeps only when it is told to. The product's `.executableTarget` in `Package.swift` gets
/// `linkerSettings: [.unsafeFlags(["-Xlinker", "--export=…", …])]` for every entry point of `BrowserExportsTemplate`; a
/// target that has linker settings is completed with the exports it lacks, each added after
/// `--export=embedded_browser_html_length`; a target that has them all is left as it is. A manifest that has no such
/// target, or whose target the completion cannot read, is left as it is.
///
/// Origin (the previous, text-based lowerer): `patch_product_linker_exports`, `browser_linker_exports`, `insert_history_location_export` and
/// `matching_package_parent`. The previous function finds the target by counting parentheses outside of quotes; this one
/// asks the syntax tree for the call, so a parenthesis in a comment or a raw string cannot end it early. The completion
/// of an existing target edits its text exactly as the previous function does. A target whose last argument is followed by a
/// comma (`name: "Demo",` and a line break) gets the setting after that comma; the previous function writes `, linkerSettings:`
/// after it, which does not compile.
public enum LinkerExports {
  public static let rule = "browser-reactor-linker-exports"

  /// Entry points that move event and secure values and the SecureField id list across the boundary in one copy
  /// instead of one call per byte. Hosts fall back to the per-byte exports when a build lacks them.
  static let bulkValueExports = ["event_value_alloc", "event_value_commit", "secure_value_pointer", "secure_ids_length", "secure_ids_pointer"]

  private static let lengthMarker = "\"--export=embedded_browser_html_length\""
  private static let historyRestoreMarker = "\"--export=embedded_browser_history_restore\""

  private static func flag(_ name: String) -> String { ", \"-Xlinker\", \"--export=\(name)\"" }

  /// `, linkerSettings: [.unsafeFlags([…])]` with every export, for a target that has no linker settings.
  static func linkerSettings() -> String {
    let flags = [
      "embedded_browser_start", "embedded_browser_set_initial_preferences", "embedded_browser_dispatch",
      "embedded_browser_dispatch_named", "embedded_browser_event_value_reset", "embedded_browser_event_value_push",
      "embedded_browser_secure_value", "embedded_browser_secure_value_reset", "embedded_browser_secure_value_byte",
      "embedded_browser_timeline_tick", "embedded_browser_batch_begin", "embedded_browser_batch_end",
      "embedded_browser_lazy_collection_count", "embedded_browser_lazy_item_count",
      "embedded_browser_lazy_estimated_extent", "embedded_browser_lazy_window", "embedded_browser_webmount_reconcile",
      "embedded_browser_html_length", "embedded_browser_html_pointer", "embedded_browser_html_byte",
      "embedded_browser_drain_tasks", "browser_io_receive", "browser_io_free", "embedded_browser_viewport",
      "embedded_browser_scroll_ack", "embedded_browser_scroll_prepare", "embedded_browser_history_ack",
      "embedded_browser_history_restore",
    ]
    var list = flags.map { "\"-Xlinker\", \"--export=\($0)\"" }.joined(separator: ", ")
    // The newer exports follow the entry they extend, the way the previous lowerer splices them into its base list.
    list = list.replacingOccurrences(
      of: lengthMarker,
      with: lengthMarker + ["embedded_browser_fiber_metric", "embedded_browser_publish_seq", "embedded_browser_publish_ack", "embedded_browser_publish_full"].map(flag).joined()
    )
    list = list.replacingOccurrences(
      of: historyRestoreMarker,
      with: historyRestoreMarker + flag("embedded_browser_history_location") + flag("embedded_browser_cookies_changed")
    )
    list = list.replacingOccurrences(
      of: lengthMarker, with: lengthMarker + bulkValueExports.map { flag("embedded_browser_\($0)") }.joined()
    )
    return ", linkerSettings: [.unsafeFlags([\(list)])]"
  }

  /// The manifest with the product's executable target patched, or nil when there is nothing to change.
  public static func patch(_ manifest: String, product: String) throws -> String? {
    guard manifest.contains(".executableTarget") else { return nil }
    let tree = Parser.parse(source: manifest)
    let finder = TargetFinder(product: product)
    finder.walk(tree)
    guard let call = finder.target, let access = call.calledExpression.as(MemberAccessExprSyntax.self),
      let rightParen = call.rightParen
    else { return nil }
    let start = access.period.startOffset
    let end = rightParen.endOffset
    let bytes = Array(manifest.utf8)
    let entry = String(decoding: bytes[start..<end], as: UTF8.self)
    // The offset in `entry` just after a comma that follows the last argument, if the call has one.
    let trailingComma = call.arguments.last?.trailingComma.map { $0.endOffset - start }
    guard let patched = patchedTarget(entry, trailingCommaEnd: trailingComma) else { return nil }
    return try apply([TextEdit(start: start, end: end, replacement: patched)], to: manifest)
  }

  /// The text of one `.executableTarget(…)` call with its exports completed; nil when it needs none or cannot be read.
  static func patchedTarget(_ entry: String, trailingCommaEnd: Int? = nil) -> String? {
    let singleExports = ["publish_seq", "publish_ack", "publish_full"] + bulkValueExports
    let complete = ["embedded_browser_html_pointer", "embedded_browser_history_location", "embedded_browser_fiber_metric", "embedded_browser_publish_full"]
      + bulkValueExports.map { "embedded_browser_\($0)" }
    if complete.allSatisfy({ entry.contains($0) }) { return nil }
    guard entry.contains("linkerSettings:") else {
      if let comma = trailingCommaEnd {
        // `name: "Demo",⏎)`: the argument follows the comma that is already there. (The previous lowerer writes
        // `name: "Demo",⏎, linkerSettings: …`, which does not compile.)
        let bytes = Array(entry.utf8)
        let setting = String(linkerSettings().dropFirst())
        return String(decoding: bytes[..<comma], as: UTF8.self) + setting + "," + String(decoding: bytes[comma...], as: UTF8.self)
      }
      return String(entry.dropLast()) + linkerSettings() + ")"
    }

    var result = entry
    /// Adds `addition` right after the first `marker`; false when there is none.
    func insert(after marker: String, _ addition: String) -> Bool {
      guard let range = result.range(of: marker, options: .literal) else { return false }
      result.insert(contentsOf: addition, at: range.upperBound)
      return true
    }
    if !result.contains("embedded_browser_html_pointer") {
      guard insert(after: lengthMarker, flag("embedded_browser_html_pointer")) else { return nil }
    }
    if !result.contains("embedded_browser_history_location") {
      if !insert(after: historyRestoreMarker, flag("embedded_browser_history_location")) {
        guard insertHistoryLocationExport(&result) else { return nil }
      }
    }
    if !result.contains("embedded_browser_fiber_metric") {
      guard insert(after: lengthMarker, flag("embedded_browser_fiber_metric")) else { return nil }
    }
    for name in singleExports {
      let export = "embedded_browser_\(name)"
      if !result.contains(export) {
        guard insert(after: lengthMarker, flag(export)) else { return nil }
      }
    }
    return result
  }

  /// Adds the history-location export at the end of the last flag list, for a target that lists no history-restore
  /// export to follow. False when the text has no `…])` shape to add it to.
  static func insertHistoryLocationExport(_ text: inout String) -> Bool {
    guard let close = text.range(of: ")]", options: [.backwards, .literal]),
      let arrayEnd = text[..<close.lowerBound].range(of: "]", options: [.backwards, .literal])
    else { return false }
    text.insert(contentsOf: flag("embedded_browser_history_location"), at: arrayEnd.lowerBound)
    return true
  }
}

private final class TargetFinder: SyntaxVisitor {
  let product: String
  var target: FunctionCallExprSyntax?

  init(product: String) {
    self.product = product
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard target == nil else { return .skipChildren }
    if let callee = node.calledExpression.as(MemberAccessExprSyntax.self), callee.declName.baseName.text == "executableTarget",
      node.rightParen != nil, !node.hasError,
      node.arguments.contains(where: { argument in
        argument.label?.text == "name" && argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == product
      })
    {
      target = node
      return .skipChildren
    }
    return .visitChildren
  }
}

extension WorkspaceLowering {
  /// Whether the driver pass `name` is selected: all of them run unless `--rules` names some.
  func runs(_ name: String) -> Bool {
    arguments.rules?.contains(name) ?? true
  }

  /// Patches the product's executable target in the lowered root's `Package.swift`. The manifest's original goes to the backup
  /// (once: a backup that is already there is the original of an earlier run and stays) and the manifest is recorded as
  /// changed.
  /// Returns the number of files written in `root` (0 or 1).
  @discardableResult
  func patchLinkerExports(in root: String, backup: String, summary: inout Summary) throws -> Int {
    let manifest = FileSystem.join(root, "Package.swift")
    guard FileSystem.exists(manifest) else { return 0 }
    let text = try FileSystem.readString(manifest)
    guard let patched = try LinkerExports.patch(text, product: arguments.product) else { return 0 }
    let backupPath = FileSystem.join(backup, "Package.swift")
    if !FileSystem.exists(backupPath) {
      try FileSystem.createDirectories(backup)
      try FileSystem.write(text, to: backupPath)
      summary.changed.append("Package.swift")
    }
    try FileSystem.write(patched, to: manifest)
    summary.totals.add(LinkerExports.rule, 1)
    return 1
  }

  /// `--sync-workspace`: the manifest of the workspace becomes the source's manifest, patched when the linker exports apply,
  /// and only the bytes that differ are written. The backup and the report entry are those of `patchLinkerExports`.
  /// Returns the number of workspace files written (0 or 1).
  func syncManifest(sourceRoot: String, root: String, backup: String, summary: inout Summary) throws -> Int {
    let source = FileSystem.join(sourceRoot, "Package.swift")
    let text = try FileSystem.readString(source)
    let patched = try runs("linker-exports") ? LinkerExports.patch(text, product: arguments.product) : nil
    let manifest = FileSystem.join(root, "Package.swift")
    let created = !FileSystem.exists(manifest) || FileSystem.isDirectory(manifest)
    var written = false
    if let patched {
      let backupPath = FileSystem.join(backup, "Package.swift")
      if !FileSystem.exists(backupPath) {
        try FileSystem.createDirectories(backup)
        try FileSystem.write(text, to: backupPath)
        summary.changed.append("Package.swift")
      }
      summary.totals.add(LinkerExports.rule, 1)
      written = try FileSystem.writeIfChanged(patched, to: manifest)
    } else {
      written = try FileSystem.writeIfChanged(text, to: manifest)
    }
    if created { FileSystem.copyPermissions(from: source, to: manifest) }
    return written ? 1 : 0
  }
}
