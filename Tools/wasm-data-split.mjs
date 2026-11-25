#!/usr/bin/env bun
// Moves the data only the second module of a split release uses into the second module (Documentation/Architecture/WASM_SPLIT.md,
// "Data that moves with the code").
//
// Binaryen's `wasm-split` moves functions and never data, so after a split the first module (`app.wasm`, the one the page waits
// for) still holds every vtable, witness table, type metadata and string literal of the whole application, although the first
// screen reads a small part of them. Their bytes are about a fifth of the first module of a large application. This step cuts
// the objects that nothing in the first module can reach out of its data section and adds them to the data section of the second
// module as active segments at the same addresses: they are written into the shared linear memory when `app-rest.wasm` is
// instantiated, which is before any of its functions can run.
//
// What decides that an object can move (all of it from the module bytes and the linker's map, no names are guessed):
//   - The object's extent comes from the linker's map (`-Xlinker -Map=`): Swift puts each global in an input section of its
//     own, so the map gives the exact bytes of each string literal, witness table and metadata record.
//   - Only data the program cannot write moves: everything the linker put in `.rodata`, and the objects of `.data` whose symbol
//     is a type metadata record (`...Mf`), protocol or value witness table (`...WP`, `...WV`) or async function pointer
//     (`...Tu`). Embedded Swift never writes them (no runtime metadata is built), but the compiler gives them no `const`.
//   - An object stays in the first module when any of its code names an address inside it (an `i32.const`, or an offset of a
//     load or store, which is where LLVM folds a global's address), when an object that stays holds a word that looks like
//     its address (read at every byte offset, so a packed pointer counts), or when an address inside it, or one past its end,
//     sits in a global's initializer. Every other object that the second module's code names, and what only those objects point
//     at, moves.
//   - A string literal is also named by an address up to 24 bytes before it (a `String` holds the address of its native object, the
//     first character less a 20-byte header), and strings the linker made share bytes (the tail of another) are one object.
//   - The map must describe this module: its objects must cover the initialized bytes of the data section, or nothing moves.
//   - What this reads is code and data, not behavior: Tools/wasm-split-release.mjs then runs the first screen with the first module
//     instrumented and drops the move if that screen touches a moved range before the second module is instantiated.
//
// usage: wasm-data-split.mjs <app.wasm> <app-rest.wasm> --link-map <map> [--check]
//        rewrites both modules in place; --check only reports.
// Run the tests with: bun test ./Tools/test-wasm-data-split.mjs

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";

/** The symbols of `.data` whose objects code never writes: type metadata, witness tables, async function pointers. */
export const READ_ONLY_DATA_SYMBOL = /(?:Mf|WP|WV|Tu)$/;
/** Alignment padding of up to this many zero bytes between two moving objects is cut with them, so they leave one run. */
const PADDING = 16;
/** Fewer bytes than this and the move is not made (a segment costs a few bytes). */
const MIN_MOVED_BYTES = 1024;

// ---- reading modules ---------------------------------------------------------------------------------------------------

function readLeb(bytes, at, signed = false) {
  let value = 0n, shift = 0n, byte;
  do {
    byte = bytes[at++];
    if (byte === undefined) throw new RangeError("unexpected end of module");
    value |= BigInt(byte & 0x7f) << shift;
    shift += 7n;
  } while (byte & 0x80);
  if (signed && (byte & 0x40)) value -= 1n << shift;
  return [Number(value), at];
}

const writeUnsigned = (value) => {
  const out = [];
  let rest = BigInt(value);
  do {
    let byte = Number(rest & 0x7fn);
    rest >>= 7n;
    if (rest !== 0n) byte |= 0x80;
    out.push(byte);
  } while (rest !== 0n);
  return out;
};
const writeSigned32 = (value) => {
  const out = [];
  let rest = value | 0;
  for (;;) {
    const byte = rest & 0x7f;
    rest >>= 7;
    if ((rest === 0 && !(byte & 0x40)) || (rest === -1 && (byte & 0x40))) { out.push(byte); return out; }
    out.push(byte | 0x80);
  }
};

