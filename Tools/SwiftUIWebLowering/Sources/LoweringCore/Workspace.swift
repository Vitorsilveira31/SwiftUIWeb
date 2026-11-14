import Dispatch
import Foundation

/// Lowers a package, as `swiftuiweb-lowering --apply` does: into a disposable workspace copy (`--workspace`) or in place,
/// with a state file and backups that `--restore` puts back (`WorkspaceRestore`).
///
/// The driver is `apply` and everything it writes around the passes. The files it produces are the build's interface to
/// the lowerer:
///  - the report (`--report`, default `.build/embedded-source-lowering/report.json` below the source root), version 4:
///    `status`, `product`, `files` (the rewritten files, in the order they were lowered; the manifest last when its linker
///    exports were completed), `rules` (the totals), `sourceRoot`, `workspace`, `sourceMap` (one entry per rewritten
///    file: `source`, `generated`, `rules`, `lineMap`, `mappings`, `hashes`) and `diagnostics`;
///  - the state (`--state`, default `.build/embedded-source-lowering/state.json` below the lowered root), version 3:
///    what `--restore` needs, with the content hashes of every rewritten file, next to a backup folder (named after the state file,
///    recorded in the state) that holds the original of each of them;
///  - the summary printed on standard output.
/// `Tools/run-browser-embedded.sh` runs the lowerer in both modes: staged builds use `--workspace`; an opted-in in-place
/// build lowers the checkout and restores it on exit.
public struct WorkspaceLowering {
  public let arguments: LoweringArguments
  public let pipeline: LoweringPipeline
  public let moduleAliases: Bool

  public init(arguments: LoweringArguments, pipeline: LoweringPipeline, moduleAliases: Bool) {
    self.arguments = arguments
    self.pipeline = pipeline
    self.moduleAliases = moduleAliases
  }

  public struct Summary: Sendable {
    /// The files that were rewritten, relative to the lowered root, in the order they were lowered.
    public var changed: [String] = []
    public var perFile: [String: RuleCounts] = [:]
    public var totals: RuleCounts = [:]
    /// The path of the report that was written.
    public var report = ""
    /// Sync mode only: the files written, created or removed in the workspace outside `.build`. Zero means the workspace
    /// is byte-for-byte what the previous run left, so a build of it would find nothing to do.
    public var workspaceChanges: Int?
    /// What the tool prints on standard output.
    public var output = ""
  }

  private static let generatedEntries: Set<String> = [".build", ".git", ".swiftpm", "node_modules", "DerivedData"]

