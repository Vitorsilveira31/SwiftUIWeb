#!/usr/bin/env bun
/*
 * Attribute the initialized data in a Swift/WASM artifact.
 *
 * The standard wasm section only tells us how many bytes are present. Swift's
 * linker map adds the useful second dimension: which archive member and input
 * section supplied those bytes. This tool deliberately has no Binaryen or
 * wasm-tools dependency so it can run in the same minimal CI image as the
 * existing size report.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const input = argument("--wasm") || process.argv[2];
const output = argument("--output");
const mapInput = argument("--link-map");
const requestedQuality = Number(argument("--brotli-quality", process.env.WASM_BROTLI_QUALITY || "11"));
const brotliQuality = Number.isFinite(requestedQuality) ? Math.max(0, Math.min(11, requestedQuality)) : 11;
if (!input || !fs.existsSync(input)) {
  console.error("usage: analyze-wasm-data.js --wasm path/to/app.wasm [--link-map path] [--output report.json]");
  process.exit(64);
}

const file = path.resolve(input);
const bytes = fs.readFileSync(file);
if (bytes.length < 8 || bytes.readUInt32LE(0) !== 0x6d736100 || bytes.readUInt32LE(4) !== 1) {
  console.error(`${file} is not a WebAssembly binary`);
  process.exit(65);
}

function readULEB(buffer, offset, limit = buffer.length) {
  let value = 0;
  let shift = 0;
  let cursor = offset;
  while (cursor < limit) {
    const byte = buffer[cursor++];
    value += (byte & 0x7f) * 2 ** shift;
    if ((byte & 0x80) === 0) return { value, next: cursor };
    shift += 7;
    if (shift > 53) throw new Error("Wasm LEB128 value is too large");
  }
  throw new Error("Truncated Wasm LEB128 value");
}

function readSLEB(buffer, offset, limit = buffer.length) {
  let value = 0;
  let shift = 0;
  let cursor = offset;
  let byte = 0;
  while (cursor < limit) {
    byte = buffer[cursor++];
    value += (byte & 0x7f) * 2 ** shift;
    shift += 7;
    if ((byte & 0x80) === 0) {
      if ((byte & 0x40) !== 0 && shift < 53) value -= 2 ** shift;
      return { value, next: cursor };
    }
    if (shift > 53) throw new Error("Wasm signed LEB128 value is too large");
  }
  throw new Error("Truncated Wasm signed LEB128 value");
}

function skipOffsetExpression(offset, limit) {
  // Active Swift data segments currently use i32.const followed by end. Keep
  // the parser tolerant of global.get and future constant-expression opcodes:
  // the expression is self-delimiting at 0x0b.
  let cursor = offset;
  let value = null;
  while (cursor < limit) {
    const opcode = bytes[cursor++];
    if (opcode === 0x0b) return { next: cursor, value };
    if (opcode === 0x41) {
      const decoded = readSLEB(bytes, cursor, limit);
      cursor = decoded.next;
      value = decoded.value;
    } else if (opcode === 0x42) {
      const decoded = readSLEB(bytes, cursor, limit);
      cursor = decoded.next;
      value = decoded.value;
    } else if (opcode === 0x23) {
      const decoded = readULEB(bytes, cursor, limit);
      cursor = decoded.next;
    } else if (opcode === 0x43) {
      cursor += 4;
    } else if (opcode === 0x44) {
      cursor += 8;
    } else {
      // The expression should be a constant expression. Unknown opcodes are
      // still consumed one byte; the end marker remains authoritative.
    }
  }
  throw new Error("Truncated data-segment offset expression");
}

function parseDataSection(start, end) {
  let cursor = start;
  const count = readULEB(bytes, cursor, end);
  cursor = count.next;
  const segments = [];
  let initializedBytes = 0;
  for (let index = 0; index < count.value; index += 1) {
    const flags = readULEB(bytes, cursor, end);
    cursor = flags.next;
    let memoryIndex = 0;
    let offset = null;
    if (flags.value === 2) {
      const memory = readULEB(bytes, cursor, end);
      memoryIndex = memory.value;
      cursor = memory.next;
      const expression = skipOffsetExpression(cursor, end);
      cursor = expression.next;
      offset = expression.value;
    } else if (flags.value === 0) {
      const expression = skipOffsetExpression(cursor, end);
      cursor = expression.next;
      offset = expression.value;
    } else if (flags.value !== 1) {
      throw new Error(`Unsupported data-segment flags ${flags.value}`);
    }
    const length = readULEB(bytes, cursor, end);
    cursor = length.next;
    const dataStart = cursor;
    const dataEnd = dataStart + length.value;
    if (dataEnd > end) throw new Error("Truncated data segment");
    initializedBytes += length.value;
    segments.push({ index, flags: flags.value, memoryIndex, offset, bytes: length.value });
    cursor = dataEnd;
  }
  return { count: count.value, initializedBytes, segments };
}

function parseMemorySection(start, end) {
  let cursor = start;
  const count = readULEB(bytes, cursor, end);
  cursor = count.next;
  const memories = [];
  for (let index = 0; index < count.value; index += 1) {
    const limits = readULEB(bytes, cursor, end);
    cursor = limits.next;
    const initial = readULEB(bytes, cursor, end);
    cursor = initial.next;
    let maximum = null;
    if (limits.value & 1) {
      const max = readULEB(bytes, cursor, end);
      maximum = max.value;
      cursor = max.next;
    }
    memories.push({ index, flags: limits.value, initialPages: initial.value, maximumPages: maximum, initialBytes: initial.value * 65536, maximumBytes: maximum == null ? null : maximum * 65536 });
  }
  return { count: count.value, memories };
}

let cursor = 8;
let dataSection = null;
let memorySection = null;
const standardNames = new Map([[0, "custom"], [1, "type"], [2, "import"], [3, "function"], [4, "table"], [5, "memory"], [6, "global"], [7, "export"], [8, "start"], [9, "element"], [10, "code"], [11, "data"], [12, "data_count"], [13, "tag"]]);
const sections = [];
while (cursor < bytes.length) {
  const sectionStart = cursor;
  const id = bytes[cursor++];
  const length = readULEB(bytes, cursor);
  cursor = length.next;
  const end = cursor + length.value;
  if (end > bytes.length) throw new Error("Truncated Wasm section");
  sections.push({ id, name: standardNames.get(id) || `section-${id}`, raw: end - sectionStart });
  if (id === 11) dataSection = parseDataSection(cursor, end);
  if (id === 5) memorySection = parseMemorySection(cursor, end);
  cursor = end;
}
if (!dataSection) dataSection = { count: 0, initializedBytes: 0, segments: [] };
dataSection.segments.sort((a, b) => b.bytes - a.bytes);

function classifyArchive(archive, source) {
  const name = archive || "";
  if (name === "lib_FoundationICU.a") return "FoundationICU";
  if (name === "libFoundationInternationalization.a") return "FoundationInternationalization";
  if (name === "libFoundationEssentials.a") return "FoundationEssentials";
  if (name === "libFoundation.a") return "Foundation";
  if (name === "libCoreFoundation.a") return "CoreFoundation";
  if (name === "lib_FoundationCollections.a") return "FoundationCollections";
  if (name === "libswiftCore.a") return "SwiftCore";
  if (name === "libswift_Concurrency.a") return "SwiftConcurrency";
  if (name === "libswiftObservation.a") return "SwiftObservation";
  if (name === "libswift_RegexParser.a") return "SwiftRegexParser";
  if (name === "libswift_StringProcessing.a") return "SwiftStringProcessing";
  if (name === "libswift_RegexBuilder.a") return "SwiftRegexBuilder";
  if (name.endsWith(".a")) return name.replace(/^lib/, "").replace(/\.a$/, "");
  const objlib = source.match(/(?:^|\/)([^/]+)\.objlib\//);
  if (objlib) return objlib[1];
  const module = source.match(/(?:^|\/)(SwiftUIWeb[^/]*?)\.build\//);
  return module ? module[1] : "Application/other";
}

function parseLinkMap(mapPath) {
  if (!mapPath || !fs.existsSync(mapPath)) return null;
  const lines = fs.readFileSync(mapPath, "utf8").split(/\n/);
  let dataStart = null;
  let dataSize = null;
  const rows = [];
  let bssInputBytes = 0;
  let inData = false;
  for (const line of lines) {
    if (!inData) {
      const header = line.match(/^\s*-\s+([0-9a-f]+)\s+([0-9a-f]+)\s+DATA$/i);
      if (header) {
        dataStart = parseInt(header[1], 16);
        dataSize = parseInt(header[2], 16);
        inData = true;
      }
      continue;
    }
    const match = line.match(/^\s*([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+(.*)$/i);
    if (!match) continue;
    // The map columns are alignment, address, size, source. Alignment is
    // useful for diagnostics but must not be mistaken for the address.
    const alignment = parseInt(match[1], 16);
    const address = parseInt(match[2], 16);
    const size = parseInt(match[3], 16);
    if (address >= dataStart + dataSize) break;
    const source = match[4];
    // An input-section row has an archive/object path followed by :(.section).
    // Child symbol rows can contain C++ `::(` text (for example ICU names),
    // so looking for any `:(` would count each symbol a second time. Require
    // the path to end in an archive member or an object-file suffix.
    const inputSection = source.match(/^(.*(?:\.a\([^)]*\)|\.(?:o|obj))):\((.*)$/) || source.match(/^(<internal>):\((.*)$/);
    if (!inputSection) continue;
    const pathPart = inputSection[1];
    const section = `(${inputSection[2].replace(/\)$/, "")})`;
    // wasm-ld prints BSS input rows with an address of zero. They contribute
    // to initial linear memory but not to the initialized Wasm data payload;
    // keep them as a separate diagnostic rather than dropping them silently.
    if (address === 0 && inputSection[2].startsWith(".bss")) {
      bssInputBytes += size;
      continue;
    }
    if (address < dataStart) continue;
    const archiveMatch = pathPart.match(/([^/]+\.a)\(([^)]*)\)/);
    const archive = archiveMatch ? archiveMatch[1] : null;
    rows.push({ alignment, address, size, source: pathPart, section, archive, category: classifyArchive(archive, pathPart) });
  }
  const contributors = new Map();
  for (const row of rows) {
    const current = contributors.get(row.category) || { category: row.category, bytes: 0, entries: 0, largest: [] };
    current.bytes += row.size;
    current.entries += 1;
    current.largest.push({ bytes: row.size, source: row.source, section: row.section });
    contributors.set(row.category, current);
  }
  const normalized = [...contributors.values()].map((entry) => {
    entry.largest.sort((a, b) => b.bytes - a.bytes);
    entry.largest = entry.largest.slice(0, 12);
    entry.percentOfData = dataSize ? entry.bytes / dataSize : 0;
    return entry;
  }).sort((a, b) => b.bytes - a.bytes);
  const attributed = normalized.reduce((total, entry) => total + entry.bytes, 0);
  // Keep the packaged ICU data visible even when future linker-map formats
  // split it across multiple FoundationICU input rows. This is the concrete
  // regression signal used by the Core-only fixture check.
  const icudtBytes = rows
    .filter((row) => /icudt\d+_dat|icu.*data/i.test(row.source) || /icudt\d+_dat/i.test(row.section))
    .reduce((total, row) => total + row.size, 0);
  return {
    path: path.resolve(mapPath), dataStart, dataSize, rows: rows.length,
    attributedBytes: attributed,
    unclassifiedBytes: Math.max(0, dataSize - attributed),
    paddingBytes: Math.max(0, dataSize - attributed),
    bssInputBytes,
    icudtBytes,
    contributors: normalized
  };
}

const report = {
  version: 1,
  artifact: file,
  raw: bytes.length,
  gzip: zlib.gzipSync(bytes, { level: 9, mtime: 0 }).length,
  brotli: zlib.brotliCompressSync(bytes, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: brotliQuality } }).length,
  brotliQuality,
  sections: sections.sort((a, b) => b.raw - a.raw),
  memorySection,
  dataSection,
  linkMap: parseLinkMap(mapInput)
};
if (output) {
  fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
}

console.log("artifact,raw,gzip,brotli,dataBytes,dataSegments");
console.log(`${file},${report.raw},${report.gzip},${report.brotli},${dataSection.initializedBytes},${dataSection.count}`);
if (report.linkMap) {
  console.log("category,bytes,percentOfData,entries");
  for (const entry of report.linkMap.contributors) {
    console.log(`${entry.category},${entry.bytes},${(entry.percentOfData * 100).toFixed(3)},${entry.entries}`);
  }
  console.log(`foundationICUBytes,${report.linkMap.contributors.find((entry) => entry.category === "FoundationICU")?.bytes || 0}`);
  console.log(`icudtBytes,${report.linkMap.icudtBytes || 0}`);
  console.log(`padding,${report.linkMap.paddingBytes},${(report.linkMap.paddingBytes / report.linkMap.dataSize * 100).toFixed(3)},`);
  console.log(`bssInput,${report.linkMap.bssInputBytes},${(report.linkMap.bssInputBytes / report.linkMap.dataSize * 100).toFixed(3)},`);
}