/** The sections of a module, in file order: `{ id, start (of the id byte), payload, end }`. */
export function listSections(wasm) {
  if (wasm.length < 8 || wasm[0] !== 0 || wasm[1] !== 0x61 || wasm[2] !== 0x73 || wasm[3] !== 0x6d) throw new Error("not a WebAssembly module");
  const sections = [];
  for (let at = 8; at < wasm.length;) {
    const [size, payload] = readLeb(wasm, at + 1);
    sections.push({ id: wasm[at], start: at, payload, end: payload + size });
    at = payload + size;
  }
  return sections;
}

/** The data segments of a module: `{ flags, offset (active segments), size, at (first byte of the contents) }`. */
export function readDataSegments(wasm, sections = listSections(wasm)) {
  const section = sections.find((entry) => entry.id === 11);
  if (!section) return { section: null, segments: [] };
  const segments = [];
  let [count, at] = readLeb(wasm, section.payload);
  for (let index = 0; index < count; index++) {
    let flags;
    [flags, at] = readLeb(wasm, at);
    let offset = null;
    if (flags === 2) [, at] = readLeb(wasm, at);
    if (flags === 0 || flags === 2) {
      if (wasm[at] !== 0x41) throw new Error(`data segment ${index}: the offset is not an i32.const`);
      [offset, at] = readLeb(wasm, at + 1, true);
      offset >>>= 0;
      if (wasm[at++] !== 0x0b) throw new Error(`data segment ${index}: the offset expression does not end where expected`);
    } else if (flags !== 1) throw new Error(`data segment ${index}: unknown flags ${flags}`);
    let size;
    [size, at] = readLeb(wasm, at);
    segments.push({ flags, offset, size, at });
    at += size;
  }
  return { section, segments };
}

/** Every `i32.const` operand and every load or store offset of a module's code that falls in [low, high], with the number of
 * times each appears; the constants of its globals' initializers too (those count as a reference of the module). */
export function codeAddresses(wasm, low, high) {
  const found = new Map();
  const note = (value) => { if (value >= low && value <= high) found.set(value, (found.get(value) ?? 0) + 1); };
  for (const section of listSections(wasm)) {
    if (section.id === 10) scanCode(wasm, section.payload, section.end, note);
    else if (section.id === 6) scanGlobals(wasm, section.payload, section.end, note);
  }
  return found;
}

function scanGlobals(w, start, end, note) {
  let [count, p] = readLeb(w, start);
  for (let index = 0; index < count; index++) {
    p += 2; // value type, mutability
    for (;;) {
      const op = w[p++];
      if (op === 0x0b) break;
      if (op === 0x41) { let value; [value, p] = readLeb(w, p, true); note(value >>> 0); }
      else if (op === 0x42 || op === 0x23 || op === 0xd2) { while (w[p++] & 0x80); }
      else if (op === 0x43) p += 4;
      else if (op === 0x44) p += 8;
      else if (op === 0xd0) p++;
      else if (![0x6a, 0x6b, 0x6c, 0x7c, 0x7d, 0x7e].includes(op)) throw new Error(`unexpected opcode 0x${op.toString(16)} in a global initializer`);
    }
  }
  if (p > end) throw new Error("the global section ends early");
}

/** Walks the function bodies. Understands the MVP and the extensions Swift's toolchain enables (sign extension, saturating
 * conversions, bulk memory, reference types, multi-value); any other opcode throws, so a module that uses one is left alone. */
