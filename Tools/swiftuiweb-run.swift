#!/usr/bin/env swift
// A small consumer-facing launcher. Run it from an application package with:
//
//   swift /path/to/swiftuiweb/Tools/swiftuiweb-run.swift \
//     --product MyApp
//
// The launcher deliberately stays outside the library targets: it only
// coordinates SwiftPM, the Embedded SDK and the static browser server.
import Foundation
import Dispatch

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct Options {
  var packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  var product = ProcessInfo.processInfo.environment["SWIFTUIWEB_PRODUCT"]
  var configuration = ProcessInfo.processInfo.environment["CONFIGURATION"] ?? "release"
  var port = ProcessInfo.processInfo.environment["PORT"]
  var buildOnly = ProcessInfo.processInfo.environment["BUILD_ONLY"] == "1"
  var loweringProfile = ProcessInfo.processInfo.environment["SWIFTUIWEB_LOWERING_PROFILE"]
  var releaseProfile = ProcessInfo.processInfo.environment["SWIFTUIWEB_RELEASE_PROFILE"]
  var devProfile = ProcessInfo.processInfo.environment["SWIFTUIWEB_DEV_PROFILE"]
  var watch = false
  var configurationWasGiven = ProcessInfo.processInfo.environment["CONFIGURATION"] != nil
}

func usage() {
  print("""
  Usage: swift Tools/swiftuiweb-run.swift [product] [options]

  Options:
    --product NAME          Executable product to build (needed when the package has several)
    --path PATH              Alias for --package-root
    --package-root PATH     Consumer package root (defaults to the current directory)
    --configuration NAME    debug or release (defaults to release)
    --port NUMBER            Browser server port
    --build-only             Build the browser bundle without starting the server
    --watch                  Development loop: build, serve, and when a source file is saved
                             rebuild (only what changed) and reload the open page. Defaults to
                             --configuration debug. Build errors show over the page.
    --lowering-profile NAME  Build profile of the source lowerer: release (default)
                             or dev, which rebuilds faster after editing the lowerer
                             and keeps full debug information
    --release-profile NAME   What a release build trades for time: size (default, the shipping
                             build), balanced (libraries unoptimized, 5 to 10% faster, app.wasm
                             about 5% larger) or fast (nothing optimized by swiftc, about 55% faster,
                             app.wasm about 2.4x larger; previews and CI, never shipping)
    --dev-profile NAME       What a debug build compiles: embedded (Embedded Swift, what ships) or
                             fast (the same sources as full Swift for regular WebAssembly: a save
                             recompiles the files it changed, several times faster; a larger and
                             slower module, never shipping). --watch defaults to fast in debug,
                             and to embedded when the toolchain has no regular WebAssembly SDK;
                             every other build defaults to embedded
    -h, --help               Show this help

  The script can be used with a path dependency or a checked-out SwiftUIWeb
  package. It sets SWIFTUIWEB_PACKAGE_ROOT before invoking the framework's
  Embedded browser launcher.
  """)
}

func fail(_ message: String) -> Never {
  fputs("swiftuiweb-run: \(message)\n", stderr)
  exit(2)
}

var options = Options()
var arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
  let argument = arguments[index]
  switch argument {
  case "-h", "--help":
    usage()
    exit(0)
  case "--product":
    index += 1
    guard index < arguments.count else { fail("--product needs a value") }
    options.product = arguments[index]
  case "--path", "--package-root":
    index += 1
    guard index < arguments.count else { fail("--package-root needs a value") }
    options.packageRoot = URL(fileURLWithPath: arguments[index], relativeTo: options.packageRoot)
  case "--configuration":
    index += 1
    guard index < arguments.count else { fail("--configuration needs a value") }
    options.configuration = arguments[index]
    options.configurationWasGiven = true
  case "--watch":
    options.watch = true
  case "--port":
    index += 1
    guard index < arguments.count else { fail("--port needs a value") }
    options.port = arguments[index]
  case "--build-only":
    options.buildOnly = true
  case "--lowering-profile":
    index += 1
    guard index < arguments.count else { fail("--lowering-profile needs a value") }
    options.loweringProfile = arguments[index]
  case "--release-profile":
    index += 1
    guard index < arguments.count else { fail("--release-profile needs a value") }
    options.releaseProfile = arguments[index]
  case "--dev-profile":
    index += 1
    guard index < arguments.count else { fail("--dev-profile needs a value") }
    options.devProfile = arguments[index]
  default:
    if argument.hasPrefix("-") { fail("unknown option \(argument)") }
    if options.product == nil { options.product = argument }
    else { fail("unexpected argument \(argument)") }
  }
  index += 1
}

