import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

// Measures how faithfully the native Fiber packed mutation records describe the
// change between two serialized snapshots of the same tree. This is a
// measurement suite: it records divergences as data (printed and written to
// `.build/render-mutation-fidelity.json`) and only asserts invariants that must
// hold regardless of the outcome (e.g. secrets never reach serialized HTML).
//
// Scope: native FiberTree with packed recording ON (the default natively) and
// `StaticHTMLFiberRenderer`. The Embedded browser snapshot copy
// (`_embeddedBrowserSnapshot` in SwiftUIWebBrowser/BrowserApp.swift) is
// wasm-only and NOT exercised here, so node ids, event tokens, secure ids,
// lazy indices, keep placeholders and root annotations are out of scope of
// these numbers. Nothing in this file changes renderer behavior.

// MARK: - Minimal HTML reader for StaticHTMLFiberRenderer output

private final class _FidelityDOMNode {
  let isText: Bool
  var open: String
  var text: String
  var children: [_FidelityDOMNode] = []
  init(isText: Bool, open: String = "", text: String = "") {
    self.isText = isText; self.open = open; self.text = text
  }
}

private let _fidelityVoidTags: Set<String> = [
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link",
  "meta", "param", "source", "track", "wbr"
]

/// The serializer escapes `& < > " '` in attribute values and text, so a `<`
/// always starts a tag and a `>` always ends one. Raw HTML nodes are not used
/// by the fixtures.
private func _fidelityParse(_ html: String) -> _FidelityDOMNode {
  let bytes = Array(html.utf8)
  let root = _FidelityDOMNode(isText: false, open: "#root")
  var stack: [_FidelityDOMNode] = [root]
  var index = 0
  while index < bytes.count {
    if bytes[index] == UInt8(ascii: "<") {
      var end = index
      while end < bytes.count, bytes[end] != UInt8(ascii: ">") { end += 1 }
      let tagBytes = Array(bytes[index...min(end, bytes.count - 1)])
      let tag = String(decoding: tagBytes, as: UTF8.self)
      if tagBytes.count > 1, tagBytes[1] == UInt8(ascii: "/") {
        if stack.count > 1 { stack.removeLast() }
      } else {
        var nameEnd = 1
        while nameEnd < tagBytes.count, tagBytes[nameEnd] != UInt8(ascii: " "), tagBytes[nameEnd] != UInt8(ascii: ">") { nameEnd += 1 }
        let name = String(decoding: tagBytes[1..<nameEnd], as: UTF8.self)
        let element = _FidelityDOMNode(isText: false, open: tag)
        stack[stack.count - 1].children.append(element)
        if !_fidelityVoidTags.contains(name.lowercased()) { stack.append(element) }
      }
      index = end + 1
    } else {
      var end = index
      while end < bytes.count, bytes[end] != UInt8(ascii: "<") { end += 1 }
      let text = String(decoding: bytes[index..<end], as: UTF8.self)
      let parent = stack[stack.count - 1]
      if let last = parent.children.last, last.isText { last.text += text }
      else { parent.children.append(_FidelityDOMNode(isText: true, text: text)) }
      index = end
    }
  }
  return root
}

/// Parses ` name="value"` pairs out of a serialized open tag.
private func _fidelityAttributes(_ open: String) -> (tag: String, attributes: [String: String])? {
  guard open.hasPrefix("<") else { return nil }
  let bytes = Array(open.utf8)
  var index = 1
  while index < bytes.count, bytes[index] != UInt8(ascii: " "), bytes[index] != UInt8(ascii: ">") { index += 1 }
  let tag = String(decoding: bytes[1..<index], as: UTF8.self)
  var attributes: [String: String] = [:]
  while index < bytes.count {
    while index < bytes.count, bytes[index] == UInt8(ascii: " ") { index += 1 }
    var nameEnd = index
    while nameEnd < bytes.count, bytes[nameEnd] != UInt8(ascii: "="), bytes[nameEnd] != UInt8(ascii: ">") { nameEnd += 1 }
    guard nameEnd < bytes.count, bytes[nameEnd] == UInt8(ascii: "=") else { break }
    let name = String(decoding: bytes[index..<nameEnd], as: UTF8.self)
    let valueStart = nameEnd + 2
    var valueEnd = valueStart
    while valueEnd < bytes.count, bytes[valueEnd] != UInt8(ascii: "\"") { valueEnd += 1 }
    attributes[name] = String(decoding: bytes[min(valueStart, bytes.count)..<min(valueEnd, bytes.count)], as: UTF8.self)
    index = valueEnd + 1
  }
  return (tag, attributes)
}

// MARK: - Snapshot of a Fiber tree with in-context serialization

private struct _FidelityNodeInfo {
  var parent: StructuralNodeID?
  var children: [StructuralNodeID]
  var kind: String
  /// Shallow serialization of the node alone (open tag, or text / span+text).
  var isolated: String
  /// Shallow serialization of the same node as found in the full-tree output.
  var context: String?
  /// Nearest element ancestor (the DOM parent) and index among its DOM children.
  var domParent: StructuralNodeID?
  var domIndex: Int?
  var leafBound: Bool
  var events: [String]
}