function scanCode(w, start, end, note) {
  let [count, p] = readLeb(w, start);
  const u = () => { let value = 0, scale = 1, byte; do { byte = w[p++]; value += (byte & 0x7f) * scale; scale *= 128; } while (byte & 0x80); return value; };
  const skipSigned = () => { while (w[p++] & 0x80); };
  const signed32 = () => { let result = 0, shift = 0, byte; do { byte = w[p++]; result |= (byte & 0x7f) << shift; shift += 7; } while (byte & 0x80); if (shift < 32 && (byte & 0x40)) result |= -1 << shift; return result >>> 0; };
  for (let index = 0; index < count; index++) {
    const size = u();
    const bodyEnd = p + size;
    for (let groups = u(); groups > 0; groups--) { u(); p++; }
    while (p < bodyEnd) {
      const op = w[p++];
      if (op <= 0x05 || op === 0x0b || op === 0x0f || op === 0x1a || op === 0x1b || (op >= 0x45 && op <= 0xc4) || op === 0xd1) {
        if (op >= 0x02 && op <= 0x04) { const type = w[p]; if (type === 0x40 || (type >= 0x6f && type <= 0x7f)) p++; else skipSigned(); }
      } else if (op === 0x0c || op === 0x0d || op === 0x10 || (op >= 0x20 && op <= 0x26) || op === 0xd2) u();
      else if (op === 0x0e) { for (let labels = u(); labels >= 0; labels--) u(); }
      else if (op === 0x11) { u(); u(); }
      else if (op === 0x1c) p += u();
      else if (op >= 0x28 && op <= 0x3e) { const align = u(); if (align & 0x40) u(); note(u()); }
      else if (op === 0x3f || op === 0x40 || op === 0xd0) p++;
      else if (op === 0x41) note(signed32());
      else if (op === 0x42) skipSigned();
      else if (op === 0x43) p += 4;
      else if (op === 0x44) p += 8;
      else if (op === 0xfc) {
        const sub = u();
        if (sub <= 7) continue;
        if (sub === 8) { u(); p++; } else if (sub === 9 || sub === 13 || (sub >= 15 && sub <= 17)) u();
        else if (sub === 10) p += 2; else if (sub === 11) p++; else if (sub === 12 || sub === 14) { u(); u(); }
        else throw new Error(`unsupported opcode 0xfc ${sub}`);
      } else throw new Error(`unsupported opcode 0x${op.toString(16)}`);
    }
    if (p !== bodyEnd) throw new Error(`function ${index}: the scan is out of step with the body`);
  }
}

// ---- the linker's map --------------------------------------------------------------------------------------------------

/**
 * The input sections of the DATA group of a wasm-ld map (`-Xlinker -Map=file`): `{ address, size, segment, section, symbol }`,
 * ordered by address. `segment` is the output segment (`.rodata`, `.data`, `.bss`), `symbol` the first symbol the section defines.
 */
export function parseLinkMap(text) {
  const objects = [];
  let inData = false, segment = null, current = null, sectionDepth = -1;
  for (const line of text.split("\n")) {
    const fields = line.trim().split(/\s+/);
    if (fields.length < 4 || !/^(-|[0-9a-f]+)$/.test(fields[0]) || !/^[0-9a-f]+$/.test(fields[1]) || !/^[0-9a-f]+$/.test(fields[2])) continue;
    const name = fields.slice(3).join(" ");
    if (fields[0] === "-" && /^[A-Z_]+$/.test(name)) { inData = name === "DATA"; sectionDepth = -1; continue; }
    if (!inData) continue;
    // The columns are Addr Off Size Out In Symbol: the output segments, the input sections and the symbols sit at three
    // indentations, which tells a symbol named like a segment (`.L.str.1`) from one: a symbol is indented past its section.
    const depth = /^(\s*\S+\s+\S+\s+\S+\s+)/.exec(line)?.[1].length ?? -1;
    if (fields[0] !== "-" && fields.length === 4 && name.startsWith(".") && !name.includes(":(") && !(sectionDepth >= 0 && depth > sectionDepth)) {
      segment = name; current = null;
    } else if (name.includes(":(") && name.endsWith(")")) {
      sectionDepth = depth;
      current = { address: Number.parseInt(fields[0], 16), size: Number.parseInt(fields[2], 16), segment, section: name.slice(name.lastIndexOf(":(") + 2, -1), symbol: null };
      objects.push(current);
    } else if (current && current.symbol === null) current.symbol = name;
  }
  return objects.sort((a, b) => a.address - b.address);
}

