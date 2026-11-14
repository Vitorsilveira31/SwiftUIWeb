import Foundation
import Testing

@testable import LoweringCore

@Suite struct ExportRewriteTests {
  // MARK: browser-exports

  @Test func aBrowserAppGetsItsEntryPointsOnce() throws {
    let source = "@main struct Demo: BrowserApp {\n  var body: some Scene { WindowGroup { Text(\"x\") } }\n}\n"
    let result = lower(source, rules: ["browser-exports"])
    #expect(result.counts["browser-reactor-entry-and-html-exports"] == 1)
    #expect(result.text.hasPrefix(source + "\n\n@_cdecl(\"embedded_browser_start\")\n"))
    #expect(result.text.contains("BrowserAppLauncher.embeddedBrowserLaunch(Demo(), configuration: Demo._configuration)"))
    #expect(result.text.contains("@_cdecl(\"embedded_browser_cookies_changed\")"))
    #expect(result.text.contains("BrowserAppLauncher.embeddedBrowserCookiesChanged()"))
    #expect(!result.text.contains("__APP__"))
    #expect(result.text.hasSuffix("embeddedBrowserHistoryLocation() }\n"))
    // A file that has the entry points is left alone.
    let again = lower(result.text, rules: ["browser-exports"])
    #expect(again.text == result.text)
    #expect(again.counts.isEmpty)
  }

  @Test func theExportsReachPrivateAndPublicBrowserApps() throws {
    for access in ["", "private ", "fileprivate ", "public ", "internal ", "package "] {
      let text = lowered("@main\n\(access)struct Demo: BrowserApp {\n  var body: some Scene { WindowGroup { Text(\"x\") } }\n}\n", rules: ["browser-exports"])
      #expect(text.contains("embedded_browser_start"), "\(access)")
    }
    let attributed = lowered("@MainActor @main struct Demo: Sendable, BrowserApp {}\n", rules: ["browser-exports"])
    #expect(attributed.contains("embeddedBrowserLaunch(Demo()"))
  }

  @Test func onlyTheMainBrowserAppStructGetsEntryPoints() throws {
    for source in [
      "struct Demo: BrowserApp {}\n",
      "@main struct Demo: App {}\n",
      "@main enum Demo: BrowserApp {}\n",
      "@main struct Demo<Content>: BrowserApp {}\n",
      "@main struct Demo: BrowserAppDelegate {}\n",
      "// @main struct Demo: BrowserApp {}\nlet x = 1\n",
      "let text = \"@main struct Demo: BrowserApp {}\"\n",
    ] {
      #expect(lowered(source, rules: ["browser-exports"]) == source, "\(source)")
    }
    // An application that is not a BrowserApp stays as it is at every access level (the same source with BrowserApp is lowered in
    // `theExportsReachPrivateAndPublicBrowserApps`).
    for access in ["", "private ", "fileprivate ", "public ", "internal ", "package "] {
      let source = "@main\n\(access)struct Demo: App {\n  var body: some Scene { WindowGroup { Text(\"x\") } }\n}\n"
      #expect(lowered(source, rules: ["browser-exports"]) == source, "\(access)")
    }
  }

  @Test func theExportsFollowTheLastLineOfAFileWithoutATrailingNewline() throws {
    let text = lowered("@main struct Demo: BrowserApp {}", rules: ["browser-exports"])
    #expect(text.hasPrefix("@main struct Demo: BrowserApp {}\n\n@_cdecl("))
  }

  @Test func theWholePipelineReportsTheExportsAndLowersTwiceTheSame() throws {
    let source = "import Observation\n@main struct Demo: BrowserApp {\n  var body: some Scene { WindowGroup { Text(\"Import failed: \\(error)\") } }\n}\nstruct Payload: Codable { let value: String }\n"
    let first = lower(source)
    #expect(first.text.contains("embedded_browser_start"))
    #expect(first.text.contains("\"Import failed\""))
    #expect(first.counts["browser-reactor-entry-and-html-exports"] == 1)
    #expect(lower(first.text).text == first.text)
  }