private struct _FidelitySnapshot {
  var nodes: [StructuralNodeID: _FidelityNodeInfo] = [:]
  var order: [StructuralNodeID] = []
  var alignmentIssues: [String] = []
  var mergedTextNodes = 0
}

@MainActor private func _fidelityIsolated(_ node: _RenderNode) -> String {
  switch node.kind {
  case .empty, .fragment: return ""
  case .text:
    let copy = node.cloneSharingChildren(); copy.children = []
    return StaticHTMLFiberRenderer().renderNode(copy)
  case .element:
    let copy = node.cloneSharingChildren(); copy.children = []
    let html = StaticHTMLFiberRenderer().renderNode(copy)
    if let end = html.firstIndex(of: ">") { return String(html[...end]) }
    return html
  }
}

@MainActor private func _fidelitySnapshot(_ tree: FiberTree) -> _FidelitySnapshot {
  var snapshot = _FidelitySnapshot()
  func collect(_ fiber: Fiber, parent: StructuralNodeID?) {
    let node = fiber.renderNode
    snapshot.order.append(fiber.structuralID)
    snapshot.nodes[fiber.structuralID] = _FidelityNodeInfo(
      parent: parent,
      children: fiber.children.map(\.structuralID),
      kind: node.kind.displayName,
      isolated: _fidelityIsolated(node),
      context: nil, domParent: nil, domIndex: nil,
      leafBound: !node.leafBindings.isEmpty,
      events: node.events.keys.sorted()
    )
    for child in fiber.children { collect(child, parent: fiber.structuralID) }
  }
  collect(tree.root, parent: nil)

  let html = StaticHTMLFiberRenderer().renderNode(tree.root.renderNode)
  let dom = _fidelityParse(html)
  var issues: [String] = []
  var merged = 0
  func assign(_ id: StructuralNodeID, _ value: String, domParent: StructuralNodeID?, domIndex: Int) {
    snapshot.nodes[id]?.context = value
    snapshot.nodes[id]?.domParent = domParent
    snapshot.nodes[id]?.domIndex = domIndex
  }
  func align(_ fiber: Fiber, _ list: [_FidelityDOMNode], _ cursor: inout Int, _ textOffset: inout Int, domParent: StructuralNodeID?) {
    let node = fiber.renderNode
    switch node.kind {
    case .empty:
      assign(fiber.structuralID, "", domParent: domParent, domIndex: cursor)
    case .fragment:
      assign(fiber.structuralID, "", domParent: domParent, domIndex: cursor)
      for child in fiber.children { align(child, list, &cursor, &textOffset, domParent: domParent) }
    case .text:
      let plain = node.attributes.isEmpty && node.styles.isEmpty && node.classes.isEmpty && node.events.isEmpty
      if plain {
        let escaped = StaticHTMLFiberRenderer().renderNode(.text(node.text ?? ""))
        if escaped.isEmpty { assign(fiber.structuralID, "", domParent: domParent, domIndex: cursor); return }
        guard cursor < list.count, list[cursor].isText else {
          issues.append("text \(fiber.structuralID) has no DOM text node"); return
        }
        let run = Array(list[cursor].text.utf8)
        let piece = Array(escaped.utf8)
        let startOffset = textOffset
        guard startOffset + piece.count <= run.count, Array(run[startOffset..<(startOffset + piece.count)]) == piece else {
          issues.append("text \(fiber.structuralID) does not match its DOM run"); return
        }
        assign(fiber.structuralID, escaped, domParent: domParent, domIndex: cursor)
        textOffset += piece.count
        if startOffset > 0 || textOffset < run.count { merged += 1 }
        if textOffset == run.count { cursor += 1; textOffset = 0 }
      } else {
        if textOffset != 0 { issues.append("element after partial text run"); cursor += 1; textOffset = 0 }
        guard cursor < list.count, !list[cursor].isText else {
          issues.append("span \(fiber.structuralID) has no DOM element"); return
        }
        let element = list[cursor]
        assign(fiber.structuralID, element.open + element.children.map { $0.isText ? $0.text : $0.open }.joined() + "</span>", domParent: domParent, domIndex: cursor)
        cursor += 1
      }
    case .element:
      if textOffset != 0 { issues.append("element after partial text run"); cursor += 1; textOffset = 0 }
      guard cursor < list.count, !list[cursor].isText else {
        issues.append("element \(fiber.structuralID) has no DOM element"); return
      }
      let element = list[cursor]
      assign(fiber.structuralID, element.open, domParent: domParent, domIndex: cursor)
      cursor += 1
      var childCursor = 0
      var childOffset = 0
      for child in fiber.children { align(child, element.children, &childCursor, &childOffset, domParent: fiber.structuralID) }
      if childCursor != element.children.count, !(childCursor == element.children.count - 1 && childOffset > 0) {
        issues.append("element \(fiber.structuralID) children consumed \(childCursor)/\(element.children.count)")
      }
    }
  }
  var cursor = 0
  var offset = 0
  align(tree.root, dom.children, &cursor, &offset, domParent: nil)
  snapshot.alignmentIssues = issues
  snapshot.mergedTextNodes = merged
  return snapshot
}

// MARK: - Decoded records

private struct _FidelityRecord {
  let opcode: _PackedMutationOpcode
  let target: StructuralNodeID?
  let parent: StructuralNodeID?
  let previous: _RenderNode?
  let next: _RenderNode?
  let index: Int
  let destination: Int
}