/** A digest of what the map says about the data (addresses, sizes, sections, symbols), not of the paths of the build that wrote it:
 * the cache of a split keeps its entry for a build whose map says the same. */
export function linkMapKey(text) {
  return createHash("sha256").update(JSON.stringify(parseLinkMap(text).map(({ address, size, segment, section, symbol }) => [address, size, segment, section, symbol]))).digest("hex");
}

/** Whether code never writes this object (see the top of this file). */
export function isReadOnly(object) {
  if (/^\.rodata(\.|$)/.test(object.segment ?? "")) return true;
  return object.segment === ".data" && READ_ONLY_DATA_SYMBOL.test(object.symbol ?? "");
}

// ---- the plan ----------------------------------------------------------------------------------------------------------

/**
 * The linker merges string literals and lets one that is the tail of another share its bytes (`-top` inside `data-padding-top`), and
 * the map lists both, overlapping. The bytes they share have one fate, so overlapping objects become one object that is read-only
 * only when each of them is; an address inside any of them is an address inside it.
 */
function joinOverlapping(objects, readOnly) {
  const sorted = objects.slice().sort((a, b) => a.address - b.address || b.size - a.size);
  const joined = [];
  for (const object of sorted) {
    const last = joined[joined.length - 1];
    if (last && object.address < last.address + last.size) {
      last.size = Math.max(last.size, object.address + object.size - last.address);
      last.members.push(object);
    } else joined.push({ address: object.address, size: object.size, segment: object.segment, section: object.section, symbol: object.symbol, members: [object] });
  }
  for (const object of joined) {
    object.readOnly = object.members.every((member) => readOnly(member));
    object.string = object.members.every((member) => /\.L\.str/.test(`${member.symbol ?? ""} ${member.section ?? ""}`));
  }
  return joined;
}

/** The distance from a Swift `String`'s object address to its first character on a 32-bit target (with room for alignment). */
const STRING_BIAS = 24;

/** The initialized memory of a module as one image: `{ low, high, bytes, present }`. */
function memoryImage(wasm, segments) {
  const active = segments.filter((segment) => segment.flags !== 1);
  if (active.length === 0) return null;
  const low = Math.min(...active.map((segment) => segment.offset));
  const high = Math.max(...active.map((segment) => segment.offset + segment.size));
  const bytes = new Uint8Array(high - low), present = new Uint8Array(high - low);
  for (const segment of active) { bytes.set(wasm.subarray(segment.at, segment.at + segment.size), segment.offset - low); present.fill(1, segment.offset - low, segment.offset - low + segment.size); }
  return { low, high, bytes, present };
}

/**
 * Whether the map describes the module. Swift names the section of a string literal after its text (`.L.str.16.data-padding-top`),
 * so the module's bytes at the object say it: most of the literals the map lists must be at the address it gives. Without enough
 * literals to tell (a module with few strings), the objects must cover the initialized non-zero bytes of the data section; the
 * bytes before a string, which are the header of its native object, are in no object, so this is not required to be exact.
 */
function mapMatches(image, objects) {
  let checked = 0, agreed = 0;
  for (const object of objects) {
    const named = /^\.L\.str\.\d+\.(.+)$/s.exec(object.symbol ?? "");
    if (!named || !/^[\x20-\x7e]+$/.test(named[1])) continue;
    const expected = Buffer.from(named[1].slice(0, Math.min(named[1].length, object.size - 1, 24)));
    if (expected.length < 4 || object.address < image.low || object.address + expected.length > image.high) continue;
    checked++;
    const at = object.address - image.low;
    if (expected.every((byte, index) => image.present[at + index] && image.bytes[at + index] === byte)) agreed++;
  }
  if (checked >= 8) return agreed / checked >= 0.9;
  const covered = new Uint8Array(image.high - image.low);
  for (const object of objects) {
    if (object.address < image.low || object.address + object.size > image.high) continue;
    covered.fill(1, object.address - image.low, object.address - image.low + object.size);
  }
  let nonZero = 0, outside = 0;
  for (let i = 0; i < covered.length; i++) { if (image.present[i] && image.bytes[i] !== 0) { nonZero++; if (!covered[i]) outside++; } }
  return nonZero === 0 || outside / nonZero < 0.02;
}