  public func run() throws -> Summary {
    let sourceRoot = try FileSystem.canonical(arguments.rootPath)
    let workspace = arguments.workspacePath.map(FileSystem.absolute)
    var mirror: SyncMirror?
    if let workspace {
      if arguments.syncWorkspace {
        mirror = try syncWorkspace(from: sourceRoot, to: workspace)
      } else {
        try prepareWorkspace(from: sourceRoot, to: workspace)
      }
    }
    let root = workspace ?? sourceRoot

    let statePath = FileSystem.join(root, arguments.statePath)
    if FileSystem.exists(statePath) { throw LoweringArguments.Failure.message("embedded source lowering already active; restore it first") }
    guard let stateDirectory = FileSystem.parent(of: statePath) else { throw LoweringArguments.Failure.message("state path has no parent") }
    let backupName = Self.backupName(forState: statePath)
    let backup = FileSystem.join(stateDirectory, backupName)
    try FileSystem.createDirectories(backup)

    // The conventional host boundary as well as the shared sources: consumer packages keep their browser entry point in a
    // `Web/` target, and a framework checkout keeps the product below `Examples/` (an example) or `Tests/Apps/` (a test app).
    // In sync mode the workspace may still hold the previous run's text, so the sources are read from the source root there
    // (the mirror has found them and the write phase brings the workspace to their final text).
    let contentRoot = mirror == nil ? root : sourceRoot
    var relativePaths: [String] = mirror?.lowered ?? []
    if mirror == nil {
      for folder in ["Sources", "Web"] + Self.productFolders(arguments.product) {
        try collectSwiftFiles(in: FileSystem.join(root, folder), relative: folder, into: &relativePaths)
      }
    }
    relativePaths.sort(by: FileSystem.pathPrecedes)

    if runs("combine-diagnostics") { try rejectCombine(in: relativePaths, root: contentRoot) }

    // Every source is read once, in order: an unreadable file fails the run before anything is written.
    let originals = try relativePaths.map { try FileSystem.readString(FileSystem.join(contentRoot, $0)) }
    let cache = arguments.cachePath.map { LoweringCache(directory: FileSystem.absolute($0)) }
    cache?.prepare()
    var usedKeys = Set<String>()
    let lowerCodable = arguments.lowerCodable
    let paths = relativePaths
    let count = paths.count

    // The @Observable classes of the whole package, read before any file is lowered: a @State in one file can hold a
    // class declared in another. @Model classes count once `model-macro` has made them observable. The scan runs
    // concurrently; the names are merged in the sorted order.
    // A concurrent worker cannot throw: a failed scan is kept in its slot and rethrown after the workers have finished.
    let scans = ResultSlots<Result<(names: Set<String>, key: String?), Error>>(count: count)
    DispatchQueue.concurrentPerform(iterations: count) { index in
      let original = originals[index]
      let scanOptions = LoweringOptions(lowerCodable: lowerCodable)
      do {
        guard let cache else {
          scans.set(.success((names: try ObservableTypeScan.names(in: original, options: scanOptions, modelMacro: true), key: nil)), at: index)
          return
        }
        let key = cache.scanKey(relative: paths[index], original: original, lowerCodable: lowerCodable)
        if let names = cache.scanEntry(for: key, source: original) {
          scans.set(.success((names: names, key: key)), at: index)
          return
        }
        let names = try ObservableTypeScan.names(in: original, options: scanOptions, modelMacro: true)
        cache.store(names, source: original, key: key)
        scans.set(.success((names: names, key: key)), at: index)
      } catch {
        scans.set(.failure(error), at: index)
      }
    }
    var observableTypes = Set<String>()
    for scan in try scans.all.map({ try $0.get() }) {
      observableTypes.formUnion(scan.names)
      if let key = scan.key { usedKeys.insert(key) }
    }

    // The generic types and protocols of the whole run, which `export-interface` needs before it can tell a generic method
    // from a plain one. Only the debug loop's `--export-interface` reads them, so the scan runs only then (or when
    // `--generic-types-out` asks for the names). Like the observable scan, it runs concurrently and is cached per file under
    // its own key.
    var genericTypeNames = Set<String>()
    if arguments.exportInterface || arguments.genericTypesOutPath != nil {
      let generics = ResultSlots<(names: Set<String>, key: String?)>(count: count)
      DispatchQueue.concurrentPerform(iterations: count) { index in
        let original = originals[index]
        guard let cache else {
          generics.set((GenericTypeScan.names(in: original), nil), at: index)
          return
        }
        let key = cache.genericScanKey(relative: paths[index], original: original)
        if let names = cache.scanEntry(for: key, source: original) {
          generics.set((names, key), at: index)
          return
        }
        let names = GenericTypeScan.names(in: original)
        cache.store(names, source: original, key: key)
        generics.set((names, key), at: index)
      }
      for scan in generics.all {
        genericTypeNames.formUnion(scan.names)
        if let key = scan.key { usedKeys.insert(key) }
      }
    }
    // Generic names of other lowerer runs (the framework's, for an application): `--generic-types-in`, one name per line.
    for path in arguments.genericTypesInPaths {
      guard FileSystem.exists(path), !FileSystem.isDirectory(path) else {
        throw LoweringArguments.Failure.message("--generic-types-in: no such file \(path)")
      }
      for line in try FileSystem.readString(path).split(whereSeparator: \.isNewline) {
        let name = line.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { genericTypeNames.insert(name) }
      }
    }
    // `--generic-types-out`: the names this run uses (its own scan and the `--generic-types-in` names), sorted, one per line.
    if let outPath = arguments.genericTypesOutPath {
      let text = genericTypeNames.sorted().map { $0 + "\n" }.joined()
      try FileSystem.write(text, to: FileSystem.absolute(outPath))
    }

    // Lowering runs concurrently; the results are written below in the sorted order, so the outputs do not depend on the
    // schedule, and an error is the one of the first file in that order.
    let options = relativePaths.map {
      LoweringOptions(
        lowerCodable: lowersAsApplication($0), moduleAliases: moduleAliases, observableTypes: observableTypes,
        exportInterface: arguments.exportInterface, genericTypeNames: genericTypeNames,
        exportInterfaceApplication: arguments.exportInterfaceApplication, stableSourceLocations: arguments.stableSourceLocations,
        fullSwift: arguments.fullSwift, sourcePath: $0,
        liveLiteralsFile: arguments.liveLiterals && lowersAsApplication($0) ? $0 : nil,
        developmentExports: arguments.developmentExports
      )
    }
    let pipeline = self.pipeline
    let passNames = pipeline.transforms.map(\.name)
    let lowerings = ResultSlots<Result<(LoweringResult, String?), Error>>(count: count)
    DispatchQueue.concurrentPerform(iterations: count) { index in
      lowerings.set(
        Result {
          try Self.lowerFile(paths[index], original: originals[index], options: options[index], pipeline: pipeline, passNames: passNames, cache: cache)
        },
        at: index
      )
    }
    let outcomes = lowerings.all

    var summary = Summary()
    var records: [String: SourceRecord] = [:]
    var diagnostics: [JSONValue] = []
    for (index, relative) in relativePaths.enumerated() {
      let path = FileSystem.join(root, relative)
      let original = originals[index]
      let (result, key) = try outcomes[index].get()
      if let key { usedKeys.insert(key) }
      diagnostics.append(contentsOf: RuleDiagnostics.entries(for: result.counts, in: original).map { $0.json(file: relative) })
      // A sync run's workspace holds the previous text of every lowered file, so each one is brought to its final text.
      if mirror != nil, try writeLowered(result.text, to: path, source: FileSystem.join(sourceRoot, relative)) { mirror?.changes += 1 }
      guard result.text != original else { continue }
      let backupPath = FileSystem.join(backup, relative)
      try FileSystem.createDirectories(FileSystem.parent(of: backupPath) ?? backup)
      try FileSystem.write(original, to: backupPath)
      if mirror == nil { try FileSystem.write(result.text, to: path) }
      summary.changed.append(relative)
      summary.perFile[relative] = result.counts
      for (rule, amount) in result.counts { summary.totals.add(rule, amount) }
      // The record is most of an unchanged run's time (two line maps and their JSON per file), and it depends only on the
      // two texts: with a cache it is computed once per version of a file.
      let recordKey = key.flatMap { cache?.recordKey(loweredKey: $0) }
      if let recordKey { usedKeys.insert(recordKey) }
      if let recordKey, let cached = cache?.recordEntry(for: recordKey) {
        records[relative] = SourceRecord(
          rules: result.counts, lineMap: .raw(cached.lineMap), mappings: .raw(cached.mappings),
          sourceHash: cached.sourceHash, generatedHash: cached.generatedHash, virtualFiles: .raw(cached.virtualFiles))
        continue
      }
      let lineMap = SourceMap.lineMap(original: original, generated: result.text)
      // `stable-source-locations`: the original line of each located declaration's first line, by its `path|key` file value.
      var virtualFiles: [String: Int] = [:]
      for (file, line) in StableSourceLocationsTransform.declarationLines(in: result.text) where line - 1 < lineMap.count {
        virtualFiles[file] = lineMap[line - 1]
      }
      let record = SourceRecord(
        rules: result.counts,
        lineMap: .array(lineMap.map { .int($0) }),
        mappings: .array(SourceMap.points(original: original, generated: result.text)),
        sourceHash: SourceMap.stableHash(original), generatedHash: SourceMap.stableHash(result.text),
        virtualFiles: .object(virtualFiles.mapValues { .int($0) })
      )
      records[relative] = record
      if let recordKey {
        cache?.store(
          LoweringCache.Record(
            sourceHash: record.sourceHash, generatedHash: record.generatedHash, lineMap: record.lineMap.pretty(atDepth: Self.recordDepth),
            mappings: record.mappings.pretty(atDepth: Self.recordDepth), virtualFiles: record.virtualFiles.pretty(atDepth: Self.recordDepth)),
          key: recordKey)
      }
    }
    if let current = mirror, current.manifest {
      let manifestChanges = try syncManifest(sourceRoot: sourceRoot, root: root, backup: backup, summary: &summary)
      mirror?.changes += manifestChanges
    } else if runs("linker-exports") {
      let patchChanges = try patchLinkerExports(in: root, backup: backup, summary: &summary)
      mirror?.changes += patchChanges
    }
    summary.workspaceChanges = mirror?.changes

    try FileSystem.createDirectories(stateDirectory)
    // A changed file without a record (the manifest, patched by the linker exports) is hashed from its text, so that
    // `--restore` can verify it like the others.
    var hashed = records
    for path in summary.changed where hashed[path] == nil {
      let original = try FileSystem.readString(FileSystem.join(backup, path))
      let lowered = try FileSystem.readString(FileSystem.join(root, path))
      hashed[path] = SourceRecord(
        rules: [:], lineMap: .array([]), mappings: .array([]), sourceHash: SourceMap.stableHash(original),
        generatedHash: SourceMap.stableHash(lowered), virtualFiles: .object([:]))
    }
    let hashes = JSONValue.object(hashed.mapValues { .object(["source": .string($0.sourceHash), "generated": .string($0.generatedHash)]) })
    try FileSystem.write(
      JSONValue.object([
        "version": .int(3),
        "status": .string("LOWERED"),
        "product": .string(arguments.product),
        "files": .array(summary.changed.map { .string($0) }),
        "rules": JSONValue(counts: summary.totals),
        "sourceRoot": .string(sourceRoot),
        "workspace": .string(root),
        "backup": .string(backupName),
        "hashes": hashes,
        "idempotent": .bool(true),
      ]).pretty() + "\n",
      to: statePath
    )

    let report = FileSystem.join(sourceRoot, arguments.reportPath)
    let sourceMap: [JSONValue] = summary.changed.map { path in
      let record = records[path]
      return .object([
        "source": .string(path),
        "generated": .string(FileSystem.join(root, path)),
        "rules": JSONValue(counts: record?.rules ?? [:]),
        "lineMap": record?.lineMap ?? .array([]),
        "mappings": record?.mappings ?? .array([]),
        "virtualFiles": record?.virtualFiles ?? .object([:]),
        "hashes": record.map { .object(["source": .string($0.sourceHash), "generated": .string($0.generatedHash)]) } ?? .null,
      ])
    }
    try FileSystem.createDirectories(FileSystem.parent(of: report).flatMap { $0.isEmpty ? nil : $0 } ?? ".")
    try FileSystem.write(
      JSONValue.object([
        "version": .int(4),
        "status": .string("LOWERED"),
        "product": .string(arguments.product),
        "files": .array(summary.changed.map { .string($0) }),
        "rules": JSONValue(counts: summary.totals),
        "sourceRoot": .string(sourceRoot),
        "workspace": .string(root),
        "sourceMap": .array(sourceMap),
        "diagnostics": .array(diagnostics),
      ]).pretty() + "\n",
      to: report
    )
    if let cache { cache.prune(keeping: usedKeys) }
    summary.report = report
    var output: [String: JSONValue] = [
      "status": .string("LOWERED"),
      "product": .string(arguments.product),
      "files": .int(summary.changed.count),
      "rules": JSONValue(counts: summary.totals),
      "workspace": .string(root),
      "report": .string(report),
    ]
    if let workspaceChanges = summary.workspaceChanges { output["workspaceChanges"] = .int(workspaceChanges) }
    summary.output = JSONValue.object(output).pretty()
    return summary
  }

