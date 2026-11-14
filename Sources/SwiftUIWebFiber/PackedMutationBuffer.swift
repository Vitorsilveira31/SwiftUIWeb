import SwiftUIWebCore

#if !hasFeature(Embedded)

/// Compact semantic mutation opcodes used by the retained structural graph.
///
/// `Mutation` remains the compatibility representation exposed by the
/// historical FiberRuntimeAdapter API.  The reconciler itself records into
/// this buffer first: records are fixed-width UInt32 words, _RenderNode values
/// live in one contiguous side table, and parent/Fiber references are resolved
/// by generational IDs. This keeps the
/// browser hot path free of an enum allocation per operation while retaining
/// enough information to materialize the old API when a host requests it.
@_spi(Renderer) public enum _PackedMutationOpcode: UInt32, Sendable {
  case insert = 1
  case remove = 2
  case update = 3
  case replace = 4
  case move = 5
}

/// A decoded record view. The backing storage remains the six-word
/// `words` array; this struct is created on demand for diagnostics, tests and
/// browser adapters and is not retained by the reconciler.
@_spi(Renderer) public struct _PackedMutationRecord: Equatable, Sendable {
  public static let wordStride = 6

  public let opcode: _PackedMutationOpcode
  /// Index into `structuralIDs` (or `noReference`).
  public let target: UInt32
  /// Index into `structuralIDs` for a parent/argument identity.
  public let argument: UInt32
  /// Start index into the compact _RenderNode side table (or `noReference`).
  public let value: UInt32
  /// Operation-specific integer argument (insert/remove index, move source).
  public let index: UInt32
  /// Bit flags describing payload shape.  The low bits are intentionally
  /// stable so a future binary browser protocol can consume records without
  /// knowing Swift enum layout.
  public let flags: UInt32

  public init(
    opcode: _PackedMutationOpcode,
    target: UInt32,
    argument: UInt32 = _PackedMutationBuffer.noReference,
    value: UInt32 = _PackedMutationBuffer.noReference,
    index: UInt32 = 0,
    flags: UInt32 = 0
  ) {
    self.opcode = opcode
    self.target = target
    self.argument = argument
    self.value = value
    self.index = index
    self.flags = flags
  }
}

/// Reusable packed mutation storage.  The buffer is a class deliberately: a
/// FiberTree owns one instance and resets it between commits, so recursive
/// reconciliation never triggers copy-on-write of the command arrays.
@MainActor @_spi(Renderer) public final class _PackedMutationBuffer {
  public nonisolated static let noReference: UInt32 = .max

  /// Whether reconciliation writes records at all. The Embedded browser host
  /// patches the DOM from the published HTML snapshot and never reads these
  /// records, so it turns this off and skips both the word appends and the
  /// retained node references. Hosts that inspect or materialize mutations
  /// (native adapters, tests) keep the default.
  public var isRecording = true

  /// Six UInt32 words per record: opcode, target ID reference, argument ID
  /// reference, payload index, operation index/source, flags.
  public private(set) var words: [UInt32] = []
  /// Deduplicated generational structural IDs referenced by records.
  public private(set) var structuralIDs: [StructuralNodeID] = []
  /// _RenderNode references needed to apply or materialize a mutation. For an
  /// insert/remove/move record this table contains one node; update/replace
  /// records contain previous and new nodes consecutively. Parent/Fiber
  /// objects are deliberately not retained per record: they are resolved from
  /// the target/argument StructuralNodeID through `ownerRoot`.
  public private(set) var nodes: [_RenderNode] = []

  private var structuralIndices: [StructuralNodeID: UInt32] = [:]
  private var lastStructuralID: StructuralNodeID?
  private var lastStructuralReference: UInt32 = .max
  private var ownerRoot: Fiber?

  public init(reserveCapacity: Int = 0) {
    if reserveCapacity > 0 {
      nodes.reserveCapacity(reserveCapacity * 2)
      structuralIDs.reserveCapacity(min(reserveCapacity * 2, 4096))
    }
  }

  public var recordCount: Int { words.count / _PackedMutationRecord.wordStride }
  public var wordCount: Int { words.count }
  /// Approximate retained storage, useful for release benchmarks. It counts
  /// contiguous words, ID entries and fixed payload values, but not the heap
  /// allocations owned by _RenderNode/Fiber references themselves.
  public var storageByteCount: Int {
    words.count * MemoryLayout<UInt32>.stride
      + structuralIDs.count * (MemoryLayout<UInt32>.stride * 2)
      + nodes.count * MemoryLayout<AnyObject>.stride
  }