/**
 * Decides what moves. `objects` is `parseLinkMap`'s result. Returns `{ reason }` when nothing can move, else
 * `{ objects (the moving ones), runs ([start, end) address ranges to cut, adjacent objects joined), stats }`.
 */
export function planDataMove({ primary, secondary, objects, readOnly = isReadOnly }) {
  const sections = listSections(primary);
  const { segments } = readDataSegments(primary, sections);
  if (segments.some((segment) => segment.flags === 1)) return { reason: "the module has passive data segments (memory.init names them by index)" };
  const image = memoryImage(primary, segments);
  if (!image) return { reason: "the module has no initialized data" };
  const data = joinOverlapping(objects.filter((object) => object.segment !== ".bss" && object.size > 0 && object.address >= image.low && object.address + object.size <= image.high), readOnly);
  if (data.length === 0 || !mapMatches(image, data)) return { reason: "the link map does not describe this module's data" };

  const primaryRefs = codeAddresses(primary, image.low, image.high);
  const secondaryRefs = codeAddresses(secondary, image.low, image.high);
  // The objects an address may name: the one that contains it, or (a pointer one past its end) the one that ends there, and a
  // string literal that starts up to STRING_BIAS bytes after it: a `String` holds the address of its native object, which is
  // the first character less the 20 bytes of header (`_StringObject.nativeBias` on a 32-bit target), and the compiler writes that
  // address as the constant, so the constant lies before the literal, in the padding or in the end of the one before it.
  const search = (address) => { let lo = 0, hi = data.length - 1, found = -1; while (lo <= hi) { const mid = (lo + hi) >> 1; if (data[mid].address <= address) { found = mid; lo = mid + 1; } else hi = mid - 1; } return found; };
  const ownersOf = (address) => {
    const at = search(address);
    const found = [];
    if (at >= 0) {
      const inside = data[at];
      if (address < inside.address + inside.size || inside.address + inside.size === address) found.push(inside);
    }
    for (let next = at + 1; next < data.length && data[next].address <= address + STRING_BIAS; next++) if (data[next].string) found.push(data[next]);
    return found;
  };
  for (const object of data) { object.byFirst = false; object.bySecond = false; object.stays = !object.readOnly; object.points = []; }
  for (const address of primaryRefs.keys()) for (const owner of ownersOf(address)) owner.byFirst = true;
  for (const address of secondaryRefs.keys()) for (const owner of ownersOf(address)) owner.bySecond = true;
  // Pointer-looking words, at every byte offset: the objects each object may point at.
  for (const object of data) {
    const base = object.address - image.low;
    for (let at = 0; at + 4 <= object.size; at++) {
      if (!image.present[base + at] || !image.present[base + at + 3]) continue;
      const word = (image.bytes[base + at] | (image.bytes[base + at + 1] << 8) | (image.bytes[base + at + 2] << 16) | (image.bytes[base + at + 3] << 24)) >>> 0;
      if (word >= image.low && word <= image.high) for (const owner of ownersOf(word)) if (owner !== object) object.points.push(owner);
    }
  }
  // A candidate is a read-only object the first module's code does not name that the second module's code names, or that only
  // such objects point at. It moves unless some object that stays in the first module (whatever the reason, and an object
  // nobody names stays too) holds a word that may point at it; that is repeated for the objects that stay because of it.
  const candidate = data.map(() => false);
  const index = new Map(data.map((object, at) => [object, at]));
  const eligible = (object) => !object.stays && !object.byFirst;
  const queue = [];
  data.forEach((object, at) => { if (eligible(object) && object.bySecond) { candidate[at] = true; queue.push(object); } });
  while (queue.length > 0) { const object = queue.pop(); for (const target of object.points) { const at = index.get(target); if (!candidate[at] && eligible(target)) { candidate[at] = true; queue.push(target); } } }
  data.forEach((object, at) => { if (!candidate[at]) queue.push(object); });
  while (queue.length > 0) { const object = queue.pop(); for (const target of object.points) { const at = index.get(target); if (candidate[at]) { candidate[at] = false; queue.push(target); } } }
  const moving = data.filter((object, at) => candidate[at]);
  // The moved bytes are the objects, with the zero padding between two of them that no object of the map owns (alignment): one
  // run, one segment in each module instead of two. Zeros the map gives to an object stay out: they may be a variable the first
  // module has changed by the time the second module's segments are written.
  const taken = objects.filter((object) => object.size > 0);
  const owned = (from, to) => { let lo = 0, hi = taken.length - 1, first = taken.length; while (lo <= hi) { const mid = (lo + hi) >> 1; if (taken[mid].address + taken[mid].size > from) { first = mid; hi = mid - 1; } else lo = mid + 1; } return first < taken.length && taken[first].address < to; };
  const runs = [];
  for (const object of moving) {
    const end = object.address + object.size;
    const last = runs[runs.length - 1];
    if (last && object.address >= last[1] && object.address - last[1] <= PADDING && (object.address === last[1] || (isZero(image, last[1], object.address) && !owned(last[1], object.address)))) last[1] = end;
    else runs.push([object.address, end]);
  }
  const bytes = moving.reduce((total, object) => total + object.size, 0);
  const stats = { objects: moving.length, bytes, runs: runs.length, considered: data.length, firstModuleReferences: data.filter((object) => object.byFirst).length };
  if (bytes < MIN_MOVED_BYTES) return { reason: `only ${bytes} bytes of data could move`, stats };
  return { objects: moving.map(({ address, size, segment, symbol }) => ({ address, size, segment, symbol })), runs, stats };
}