@MainActor private func _fidelityDecode(_ buffer: _PackedMutationBuffer) -> [_FidelityRecord] {
  (0..<buffer.recordCount).compactMap { position in
    guard let record = buffer.record(at: position) else { return nil }
    let count = Int((record.flags >> 24) & 0xff)
    let first = buffer.node(at: record.value)
    let second = count > 1 ? buffer.node(at: record.value &+ 1) : nil
    return _FidelityRecord(
      opcode: record.opcode,
      target: buffer.structuralID(at: record.target),
      parent: buffer.structuralID(at: record.argument),
      previous: first,
      next: second ?? first,
      index: Int(record.index),
      destination: Int(record.flags & 0x00ff_ffff)
    )
  }
}

// MARK: - Results

private final class _FidelityResults {
  struct Category {
    var transitions = 0
    var opcodes: [String: Int] = [:]
    var falseNegatives = 0
    var leafChannelCovered = 0
    var falsePositives = 0
    var localityDivergences = 0
    var localityAttributes: [String: Int] = [:]
    var updateRecords = 0
    var directlyApplicable = 0
    var needsStructure = 0
    var noDOMEffect = 0
    var opKinds: [String: Int] = [:]
    var orderingChecks = 0
    var orderingLiteralPass = 0
    var orderingDeclarativePass = 0
    var orderingIndexOrderPass = 0
    var recordedMoves = 0
    var minimalMoves = 0
    var domIndexTranslations = 0
    var mergedTextNodes = 0
    var alignmentIssues = 0
    var sideChannels: [String: Int] = [:]
  }
  var categories: [String: Category] = [:]
  var transitions: [[String: Any]] = []

  func write() {
    var categoryJSON: [String: Any] = [:]
    for (name, value) in categories {
      categoryJSON[name] = [
        "transitions": value.transitions,
        "opcodes": value.opcodes,
        "falseNegatives": value.falseNegatives,
        "leafChannelCovered": value.leafChannelCovered,
        "falsePositives": value.falsePositives,
        "localityDivergences": value.localityDivergences,
        "localityAttributes": value.localityAttributes,
        "updateRecords": value.updateRecords,
        "updateDirectlyApplicable": value.directlyApplicable,
        "updateNeedsStructure": value.needsStructure,
        "updateNoDOMEffect": value.noDOMEffect,
        "updateOpKinds": value.opKinds,
        "orderingChecks": value.orderingChecks,
        "orderingLiteralSequentialPass": value.orderingLiteralPass,
        "orderingDeclarativePass": value.orderingDeclarativePass,
        "orderingRemoveThenIndexOrderPass": value.orderingIndexOrderPass,
        "recordedMoves": value.recordedMoves,
        "minimalMoves": value.minimalMoves,
        "domIndexTranslations": value.domIndexTranslations,
        "mergedAdjacentTextNodes": value.mergedTextNodes,
        "alignmentIssues": value.alignmentIssues,
        "sideChannels": value.sideChannels,
      ] as [String: Any]
    }
    let payload: [String: Any] = [
      "note": "Native FiberTree + StaticHTMLFiberRenderer only; the Embedded snapshot injections (BrowserApp.swift) are not exercised.",
      "categories": categoryJSON,
      "transitions": transitions,
    ]
    // The report goes to the host's disk (`HostFiles`), where the tools that read it look.
    let packageRoot = HostFiles.parent(HostFiles.parent(HostFiles.directory()))
    let output = packageRoot + "/.build/render-mutation-fidelity.json"
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
       HostFiles.write(Array(data), to: output) {
      print("render-mutation-fidelity: wrote \(output)")
    }
    for name in categories.keys.sorted() {
      let value = categories[name]!
      print("render-mutation-fidelity,category=\(name),transitions=\(value.transitions),opcodes=\(value.opcodes.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: "/")),fn=\(value.falseNegatives),leafCovered=\(value.leafChannelCovered),fp=\(value.falsePositives),locality=\(value.localityDivergences)\(value.localityAttributes.isEmpty ? "" : "[" + value.localityAttributes.keys.sorted().joined(separator: ",") + "]"),updates=\(value.updateRecords),direct=\(value.directlyApplicable),structure=\(value.needsStructure),noDOM=\(value.noDOMEffect),ops=\(value.opKinds.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: "/")),ordering=\(value.orderingChecks)/literal:\(value.orderingLiteralPass)/declarative:\(value.orderingDeclarativePass)/indexOrder:\(value.orderingIndexOrderPass),moves=\(value.recordedMoves)/min:\(value.minimalMoves),domIndexTranslations=\(value.domIndexTranslations),mergedText=\(value.mergedTextNodes),alignmentIssues=\(value.alignmentIssues),side=\(value.sideChannels.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: "/"))")
    }
  }
}

private func _fidelityOpcodeName(_ opcode: _PackedMutationOpcode) -> String {
  switch opcode {
  case .insert: return "insert"
  case .remove: return "remove"
  case .update: return "update"
  case .replace: return "replace"
  case .move: return "move"
  }
}

/// Classifies one changed serialized attribute as a direct DOM op kind.
private func _fidelityAttributeOpKind(_ name: String) -> String {
  if name == "class" { return "class" }
  if name == "style" { return "style" }
  if name.hasPrefix("data-fiber-event-") { return "event-attr" }
  return "attr"
}

