#!/usr/bin/env bun
// WebAssembly inventory and release audit: every section byte of each final .wasm in a bundle (or one .wasm file),
// the local runtime assets' compressed sizes, and, when a wasm-ld link map is given, a conservative attribution of
// code and data to linker inputs. The module framing is parsed strictly; the attribution only uses matching map rows.
//
//   bun Tools/wasm-audit.mjs <bundle|file.wasm> [--output report.json] [--brotli-quality n] [--max-brotli bytes]
//                            [--link-map map.txt [--map-reference reference.wasm]]
import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, join, relative } from "node:path";
import { spawnSync } from "node:child_process";
import { deflateRawSync, gzipSync } from "node:zlib";
import { fixed } from "./format-compat.mjs";

const MAGIC = Buffer.from("\0asm\x01\0\0\0", "latin1");
const SECTION_NAMES = ["custom", "type", "import", "function", "table", "memory", "global", "export", "start", "element", "code", "data", "data_count", "tag"];

export class AuditError extends Error {}

const sha256 = (data) => createHash("sha256").update(data).digest("hex");
const orZero = (value) => value ?? 0;

export class Reader {
  constructor(data, pos, end) {
    if (pos > end || end > data.length) throw new AuditError("invalid reader bounds");
    Object.assign(this, { data, pos, end });
  }

  take(size) {
    const end = this.pos + size;
    if (end > this.end) throw new AuditError(`truncated data at byte ${this.pos}`);
    const bytes = this.data.subarray(this.pos, end);
    this.pos = end;
    return bytes;
  }

  byte() {
    return this.take(1)[0];
  }

  /** Unsigned LEB128 of at most `bits` bits. */
  uint(bits) {
    let value = 0;
    for (let index = 0; index < Math.ceil(bits / 7); index += 1) {
      const byte = this.byte();
      const shift = index * 7;
      if (shift >= 64 || ((byte & 0x7f) >> Math.min(Math.max(bits - shift, 0), 7)) !== 0) throw new AuditError("overflowing unsigned LEB128");
      value += (byte & 0x7f) * 2 ** shift;
      if (byte < 128) return value;
    }
    throw new AuditError("unterminated unsigned LEB128");
  }

  /** Signed LEB128 of at most `bits` bits, as a BigInt. */
  signed(bits) {
    let value = 0n;
    for (let index = 0; index < Math.ceil(bits / 7); index += 1) {
      const byte = this.byte();
      const shift = BigInt(index * 7);
      value |= BigInt(byte & 0x7f) << shift;
      if (byte < 128) {
        if (byte & 0x40) value -= 1n << (shift + 7n);
        const limit = 1n << BigInt(bits - 1);
        if (value < -limit || value >= limit) throw new AuditError("overflowing signed LEB128");
        return value;
      }
    }
    throw new AuditError("unterminated signed LEB128");
  }