function isZero(image, from, to) {
  for (let address = from; address < to; address++) { const at = address - image.low; if (image.present[at] && image.bytes[at] !== 0) return false; }
  return true;
}

// ---- rewriting the modules ---------------------------------------------------------------------------------------------

const concat = (parts) => {
  const out = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let at = 0;
  for (const part of parts) { out.set(part, at); at += part.length; }
  return out;
};
const section = (id, payload) => concat([Uint8Array.of(id), Uint8Array.from(writeUnsigned(payload.length)), payload]);
const dataSegment = (offset, bytes) => concat([Uint8Array.from([0, 0x41, ...writeSigned32(offset | 0), 0x0b, ...writeUnsigned(bytes.length)]), bytes]);

/**
 * Moves the address ranges `runs` out of the first module's active data segments into the second module, as active data
 * segments after its code (the pieces keep their addresses). Returns the two modules.
 */
export function moveData(primary, secondary, runs) {
  const sections = listSections(primary);
  const { section: dataSection, segments } = readDataSegments(primary, sections);
  if (!dataSection) throw new Error("the first module has no data section");
  if (segments.some((segment) => segment.flags === 1)) throw new Error("passive data segments cannot be rewritten");
  const order = (ranges) => ranges.slice().sort((a, b) => a[0] - b[0]);
  const moved = order(runs);
  const kept = [], carried = [];
  for (const segment of segments) {
    const start = segment.offset, end = segment.offset + segment.size;
    let pieces = [[start, end]];
    for (const [from, to] of moved) {
      if (to <= start) continue;
      if (from >= end) break;
      const next = [];
      for (const [x, y] of pieces) {
        if (to <= x || from >= y) { next.push([x, y]); continue; }
        if (from > x) next.push([x, from]);
        if (to < y) next.push([to, y]);
      }
      pieces = next;
    }
    for (const [x, y] of pieces) kept.push(dataSegment(x, primary.subarray(segment.at + (x - start), segment.at + (y - start))));
    for (const [from, to] of moved) {
      if (to <= start) continue;
      if (from >= end) break;
      const x = Math.max(from, start), y = Math.min(to, end);
      carried.push([x, dataSegment(x, primary.subarray(segment.at + (x - start), segment.at + (y - start)))]);
    }
  }
  carried.sort((a, b) => a[0] - b[0]);
  const count = (items) => Uint8Array.from(writeUnsigned(items.length));
  const newPrimary = rewrite(primary, sections, new Map([[11, section(11, concat([count(kept), ...kept]))], [12, section(12, count(kept))]]));

  const secondSections = listSections(secondary);
  if (secondSections.some((entry) => entry.id === 11)) throw new Error("the second module has a data section already");
  const code = secondSections.find((entry) => entry.id === 10);
  if (!code) throw new Error("the second module has no code section");
  const added = section(11, concat([count(carried), ...carried.map(([, segment]) => segment)]));
  return {
    primary: newPrimary,
    secondary: rewrite(secondary, secondSections, new Map([[12, section(12, count(carried))]]), { after: code.id, section: added }),
  };
}