  /// Lowers one file, from the cache when its entry matches, and returns the result with the cache key used (nil without a
  /// cache). Only a result that passed the idempotency check is stored.
  private static func lowerFile(
    _ relative: String, original: String, options: LoweringOptions, pipeline: LoweringPipeline, passNames: [String], cache: LoweringCache?
  ) throws -> (LoweringResult, String?) {
    var cacheKey: String?
    if let cache {
      let key = cache.loweredKey(relative: relative, original: original, passNames: passNames, options: options)
      cacheKey = key
      if let entry = cache.loweredEntry(for: key, source: original) {
        return (LoweringResult(text: entry.lowered, counts: entry.counts), key)
      }
    }
    let result: LoweringResult
    do {
      result = try pipeline.lower(original, options: options)
    } catch let error as LoweringError {
      throw LoweringArguments.Failure.message(error.formatted(path: relative, source: original))
    }
    if result.text != original {
      // Lowering what was lowered must change nothing: a transform that is not idempotent would give the next build a
      // different workspace, and output the lowerer cannot read again is a lowerer bug.
      let again: LoweringResult
      do {
        again = try pipeline.lower(result.text, options: options)
      } catch let error as LoweringError {
        throw LoweringArguments.Failure.message("\(relative): generated output is not re-parseable: \(error)")
      }
      guard again.text == result.text else {
        throw LoweringArguments.Failure.message("\(relative):1:1: [SWUI-L002] lowering is not idempotent")
      }
    }
    if let cache, let cacheKey {
      cache.store(LoweringCache.Lowered(source: original, lowered: result.text, counts: result.counts), key: cacheKey)
    }
    return (result, cacheKey)
  }