private func _fidelityLIS(_ values: [Int]) -> Int {
  var tails: [Int] = []
  for value in values {
    var low = 0, high = tails.count
    while low < high { let mid = (low + high) / 2; if tails[mid] < value { low = mid + 1 } else { high = mid } }
    if low == tails.count { tails.append(value) } else { tails[low] = value }
  }
  return tails.count
}

// MARK: - Transition analysis

@MainActor private func _fidelityTransition(
  _ results: _FidelityResults,
  category: String,
  name: String,
  tree: FiberTree,
  sideChannels: (() -> [String])? = nil,
  dropRecords: Set<_PackedMutationOpcode> = [],
  change: () -> Void
) {
  _ = tree.renderNode
  let before = _fidelitySnapshot(tree)
  let flushesBefore = tree.metrics.schedulerStructuralFlushes + tree.metrics.schedulerSubtreeFlushes
  let leafBefore = tree.metrics.bindingCellUpdates
  change()
  _ = tree.renderNode
  let flushed = tree.metrics.schedulerStructuralFlushes + tree.metrics.schedulerSubtreeFlushes > flushesBefore
  let leafUpdates = tree.metrics.bindingCellUpdates - leafBefore
  // `dropRecords` exists only for the detector's negative control below.
  let records = flushed ? _fidelityDecode(tree._lastPackedMutations).filter { !dropRecords.contains($0.opcode) } : []
  let after = _fidelitySnapshot(tree)
  let side = sideChannels?() ?? []

  var stats = results.categories[category] ?? .init()
  stats.transitions += 1
  stats.mergedTextNodes += after.mergedTextNodes
  stats.alignmentIssues += after.alignmentIssues.count + before.alignmentIssues.count
  for channel in side { stats.sideChannels[channel, default: 0] += 1 }
  var opcodeCounts: [String: Int] = [:]
  for record in records { opcodeCounts[_fidelityOpcodeName(record.opcode), default: 0] += 1 }
  for (key, value) in opcodeCounts { stats.opcodes[key, default: 0] += value }

  let updates = Set(records.filter { $0.opcode == .update }.compactMap(\.target))
  let replaces = Set(records.filter { $0.opcode == .replace }.compactMap(\.target))
  let inserts = records.filter { $0.opcode == .insert }.compactMap(\.target)
  let removes = records.filter { $0.opcode == .remove }.compactMap(\.target)
  func descendants(of id: StructuralNodeID, in snapshot: _FidelitySnapshot, includingSelf: Bool) -> Set<StructuralNodeID> {
    var result: Set<StructuralNodeID> = includingSelf ? [id] : []
    var stack = snapshot.nodes[id]?.children ?? []
    while let next = stack.popLast() {
      result.insert(next)
      stack.append(contentsOf: snapshot.nodes[next]?.children ?? [])
    }
    return result
  }
  var coveredNew = Set<StructuralNodeID>()
  for id in inserts { coveredNew.formUnion(descendants(of: id, in: after, includingSelf: true)) }
  for id in replaces { coveredNew.formUnion(descendants(of: id, in: after, includingSelf: false)) }
  var coveredOld = Set<StructuralNodeID>()
  for id in removes { coveredOld.formUnion(descendants(of: id, in: before, includingSelf: true)) }
  for id in replaces { coveredOld.formUnion(descendants(of: id, in: before, includingSelf: false)) }

  var falseNegatives: [String] = []
  var falsePositives: [String] = []
  var leafCovered = 0
  let structuralParents = Set(records.filter { $0.opcode == .insert || $0.opcode == .remove || $0.opcode == .move }.compactMap(\.parent))
  for id in after.order {
    if coveredNew.contains(id) { continue }
    guard let new = after.nodes[id] else { continue }
    guard let old = before.nodes[id] else {
      falseNegatives.append("new node \(id.index):\(id.generation) (\(new.kind)) outside insert/replace")
      continue
    }
    if old.context != new.context, !updates.contains(id), !replaces.contains(id) {
      if new.leafBound, leafUpdates > 0 { leafCovered += 1 }
      else { falseNegatives.append("\(new.kind) \(id.index):\(id.generation): '\(old.context ?? "nil")' -> '\(new.context ?? "nil")'") }
    }
    if old.children != new.children, !replaces.contains(id), !structuralParents.contains(id) {
      falseNegatives.append("children of \(new.kind) \(id.index):\(id.generation) changed without structural records")
    }
  }
  for id in before.order where after.nodes[id] == nil && !coveredOld.contains(id) && !replaces.contains(id) {
    falseNegatives.append("node \(id.index):\(id.generation) disappeared without remove")
  }
  for id in updates {
    if let old = before.nodes[id], let new = after.nodes[id], old.context == new.context {
      let record = records.first { $0.opcode == .update && $0.target == id }
      var reasons: [String] = []
      if let previous = record?.previous, let next = record?.next {
        if previous.kind == .fragment || previous.kind == .empty { reasons.append("non-DOM kind \(previous.kind.displayName)") }
        if previous.attributes != next.attributes { reasons.append("attributes") }
        if previous.events.keys.sorted() != next.events.keys.sorted() { reasons.append("events \(previous.events.keys.sorted()) -> \(next.events.keys.sorted())") }
        if previous.taskRegistrations.map(\.key) != next.taskRegistrations.map(\.key) { reasons.append("tasks") }
        if previous.text != next.text { reasons.append("text") }
        if previous.styles != next.styles { reasons.append("styles") }
        if previous.classes != next.classes { reasons.append("classes") }
      }
      falsePositives.append("\(new.kind) \(id.index):\(id.generation) [\(reasons.joined(separator: "; "))]")
    }
  }
  stats.falseNegatives += falseNegatives.count
  stats.falsePositives += falsePositives.count
  stats.leafChannelCovered += leafCovered

  // Locality and representability.
  var locality: [String] = []
  var updateOps: [[String: Any]] = []
  for record in records where record.opcode == .update || record.opcode == .replace {
    guard let id = record.target, let next = record.next, let previous = record.previous else { continue }
    let isolatedNew = _fidelityIsolated(next)
    let inContext = after.nodes[id]?.context ?? ""
    if isolatedNew != inContext {
      stats.localityDivergences += 1
      let a = _fidelityAttributes(isolatedNew)?.attributes ?? [:]
      let b = _fidelityAttributes(inContext)?.attributes ?? [:]
      let names = Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.sorted()
      for name in names { stats.localityAttributes[name, default: 0] += 1 }
      if names.isEmpty { stats.localityAttributes["<non-attribute>", default: 0] += 1 }
      locality.append("\(id.index):\(id.generation) isolated='\(isolatedNew)' context='\(inContext)'")
    }
    guard record.opcode == .update else { continue }
    stats.updateRecords += 1
    let oldShallow = _fidelityIsolated(previous)
    var ops: [String] = []
    var structural = false
    switch (previous.kind, next.kind) {
    case (.fragment, _), (.empty, _):
      break
    case (.text, .text):
      let oldPlain = !oldShallow.hasPrefix("<span"), newPlain = !isolatedNew.hasPrefix("<span")
      if oldPlain != newPlain { structural = true; ops.append("text<->span") }
      else if oldPlain { if previous.text != next.text { ops.append("text") } }
      else {
        if previous.text != next.text { ops.append("text") }
        let a = _fidelityAttributes(oldShallow)?.attributes ?? [:], b = _fidelityAttributes(isolatedNew)?.attributes ?? [:]
        for name in Set(a.keys).union(b.keys) where a[name] != b[name] { ops.append(_fidelityAttributeOpKind(name)) }
      }
    case (.element, .element):
      let a = _fidelityAttributes(oldShallow), b = _fidelityAttributes(isolatedNew)
      if a?.tag != b?.tag { structural = true; ops.append("tag") }
      else {
        let x = a?.attributes ?? [:], y = b?.attributes ?? [:]
        for name in Set(x.keys).union(y.keys) where x[name] != y[name] {
          ops.append(_fidelityAttributeOpKind(name) + (y[name] == nil ? "-remove" : x[name] == nil ? "-add" : ""))
        }
      }
    default:
      structural = true; ops.append("kind")
    }
    if structural { stats.needsStructure += 1 }
    else if ops.isEmpty { stats.noDOMEffect += 1 }
    else { stats.directlyApplicable += 1 }
    for op in ops { stats.opKinds[op, default: 0] += 1 }
    updateOps.append(["target": "\(id.index):\(id.generation)", "ops": ops, "structural": structural])
  }

  // Ordering / identity per parent.
  var ordering: [[String: Any]] = []
  for parent in structuralParents.sorted(by: { ($0.index, $0.generation) < ($1.index, $1.generation) }) {
    guard let oldList = before.nodes[parent]?.children, let newList = after.nodes[parent]?.children else { continue }
    let ops = records.filter { $0.parent == parent && ($0.opcode == .insert || $0.opcode == .remove || $0.opcode == .move) }
    stats.orderingChecks += 1
    // (a) literal: apply each record's indices in emission order to the current array.
    var literal = oldList
    for op in ops {
      guard let id = op.target else { continue }
      switch op.opcode {
      case .move:
        if op.index < literal.count { literal.remove(at: op.index) }
        literal.insert(id, at: min(op.destination, literal.count))
      case .insert: literal.insert(id, at: min(op.index, literal.count))
      case .remove: if op.index < literal.count { literal.remove(at: op.index) }
      default: break
      }
    }
    // (b) declarative: movers/inserts at their destination, unmoved survivors keep old index.
    let removed = Set(ops.filter { $0.opcode == .remove }.compactMap(\.target))
    let moved = Set(ops.filter { $0.opcode == .move }.compactMap(\.target))
    let insertedCount = ops.filter { $0.opcode == .insert }.count
    var slots = [StructuralNodeID?](repeating: nil, count: max(0, oldList.count - removed.count + insertedCount))
    var declarativeOK = true
    func place(_ id: StructuralNodeID, _ index: Int) {
      if index < slots.count, slots[index] == nil { slots[index] = id } else { declarativeOK = false }
    }
    for op in ops { if let id = op.target { if op.opcode == .move { place(id, op.destination) } else if op.opcode == .insert { place(id, op.index) } } }
    for (index, id) in oldList.enumerated() where !removed.contains(id) && !moved.contains(id) { place(id, index) }
    let declarative = declarativeOK && slots.allSatisfy { $0 != nil } && slots.compactMap { $0 } == newList
    // (c) remove by identity first, then moves/inserts in ascending destination.
    var indexOrder = oldList.filter { !removed.contains($0) }
    let placements = ops.filter { $0.opcode != .remove }.map { ($0.target!, $0.opcode == .move ? $0.destination : $0.index) }.sorted { $0.1 < $1.1 }
    for (id, destination) in placements {
      indexOrder.removeAll { $0 == id }
      indexOrder.insert(id, at: min(destination, indexOrder.count))
    }
    if literal == newList { stats.orderingLiteralPass += 1 }
    if declarative { stats.orderingDeclarativePass += 1 }
    if indexOrder == newList { stats.orderingIndexOrderPass += 1 }
    let survivors = newList.filter { oldList.contains($0) }
    let oldPositions = Dictionary(uniqueKeysWithValues: oldList.enumerated().map { ($1, $0) })
    let minimal = survivors.count - _fidelityLIS(survivors.compactMap { oldPositions[$0] })
    stats.recordedMoves += moved.count
    stats.minimalMoves += minimal
    for op in ops where op.opcode != .remove {
      guard let id = op.target, let domIndex = after.nodes[id]?.domIndex else { continue }
      let fiberIndex = op.opcode == .move ? op.destination : op.index
      if domIndex != fiberIndex || after.nodes[id]?.domParent != parent { stats.domIndexTranslations += 1 }
    }
    ordering.append([
      "parent": "\(parent.index):\(parent.generation)",
      "parentKind": after.nodes[parent]?.kind ?? "?",
      "old": oldList.count, "new": newList.count,
      "records": ops.map { "\(_fidelityOpcodeName($0.opcode))(\($0.index)\($0.opcode == .move ? "->\($0.destination)" : ""))" },
      "literalSequential": literal == newList,
      "declarative": declarative,
      "removeThenIndexOrder": indexOrder == newList,
      "recordedMoves": moved.count,
      "minimalMoves": minimal,
    ])
  }
  results.categories[category] = stats
  results.transitions.append([
    "category": category,
    "name": name,
    "reconciled": flushed,
    "leafUpdates": leafUpdates,
    "records": opcodeCounts,
    "falseNegatives": falseNegatives,
    "falsePositives": falsePositives,
    "locality": locality,
    "updates": updateOps,
    "ordering": ordering,
    "sideChannels": side,
    "alignmentIssues": before.alignmentIssues + after.alignmentIssues,
  ])
}

