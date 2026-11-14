import Foundation

/// The command line of the Swift lowerer: the previous lowerer's contract (`--apply|--restore`, `--root`, `--product`,
/// `--workspace`, `--lower-codable`, `--report`, `--state`, `-h`), so the build can run either tool with the same
/// arguments, plus two options for the golden harness: `--rules` and `--list-passes`.
public struct LoweringArguments: Sendable {
  public enum Mode: Sendable {
    case apply
    case restore
  }

  public var mode = Mode.apply
  /// The paths are kept as they were given: the report prints a workspace path as it was joined to the working directory.
  public var rootPath = "."
  public var product = "ShowcaseApp"
  public var workspacePath: String?
  /// Where the per-file result cache lives (`--cache`). `nil` lowers every file, as the lowerer always has.
  public var cachePath: String?
  /// Keeps the persistent workspace (`--workspace`) an exact mirror of the source, rewriting only the files whose bytes
  /// change, so unchanged files keep their modification times (`--sync-workspace`). Needs a workspace.
  public var syncWorkspace = false
  public var lowerCodable = false
  /// Marks the framework's non-generic functions `@export(interface)`, so the debug development loop compiles them once
  /// in their own library (`--export-interface`). Only the debug development loop passes it.
  public var exportInterface = false
  /// `--export-interface-application`: `export-interface` also marks application files (`lowerCodable`). Needs
  /// `exportInterface`. The staged debug loop passes it for the application and its local packages.
  public var exportInterfaceApplication = false
  /// `--stable-source-locations`: `stable-source-locations` gives every declaration its own `#sourceLocation`, so an edit in
  /// one declaration leaves the others' locations, and the module bytes, alone (debug development loop only).
  public var stableSourceLocations = false
  /// `--full-swift`: the lowered tree is compiled as full Swift for regular WebAssembly (the development profile), so
  /// `embedded-feature-condition` makes every `hasFeature(Embedded)` condition true.
  public var fullSwift = false
  /// `--generic-types-out PATH`: after the generic-type scan, the names of the run (sorted, one per line) are written there.
  public var genericTypesOutPath: String?
  /// `--generic-types-in PATH` (repeatable): names read from these files (one per line, blank lines ignored) are unioned into
  /// the run's generic-type names before lowering. A missing file is an error.
  public var genericTypesInPaths: [String] = []
  /// Wraps the literals of application files in `_live(id, literal)` (`--live-literals`).
  public var liveLiterals = false
  /// `--development-exports`: the application's entry file also gets the entry points only the development loop calls
  /// (`embedded_browser_state_save`, which keeps the page's state across a reload).
  public var developmentExports = false
  /// Where the report goes, relative to the source root. Always written, like the previous lowerer's.
  public var reportPath = ".build/embedded-source-lowering/report.json"
  /// Where the state goes, relative to the lowered root (the workspace, or the source root when lowering in place). It
  /// records what `--restore` has to put back.
  public var statePath = ".build/embedded-source-lowering/state.json"
  /// Pass names to run; `nil` runs every ported pass.
  public var rules: [String]?
  public var help = false
  public var listPasses = false

  public init() {}

  public var root: URL {
    get { URL(fileURLWithPath: rootPath) }
    set { rootPath = newValue.path }
  }

  public var workspace: URL? {
    get { workspacePath.map { URL(fileURLWithPath: $0) } }
    set { workspacePath = newValue?.path }
  }

  /// `nil` while the report goes to its default place.
  public var report: URL? {
    get { reportPath == Self.defaultReport ? nil : URL(fileURLWithPath: reportPath) }
    set { reportPath = newValue?.path ?? Self.defaultReport }
  }

  private static let defaultReport = LoweringArguments().reportPath

  /// The previous lowerer's usage line.
  public static let usage =
    "Usage: swiftuiweb-lowering --apply|--restore [--root PATH] [--product NAME] [--workspace PATH] [--cache PATH] [--sync-workspace] [--lower-codable] [--export-interface [--export-interface-application] [--generic-types-in PATH]... [--generic-types-out PATH]] [--stable-source-locations] [--full-swift] [--live-literals] [--development-exports] [--report PATH] [--state PATH]"

  public enum Failure: Error, CustomStringConvertible {
    case message(String)
    public var description: String {
      switch self { case .message(let text): text }
    }
  }

  public static func parse(_ values: [String]) throws -> LoweringArguments {
    var arguments = LoweringArguments()
    var applies = false
    var restores = false
    var iterator = values.makeIterator()
    func value(_ option: String) throws -> String {
      guard let next = iterator.next() else { throw Failure.message("\(option) needs a value") }
      return next
    }
    while let argument = iterator.next() {
      switch argument {
      case "--apply": applies = true
      case "--restore": restores = true
      case "--lower-codable": arguments.lowerCodable = true
      case "--export-interface": arguments.exportInterface = true
      case "--export-interface-application": arguments.exportInterfaceApplication = true
      case "--stable-source-locations": arguments.stableSourceLocations = true
      case "--full-swift": arguments.fullSwift = true
      case "--generic-types-out": arguments.genericTypesOutPath = try value(argument)
      case "--generic-types-in": arguments.genericTypesInPaths.append(try value(argument))
      case "--live-literals": arguments.liveLiterals = true
      case "--development-exports": arguments.developmentExports = true
      case "--root": arguments.rootPath = try value(argument)
      case "--product": arguments.product = try value(argument)
      case "--workspace": arguments.workspacePath = try value(argument)
      case "--cache": arguments.cachePath = try value(argument)
      case "--sync-workspace": arguments.syncWorkspace = true
      case "--report": arguments.reportPath = try value(argument)
      case "--state": arguments.statePath = try value(argument)
      case "--rules": arguments.rules = try value(argument).split(separator: ",").map { String($0).trimmingWhitespace() }
      case "--list-passes":
        arguments.listPasses = true
        return arguments
      case "-h", "--help":
        arguments.help = true
        return arguments
      default: throw Failure.message("unknown option \(argument)")
      }
    }
    if applies == restores { throw Failure.message("pass exactly one of --apply or --restore") }
    if arguments.syncWorkspace, arguments.workspacePath == nil { throw Failure.message("--sync-workspace needs --workspace") }
    if arguments.exportInterfaceApplication, !arguments.exportInterface {
      throw Failure.message("--export-interface-application needs --export-interface")
    }
    arguments.mode = restores ? .restore : .apply
    return arguments
  }
}