  /// Where a framework checkout keeps a product's sources: an example or a test app, and the code the examples share
  /// (`Examples/CloneKit`), which is application code too and so gets the Codable lowering.
  static func productFolders(_ product: String) -> [String] {
    ["Examples/\(product)", "Tests/Apps/\(product)", "Examples/CloneKit"]
  }

  /// The backup folder of a state file, beside it and named after it (`app-state.json` keeps its originals in
  /// `app-state.backup`). States that share a folder, as the framework's and the application's do in an in-place build, must
  /// not share a backup: restoring one would remove the originals the other needs.
  static func backupName(forState statePath: String) -> String {
    var name = FileSystem.lastComponent(of: statePath)
    if name.hasSuffix(".json") { name.removeLast(".json".count) }
    return (name.isEmpty ? "state" : name) + ".backup"
  }

  /// What the report keeps about one rewritten source.
  /// Where a record's values sit in the report: the report, its `sourceMap`, the file's entry, the value.
  private static let recordDepth = 3

  private struct SourceRecord {
    var rules: RuleCounts
    /// The line map, the mappings and the located declarations as the report holds them (built, or a cached text).
    var lineMap: JSONValue
    var mappings: JSONValue
    var sourceHash: String
    var generatedHash: String
    /// `stable-source-locations`: `path|key` to the original line of the declaration's first line.
    var virtualFiles: JSONValue
  }