// MARK: - Fixtures

private struct _FidelityCounter: View {
  @State private var count = 0
  var body: some View {
    VStack {
      Text("count \(count)")
      Button("increment") { count += 1 }
    }
  }
}

private struct _FidelityTextInput: View {
  @State private var text = ""
  var body: some View {
    VStack {
      TextField("Name", text: $text)
      Text("static label")
    }
  }
}

private struct _FidelitySecureInput: View {
  @State private var secret = ""
  let showsLength: Bool
  var body: some View {
    VStack {
      SecureField("Password", text: $secret)
      if showsLength { Text("length \(secret.count)") }
    }
  }
}

private struct _FidelityAnimated: View {
  @State private var on = false
  let implicit: Bool
  var body: some View {
    VStack {
      if implicit {
        Text("fade").opacity(on ? 1 : 0.25).animation(.easeInOut, value: on)
      } else {
        Text("fade").opacity(on ? 1 : 0.25)
      }
      Button("toggle") {
        if implicit { on.toggle() } else { withAnimation(.easeInOut) { on.toggle() } }
      }
    }
  }
}

private struct _FidelityEnvironmentReader: View {
  @Environment(\.colorScheme) private var scheme
  var body: some View { Text(scheme == .dark ? "dark" : "light") }
}

@MainActor private func _fidelityTree<V: View>(_ view: V) -> FiberTree {
  let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
  tree.setExternalInvalidationHandler({}, deferUpdates: true)
  return tree
}