/** `module` with the sections named in `replacements` (by id) replaced where they are, and `insert` (`{ after, section }`) added after
 * the section with that id. A replaced section the module does not have is not added. */
function rewrite(module, sections, replacements, insert = null) {
  const parts = [];
  let at = 0;
  for (const entry of sections) {
    if (replacements.has(entry.id)) { parts.push(module.subarray(at, entry.start), replacements.get(entry.id)); at = entry.end; }
    if (insert && entry.id === insert.after) { parts.push(module.subarray(at, entry.end), insert.section); at = entry.end; }
  }
  parts.push(module.subarray(at));
  return concat(parts);
}

/**
 * The whole step: plans the move from the map, rewrites both modules and checks the result still validates. Returns
 * `{ primary, secondary, moved: { objects, bytes, runs } }`, or `{ reason }` (with the two modules untouched) when nothing moved.
 */
export function splitData({ primary, secondary, linkMap, readOnly }) {
  let plan;
  try {
    plan = planDataMove({ primary, secondary, objects: parseLinkMap(linkMap), readOnly });
  } catch (error) {
    return { reason: `the data could not be analysed (${error.message})` };
  }
  if (plan.reason) return { reason: plan.reason, stats: plan.stats };
  const result = moveData(primary, secondary, plan.runs);
  for (const [name, bytes] of [["first", result.primary], ["second", result.secondary]]) {
    if (!WebAssembly.validate(bytes)) return { reason: `the ${name} module did not validate after the move` };
  }
  return { ...result, moved: { objects: plan.objects.length, bytes: plan.stats.bytes, runs: plan.runs.length, ranges: plan.runs }, stats: plan.stats };
}

async function main(argv) {
  const { values, positionals } = parseArgs({ args: argv, allowPositionals: true, options: { "link-map": { type: "string" }, check: { type: "boolean", default: false } } });
  if (positionals.length !== 2 || !values["link-map"]) {
    console.error("usage: wasm-data-split.mjs <app.wasm> <app-rest.wasm> --link-map <map> [--check]");
    return 2;
  }
  const [firstPath, secondPath] = positionals;
  const result = splitData({ primary: new Uint8Array(readFileSync(firstPath)), secondary: new Uint8Array(readFileSync(secondPath)), linkMap: readFileSync(values["link-map"], "utf8") });
  if (result.reason) { console.log(`nothing moved: ${result.reason}`); return 0; }
  console.log(`moved ${result.moved.objects} objects (${result.moved.bytes} bytes in ${result.moved.runs} runs) from ${firstPath} to ${secondPath}`);
  if (!values.check) { writeFileSync(firstPath, result.primary); writeFileSync(secondPath, result.secondary); }
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(await main(process.argv.slice(2)));
