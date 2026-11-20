import Foundation

/// How often each rule fired, keyed by the rule name the previous lowerer reports.
public typealias RuleCounts = [String: Int]

extension Dictionary where Key == String, Value == Int {
  mutating func add(_ rule: String, _ amount: Int) {
    if amount != 0 { self[rule, default: 0] += amount }
  }
}

/// The per-run choices a transform reads. They mirror the previous lowerer's `TransformOptions`.
public struct LoweringOptions: Sendable {
  /// Application sources are lowered with `--lower-codable`; framework sources are not.
  public var lowerCodable: Bool
  /// `SWIFTUIWEB_MODULE_ALIASES=1`: the application aliases `SwiftUI` to SwiftUIWeb, so injected imports spell
  /// `SwiftUI`. Passed in rather than read here so a transform never depends on process-global state.
  public var moduleAliases: Bool
  /// The `@Observable` classes declared anywhere in the lowered package (the workspace driver scans for them before it
  /// lowers a file), which `observable-state` reads: a `@State` holding one is kept as a retained reference model.
  public var observableTypes: Set<String>
  /// `--export-interface`: framework functions that are not generic are marked `@export(interface)` (`export-interface`).
  public var exportInterface: Bool
  /// The generic types and protocols declared anywhere in the lowered run, by simple and dotted name (the workspace driver
  /// scans for them before it lowers a file, when `exportInterface` is set). `export-interface` reads it: a method of one
  /// of these, or of an extension of one, is generic and is left alone.
  public var genericTypeNames: Set<String>
  /// `--export-interface-application`: `export-interface` also applies to application files (`lowerCodable`). The
  /// application's run needs the framework's generic names (`genericTypeNames`), since it scans only its own files.
  public var exportInterfaceApplication: Bool
  /// `--stable-source-locations`: `stable-source-locations` gives each declaration its own `#sourceLocation` (debug loop).
  public var stableSourceLocations: Bool
  /// `--full-swift`: the tree is compiled as full Swift (the development profile), so `embedded-feature-condition` makes
  /// every `hasFeature(Embedded)` condition true.
  public var fullSwift: Bool
  /// The file's path relative to the lowered root, as the report names it. `stable-source-locations` writes it into the
  /// directives (`path|key`); nil in a test that lowers a bare source.
  public var sourcePath: String?
  /// `--live-literals`: the file's path relative to the lowered root, for an application file; `nil` leaves
  /// its literals as written (`live-literals`).
  public var liveLiteralsFile: String?
  /// `--development-exports`: the entry file gets the development loop's entry points (`browser-exports`).
  public var developmentExports: Bool

  public init(
    lowerCodable: Bool = false, moduleAliases: Bool = false, observableTypes: Set<String> = [], exportInterface: Bool = false,
    genericTypeNames: Set<String> = [], exportInterfaceApplication: Bool = false, stableSourceLocations: Bool = false,
    fullSwift: Bool = false, sourcePath: String? = nil, liveLiteralsFile: String? = nil, developmentExports: Bool = false
  ) {
    self.lowerCodable = lowerCodable
    self.moduleAliases = moduleAliases
    self.observableTypes = observableTypes
    self.exportInterface = exportInterface
    self.genericTypeNames = genericTypeNames
    self.exportInterfaceApplication = exportInterfaceApplication
    self.stableSourceLocations = stableSourceLocations
    self.fullSwift = fullSwift
    self.sourcePath = sourcePath
    self.liveLiteralsFile = liveLiteralsFile
    self.developmentExports = developmentExports
  }
}

/// One pass over a source file. A transform parses the text it is given, computes edits against that tree and
/// returns the edited text, so the next transform parses what this one produced, as the previous passes read each
/// other's output.
public protocol SourceTransform: Sendable {
  /// The pass name `--rules` selects it by.
  var name: String { get }
  /// Whether the pass applies to a file lowered with `options`.
  func applies(to options: LoweringOptions) -> Bool
  func transform(_ text: String, options: LoweringOptions, counts: inout RuleCounts) throws -> String
}

public struct LoweringResult: Sendable {
  public var text: String
  public var counts: RuleCounts
}

/// The ordered list of transforms. The order is the previous lowerer's order for the passes that exist here.
public struct LoweringPipeline: Sendable {
  public let transforms: [any SourceTransform]

  public init(transforms: [any SourceTransform]) {
    self.transforms = transforms
  }

  /// Every pass, in the order they run. The
  /// Codable import is the one step that has its own entry: it is decided after `as-data-bridge`.
  public static let ported: [any SourceTransform] = [
    LiveLiteralsTransform(),
    ModelMacroTransform(),
    ErrorInterpolationTransform(),
    ObservableTransform(),
    EmbeddedCodableTransform(),
    TaskCheckCancellationTransform(),
    PlatformConditionTransform(),
    ProtocolExtensionTransform(),
    PreviewRemovalTransform(),
    WeakReferenceTransform(),
    QuerySortTransform(),
    DefaultsCastTransform(),
    TypeOfTestTransform(),
    EnvironmentEntryTransform(),
    DataBridgeTransform(),
    EmbeddedCodableImportTransform(),
    TableSortingTransform(),
    SimpleRulesTransform(),
    FinalClassTransform(),
    ErrorDescriptionTransform(),
    ObservableStateTransform(),
    PublishedImportTransform(),
    StateMemberIDTransform(),
    ViewInputComparisonTransform(),
    StateInstallationTransform(),
    RendererSPITransform(),
    BrowserExportsTransform(),
    EmbeddedConditionTransform(),
    ExportInterfaceTransform(),
    StableSourceLocationsTransform(),
  ]

  public static var standard: LoweringPipeline { LoweringPipeline(transforms: ported) }

  /// The checks and rewrites that belong to the workspace driver and not to one source file: Combine is rejected before
  /// anything is lowered, and the product's `Package.swift` gets its linker exports after the sources are lowered.
  public static let driverPasses = ["combine-diagnostics", "linker-exports"]

  public static var passNames: [String] {
    var seen = Set<String>()
    return (ported.map(\.name) + driverPasses).filter { seen.insert($0).inserted }
  }

  /// A pipeline limited to the named passes, or `nil` when a name is not a ported pass.
  public func selecting(_ names: [String]) -> LoweringPipeline? {
    let known = Set(transforms.map(\.name)).union(Self.driverPasses)
    guard names.allSatisfy(known.contains) else { return nil }
    return LoweringPipeline(transforms: transforms.filter { names.contains($0.name) })
  }

  /// Lowers one source. Throws a `LoweringError` for a source the lowerer refuses to rewrite.
  public func lower(_ source: String, options: LoweringOptions) throws -> LoweringResult {
    var options = options
    if transforms.contains(where: { $0.name == ObservableStateTransform.passName }) {
      // The classes the file declares are known to `observable-state` even after `observable` has removed the attribute
      // that names them, so they are read from the source the pipeline was given.
      options.observableTypes.formUnion(try ObservableTypeScan.names(in: source, options: options, modelMacro: transforms.contains(where: { $0.name == "model-macro" })))
    }
    var text = source
    var counts = RuleCounts()
    for transform in transforms where transform.applies(to: options) {
      do {
        text = try transform.transform(text, options: options, counts: &counts)
      } catch let error as LoweringError where error.code == "SWUI-L003" {
        // The edit's offset is into the text this pass was given, which an earlier pass may have changed.
        throw LoweringError(code: error.code, message: "rule \(transform.name): \(error.message)", offset: error.offset)
      }
    }
    return LoweringResult(text: text, counts: counts)
  }
}