  /// Clears records while retaining capacity and reusing the dictionary and
  /// side tables on the next commit.
  public func reset() {
    words.removeAll(keepingCapacity: true)
    structuralIDs.removeAll(keepingCapacity: true)
    nodes.removeAll(keepingCapacity: true)
    structuralIndices.removeAll(keepingCapacity: true)
    lastStructuralID = nil
    lastStructuralReference = Self.noReference
  }

  /// Associates the retained root used to resolve parent/Fiber references
  /// during compatibility materialization. The root is not part of the wire
  /// representation and is never exposed to application code.
  package func setOwnerRoot(_ root: Fiber) { ownerRoot = root }

  @inline(__always)
  private func structuralReference(_ id: StructuralNodeID?) -> UInt32 {
    guard let id else { return Self.noReference }
    if lastStructuralID == id { return lastStructuralReference }
    if let existing = structuralIndices[id] {
      lastStructuralID = id
      lastStructuralReference = existing
      return existing
    }
    let index = UInt32(structuralIDs.count)
    structuralIDs.append(id)
    structuralIndices[id] = index
    lastStructuralID = id
    lastStructuralReference = index
    return index
  }

  @inline(__always)
  @discardableResult
  private func appendRecord(
    _ opcode: _PackedMutationOpcode,
    targetID: StructuralNodeID?,
    argumentID: StructuralNodeID? = nil,
    primary: _RenderNode? = nil,
    secondary: _RenderNode? = nil,
    index: Int = 0,
    flags: UInt32 = 0
  ) -> Int {
    guard isRecording else { return -1 }
    let target = structuralReference(targetID)
    let argument = structuralReference(argumentID)
    let value: UInt32
    if let primary {
      value = UInt32(nodes.count)
      nodes.append(primary)
      if let secondary { nodes.append(secondary) }
    } else { value = Self.noReference }
    let nodeCount = secondary == nil ? (primary == nil ? 0 : 1) : 2
    words.append(opcode.rawValue)
    words.append(target)
    words.append(argument)
    words.append(value)
    words.append(UInt32(clamping: index))
    words.append(flags | (UInt32(nodeCount) << 24))
    return recordCount - 1
  }

  // MARK: Reconciler emission

  @inline(__always)
  package func appendInsert(node: _RenderNode, parent: Fiber, index: Int, targetID: StructuralNodeID) {
    _ = appendRecord(
      .insert,
      targetID: targetID,
      argumentID: parent.structuralID,
      primary: node,
      index: index,
      flags: 1 << 0
    )
  }

  @inline(__always)
  package func appendRemove(node: _RenderNode, parent: Fiber, index: Int, targetID: StructuralNodeID) {
    _ = appendRecord(
      .remove,
      targetID: targetID,
      argumentID: parent.structuralID,
      primary: node,
      index: index,
      flags: 1 << 0
    )
  }

  @inline(__always)
  package func appendUpdate(previous: _RenderNode, new: _RenderNode, fiber: Fiber) {
    _ = appendRecord(
      .update,
      targetID: fiber.structuralID,
      primary: previous,
      secondary: new,
      flags: (1 << 0) | (1 << 1) | (1 << 2)
    )
  }

  @inline(__always)
  package func appendReplace(previous: _RenderNode, new: _RenderNode, fiber: Fiber) {
    _ = appendRecord(
      .replace,
      targetID: fiber.structuralID,
      primary: previous,
      secondary: new,
      flags: (1 << 0) | (1 << 1) | (1 << 2)
    )
  }

  @inline(__always)
  package func appendMove(node: _RenderNode, parent: Fiber, from: Int, to: Int, targetID: StructuralNodeID) {
    _ = appendRecord(
      .move,
      targetID: targetID,
      argumentID: parent.structuralID,
      primary: node,
      index: from,
      // Move destinations fit in the low 24 bits; the high byte is reserved
      // for the node-count marker added by appendRecord. The opcode itself
      // identifies this operation, so no additional move flag is required.
      flags: UInt32(clamping: to) & 0x00ff_ffff
    )
  }

  // MARK: Inspection/materialization

  @inline(__always)
  public func record(at index: Int) -> _PackedMutationRecord? {
    guard index >= 0, index < recordCount else { return nil }
    let words = self.words
    let offset = index * _PackedMutationRecord.wordStride
    guard let opcode = _PackedMutationOpcode(rawValue: words[offset]) else { return nil }
    return _PackedMutationRecord(
      opcode: opcode,
      target: words[offset + 1],
      argument: words[offset + 2],
      value: words[offset + 3],
      index: words[offset + 4],
      flags: words[offset + 5]
    )
  }