  /// The Swift files below `base` (`relative` is its place below the lowered root), like the previous lowerer's walk: a
  /// directory is entered whatever its name, and `.swift` alone is a file without an extension.
  private func collectSwiftFiles(in base: String, relative: String, into output: inout [String]) throws {
    guard FileSystem.exists(base) else { return }
    // Links reach this walk only in place (a workspace holds copies). Lowering one would replace the link or rewrite what
    // it points at, and leaving it would build it unlowered, unlike a workspace run: the run stops and says so.
    func refuse(_ path: String) -> LoweringArguments.Failure {
      .message("in-place lowering cannot lower \(path): it is a symbolic link; lower into a workspace (--workspace) instead")
    }
    if FileSystem.isSymbolicLink(base) { throw refuse(base) }
    for name in try FileSystem.entries(of: base, context: "read") {
      let path = FileSystem.join(base, name)
      let relativePath = "\(relative)/\(name)"
      if FileSystem.isSymbolicLink(path) {
        // Only a link that brings Swift sources is refused; a linked folder of resources is not lowered either way.
        if name.hasSuffix(".swift") || (FileSystem.isLinkToDirectory(path) && FileSystem.containsSwiftFile(path)) { throw refuse(path) }
      } else if FileSystem.isDirectory(path) {
        try collectSwiftFiles(in: path, relative: relativePath, into: &output)
      } else if name.hasSuffix(".swift"), name != ".swift" {
        output.append(relativePath)
      }
    }
  }

  // MARK: Sync workspace

  /// What a sync run found in the source: the `.swift` files that will be lowered (relative, sorted; their text is written by
  /// the write phase) and whether the manifest is written by the sync (it is patched by `syncManifest`).
  private struct SyncMirror {
    var lowered: [String] = []
    var manifest = false
    /// Files written, created or removed in the workspace outside `.build` so far (`Summary.workspaceChanges`).
    var changes = 0
  }

