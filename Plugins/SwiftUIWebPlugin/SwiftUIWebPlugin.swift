import Foundation
import PackagePlugin
import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct SwiftUIWebPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let consumerRoot = context.package.directoryURL
    let frameworkRoot = try locateFrameworkRoot(context: context)
    let launcher = frameworkRoot.appendingPathComponent("Tools/swiftuiweb-run.swift")

    guard FileManager.default.isReadableFile(atPath: launcher.path) else {
      Diagnostics.error("SwiftUIWeb launcher not found at \(launcher.path)")
      throw PluginError.missingLauncher
    }

    var forwardedArguments = arguments
    if hasOption("--serve", in: forwardedArguments) || hasOption("--port", in: forwardedArguments) {
      Diagnostics.error(
        "SwiftPM command plugins are sandboxed and cannot bind a localhost server. " +
          "Build with this command, then serve with `swift Tools/swiftuiweb-run.swift --path . --product <Product>`."
      )
      throw PluginError.serverRequiresLauncher
    }
    if !hasOption("--path", in: forwardedArguments) && !hasOption("--package-root", in: forwardedArguments) {
      forwardedArguments.insert(contentsOf: ["--package-root", consumerRoot.path], at: 0)
    }
    // A command plugin has no network permission by design: the zero-flag
    // consumer command must work in SwiftPM's sandbox.  It therefore builds a
    // disposable bundle by default.  The standalone launcher owns the server
    // lifecycle, port selection and Ctrl-C cleanup outside that sandbox.
    if !hasOption("--build-only", in: forwardedArguments)
      && !hasOption("--help", in: forwardedArguments)
      && !hasOption("-h", in: forwardedArguments) {
      forwardedArguments.append("--build-only")
    }

    var environment = ProcessInfo.processInfo.environment
    environment["SWIFTUIWEB_ROOT"] = frameworkRoot.path
    let pluginWorkDirectory = context.pluginWorkDirectoryURL
    environment["SWIFTUIWEB_PLUGIN_MODE"] = "1"
    environment["SWIFTUIWEB_PLUGIN_WORK_DIR"] = pluginWorkDirectory.path
    environment["SWIFTUIWEB_BUILD_ROOT"] = pluginWorkDirectory.appendingPathComponent("build", isDirectory: true).path
    environment["SWIFTUIWEB_BUNDLE_ROOT"] = pluginWorkDirectory.appendingPathComponent("browser", isDirectory: true).path

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", launcher.path] + forwardedArguments
    process.environment = environment
    process.currentDirectoryURL = consumerRoot
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    try process.run()
    let signalSources = installSignalForwarding { process.terminate() }
    process.waitUntilExit()
    signalSources.forEach { $0.cancel() }
    if process.terminationStatus != 0 {
      throw PluginError.launcherFailed(process.terminationStatus)
    }
  }

  private func installSignalForwarding(_ handler: @escaping () -> Void) -> [DispatchSourceSignal] {
    [SIGINT, SIGTERM, SIGHUP].map { signalNumber in
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
      source.setEventHandler(handler: handler)
      source.resume()
      return source
    }
  }

  private func locateFrameworkRoot(context: PluginContext) throws -> URL {
    if let configuredRoot = ProcessInfo.processInfo.environment["SWIFTUIWEB_ROOT"] {
      return URL(fileURLWithPath: configuredRoot).resolvingSymlinksInPath().standardizedFileURL
    }

    // Prefer the exact package identity; a substring match counts only when it is the sole candidate, so a
    // look-alike dependency (`my-swiftuiweb-fork`) cannot take the framework's place.
    let candidates = context.package.dependencies.map(\.package)
    let exact = candidates.first { $0.id.lowercased() == "swiftuiweb" }
    let fuzzy = candidates.filter { ($0.id + " " + $0.displayName).lowercased().contains("swiftuiweb") }
    if let package = exact ?? (fuzzy.count == 1 ? fuzzy[0] : nil) {
      return package.directoryURL.resolvingSymlinksInPath().standardizedFileURL
    }

    // This also makes `swift package plugin swiftuiweb` useful when invoked
    // from the SwiftUIWeb checkout itself.
    let local = context.package.directoryURL
    if FileManager.default.fileExists(atPath: local.appendingPathComponent("Tools/run-browser.sh").path) {
      return local.resolvingSymlinksInPath().standardizedFileURL
    }
    throw PluginError.frameworkDependencyNotFound
  }

  private func hasOption(_ option: String, in arguments: [String]) -> Bool {
    arguments.contains { argument in
      argument == option || argument.hasPrefix(option + "=")
    }
  }
}

private enum PluginError: Error, CustomStringConvertible {
  case missingLauncher
  case frameworkDependencyNotFound
  case serverRequiresLauncher
  case launcherFailed(Int32)

  var description: String {
    switch self {
    case .missingLauncher:
      return "The SwiftUIWeb launcher is unavailable."
    case .frameworkDependencyNotFound:
      return "Add SwiftUIWeb as a package dependency or set SWIFTUIWEB_ROOT."
    case .serverRequiresLauncher:
      return "Use Tools/swiftuiweb-run.swift for the local server lifecycle."
    case .launcherFailed(let status):
      return "SwiftUIWeb launcher exited with status \(status)."
    }
  }
}