options.packageRoot = options.packageRoot.standardizedFileURL
guard FileManager.default.fileExists(atPath: options.packageRoot.appendingPathComponent("Package.swift").path) else {
  fail("no Package.swift found at \(options.packageRoot.path)")
}
// A package with one executable needs no --product: its name is read from the manifest's text (`.executable(name:` among
// the products, else `.executableTarget(name:`), which costs nothing next to asking SwiftPM to describe the package.
func executables(inManifestAt url: URL) -> [String] {
  guard let manifest = try? String(contentsOf: url, encoding: .utf8) else { return [] }
  func names(after marker: String) -> [String] {
    var found: [String] = []
    var rest = Substring(manifest)
    while let range = rest.range(of: marker) {
      rest = rest[range.upperBound...]
      let trimmed = rest.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })
      guard trimmed.hasPrefix("name:") else { continue }
      let value = trimmed.dropFirst("name:".count).drop(while: { $0 == " " })
      guard value.hasPrefix("\"") , let end = value.dropFirst().firstIndex(of: "\"") else { continue }
      let name = String(value.dropFirst()[..<end])
      if !found.contains(name) { found.append(name) }
    }
    return found
  }
  let products = names(after: ".executable(")
  return products.isEmpty ? names(after: ".executableTarget(") : products
}
if options.product == nil || options.product?.isEmpty == true {
  let found = executables(inManifestAt: options.packageRoot.appendingPathComponent("Package.swift"))
  if found.count == 1 { options.product = found[0] }
  else if found.count > 1 { fail("this package has \(found.count) executables (\(found.joined(separator: ", "))); pass --product <name>") }
}
guard let product = options.product, !product.isEmpty else {
  fail("pass --product <executable>, for example --product MyApp")
}

let scriptRoot: URL
if let configuredRoot = ProcessInfo.processInfo.environment["SWIFTUIWEB_ROOT"] {
  scriptRoot = URL(fileURLWithPath: configuredRoot).resolvingSymlinksInPath().standardizedFileURL
} else {
  scriptRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}
let launcher = scriptRoot.appendingPathComponent("Tools/run-browser.sh")
guard FileManager.default.isExecutableFile(atPath: launcher.path) else {
  fail("cannot find SwiftUIWeb launcher at \(launcher.path); set SWIFTUIWEB_ROOT")
}

var environment = ProcessInfo.processInfo.environment
environment["SWIFTUIWEB_PACKAGE_ROOT"] = options.packageRoot.path
environment["SWIFTUIWEB_PRODUCT"] = product
environment["CONFIGURATION"] = options.configuration
if let port = options.port { environment["PORT"] = port }
if options.buildOnly { environment["BUILD_ONLY"] = "1" }
if let profile = options.loweringProfile {
  guard ["dev", "release"].contains(profile) else { fail("--lowering-profile is dev or release, not \(profile)") }
  environment["SWIFTUIWEB_LOWERING_PROFILE"] = profile
}
if let profile = options.releaseProfile {
  guard ["size", "balanced", "fast"].contains(profile) else { fail("--release-profile is size, balanced or fast, not \(profile)") }
  environment["SWIFTUIWEB_RELEASE_PROFILE"] = profile
}
// A project that aliases `SwiftUI`/`Foundation` to SwiftUIWeb's modules (`-module-alias` in its manifest) imports them
// by the Apple names, so the source lowering must not inject `import SwiftUIWeb`.
if let manifest = try? String(contentsOf: options.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8),
   manifest.contains("-module-alias") {
  environment["SWIFTUIWEB_MODULE_ALIASES"] = "1"
}

if let profile = options.devProfile {
  guard ["embedded", "fast"].contains(profile) else { fail("--dev-profile is embedded or fast, not \(profile)") }
  environment["SWIFTUIWEB_DEV_PROFILE"] = profile
}
if options.watch {
  guard !options.buildOnly else { fail("--watch serves the app; it cannot be combined with --build-only") }
  // A debug build is the one to iterate on: it links faster and the reload cycle is what matters here.
  if !options.configurationWasGiven { environment["CONFIGURATION"] = "debug" }
}
if environment["SWIFTUIWEB_DEV_PROFILE"] == "fast", (environment["CONFIGURATION"] ?? options.configuration) != "debug" {
  fail("--dev-profile fast needs --configuration debug: a release is always Embedded Swift")
}

let process = Process()
if options.watch {
  let watcher = scriptRoot.appendingPathComponent("Tools/dev-watch.mjs")
  guard FileManager.default.fileExists(atPath: watcher.path) else { fail("cannot find \(watcher.path); set SWIFTUIWEB_ROOT") }
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  var watchArguments = ["bun", watcher.path, "--package-root", options.packageRoot.path, "--product", product,
                        "--configuration", environment["CONFIGURATION"] ?? "debug"]
  if let port = options.port { watchArguments += ["--port", port] }
  process.arguments = watchArguments
} else {
  process.executableURL = launcher
  process.arguments = [product]
}
process.environment = environment
process.currentDirectoryURL = scriptRoot
do {
  try process.run()
  let signalSources: [DispatchSourceSignal] = [SIGINT, SIGTERM, SIGHUP].map { signalNumber in
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
    source.setEventHandler { process.terminate() }
    source.resume()
    return source
  }
  process.waitUntilExit()
  signalSources.forEach { $0.cancel() }
  exit(process.terminationStatus)
} catch {
  fail("could not start launcher: \(error.localizedDescription)")
}