  /// `--sync-workspace`: makes `workspace` an exact mirror of `source`, with the rules of `prepareWorkspace`, but writes a
  /// file only when its bytes differ, so an unchanged file keeps its modification time (`Tools/sync-tree.mjs`). Entries the
  /// source no longer has are removed, except the generated folders (`.build` keeps the lowerer's state). The state and the
  /// backup of the previous sync run go first, so that run does not count as an active lowering.
  private func syncWorkspace(from source: String, to workspace: String) throws -> SyncMirror {
    let statePath = FileSystem.join(workspace, arguments.statePath)
    if FileSystem.exists(statePath) { try FileSystem.removeStale(statePath) }
    if let stateDirectory = FileSystem.parent(of: statePath) {
      let backup = FileSystem.join(stateDirectory, Self.backupName(forState: statePath))
      if FileSystem.exists(backup) { try FileSystem.removeStale(backup) }
    }
    try FileSystem.createDirectories(workspace, context: "create workspace \(workspace)")
    let canonicalWorkspace = (try? FileSystem.canonical(workspace)) ?? workspace
    var mirror = SyncMirror()
    _ = try mirrorTree(source, workspace, relative: "", skipping: canonicalWorkspace, ancestors: [], mirror: &mirror)
    mirror.lowered.sort(by: FileSystem.pathPrecedes)
    return mirror
  }

  /// The `.swift` files this lowerer lowers: the same folders `run()` collects from.
  private func isLowered(_ path: String) -> Bool {
    let folders = ["Sources", "Web"] + Self.productFolders(arguments.product)
    return path.hasSuffix(".swift") && path != ".swift" && folders.contains { path.hasPrefix($0 + "/") }
  }

  /// One directory of the mirror, with `copyTree`'s exclusions and link-cycle check. Returns false when the directory is a
  /// link cycle (it is not kept, as `copyTree` does not copy it). The top level does not count as an ancestor, as in
  /// `prepareWorkspace`.
  @discardableResult
  private func mirrorTree(
    _ source: String, _ destination: String, relative: String, skipping canonicalWorkspace: String, ancestors: [String], mirror: inout SyncMirror
  ) throws -> Bool {
    let canonical = (try? FileSystem.canonical(source)) ?? source
    if ancestors.contains(canonical) { return false }
    if FileSystem.existsWithoutFollowing(destination), !FileSystem.isDirectory(destination) {
      mirror.changes += FileSystem.removedCount(destination)
      try FileSystem.removeStale(destination)
    }
    try FileSystem.createDirectories(destination, context: "create workspace directory \(destination)")
    let childAncestors = relative.isEmpty ? [] : ancestors + [canonical]
    var mirrored = Set<String>()
    for name in try FileSystem.entries(of: source, context: "read workspace source directory") {
      if Self.generatedEntries.contains(name) { continue }
      let from = FileSystem.join(source, name)
      let to = FileSystem.join(destination, name)
      let path = relative.isEmpty ? name : "\(relative)/\(name)"
      if FileSystem.isDirectory(from) || FileSystem.isLinkToDirectory(from) {
        if isCacheDirectory(from) { continue }
        if ((try? FileSystem.canonical(from)) ?? from) == canonicalWorkspace { continue }
        if try mirrorTree(from, to, relative: path, skipping: canonicalWorkspace, ancestors: childAncestors, mirror: &mirror) {
          mirrored.insert(name)
        }
      } else if relative.isEmpty, name == "Package.swift" {
        mirror.manifest = true
        mirrored.insert(name)
      } else if isLowered(path) {
        mirror.lowered.append(path)
        mirrored.insert(name)
      } else {
        if FileSystem.exists(to), FileSystem.isDirectory(to) {
          mirror.changes += FileSystem.removedCount(to)
          try FileSystem.removeStale(to)
        }
        if try FileSystem.copyIfChanged(from: from, to: to) { mirror.changes += 1 }
        mirrored.insert(name)
      }
    }
    // Entries the source does not have any more go; the generated folders stay.
    for name in try FileSystem.entries(of: destination, context: "read workspace directory") where !mirrored.contains(name) {
      if Self.generatedEntries.contains(name) { continue }
      let entry = FileSystem.join(destination, name)
      mirror.changes += FileSystem.removedCount(entry, keeping: Self.generatedEntries)
      try FileSystem.removeStale(entry, keeping: Self.generatedEntries)
    }
    return true
  }