  // MARK: linker-exports

  private static let flags = ["html_pointer", "history_location", "fiber_metric", "publish_seq", "publish_ack", "publish_full"]
  private static let bulk = LinkerExports.bulkValueExports

  private func target(_ arguments: String = "name: \"Demo\"") -> String {
    "let p = Package(targets: [.executableTarget(\(arguments))])\n"
  }

  @Test func aTargetWithoutLinkerSettingsGetsEveryExport() throws {
    let patched = try #require(try LinkerExports.patch(target(), product: "Demo"))
    for name in Self.flags + Self.bulk {
      #expect(patched.contains("\"--export=embedded_browser_\(name)\""), "\(name)")
    }
    #expect(patched.hasPrefix("let p = Package(targets: [.executableTarget(name: \"Demo\", linkerSettings: [.unsafeFlags([\"-Xlinker\", \"--export=embedded_browser_start\", "))
    #expect(patched.hasSuffix("\"--export=embedded_browser_history_restore\", \"-Xlinker\", \"--export=embedded_browser_history_location\", \"-Xlinker\", \"--export=embedded_browser_cookies_changed\"])])])\n"))
    // Each export is listed once.
    #expect(patched.components(separatedBy: "embedded_browser_history_location").count == 2)
    #expect(patched.components(separatedBy: "embedded_browser_fiber_metric").count == 2)
    // The flags follow the HTML length export in the order the previous lowerer writes them.
    #expect(
      patched.contains(
        "\"--export=embedded_browser_html_length\", \"-Xlinker\", \"--export=embedded_browser_event_value_alloc\", \"-Xlinker\", \"--export=embedded_browser_event_value_commit\", \"-Xlinker\", \"--export=embedded_browser_secure_value_pointer\", \"-Xlinker\", \"--export=embedded_browser_secure_ids_length\", \"-Xlinker\", \"--export=embedded_browser_secure_ids_pointer\", \"-Xlinker\", \"--export=embedded_browser_fiber_metric\", \"-Xlinker\", \"--export=embedded_browser_publish_seq\", \"-Xlinker\", \"--export=embedded_browser_publish_ack\", \"-Xlinker\", \"--export=embedded_browser_publish_full\", \"-Xlinker\", \"--export=embedded_browser_html_pointer\""
      ))
    // A complete export list is already patched.
    #expect(try LinkerExports.patch(patched, product: "Demo") == nil)
  }

  @Test func theTargetIsFoundByNameInTheTreeNotByCountingParentheses() throws {
    let manifest = """
      // .executableTarget(name: "Demo") in a comment
      let p = Package(name: "(", targets: [
        .executableTarget(name: "Other", path: "Sources/)"),
        .executableTarget(
          name: "Demo",
          dependencies: ["A"], // )
          path: #"Sources/")"#
        ),
        .testTarget(name: "DemoTests"),
      ])

      """
    let patched = try #require(try LinkerExports.patch(manifest, product: "Demo"))
    #expect(patched.contains("path: #\"Sources/\")\"#\n  , linkerSettings: [.unsafeFlags([\"-Xlinker\""))
    #expect(patched.contains(".executableTarget(name: \"Other\", path: \"Sources/)\"),"))
    #expect(patched.contains("\"])]),\n  .testTarget(name: \"DemoTests\"),\n])\n"))
    #expect(patched.components(separatedBy: "embedded_browser_start").count == 2)
  }

  @Test func aTrailingCommaAfterTheLastArgumentIsKept() throws {
    let manifest = "let p = Package(targets: [\n  .executableTarget(\n    name: \"Demo\",\n    path: \"Sources\", // note\n  ),\n])\n"
    let patched = try #require(try LinkerExports.patch(manifest, product: "Demo"))
    #expect(patched.hasPrefix("let p = Package(targets: [\n  .executableTarget(\n    name: \"Demo\",\n    path: \"Sources\", linkerSettings: [.unsafeFlags([\"-Xlinker\", "))
    #expect(patched.hasSuffix("\"])], // note\n  ),\n])\n"))
    #expect(!patched.contains(",\n  , linkerSettings"))
    #expect(!patched.contains(", ,"))
    #expect(!patched.contains(",,"))
    // The setting is not added twice, and the one-line spelling is unchanged.
    #expect(try LinkerExports.patch(patched, product: "Demo") == nil)
    let oneLine = try #require(try LinkerExports.patch("let p = Package(targets: [.executableTarget(name: \"Demo\", path: \"S\",)])\n", product: "Demo"))
    #expect(oneLine.contains("path: \"S\", linkerSettings: [.unsafeFlags(["))
    #expect(oneLine.hasSuffix("\"])],)])\n"))
  }

  @Test func aManifestWithoutThatTargetIsLeftAlone() throws {
    #expect(try LinkerExports.patch("let p = Package()\n", product: "Demo") == nil)
    #expect(try LinkerExports.patch(target("name: \"Other\""), product: "Demo") == nil)
    #expect(try LinkerExports.patch("let p = Package(targets: [.target(name: \"Demo\")])\n", product: "Demo") == nil)
  }

  @Test func malformedTargetsAreLeftAlone() throws {
    for malformed in [
      "let p = Package(targets: [.executableTarget name: \"Demo\"])\n",
      "let p = Package(targets: [.executableTarget(name: \"Demo\"",
      "let p = Package(targets: [.executableTarget(name: \"Demo\", linkerSettings: [.unsafeFlags([\"--export=embedded_browser_html_length\"]) )\n",
    ] {
      #expect(try LinkerExports.patch(malformed, product: "Demo") == nil, "\(malformed)")
    }
  }

  @Test func existingLinkerSettingsAreCompletedAfterTheHTMLLengthExport() throws {
    func settings(_ flags: [String]) -> String {
      target("name: \"Demo\", linkerSettings: [.unsafeFlags([\(flags.map { "\"--export=\($0)\"" }.joined(separator: ", "))])]")
    }
    // Flags the previous lowerer cannot place are left alone.
    #expect(try LinkerExports.patch(settings(["x"]), product: "Demo") == nil)
    #expect(try LinkerExports.patch(settings(["embedded_browser_html_pointer", "embedded_browser_history_location"]), product: "Demo") == nil)
    #expect(try LinkerExports.patch("let p = Package(targets: .executableTarget(name: \"Demo\", linkerSettings: \"--export=embedded_browser_html_length)]\"))\n", product: "Demo") == nil)

    let both = try #require(try LinkerExports.patch(settings(["embedded_browser_html_length", "embedded_browser_history_restore"]), product: "Demo"))
    #expect(both.contains("\"--export=embedded_browser_history_restore\", \"-Xlinker\", \"--export=embedded_browser_history_location\""))
    #expect(both.contains("\"--export=embedded_browser_html_length\", \"-Xlinker\", \"--export=embedded_browser_secure_ids_pointer\""))
    #expect(both.contains("embedded_browser_fiber_metric"))
    // Without a history-restore export the location export ends the flag list.
    let lengthOnly = try #require(try LinkerExports.patch(settings(["embedded_browser_html_length"]), product: "Demo"))
    #expect(lengthOnly.contains("\"--export=embedded_browser_html_length\", \"-Xlinker\", \"--export=embedded_browser_secure_ids_pointer\""))
    #expect(lengthOnly.hasSuffix(", \"-Xlinker\", \"--export=embedded_browser_history_location\"])])])\n"))

    // Exports already listed stay where they are and are not listed twice.
    let partial = settings([
      "embedded_browser_html_length", "embedded_browser_html_pointer", "embedded_browser_history_location",
      "embedded_browser_fiber_metric", "embedded_browser_publish_seq",
    ])
    let completed = try #require(try LinkerExports.patch(partial, product: "Demo"))
    #expect(completed.components(separatedBy: "embedded_browser_publish_seq").count == 2)
    for name in ["publish_ack", "publish_full", "secure_ids_pointer"] {
      #expect(completed.contains("\"--export=embedded_browser_\(name)\""), "\(name)")
    }
  }

  @Test func theHistoryLocationExportEndsTheLastFlagList() throws {
    var valid = "unsafeFlags([\"--export=embedded_browser_history_restore\"])])"
    #expect(LinkerExports.insertHistoryLocationExport(&valid))
    #expect(valid == "unsafeFlags([\"--export=embedded_browser_history_restore\", \"-Xlinker\", \"--export=embedded_browser_history_location\"])])")

    var malformed = "\"--export=embedded_browser_history_restore)]\""
    #expect(!LinkerExports.insertHistoryLocationExport(&malformed))
    #expect(malformed == "\"--export=embedded_browser_history_restore)]\"")
    var missingClose = "\"--export=embedded_browser_history_restore\""
    #expect(!LinkerExports.insertHistoryLocationExport(&missingClose))
  }

  // MARK: The workspace

  private func makePackage(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swl-\(UUID().uuidString)")
    for (path, content) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try content.write(to: url, atomically: true, encoding: .utf8)
    }
    return root
  }

  private func lowerWorkspace(
    _ files: [String: String], product: String = "Demo", rules: [String]? = nil
  ) throws -> (summary: WorkspaceLowering.Summary, source: URL, workspace: URL) {
    let root = try makePackage(files)
    let workspace = root.deletingLastPathComponent().appendingPathComponent("swl-ws-\(UUID().uuidString)")
    var arguments = LoweringArguments()
    arguments.root = root
    arguments.workspace = workspace
    arguments.product = product
    arguments.rules = rules
    arguments.lowerCodable = true
    let summary = try WorkspaceLowering(arguments: arguments, pipeline: .standard, moduleAliases: false).run()
    return (summary, root, workspace)
  }

  @Test func theWorkspaceManifestGainsTheLinkerExportsAndIsReportedChanged() throws {
    let package = "let p = Package(targets: [.executableTarget(name: \"Demo\")])\n"
    let result = try lowerWorkspace([
      "Package.swift": package,
      "Sources/App.swift": "@main struct Demo: BrowserApp {}\n",
    ])
    defer {
      try? FileManager.default.removeItem(at: result.source)
      try? FileManager.default.removeItem(at: result.workspace)
    }
    #expect(result.summary.changed == ["Sources/App.swift", "Package.swift"])
    #expect(result.summary.totals["browser-reactor-linker-exports"] == 1)
    #expect(result.summary.totals["browser-reactor-entry-and-html-exports"] == 1)
    let patched = try String(contentsOf: result.workspace.appendingPathComponent("Package.swift"), encoding: .utf8)
    #expect(try patched == LinkerExports.patch(package, product: "Demo"))
    // The package being lowered is not touched.
    #expect(try String(contentsOf: result.source.appendingPathComponent("Package.swift"), encoding: .utf8) == package)
  }

  @Test func theDriverPassesCanBeLeftOut() throws {
    let package = "let p = Package(targets: [.executableTarget(name: \"Demo\")])\n"
    let result = try lowerWorkspace(
      ["Package.swift": package, "Sources/App.swift": "@main struct Demo: BrowserApp {}\n"], rules: ["browser-exports"]
    )
    defer {
      try? FileManager.default.removeItem(at: result.source)
      try? FileManager.default.removeItem(at: result.workspace)
    }
    #expect(result.summary.changed == ["Sources/App.swift"])
    #expect(try String(contentsOf: result.workspace.appendingPathComponent("Package.swift"), encoding: .utf8) == package)
  }
}