/// Runs a root-driven sequence: each step reconciles `make(step)` against the
/// retained tree, exactly as a root pass with new view values does.
@MainActor private func _fidelityRootSequence<V: View>(
  _ results: _FidelityResults,
  category: String,
  name: String,
  steps: [Int],
  sideChannels: (() -> [String])? = nil,
  _ make: @escaping (Int) -> V
) {
  guard let first = steps.first else { return }
  let tree = _fidelityTree(AnyView(make(first)))
  var previous = first
  for step in steps.dropFirst() {
    _fidelityTransition(results, category: category, name: "\(name) \(previous)->\(step)", tree: tree, sideChannels: sideChannels) {
      _ = tree._updateForRenderer(AnyView(make(step)))
    }
    previous = step
  }
}

// MARK: - Suite

@Suite(.serialized)
@MainActor
struct RenderMutationFidelityTests {
  @Test
  func measureFiberRecordFidelityAcrossCategories() {
    let results = _FidelityResults()

    // Environment-derived attributes changing at an ancestor.
    _fidelityRootSequence(results, category: "environment", name: "disabled", steps: [0, 1, 0]) { step in
      VStack {
        Button("Save") {}
        TextField("Name", text: .constant("v"))
        Toggle("Flag", isOn: .constant(true))
        Text("label")
      }.disabled(step == 1)
    }
    _fidelityRootSequence(results, category: "environment", name: "colorScheme", steps: [0, 1, 0]) { step in
      VStack { _FidelityEnvironmentReader(); Text("other") }
        .environment(\.colorScheme, step == 1 ? .dark : .light)
    }
    _fidelityRootSequence(results, category: "environment", name: "font", steps: [0, 1, 2]) { step in
      VStack { Text("title"); HStack { Text("a"); Text("b") } }
        .font(step == 0 ? .body : step == 1 ? .title : .caption)
    }
    _fidelityRootSequence(results, category: "environment", name: "foregroundStyle", steps: [0, 1, 0]) { step in
      VStack { Text("a"); Image(systemName: "star"); Button("b") {} }
        .foregroundStyle(step == 1 ? Color.red : Color.blue)
    }

    // Event handler identity: closure capture changes, handler added/removed.
    var hits: [Int] = []
    let handlerTree = _fidelityTree(AnyView(Button("Tap") { hits.append(0) }))
    for value in 1...3 {
      _fidelityTransition(results, category: "eventHandler", name: "closure capture \(value - 1)->\(value)", tree: handlerTree) {
        _ = handlerTree._updateForRenderer(AnyView(Button("Tap") { hits.append(value) }))
      }
      handlerTree.dispatch(event: "click")
    }
    results.transitions.append(["category": "eventHandler", "name": "closure dispatch after update", "dispatchedValues": hits])
    _fidelityRootSequence(results, category: "eventHandler", name: "onTapGesture added/removed", steps: [0, 1, 0]) { step in
      VStack {
        if step == 1 { Text("target").onTapGesture {} } else { Text("target") }
      }
    }
    _fidelityRootSequence(results, category: "eventHandler", name: "button disabled removes click", steps: [0, 1, 0]) { step in
      Button("Go") {}.disabled(step == 1)
    }
    _fidelityRootSequence(results, category: "eventHandler", name: "onHover added/removed", steps: [0, 1, 0]) { step in
      Text("hover").onHover { _ in if step == 1 { hits.append(-1) } }
    }

    // Styles / modifiers propagating to descendants.
    _fidelityRootSequence(results, category: "styleModifier", name: "padding/background/opacity on container", steps: [0, 1, 2]) { step in
      VStack { Text("one"); Text("two") }
        .padding(CGFloat(8 + step * 4))
        .background(step == 2 ? Color.green : Color.gray)
        .opacity(step == 1 ? 0.5 : 1)
    }
    _fidelityRootSequence(results, category: "styleModifier", name: "tint and bold", steps: [0, 1]) { step in
      VStack { Button("tinted") {}; Toggle("t", isOn: .constant(step == 1)); Text("bold").bold(step == 1) }
        .tint(step == 1 ? Color.orange : Color.blue)
    }

    // Parent-context layout.
    _fidelityRootSequence(results, category: "parentLayout", name: "VStack alignment/spacing", steps: [0, 1, 2]) { step in
      VStack(alignment: step == 0 ? .leading : step == 1 ? .center : .trailing, spacing: CGFloat(4 * (step + 1))) {
        Text("a"); Text("bb"); Text("ccc")
      }
    }
    _fidelityRootSequence(results, category: "parentLayout", name: "frame size/alignment", steps: [0, 1]) { step in
      Text("framed").frame(width: step == 0 ? 100 : 200, height: 40, alignment: step == 0 ? .leading : .bottomTrailing)
    }
    _fidelityRootSequence(results, category: "parentLayout", name: "HStack<->VStack", steps: [0, 1, 0]) { step in
      Group {
        if step == 0 { HStack { Text("x"); Text("y") } } else { VStack { Text("x"); Text("y") } }
      }
    }
    _fidelityRootSequence(results, category: "parentLayout", name: "Spacer/frame maxWidth", steps: [0, 1]) { step in
      HStack { Text("left"); if step == 1 { Spacer() }; Text("right") }.frame(maxWidth: step == 1 ? .infinity : nil)
    }

    // Animations / transactions.
    for implicit in [false, true] {
      let tree = _fidelityTree(_FidelityAnimated(implicit: implicit))
      for index in 0..<2 {
        _fidelityTransition(results, category: "animation", name: implicit ? "animation(value:) #\(index)" : "withAnimation #\(index)", tree: tree, sideChannels: {
          tree.root.stateStore._takeAnimationTransactionCSS() != nil ? ["animationTransactionCSS"] : []
        }) {
          tree.dispatch(event: "click")
        }
      }
    }

    // SecureField value changes (must never be serialized).
    for showsLength in [false, true] {
      let tree = _fidelityTree(_FidelitySecureInput(showsLength: showsLength))
      for (index, value) in ["hunter2", "hunter22", ""].enumerated() {
        _fidelityTransition(results, category: "secureField", name: "secure value #\(index) showsLength=\(showsLength)", tree: tree) {
          tree.dispatch(event: "input", value: value)
        }
        let html = StaticHTMLFiberRenderer().renderNode(tree.renderNode)
        if !value.isEmpty { #expect(!html.contains(value)) }
      }
    }
    // The leaf channel (what a direct-op host would forward) carries the secret.
    do {
      let tree = _fidelityTree(_FidelitySecureInput(showsLength: false))
      _ = tree.renderNode
      tree.dispatch(event: "input", value: "s3cret")
      let leaf = tree._drainLeafUpdates(preservingPackedMutations: true)
      results.transitions.append([
        "category": "secureField",
        "name": "leaf channel payload",
        "leafUpdates": leaf.count,
        "leafOperations": leaf.map { "\($0.operation)" },
        "leafValueEqualsSecret": leaf.contains { $0.value == "s3cret" },
      ])
      var stats = results.categories["secureField"] ?? .init()
      if leaf.contains(where: { $0.value == "s3cret" }) { stats.sideChannels["leafUpdateCarriesSecret", default: 0] += 1 }
      results.categories["secureField"] = stats
    }

    // TextField leaf binding (value written into the _RenderNode without a record).
    do {
      let tree = _fidelityTree(_FidelityTextInput())
      for (index, value) in ["a", "ab", ""].enumerated() {
        _fidelityTransition(results, category: "leafBinding", name: "TextField value #\(index)", tree: tree) {
          tree.dispatch(event: "input", value: value)
        }
      }
    }

    // Keyed list reorders / inserts / removes / moves.
    let sequences: [[Int]] = [[1, 2, 3, 4, 5], [5, 1, 2, 3, 4], [5, 1, 3, 4], [5, 1, 6, 3, 4], [4, 3, 6, 1, 5], [2, 4, 6], [], [1, 2], [2, 1]]
    for header in [false, true] {
      let tree = _fidelityTree(AnyView(VStack { if header { Text("header") }; ForEach(sequences[0], id: \.self) { Text("row \($0)") } }))
      for index in 1..<sequences.count {
        let ids = sequences[index]
        _fidelityTransition(results, category: "keyedList", name: "header=\(header) \(sequences[index - 1])->\(ids)", tree: tree) {
          _ = tree._updateForRenderer(AnyView(VStack { if header { Text("header") }; ForEach(ids, id: \.self) { Text("row \($0)") } }))
        }
      }
    }
    do {
      struct Item { let id: Int; let value: String }
      func rows(_ items: [Item]) -> AnyView {
        AnyView(List { ForEach(items, id: \.id) { item in HStack { Text("item \(item.id)"); Text(item.value) } } })
      }
      let a = [Item(id: 1, value: "x"), Item(id: 2, value: "y"), Item(id: 3, value: "z")]
      let b = [Item(id: 3, value: "z!"), Item(id: 1, value: "x"), Item(id: 4, value: "new")]
      let tree = _fidelityTree(rows(a))
      _fidelityTransition(results, category: "keyedList", name: "List reorder+content+insert+remove", tree: tree) { _ = tree._updateForRenderer(rows(b)) }
      _fidelityTransition(results, category: "keyedList", name: "List back", tree: tree) { _ = tree._updateForRenderer(rows(a)) }
    }

    // Text changes.
    _fidelityRootSequence(results, category: "text", name: "plain text", steps: [0, 1, 2]) { step in
      VStack { Text("value \(step)"); Text("constant") }
    }
    _fidelityRootSequence(results, category: "text", name: "adjacent concatenated text", steps: [0, 1]) { step in
      Text("a\(step)") + Text("b").bold()
    }
    do {
      let tree = _fidelityTree(_FidelityCounter())
      for index in 0..<3 {
        _fidelityTransition(results, category: "text", name: "@State counter #\(index)", tree: tree) { tree.dispatch(event: "click") }
      }
    }

    // Conditional replace.
    _fidelityRootSequence(results, category: "conditional", name: "if/else Text<->Button", steps: [0, 1, 0]) { step in
      VStack { if step == 0 { Text("A") } else { Button("B") {} } }
    }
    _fidelityRootSequence(results, category: "conditional", name: "optional view", steps: [0, 1, 0]) { step in
      VStack { Text("before"); if step == 1 { Text("inserted").padding() }; Text("after") }
    }
    _fidelityRootSequence(results, category: "conditional", name: "AnyView type switch", steps: [0, 1]) { step in
      step == 0 ? AnyView(Text("text")) : AnyView(Image(systemName: "star"))
    }

    // Negative control: the same kinds of transitions with records withheld
    // must be reported as false negatives, proving the detector is live.
    do {
      let tree = _fidelityTree(AnyView(VStack { Text("v0"); ForEach([1, 2], id: \.self) { Text("r\($0)") } }))
      _fidelityTransition(results, category: "zzControlDroppedRecords", name: "update withheld", tree: tree, dropRecords: [.update]) {
        _ = tree._updateForRenderer(AnyView(VStack { Text("v1"); ForEach([1, 2], id: \.self) { Text("r\($0)") } }))
      }
      _fidelityTransition(results, category: "zzControlDroppedRecords", name: "structure withheld", tree: tree, dropRecords: [.insert, .remove, .move]) {
        _ = tree._updateForRenderer(AnyView(VStack { Text("v1"); ForEach([3, 1], id: \.self) { Text("r\($0)") } }))
      }
      #expect((results.categories["zzControlDroppedRecords"]?.falseNegatives ?? 0) >= 3)
    }

    results.write()
    // Invariants that must hold independent of the measurement.
    #expect(!results.categories.isEmpty)
    #expect(hits.suffix(3) == [1, 2, 3])
  }
}