  /// Sync mode: a lowered file's final text goes into the workspace, and only when its bytes differ. A new file gets the
  /// permissions of its source, as the copy of a normal workspace gives it. Returns whether the file was written.
  private func writeLowered(_ text: String, to path: String, source: String) throws -> Bool {
    let created = !FileSystem.exists(path) || FileSystem.isDirectory(path)
    let written = try FileSystem.writeIfChanged(text, to: path)
    if written, created { FileSystem.copyPermissions(from: source, to: path) }
    return written
  }

  // MARK: Workspace copy

  /// Copies the package into `workspace`, leaving out generated output and package caches. The whole package, not a list of
  /// well-known folders: targets, resources and local libraries can live in any directory the manifest names. A workspace
  /// placed inside its own source is never copied into itself.
  private func prepareWorkspace(from source: String, to workspace: String) throws {
    let files = FileManager.default
    if FileSystem.exists(workspace) {
      do {
        try files.removeItem(atPath: workspace)
      } catch {
        throw LoweringArguments.Failure.message("remove previous workspace \(workspace): \(FileSystem.describe(error))")
      }
    }
    try FileSystem.createDirectories(workspace, context: "create workspace \(workspace)")
    let manifests = ["Package.swift", "Package.resolved"]
    for name in manifests where FileSystem.exists(FileSystem.join(source, name)) {
      try FileSystem.copy(from: FileSystem.join(source, name), to: FileSystem.join(workspace, name))
    }
    let canonicalWorkspace = (try? FileSystem.canonical(workspace)) ?? workspace
    for name in try FileSystem.entries(of: source, context: "read workspace source directory") {
      if Self.generatedEntries.contains(name) || manifests.contains(name) { continue }
      let from = FileSystem.join(source, name)
      let to = FileSystem.join(workspace, name)
      if FileSystem.isDirectory(from) || FileSystem.isLinkToDirectory(from) {
        if isCacheDirectory(from) { continue }
        if ((try? FileSystem.canonical(from)) ?? from) == canonicalWorkspace { continue }
        try copyTree(from: from, to: to, skipping: canonicalWorkspace, ancestors: [])
      } else {
        try FileSystem.copy(from: from, to: to)
      }
    }
  }

  /// Build tools mark their caches with a CACHEDIR.TAG; they are build output, and one alone is thousands of files.
  private func isCacheDirectory(_ path: String) -> Bool {
    let tag = FileSystem.join(path, "CACHEDIR.TAG")
    return FileSystem.exists(tag) && !FileSystem.isDirectory(tag)
  }

  /// `skipping` is the workspace, and `ancestors` the canonical directories being copied, so a link cycle cannot recurse.
  private func copyTree(from source: String, to destination: String, skipping: String, ancestors: [String]) throws {
    let canonical = (try? FileSystem.canonical(source)) ?? source
    if ancestors.contains(canonical) { return }
    try FileSystem.createDirectories(destination, context: "create workspace directory \(destination)")
    for name in try FileSystem.entries(of: source, context: "read workspace source directory") {
      // Lowering workspaces are disposable compiler inputs: never copy generated output into them. A consumer example can
      // live under the framework's `Examples/` tree, so copying `.build` would recursively copy the lowerer's own staging
      // directory until the filesystem rejects the path.
      if Self.generatedEntries.contains(name) { continue }
      let from = FileSystem.join(source, name)
      let to = FileSystem.join(destination, name)
      if FileSystem.isDirectory(from) || FileSystem.isLinkToDirectory(from) {
        if isCacheDirectory(from) { continue }
        if ((try? FileSystem.canonical(from)) ?? from) == skipping { continue }
        try copyTree(from: from, to: to, skipping: skipping, ancestors: ancestors + [canonical])
      } else {
        try FileSystem.copy(from: from, to: to)
      }
    }
  }
}