  @inline(__always)
  public func structuralID(at reference: UInt32) -> StructuralNodeID? {
    guard reference != Self.noReference, Int(reference) < structuralIDs.count else { return nil }
    return structuralIDs[Int(reference)]
  }

  @inline(__always)
  public func node(at reference: UInt32) -> _RenderNode? {
    guard reference != Self.noReference, Int(reference) < nodes.count else { return nil }
    return nodes[Int(reference)]
  }

  /// Compatibility boundary for callers that still require `[Mutation]`.
  /// Materialization is deliberately explicit and is not used by the
  /// reconciler itself.
  package func materialize() -> [Mutation] {
    var result: [Mutation] = []
    result.reserveCapacity(recordCount)
    var indexedFibers: [StructuralNodeID: Fiber]? = nil
    if recordCount > 16, let ownerRoot {
      var index: [StructuralNodeID: Fiber] = [:]
      index.reserveCapacity(recordCount)
      indexFibers(ownerRoot, into: &index)
      indexedFibers = index
    }
    for index in 0..<recordCount {
      guard let record = record(at: index), record.value != Self.noReference,
            Int(record.value) < nodes.count,
            let ownerRoot else { continue }
      let primary = nodes[Int(record.value)]
      let nodeCount = Int((record.flags >> 24) & 0xff)
      let secondary = nodeCount > 1 && Int(record.value) + 1 < nodes.count ? nodes[Int(record.value) + 1] : nil
      switch record.opcode {
      case .insert:
        guard let parentID = structuralID(at: record.argument), let parent = lookup(parentID, root: ownerRoot, index: indexedFibers) else { continue }
        result.append(.insert(node: primary, parent: parent, index: Int(record.index)))
      case .remove:
        guard let parentID = structuralID(at: record.argument), let parent = lookup(parentID, root: ownerRoot, index: indexedFibers) else { continue }
        result.append(.remove(node: primary, parent: parent, index: Int(record.index)))
      case .update:
        guard let secondary, let targetID = structuralID(at: record.target), let fiber = lookup(targetID, root: ownerRoot, index: indexedFibers) else { continue }
        result.append(.update(previous: primary, new: secondary, fiber: fiber))
      case .replace:
        guard let secondary, let targetID = structuralID(at: record.target), let fiber = lookup(targetID, root: ownerRoot, index: indexedFibers) else { continue }
        result.append(.replace(previous: primary, new: secondary, fiber: fiber))
      case .move:
        guard let parentID = structuralID(at: record.argument), let parent = lookup(parentID, root: ownerRoot, index: indexedFibers) else { continue }
        result.append(.move(node: primary, parent: parent, from: Int(record.index), to: Int(record.flags & 0x00ff_ffff)))
      }
    }
    return result
  }

  private func lookup(_ id: StructuralNodeID, root: Fiber, index: [StructuralNodeID: Fiber]?) -> Fiber? {
    if let index { return index[id] }
    return resolve(id, in: root)
  }

  private func indexFibers(_ fiber: Fiber, into index: inout [StructuralNodeID: Fiber]) {
    index[fiber.structuralID] = fiber
    for child in fiber.children { indexFibers(child, into: &index) }
  }

  private func resolve(_ id: StructuralNodeID, in root: Fiber) -> Fiber? {
    guard root.structuralID != id else { return root }
    for child in root.children {
      if let found = resolve(id, in: child) { return found }
    }
    return nil
  }
}
#else
// The Embedded browser never reads the packed record stream (the host consumes the HTML
// snapshot), so only the entry points the reconciler calls remain, and they do nothing.
// The recording implementation, `materialize()` and the opcode/record types are native-only.
@_spi(Renderer) public final class _PackedMutationBuffer {
  public var isRecording = false
  public init(reserveCapacity: Int = 0) {}
  public var recordCount: Int { 0 }
  public var storageByteCount: Int { 0 }
  public func reset() {}
  package func setOwnerRoot(_ root: Fiber) {}
  package func appendInsert(node: _RenderNode, parent: Fiber, index: Int, targetID: StructuralNodeID) {}
  package func appendRemove(node: _RenderNode, parent: Fiber, index: Int, targetID: StructuralNodeID) {}
  package func appendUpdate(previous: _RenderNode, new: _RenderNode, fiber: Fiber) {}
  package func appendReplace(previous: _RenderNode, new: _RenderNode, fiber: Fiber) {}
  package func appendMove(node: _RenderNode, parent: Fiber, from: Int, to: Int, targetID: StructuralNodeID) {}
  package func materialize() -> [Mutation] { [] }
}
#endif