  name() {
    const bytes = this.take(this.uint(32));
    try {
      return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch {
      throw new AuditError("invalid UTF-8 name");
    }
  }

  count() {
    const count = this.uint(32);
    if (count > this.end - this.pos) throw new AuditError("vector count exceeds remaining bytes");
    return count;
  }

  finish() {
    if (this.pos !== this.end) throw new AuditError(`unconsumed bytes at ${this.pos} of ${this.end}`);
  }
}

function valueType(reader) {
  const value = reader.byte();
  if (value === 0x63 || value === 0x64) reader.signed(33);
  else if (![0x7f, 0x7e, 0x7d, 0x7c, 0x7b, 0x70, 0x6f].includes(value)) throw new AuditError(`unsupported value type 0x${value.toString(16)}`);
}

function limits(reader, memory) {
  const flags = reader.uint(32);
  if ((flags & ~(memory ? 15 : 5)) !== 0) throw new AuditError(`unsupported limits flags ${flags}`);
  if (!memory && flags & 4) throw new AuditError("table64 limits are not decoded by this version");
  const bits = flags & 4 ? 64 : 32;
  const minimum = reader.uint(bits);
  const maximum = flags & 1 ? reader.uint(bits) : null;
  const pageLog2 = memory && flags & 8 ? reader.uint(32) : 16;
  if (pageLog2 > 16 || (maximum !== null && minimum > maximum)) throw new AuditError("invalid memory/table limits");
  return {
    flags, minimum, maximum,
    initial_bytes: memory ? minimum * 2 ** pageLog2 : null,
    page_size: memory ? 2 ** pageLog2 : null,
    shared: (flags & 2) !== 0,
    memory64: (flags & 4) !== 0,
  };
}

const memoryRecord = (index, imported, lim) => ({ index, imported, ...lim });

/** The value of a constant expression as an address, or null when it is not a plain constant. */
function constantExpression(reader) {
  const stack = [];
  for (;;) {
    const opcode = reader.byte();
    if (opcode === 0x0b) {
      if (stack.length !== 1) throw new AuditError("invalid constant expression stack");
      return stack.pop();
    }
    if (opcode === 0x41 || opcode === 0x42) stack.push(Number(BigInt.asUintN(64, reader.signed(opcode === 0x41 ? 32 : 64))));
    else if (opcode === 0x23) { reader.uint(32); stack.push(null); }
    else if (opcode === 0x43) { reader.take(4); stack.push(null); }
    else if (opcode === 0x44) { reader.take(8); stack.push(null); }
    else if ([0x6a, 0x6b, 0x6c, 0x7c, 0x7d, 0x7e].includes(opcode)) {
      if (stack.length < 2) throw new AuditError("invalid extended constant expression");
      const b = stack.pop();
      const a = stack.pop();
      if (a === null || b === null) stack.push(null);
      else if (opcode === 0x6a || opcode === 0x7c) stack.push(a + b);
      else if (opcode === 0x6b || opcode === 0x7d) stack.push(a - b);
      else stack.push(a * b);
    } else throw new AuditError(`unsupported constant expression opcode 0x${opcode.toString(16)}`);
  }
}

/** Every section with its exact offsets and sizes; the sections and the 8-byte header cover the module. */
function sections(data) {
  if (!data.subarray(0, 8).equals(MAGIC)) throw new AuditError("expected a WebAssembly v1 core module, not an archive or component");
  const reader = new Reader(data, 8, data.length);
  const seen = new Set();
  const result = [];
  while (reader.pos < reader.end) {
    const start = reader.pos;
    const id = reader.byte();
    const payloadBytes = reader.uint(32);
    const payload = reader.pos;
    reader.take(payloadBytes);
    const end = reader.pos;
    if (id !== 0 && seen.has(id)) throw new AuditError(`duplicate standard section ${id}`);
    seen.add(id);
    if (id >= SECTION_NAMES.length) throw new AuditError(`unknown section id ${id}`);
    let name = SECTION_NAMES[id];
    let content = payload;
    if (id === 0) {
      const custom = new Reader(data, payload, end);
      name = custom.name();
      content = custom.pos;
    }
    result.push({ id, name, offset: start, payload_offset: payload, content_offset: content, end, raw_bytes: end - start, payload_bytes: payloadBytes, header_bytes: payload - start });
  }
  return result;
}

/** The inventory of one module: sections, functions (with names and exports), data segments, imports, exports, memories. */
export function parseModule(data) {
  const records = sections(data);
  const functions = [];
  let dataSegments = [];
  const imports = [];
  const exports = [];
  const memories = [];
  const names = new Map();
  const producers = {};
  const warnings = [];
  let dataStatus = "ABSENT";
  let importIndicesKnown = true;
  let declaredFunctions = null;
  for (const section of records) {
    const reader = new Reader(data, section.content_offset, section.end);
    try {
      if (section.id === 2) {
        for (let remaining = reader.count(); remaining > 0; remaining -= 1) {
          const row = { module: reader.name(), name: reader.name(), kind: reader.byte() };
          if (row.kind === 0) row.type_index = reader.uint(32);
          else if (row.kind === 1) { valueType(reader); row.limits = limits(reader, false); }
          else if (row.kind === 2) { row.limits = limits(reader, true); memories.push(memoryRecord(memories.length, true, row.limits)); }
          else if (row.kind === 3) { valueType(reader); reader.byte(); }
          else if (row.kind === 4) { reader.byte(); reader.uint(32); }
          else throw new AuditError(`unsupported import kind ${row.kind}`);
          imports.push(row);
        }
        reader.finish();
      } else if (section.id === 3) {
        declaredFunctions = reader.count();
        for (let index = 0; index < declaredFunctions; index += 1) reader.uint(32);
        reader.finish();
      } else if (section.id === 5) {
        for (let remaining = reader.count(); remaining > 0; remaining -= 1) memories.push(memoryRecord(memories.length, false, limits(reader, true)));
        reader.finish();
      } else if (section.id === 7) {
        for (let remaining = reader.count(); remaining > 0; remaining -= 1) exports.push({ name: reader.name(), kind: reader.byte(), index: reader.uint(32) });
        reader.finish();
      } else if (section.id === 10) {
        const imported = imports.filter((row) => row.kind === 0).length;
        const total = reader.count();
        for (let ordinal = 0; ordinal < total; ordinal += 1) {
          const offset = reader.pos;
          const length = reader.uint(32);
          const bodyOffset = reader.pos;
          if (length === 0) throw new AuditError("empty function body");
          const body = reader.take(length);
          functions.push({ index: importIndicesKnown ? ordinal + imported : null, ordinal, offset, body_offset: bodyOffset, raw_bytes: reader.pos - offset, body_bytes: length, sha256: sha256(body) });
        }
        reader.finish();
      } else if (section.id === 11) {
        const local = [];
        const total = reader.count();
        for (let index = 0; index < total; index += 1) {
          const offset = reader.pos;
          const flags = reader.uint(32);
          if (flags > 2) throw new AuditError(`unsupported data segment flags ${flags}`);
          const memory = flags === 2 ? reader.uint(32) : 0;
          const address = flags === 1 ? null : constantExpression(reader);
          const size = reader.uint(32);
          const payloadOffset = reader.pos;
          reader.take(size);
          local.push({ index, memory_index: memory, passive: flags === 1, memory_address: address, offset, payload_offset: payloadOffset, bytes: size, raw_bytes: reader.pos - offset });
        }
        reader.finish();
        dataSegments = local;
        dataStatus = "PARSED";
      } else if (section.id === 0 && section.name === "name") {
        while (reader.pos < reader.end) {
          const subsection = reader.byte();
          const size = reader.uint(32);
          const childStart = reader.pos;
          reader.take(size);
          const child = new Reader(data, childStart, childStart + size);
          if (subsection === 1) {
            for (let remaining = child.count(); remaining > 0; remaining -= 1) {
              const index = child.uint(32);
              if (names.has(index)) throw new AuditError("duplicate function name entry");
              names.set(index, child.name());
            }
            child.finish();
          }
        }
      } else if (section.id === 0 && section.name === "producers") {
        for (let remaining = reader.count(); remaining > 0; remaining -= 1) {
          const field = reader.name();
          const values = [];
          for (let versions = reader.count(); versions > 0; versions -= 1) values.push({ name: reader.name(), version: reader.name() });
          producers[field] = values;
        }
        reader.finish();
      }
    } catch (error) {
      if (!(error instanceof AuditError)) throw error;
      if (section.id === 2) importIndicesKnown = false;
      if (section.id === 11) dataStatus = "UNSUPPORTED";
      warnings.push(`${section.name}: ${error.message}`);
    }
  }
  if (declaredFunctions !== null && functions.length !== declaredFunctions) throw new AuditError("function/code section counts differ");
  for (const fn of functions) {
    fn.name = fn.index === null ? null : names.get(fn.index) ?? null;
    fn.exports = exports.filter((row) => row.kind === 0 && row.index === fn.index).map((row) => row.name);
  }
  const semantic = Buffer.concat([MAGIC, ...records.filter((section) => section.id !== 0).map((section) => data.subarray(section.offset, section.end))]);
  return {
    version: 1, raw_bytes: data.length, sha256: sha256(data), semantic_sha256: sha256(semantic), sections: records, functions,
    data_segments: dataSegments, data_parse_status: dataStatus, imports, import_indices_known: importIndicesKnown, exports, memories, producers, warnings,
    relocatable: records.some((section) => section.name === "linking" || section.name.startsWith("reloc.")),
  };
}

// --- compression ------------------------------------------------------------------------------------------------------

/** The size of `data` compressed by a command line tool, or null when the tool is missing or fails. */
function toolSize(program, args, data) {
  const finished = spawnSync(program, args, { input: data, maxBuffer: 1 << 30, stdio: ["pipe", "pipe", "inherit"] });
  return finished.error || finished.status !== 0 ? null : finished.stdout.length;
}

function sevenZipSize(data) {
  const directory = mkdtempSync(join(tmpdir(), "swiftuiweb-7z-"));
  try {
    const input = join(directory, "input.bin");
    const archive = join(directory, "output.7z");
    writeFileSync(input, data);
    for (const program of ["7zz", "7z"]) {
      const finished = spawnSync(program, ["a", "-t7z", "-mx=9", archive, input], { stdio: "ignore" });
      if (!finished.error) return finished.status === 0 ? statSync(archive).size : null;
    }
    return null;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function compressed(data, quality) {
  return {
    raw: data.length,
    gzip: gzipSync(data, { level: 9 }).length,
    brotli: toolSize("brotli", ["-q", String(quality), "-c"], data),
    zstd19: toolSize("zstd", ["-q", "-19", "-c"], data),
    zstd22: toolSize("zstd", ["-q", "--ultra", "-22", "-c"], data),
    zstd_ultra: toolSize("zstd", ["-q", "--ultra", "-19", "-c"], data),
    experimental: {
      deflate9: deflateRawSync(data, { level: 9 }).length,
      xz9: toolSize("xz", ["-9", "-c"], data),
      lzma_max: toolSize("lzma", ["-9", "-c"], data),
      lz4_hc: toolSize("lz4", ["-12", "-c"], data),
      bzip2_9: toolSize("bzip2", ["-9", "-c"], data),
      "7z_ultra": sevenZipSize(data),
    },
  };
}

// --- linker attribution -----------------------------------------------------------------------------------------------

const lastMatch = (text, pattern) => [...text.matchAll(pattern)].at(-1);

/** The category of a linker input (or a function name): a SwiftUIWeb target, ICU, Foundation, Swift support, ... */
export function bucket(source) {
  if (/FoundationICU|libicu|icudt\d+_dat/i.test(source)) return "ICU";
  const targets = [...source.matchAll(/(SwiftUIWeb[A-Za-z0-9_]*)(?:-[tp])?\.build/g)].map((match) => match[1]);
  const target = targets.at(-1);
  if ((target !== undefined && target !== "SwiftUIWeb") || targets.length > 1) return target ?? "";
  const module = lastMatch(source, /(SwiftUIWeb[A-Za-z0-9_]*)(?:[/-]|\.swift|\.o\b)/g);
  if (module) return module[1];
  if (/(?:lib)?Foundation(?:Essentials|Internationalization|Networking)?(?:[./(_-]|$)/.test(source)) return "Foundation";
  if (source.includes("JavaScriptKit") || source.includes("JavaScriptEventLoop")) return "JavaScriptKit";
  if (/Crypto|BoringSSL|ASN1|crypto/.test(source)) return "Crypto";
  if (/SwiftSyntax|SwiftParser|SwiftCompilerPlugin|BridgeJSMacros/.test(source)) return "Host-tool-named input (investigate)";
  if (target !== undefined) return target;
  if (/libswift|swift_(?:alloc|release|retain|once|task)|\$ss/.test(source)) return "Swift support";
  if (/libc\.|libm\.|libclang_rt|compiler-rt|libc\+\+/.test(source)) return "C/C++ support";
  return "Other / unclassified";
}

/** The rows of a wasm-ld map that name an input section (`source.o:(.text.f)`), with the CODE/DATA group they sit in. */
export function parseLinkMap(text) {
  if (!/Addr\s+Off\s+Size\s+Out/.test(text)) throw new AuditError("expected a wasm-ld Addr / Off / Size link map");
  let group = null;
  const rows = [];
  for (const line of text.split(/\r?\n/)) {
    // Split on whitespace rather than one regex with overlapping \s quantifiers, which backtracks on a crafted line.
    const fields = line.trim().split(/\s+/);
    if (fields.length < 4 || !/^(-|[0-9a-fA-F]+)$/.test(fields[0]) || !/^[0-9a-fA-F]+$/.test(fields[1]) || !/^[0-9a-fA-F]+$/.test(fields[2])) continue;
    const [addressText, , sizeText] = fields;
    const name = fields.slice(3).join(" ");
    const address = addressText === "-" ? null : Number.parseInt(addressText, 16);
    if (address === null && /^[A-Z_]+(?:\([^)]*\))?$/.test(name)) {
      group = name;
      continue;
    }
    const parent = /(.*(?:\.a\([^)]*\)|\.(?:o|obj)|<internal>)):\((.*)\)$/.exec(name);
    if (parent) rows.push({ section_group: group, address, bytes: Number.parseInt(sizeText, 16), source: parent[1], input_section: parent[2], category: bucket(parent[1]) });
  }
  return rows;
}

/** Bytes covered by exactly one category (`[start, end, category]` intervals may overlap) and the bytes covered by several. */
export function cover(intervals) {
  const events = new Map();
  for (const [start, end, category] of intervals) {
    if (end <= start) continue;
    for (const [position, delta] of [[start, 1], [end, -1]]) events.set(position, [...(events.get(position) ?? []), [category, delta]]);
  }
  const active = new Map();
  const totals = new Map();
  let previous = null;
  let ambiguous = 0;
  for (const position of [...events.keys()].sort((a, b) => a - b)) {
    if (previous !== null && position > previous) {
      const categories = [...active].filter(([, count]) => count > 0).map(([category]) => category);
      if (categories.length === 1) totals.set(categories[0], orZero(totals.get(categories[0])) + position - previous);
      else if (categories.length > 1) ambiguous += position - previous;
    }
    for (const [category, delta] of events.get(position)) active.set(category, orZero(active.get(category)) + delta);
    previous = position;
  }
  return [totals, ambiguous];
}

const sum = (values) => [...values].reduce((total, value) => total + value, 0);
const add = (map, key, value) => map.set(key, orZero(map.get(key)) + value);
/** Contributors for each key of the maps, largest first. */
function contributors(codeBytes, dataBytes, field, extra = () => ({})) {
  return [...new Set([...codeBytes.keys(), ...dataBytes.keys()])].sort().map((key) => {
    const code = orZero(codeBytes.get(key));
    const data = orZero(dataBytes.get(key));
    return { [field]: key, ...extra(key), code_bytes: code, data_bytes: data, raw_bytes: code + data };
  }).sort((a, b) => b.raw_bytes - a.raw_bytes || (a[field] < b[field] ? -1 : a[field] > b[field] ? 1 : 0));
}

/** Code and data bytes of `module` by linker input and by category, when the map rows agree with the module's layout. */
function attribute(module, rows) {
  const { functions } = module;
  const codeRows = rows.filter((row) => row.section_group === "CODE" && row.bytes > 0);
  const codeTotal = sum(functions.map((fn) => fn.raw_bytes));
  const codeMatches = codeRows.length === functions.length && codeRows.every((row, index) => row.bytes === functions[index].raw_bytes);
  const code = new Map();
  const codeByInput = new Map();
  const warnings = [];
  if (codeMatches) {
    codeRows.forEach((row, index) => {
      add(code, row.category, functions[index].raw_bytes);
      add(codeByInput, row.source, functions[index].raw_bytes);
    });
  } else warnings.push("Code map rows do not match function record order/sizes; code attribution withheld.");
  const intervals = [];
  const inputIntervals = [];
  const bss = [];
  const unresolved = [];
  for (const row of rows.filter((candidate) => candidate.section_group === "DATA")) {
    if (row.input_section.startsWith(".bss")) {
      if (row.address !== null) bss.push([row.address, row.address + row.bytes, row.category]);
      continue;
    }
    if (row.address === null) continue;
    let remaining = row.bytes;
    for (const segment of module.data_segments) {
      if (segment.passive || segment.memory_address === null || segment.memory_index !== 0) continue;
      const low = Math.max(row.address, segment.memory_address);
      const high = Math.min(row.address + row.bytes, segment.memory_address + segment.bytes);
      if (high > low) {
        const start = segment.payload_offset + low - segment.memory_address;
        intervals.push([start, start + high - low, row.category]);
        inputIntervals.push([start, start + high - low, row.source]);
        remaining -= high - low;
      }
    }
    if (remaining > 0) unresolved.push({ source: row.source, bytes_not_matched: remaining });
  }
  const [data, ambiguous] = cover(intervals);
  const [dataByInput, ambiguousInput] = cover(inputIntervals);
  const [bssByCategory, bssAmbiguous] = cover(bss);
  const initialized = sum(module.data_segments.map((segment) => segment.bytes));
  const attributedCode = sum(code.values());
  const attributedData = sum(data.values());
  if (attributedData + ambiguous > initialized) throw new AuditError("attribution exceeds actual data payload");
  return {
    status: codeMatches && unresolved.length === 0 && ambiguous === 0 ? "LAYOUT_MATCHED" : "PARTIAL",
    input_contributors: contributors(codeByInput, dataByInput, "source", (source) => ({ category: bucket(source) })),
    ambiguous_input_data_bytes: ambiguousInput,
    contributors: contributors(code, data, "category"),
    attributed_code_bytes: attributedCode,
    unattributed_code_bytes: codeTotal - attributedCode,
    attributed_data_bytes: attributedData,
    unattributed_data_bytes: initialized - attributedData,
    ambiguous_data_bytes: ambiguous,
    bss_bytes_by_category: bssByCategory,
    ambiguous_bss_bytes: bssAmbiguous,
    bss_is_not_download_bytes: true,
    unmatched_data_rows: unresolved.slice(0, 30),
    warnings,
  };
}

// --- bundle ----------------------------------------------------------------------------------------------------------

const NOT_RUNTIME_SUFFIXES = [".d.ts", ".wasm.size.json", ".wasm.data.json", ".wasm.report.json"];
const NOT_RUNTIME_EXTENSIONS = [".a", ".o", ".obj", ".swift", ".rs", ".c", ".cpp", ".h", ".hpp", ".swiftmodule", ".swiftdoc", ".swiftsourceinfo", ".toml", ".lock", ".log", ".map", ".md", ".ts"];

const runtimeAsset = (path) => {
  const name = basename(path);
  return !(["package.json", "release-manifest.json", "release-size.json"].includes(name) || path === "platforms/node.js"
    || NOT_RUNTIME_SUFFIXES.some((suffix) => name.endsWith(suffix)) || NOT_RUNTIME_EXTENSIONS.includes(extname(path)));
};

/** The files below `directory` (paths relative to `root`, visible entries only, in name order); a symlink is an error because it would be omitted. */
function collect(root, directory, files = []) {
  for (const name of readdirSync(directory).sort()) {
    const path = join(directory, name);
    if (name.startsWith(".")) continue;
    if (lstatSync(path).isSymbolicLink()) throw new AuditError(`materialize bundle symlinks before auditing; refusing to omit linked assets: ${path}`);
    if (statSync(path).isDirectory()) collect(root, path, files);
    else if (statSync(path).isFile()) files.push(relative(root, path));
  }
  return files;
}

// --- report ----------------------------------------------------------------------------------------------------------

/** Pretty JSON with a two-space indent and sorted keys; a Map is an object. */
function pretty(value, level = 0) {
  if (value === null || value === undefined) return "null";
  if (typeof value !== "object") return JSON.stringify(value);
  const pad = "  ".repeat(level + 1);
  const close = "  ".repeat(level);
  const entries = Array.isArray(value) ? value.map((item) => pretty(item, level + 1))
    : [...(value instanceof Map ? value : Object.entries(value))].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([key, item]) => `${JSON.stringify(key)}: ${pretty(item, level + 1)}`);
  const [open, end] = Array.isArray(value) ? ["[", "]"] : ["{", "}"];
  return entries.length === 0 ? open + end : `${open}\n${pad}${entries.join(`,\n${pad}`)}\n${close}${end}`;
}

/** The Markdown summary. Values print as JSON (strings quoted, `null` for unmeasured), as the report always has. */
export function markdown(report) {
  const j = JSON.stringify;
  const total = report.local_runtime_total;
  const experimental = report.experimental_compression_total;
  const lines = [
    "# WebAssembly audit", "", `Input: \`${report.input}\``, "",
    "| Local runtime assets | Raw bytes | gzip bytes | Brotli bytes | Zstd 19 | Zstd 22 | Zstd Ultra |",
    "| :--- | ---: | ---: | ---: | ---: | ---: | ---: |",
    `| Total | ${j(total.raw)} | ${j(total.gzip)} | ${total.brotli === null ? "not measured" : total.brotli} | ${j(total.zstd19)} | ${j(total.zstd22)} | ${j(total.zstd_ultra)} |`,
    "", "Experimental compression (comparison only):",
    "| Codec | Bytes | Browser delivery gate |", "| :--- | ---: | :--- |",
    `| Deflate level 9 | ${j(experimental.deflate9)} | no |`,
    `| XZ/LZMA2 level 9 | ${j(experimental.xz9)} | no |`,
    `| LZMA maximum | ${j(experimental.lzma_max)} | no |`,
    `| LZ4 high compression | ${j(experimental.lz4_hc)} | no |`,
    `| Bzip2 level 9 | ${j(experimental.bzip2_9)} | no |`,
    `| 7z/LZMA2 ultra | ${j(experimental["7z_ultra"])} | no |`,
    "", `Size target: **${j(report.size_gate.status)}** (reported, not enforced). Embedded: **not established by binary inventory**.`, "",
  ];
  for (const module of report.modules) {
    lines.push(`## ${j(module.path)}`, "", `SHA-256: \`${j(module.sha256)}\``, "", "| Section | Bytes | % of module |", "| :--- | ---: | ---: |", "| Module header | 8 | |");
    for (const section of [...module.sections].sort((a, b) => b.raw_bytes - a.raw_bytes)) {
      lines.push(`| ${j(section.name)} | ${section.raw_bytes} | ${fixed(100 * section.raw_bytes / module.raw_bytes, 3)}% |`);
    }
    const attribution = module.link_attribution;
    if (attribution?.contributors) {
      lines.push("", `Linker attribution: ${j(attribution.status)}.`, "", "| Input category | Code bytes | Initialized data bytes | Raw total |", "| :--- | ---: | ---: | ---: |");
      for (const row of attribution.contributors) lines.push(`| ${j(row.category)} | ${row.code_bytes} | ${row.data_bytes} | ${row.raw_bytes} |`);
    }
    lines.push("", "### Largest function bodies", "", "| Index | Body bytes | Name / export |", "| ---: | ---: | :--- |");
    for (const fn of [...module.functions].sort((a, b) => b.body_bytes - a.body_bytes).slice(0, 15)) {
      lines.push(`| ${j(fn.index)} | ${fn.body_bytes} | ${(fn.name || fn.exports.join(", ")).replaceAll("|", "&#124;")} |`);
    }
  }
  lines.push("", "## Interpretation", "", ...report.notes.map((note) => `* ${note}`), "", `External URL candidates: ${report.external_url_candidates.length}. See the JSON for details.`);
  return lines.join("\n");
}

const NOTES = [
  "Every section byte plus the 8-byte module header is accounted for.",
  "Brotli/gzip/zstd apply to whole files. Compressed per-library or per-section sizes are not additive.",
  "Experimental codecs are measured for comparison only and are not delivery gates.",
  "The runtime-asset sum is a conservative local deployment inventory, not an initial-page network transfer measurement.",
  "External URLs are candidates, not proven requests; remote payload bytes are unknown, not zero.",
  "Initial linear memory includes zero-filled/BSS space and is not download size or live application RAM.",
  "Function name categories are hints. Object/member attribution requires the corresponding linker map.",
  "Compilation logs and input provenance are needed to establish Embedded mode; a small stripped Wasm cannot establish it.",
];
const SIZE_KEYS = ["raw", "gzip", "brotli", "zstd19", "zstd22", "zstd_ultra"];
const EXPERIMENTAL_KEYS = ["deflate9", "xz9", "lzma_max", "lz4_hc", "bzip2_9", "7z_ultra"];

function parseOptions(argv) {
  const [input, ...rest] = argv;
  if (input === undefined) throw new AuditError("usage: wasm-audit <bundle> [--output path] [--brotli-quality n]");
  const options = { input, output: ".build/wasm-audit/report.json", quality: 11, linkMap: null, mapReference: null, maxBrotli: null };
  const names = { "--output": "output", "--brotli-quality": "quality", "--link-map": "linkMap", "--map-reference": "mapReference", "--max-brotli": "maxBrotli" };
  for (let index = 0; index < rest.length; index += 2) {
    if (!Object.hasOwn(names, rest[index])) throw new AuditError(`unknown argument ${rest[index]}`);
    if (rest[index + 1] === undefined) throw new AuditError(`${rest[index]} requires a value`);
    options[names[rest[index]]] = ["--brotli-quality", "--max-brotli"].includes(rest[index]) ? Number(rest[index + 1]) : rest[index + 1];
  }
  if (!Number.isInteger(options.quality) || options.quality < 0 || options.quality > 255) throw new AuditError("--brotli-quality must be an integer from 0 to 255");
  if (options.maxBrotli !== null && !(Number.isInteger(options.maxBrotli) && options.maxBrotli > 0)) throw new AuditError("max-brotli must be positive");
  if (options.mapReference !== null && options.linkMap === null) throw new AuditError("map-reference requires link-map");
  if (options.linkMap !== null && !existsSync(options.linkMap)) throw new AuditError("link map does not exist");
  if (options.mapReference !== null && !existsSync(options.mapReference)) throw new AuditError("map reference does not exist");
  return options;
}

function audit(options) {
  const { input, quality, linkMap, mapReference, maxBrotli } = options;
  const isFile = existsSync(input) && statSync(input).isFile();
  if (isFile && extname(input) !== ".wasm") throw new AuditError("a single-file input must be a final .wasm");
  if (!isFile && !(existsSync(input) && statSync(input).isDirectory())) throw new AuditError("input path does not exist");
  const root = isFile ? dirname(input) : input;
  const files = isFile ? [basename(input)] : collect(input, input);
  const wasmFiles = files.filter((path) => extname(path) === ".wasm");
  if (wasmFiles.length === 0) throw new AuditError("no final .wasm found in the input");
  if (linkMap !== null && wasmFiles.length !== 1) throw new AuditError("a link map must be paired with exactly one Wasm input");
  const linkRows = linkMap === null ? null : parseLinkMap(readFileSync(linkMap, "utf8"));
  const totals = Object.fromEntries(SIZE_KEYS.map((key) => [key, 0]));
  const experimentalTotals = Object.fromEntries(EXPERIMENTAL_KEYS.map((key) => [key, 0]));
  const urls = new Set();
  const assets = [];
  const modules = [];
  for (const relative of files.filter(runtimeAsset)) {
    const bytes = readFileSync(join(root, relative));
    const sizes = compressed(bytes, quality);
    for (const key of SIZE_KEYS) totals[key] = sizes[key] === null ? null : orZero(totals[key]) + sizes[key];
    for (const key of EXPERIMENTAL_KEYS) experimentalTotals[key] = sizes.experimental[key] === null ? null : orZero(experimentalTotals[key]) + sizes.experimental[key];
    if (["html", "js", "mjs", "css"].includes(extname(relative).slice(1))) {
      for (const [url] of new TextDecoder().decode(bytes).matchAll(/https?:\/\/[^\s\x00"'<>`\\)]+/g)) urls.add(url);
    }
    const path = relative.replaceAll("\\", "/");
    assets.push({ path, sha256: sha256(bytes), ...Object.fromEntries(SIZE_KEYS.map((key) => [key, sizes[key]])), experimental_compression: sizes.experimental });
    if (extname(relative) !== ".wasm") continue;
    const module = parseModule(bytes);
    if (module.relocatable) throw new AuditError("relocatable Wasm object is not a final application");
    Object.assign(module, {
      path,
      compressed_bytes: sizes,
      known_header_bytes: 8 + sum(module.sections.map((section) => section.header_bytes)),
      name_hints: module.functions.filter((fn) => fn.name !== null).map((fn) => ({ index: fn.index, name: fn.name, category: bucket(fn.name), bytes: fn.raw_bytes })),
      name_hints_are_attribution: false,
      link_attribution: null,
    });
    if (linkRows) {
      const reference = mapReference === null ? null : parseModule(readFileSync(mapReference));
      if (reference === null || reference.semantic_sha256 === module.semantic_sha256) {
        module.link_attribution = {
          ...attribute(module, linkRows),
          association: reference ? "REFERENCE_SEMANTIC_HASH_MATCH" : "CALLER_SUPPLIED_MAP_UNVERIFIED",
          map_sha256: sha256(readFileSync(linkMap)),
        };
      } else module.link_attribution = { status: "REJECTED", reason: "reference executable sections differ; optimizer or a different build changed the code/data" };
    }
    modules.push(module);
  }
  if (modules.length === 0) throw new AuditError("no deployable Wasm module was inventoried");
  const measured = totals.brotli;
  // Size is a target the report states, never a failure: over the target is reported, and the exit status does not change.
  const status = maxBrotli === null ? "NOT_REQUESTED" : measured === null ? "UNMEASURED" : measured < maxBrotli ? "WITHIN_TARGET" : "OVER_TARGET";
  const profile = (level, delivery) => ({ level, delivery });
  return {
    schema_version: 1,
    input,
    brotli_quality: quality,
    compression_profiles: {
      gzip: profile("-9", true), brotli: profile(`-${quality}`, true), zstd19: profile("-19", false), zstd22: profile("--ultra -22", false),
      zstd_ultra: profile("--ultra -19", false), deflate9: profile("-9", true), xz9: profile("-9", false), lzma_max: profile("maximum/-9", false),
      lz4_hc: profile("high compression/-12", false), bzip2_9: profile("-9", false), "7z_ultra": profile("ultra", false),
    },
    modules,
    runtime_assets: assets,
    local_runtime_total: totals,
    experimental_compression_total: experimentalTotals,
    size_gate: { status, limit_exclusive_bytes: maxBrotli, scope: "all_local_runtime_assets_brotli_sum", measured_bytes: measured },
    external_url_candidates: [...urls].sort(),
    embedded_status: "NOT_ESTABLISHED_BY_BINARY_INVENTORY",
    notes: NOTES,
  };
}

function writeAtomic(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const temporary = `${path}.${process.pid}.tmp`;
  writeFileSync(temporary, text);
  renameSync(temporary, path);
}

if (import.meta.main) {
  try {
    const options = parseOptions(process.argv.slice(2));
    const report = audit(options);
    const markdownPath = options.output.replace(/(\.[^./]*)?$/, ".md");
    writeAtomic(options.output, pretty(report));
    writeAtomic(markdownPath, markdown(report));
    console.log(`${markdown(report)}\nJSON: ${options.output}\nMarkdown: ${markdownPath}`);
  } catch (error) {
    console.error(`wasm-audit: ${error.message}`);
    process.exit(1);
  }
}
