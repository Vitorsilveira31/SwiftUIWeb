import Foundation

/// The per-file result cache behind `--cache PATH`. A file's lowering and its observable-type scan are pure functions of
/// its text, the options and the lowerer itself, so an entry is keyed by all of them and stored as one JSON file below
/// the cache directory. The entry keeps the original text too: a hit requires it to be byte-identical to the file being
/// lowered, which guards against a hash collision.
///
/// The cache is an optimisation only. A missing, unreadable or corrupt entry is a miss, and a write that fails is ignored,
/// so no cache problem can fail a build.
struct LoweringCache: Sendable {
  /// Bumped when the meaning of an entry changes.
  static let formatVersion = "1"

  /// The check of a list of fields: each field is prefixed with its length, so moving text from one field to another
  /// changes the check. It detects a damaged or edited entry; it is not a security hash.
  static func fieldsCheck(_ fields: [String]) -> String {
    SourceMap.stableHash(fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "\n"))
  }

  /// The entries of a file lowered by the pipeline. `check` is written with the entry, so a read whose fields no longer
  /// match it is a miss, and the lowering runs again and rewrites the entry.
  struct Lowered: Codable {
    var source: String
    var lowered: String
    var counts: RuleCounts
    var check: String

    init(source: String, lowered: String, counts: RuleCounts) {
      self.source = source
      self.lowered = lowered
      self.counts = counts
      self.check = Self.fieldsCheck(source: source, lowered: lowered, counts: counts)
    }

    var isIntact: Bool { check == Self.fieldsCheck(source: source, lowered: lowered, counts: counts) }

    private static func fieldsCheck(source: String, lowered: String, counts: RuleCounts) -> String {
      LoweringCache.fieldsCheck([source, lowered] + counts.sorted { $0.key < $1.key }.flatMap { [$0.key, String($0.value)] })
    }
  }

  /// What the report says about a lowered file, which is a function of its original and lowered text: the two hashes and
  /// the line map, the mappings and the located declarations as the JSON the report holds (`JSONValue.pretty()`).
  struct Record {
    var sourceHash: String
    var generatedHash: String
    var lineMap: String
    var mappings: String
    var virtualFiles: String
    /// The check of the fields above as they were when the record was made. `encoded` writes this value, not a fresh one,
    /// so a record changed after it was made is written with a check that no longer matches and is read back as a miss.
    var check: String

    /// The entry's file: a line with the two hashes, the check and the UTF-8 lengths of the three texts, then the texts.
    /// Not JSON: the texts are megabytes of JSON already, and escaping them into a JSON string and back costs more than the read.
    var encoded: Data {
      var data = Data("\(sourceHash) \(generatedHash) \(check) \(lineMap.utf8.count) \(mappings.utf8.count) \(virtualFiles.utf8.count)\n".utf8)
      data.append(contentsOf: lineMap.utf8); data.append(contentsOf: mappings.utf8); data.append(contentsOf: virtualFiles.utf8)
      return data
    }

    init(sourceHash: String, generatedHash: String, lineMap: String, mappings: String, virtualFiles: String) {
      self.sourceHash = sourceHash; self.generatedHash = generatedHash; self.lineMap = lineMap; self.mappings = mappings; self.virtualFiles = virtualFiles
      self.check = LoweringCache.fieldsCheck([sourceHash, generatedHash, lineMap, mappings, virtualFiles])
    }

    init?(encoded data: Data) {
      guard let newline = data.firstIndex(of: 0x0A), let header = String(data: data[data.startIndex..<newline], encoding: .utf8) else { return nil }
      let fields = header.split(separator: " ")
      guard fields.count == 6, let first = Int(fields[3]), let second = Int(fields[4]), let third = Int(fields[5]), first >= 0, second >= 0, third >= 0 else { return nil }
      let start = data.index(after: newline)
      // The lengths come from the file: an overflowing sum is a corrupt entry, which is a miss.
      let (partial, overflowed) = first.addingReportingOverflow(second)
      let (total, overflowedTotal) = partial.addingReportingOverflow(third)
      guard !overflowed, !overflowedTotal, data.distance(from: start, to: data.endIndex) == total else { return nil }
      let a = data.index(start, offsetBy: first), b = data.index(a, offsetBy: second)
      guard let lineMap = String(data: data[start..<a], encoding: .utf8), let mappings = String(data: data[a..<b], encoding: .utf8),
        let virtualFiles = String(data: data[b...], encoding: .utf8)
      else { return nil }
      let sourceHash = String(fields[0]), generatedHash = String(fields[1])
      // An entry whose fields do not match the check written with them was damaged or edited: it is a miss.
      guard LoweringCache.fieldsCheck([sourceHash, generatedHash, lineMap, mappings, virtualFiles]) == String(fields[2]) else { return nil }
      self.init(sourceHash: sourceHash, generatedHash: generatedHash, lineMap: lineMap, mappings: mappings, virtualFiles: virtualFiles)
    }
  }

  /// The observable-type names a file declares. `check` is written with the entry, as for `Lowered`.
  struct Scan: Codable {
    var source: String
    var names: [String]
    var check: String

    init(source: String, names: [String]) {
      self.source = source
      self.names = names
      self.check = LoweringCache.fieldsCheck([source] + names)
    }

    var isIntact: Bool { check == LoweringCache.fieldsCheck([source] + names) }
  }

  let directory: String
  /// Identifies the running lowerer binary (path, size and modification time), so a rebuilt lowerer never reuses entries.
  let identity: String

  init(directory: String) {
    self.directory = directory
    self.identity = Self.binaryIdentity()
  }

  /// Makes the directory; a failure is ignored, and every later read misses and every write is dropped.
  func prepare() {
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  }

  func loweredKey(relative: String, original: String, passNames: [String], options: LoweringOptions) -> String {
    Self.hash([
      Self.formatVersion,
      identity,
      "lowered",
      passNames.joined(separator: ","),
      "lower-codable=\(options.lowerCodable)",
      "module-aliases=\(options.moduleAliases)",
      "observable-types=" + options.observableTypes.sorted().joined(separator: ","),
      "export-interface=\(options.exportInterface)",
      "export-interface-application=\(options.exportInterfaceApplication)",
      "live-literals=\(options.liveLiteralsFile ?? "")",
      "development-exports=\(options.developmentExports)",
      "generic-types=" + options.genericTypeNames.sorted().joined(separator: ","),
      "stable-source-locations=\(options.stableSourceLocations)",
      "full-swift=\(options.fullSwift)",
      relative,
      original,
    ])
  }

  func scanKey(relative: String, original: String, lowerCodable: Bool) -> String {
    Self.hash([
      Self.formatVersion,
      identity,
      "observable-scan",
      "lower-codable=\(lowerCodable)",
      relative,
      original,
    ])
  }

  /// The key of a file's generic-type scan. It is a separate scan from the observable one, so the two never share an entry.
  func genericScanKey(relative: String, original: String) -> String {
    Self.hash([
      Self.formatVersion,
      identity,
      "generic-type-scan",
      relative,
      original,
    ])
  }

  func loweredEntry(for key: String, source: String) -> Lowered? {
    guard let entry: Lowered = read(key), entry.source.utf8.elementsEqual(source.utf8), entry.isIntact else { return nil }
    return entry
  }

  /// The key of a lowered file's report record: its lowering's key, which already holds the original text, the passes
  /// and the options.
  func recordKey(loweredKey: String) -> String { Self.hash([Self.formatVersion, identity, "report-record", loweredKey]) }

  func recordEntry(for key: String) -> Record? { FileManager.default.contents(atPath: path(key)).flatMap(Record.init(encoded:)) }

  func store(_ record: Record, key: String) { try? record.encoded.write(to: URL(fileURLWithPath: path(key)), options: .atomic) }

  func scanEntry(for key: String, source: String) -> Set<String>? {
    guard let entry: Scan = read(key), entry.source.utf8.elementsEqual(source.utf8), entry.isIntact else { return nil }
    return Set(entry.names)
  }

  func store(_ entry: Lowered, key: String) {
    write(entry, key: key)
  }

  func store(_ names: Set<String>, source: String, key: String) {
    write(Scan(source: source, names: names.sorted()), key: key)
  }

  /// Deletes the entries of this directory that the run did not use, so the cache stays bounded. Only files named like
  /// a cache key are touched.
  func prune(keeping used: Set<String>) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where Self.isEntryName(name) && !used.contains(String(name.dropLast(".json".count))) {
      try? FileManager.default.removeItem(atPath: FileSystem.join(directory, name))
    }
  }

  // MARK: Storage

  private func path(_ key: String) -> String {
    FileSystem.join(directory, key + ".json")
  }

  private func read<Entry: Decodable>(_ key: String) -> Entry? {
    guard let data = FileManager.default.contents(atPath: path(key)) else { return nil }
    return try? JSONDecoder().decode(Entry.self, from: data)
  }

  private func write<Entry: Encodable>(_ entry: Entry, key: String) {
    guard let data = try? JSONEncoder().encode(entry) else { return }
    try? data.write(to: URL(fileURLWithPath: path(key)), options: .atomic)
  }

  // MARK: Keys

  static func hash(_ fields: [String]) -> String {
    SourceMap.stableHash(fields.joined(separator: "\n"))
  }

  /// Cache keys are 16 lowercase hex digits followed by `.json`.
  private static func isEntryName(_ name: String) -> Bool {
    guard name.hasSuffix(".json") else { return false }
    let stem = name.dropLast(".json".count)
    return stem.count == 16 && stem.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  /// The running lowerer: its resolved path, size and modification time. `unknown` when none of them can be read.
  static func binaryIdentity() -> String {
    guard let argv0 = CommandLine.arguments.first, !argv0.isEmpty, let path = executablePath(argv0) else { return "unknown" }
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return "unknown" }
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
    return "\(path)|\(size)|\(modified)"
  }

  /// `argv[0]` as a path: used as given when it names a file, looked up on `PATH` when it is a bare name.
  private static func executablePath(_ argv0: String) -> String? {
    if argv0.contains("/") {
      return URL(fileURLWithPath: argv0).resolvingSymlinksInPath().path
    }
    let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
    for directory in directories {
      let candidate = FileSystem.join(String(directory), argv0)
      if FileManager.default.isExecutableFile(atPath: candidate) {
        return URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
      }
    }
    return nil
  }
}

/// Collects one result per index from concurrent workers. Each index is written once, under a lock.
final class ResultSlots<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Value?]

  init(count: Int) {
    values = Array(repeating: nil, count: count)
  }

  func set(_ value: Value, at index: Int) {
    lock.withLock { values[index] = value }
  }

  /// Every value in index order. Call only after all workers have finished.
  var all: [Value] {
    lock.withLock { values.map { $0! } }
  }
}
