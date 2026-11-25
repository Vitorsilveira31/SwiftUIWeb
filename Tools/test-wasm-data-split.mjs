// Tests Tools/wasm-data-split.mjs: the link map reader, the scan of a module's code for the data addresses it names, which data
// moves into the second module and which stays, and the rewritten modules (they validate, and the two instantiated together
// leave memory as the unsplit module had it).
// Run with: bun test ./Tools/test-wasm-data-split.mjs
import { expect, test } from "bun:test";
import { codeAddresses, isReadOnly, listSections, moveData, parseLinkMap, planDataMove, readDataSegments, splitData } from "./wasm-data-split.mjs";

// ---- a small assembler for the modules the tests need ------------------------------------------------------------------

const uleb = (value) => { const out = []; do { let byte = value & 0x7f; value = Math.floor(value / 128); if (value) byte |= 0x80; out.push(byte); } while (value); return out; };
const sleb = (value) => { const out = []; for (;;) { const byte = value & 0x7f; value >>= 7; if ((value === 0 && !(byte & 0x40)) || (value === -1 && (byte & 0x40))) { out.push(byte); return out; } out.push(byte | 0x80); } };
const vec = (items) => [...uleb(items.length), ...items.flat()];
const section = (id, body) => [id, ...uleb(body.length), ...body];
const name = (text) => [...uleb(text.length), ...Buffer.from(text)];

const I32_CONST = (value) => [0x41, ...sleb(value)];
const DROP = [0x1a];
/** A function body from its instructions (no locals). */
const body = (...instructions) => { const code = [0, ...instructions.flat(), 0x0b]; return [...uleb(code.length), ...code]; };
/** Reads the address `value` the way the compiler writes a folded global: `i32.const 0; i32.load offset=value; drop`. */
const LOAD_AT = (offset) => [...I32_CONST(0), 0x28, 0x02, ...uleb(offset), ...DROP];
const NAMED = (address) => [...I32_CONST(address), ...DROP];

/**
 * A module with one memory (defined and exported, or imported from "primary"), the given globals, function bodies and data
 * segments (`{ at, bytes }`; passive ones have no `at`).
 */
function wasm({ imported = false, globals = [], bodies = [], data = [], dataCount = false, extra = [] }) {
  const parts = [[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]];
  parts.push(section(1, vec([[0x60, 0, 0]])));
  if (imported) parts.push(section(2, vec([[...name("primary"), ...name("memory"), 0x02, 0x00, 0x01]])));
  parts.push(section(3, vec(bodies.map(() => [0]))));
  if (!imported) parts.push(section(5, vec([[0x00, 0x01]])));
  if (globals.length) parts.push(section(6, vec(globals.map((value) => [0x7f, 0x00, ...I32_CONST(value), 0x0b]))));
  if (!imported) parts.push(section(7, vec([[...name("memory"), 0x02, 0x00]])));
  if (dataCount) parts.push(section(12, uleb(data.length)));
  parts.push(section(10, vec(bodies)));
  if (data.length) parts.push(section(11, vec(data.map(({ at, bytes }) => at === undefined ? [1, ...uleb(bytes.length), ...bytes] : [0, ...I32_CONST(at), 0x0b, ...uleb(bytes.length), ...bytes]))));
  for (const custom of extra) parts.push(section(0, [...name(custom.name), ...custom.bytes]));
  return Uint8Array.from(parts.flat());
}

const fill = (length, value) => Array.from({ length }, (_, index) => (typeof value === "function" ? value(index) : value));
const word = (value) => [value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >>> 24) & 0xff];

/** The initialized memory of the instantiated modules as a map from address to byte (only non-zero bytes). */
function memoryOf(first, second = null) {
  const primary = new WebAssembly.Instance(new WebAssembly.Module(first), {});
  if (second) new WebAssembly.Instance(new WebAssembly.Module(second), { primary: primary.exports });
  const bytes = new Uint8Array(primary.exports.memory.buffer);
  const out = new Map();
  bytes.forEach((byte, address) => { if (byte !== 0) out.set(address, byte); });
  return out;
}

// ---- the linker's map --------------------------------------------------------------------------------------------------

// wasm-ld's columns: Addr Off Size (8 hex digits each), then the output segment, the input section 8 columns in, its symbols 16.
const column = (address, size, text, depth = 0) => `${address.toString(16).padStart(8)} ${(0x275cf5).toString(16).padStart(8)} ${size.toString(16).padStart(8)} ${" ".repeat(depth)}${text}`;
const rows = (...lines) => ["    Addr      Off     Size Out     In      Symbol", ...lines].join("\n") + "\n";
const segmentRow = (address, size, segment) => column(address, size, segment);
const objectRow = (address, size, file, section, symbol) => [column(address, size, `${file}:(${section})`, 8), ...(symbol ? [column(address, size, symbol, 16)] : [])].join("\n");

const MAP = rows(
  "       -        8      98c TYPE",
  "       -     7ecd   26de27 CODE",
  "       -     7ecf        6         <internal>:(__wasm_call_ctors)",
  "       -     7ed5       38         /sdk/libc.a(crt1.c.o):(_initialize)",
  "       -     7ed5       38                 _initialize",
  "       -   275cf4    25c0e DATA",
  segmentRow(0x1000, 0x185b0, ".rodata"),
  objectRow(0x1000, 0x20c3, "<internal>", ".rodata", null),
  objectRow(0x30d0, 0x14, "/app/Site.o", ".rodata..L.str.19.SWIFTUIWEB_LANGUAGE", ".L.str.19.SWIFTUIWEB_LANGUAGE"),
  objectRow(0x30e4, 4, "/app/Site.o", ".rodata.$e18SwiftUIWebFeatures12StorageErrorOs0E0AAWP", "$e18SwiftUIWebFeatures12StorageErrorOs0E0AAWP"),
  segmentRow(0x195b0, 0xc8f0, ".data"),
  objectRow(0x195b0, 0xd0, "/app/Core.o", ".data.$e14SwiftUIWebCore13_StagedRenderCMf", "$e14SwiftUIWebCore13_StagedRenderCMf"),
  objectRow(0x1a000, 0x10, "/app/Core.o", ".data.counter", "$e4Site7counterSivp"),
  segmentRow(0x1b000, 0x1000, ".bss"),
  objectRow(0x1b000, 0x1000, "/app/Core.o", ".bss.cache", "$e4Site5cacheSVvp"),
);

test("the map's data objects: output segment, extent and first symbol, with the code rows and the symbols left out", () => {
  const objects = parseLinkMap(MAP);
  expect(objects.map((object) => [object.address, object.size, object.segment, object.symbol])).toEqual([
    [0x1000, 0x20c3, ".rodata", null],
    [0x30d0, 0x14, ".rodata", ".L.str.19.SWIFTUIWEB_LANGUAGE"],
    [0x30e4, 4, ".rodata", "$e18SwiftUIWebFeatures12StorageErrorOs0E0AAWP"],
    [0x195b0, 0xd0, ".data", "$e14SwiftUIWebCore13_StagedRenderCMf"],
    [0x1a000, 0x10, ".data", "$e4Site7counterSivp"],
    [0x1b000, 0x1000, ".bss", "$e4Site5cacheSVvp"],
  ]);
  expect(parseLinkMap("not a map").length).toBe(0);
});

test("what code never writes: .rodata, and the metadata and witness tables of .data", () => {
  const object = (segment, symbol) => ({ segment, symbol });
  expect(isReadOnly(object(".rodata", ".L.str.1"))).toBe(true);
  expect(isReadOnly(object(".rodata.str", null))).toBe(true);
  expect(isReadOnly(object(".data", "$e14SwiftUIWebCore13_StagedRenderCMf"))).toBe(true);
  expect(isReadOnly(object(".data", "$e18SwiftUIWebFeatures12StorageErrorOs0E0AAWP"))).toBe(true);
  expect(isReadOnly(object(".data", "$e4Site5ThingVWV"))).toBe(true);
  expect(isReadOnly(object(".data", "$e4Site7counterSivp"))).toBe(false);
  expect(isReadOnly(object(".data", null))).toBe(false);
  expect(isReadOnly(object(".bss", "$e4Site5cacheSVvp"))).toBe(false);
  expect(isReadOnly(object(".rodatax", "x"))).toBe(false);
});

// ---- the scan ----------------------------------------------------------------------------------------------------------

test("the scan finds the constants, the folded offsets and the globals' initializers that fall in the data range", () => {
  const module = wasm({
    globals: [5000, 7],
    bodies: [
      body(NAMED(4200), LOAD_AT(4300)),
      // Every kind of immediate between them must be stepped over: a block type, br_table, a call_indirect, memory.copy, an i64.
      body([0x02, 0x40], [0x41, 1], [0x0d, 0], [0x0e, 1, 0, 0], [0x0b], [0x42, 0x80, 0x80, 0x01], DROP, NAMED(4500)),
    ],
    data: [{ at: 4096, bytes: [1, 2, 3] }],
  });
  const found = codeAddresses(module, 4096, 5000);
  expect([...found.keys()].sort((a, b) => a - b)).toEqual([4200, 4300, 4500, 5000]);
  expect(codeAddresses(module, 4096, 4999).has(5000)).toBe(false);
});

test("a module with an opcode the scan does not know is refused, not guessed at", () => {
  const simd = wasm({ bodies: [body([0xfd, 0x0c, ...fill(16, 0)])] });
  expect(() => codeAddresses(simd, 0, 10)).toThrow(/unsupported opcode 0xfd/);
});

// ---- the plan and the move ---------------------------------------------------------------------------------------------

/**
 * Six objects of a first module's memory (addresses 4096 and up, each 1 KB but the small ones):
 *   moving    4096  1024 B  .rodata, named by the second module only
 *   follower  5120  1024 B  .rodata, named by no code, pointed at by `moving` (its first word)
 *   kept      6144  1024 B  .rodata, named by the first module's code
 *   shared    7168  1024 B  .rodata, named by the second module and pointed at by `table`, which stays
 *   table     8192    16 B  .data variable (mutable), holds the address of `shared`
 *   metadata  8208  1024 B  .data type metadata (`...Mf`), named by the second module only
 *   lonely    9232  1024 B  .rodata, named by nobody
 */
function fixture(options = {}) {
  const at = (address, bytes, length) => ({ at: address, bytes: [...bytes, ...fill(length - bytes.length, (index) => ((address + index) % 250) + 1)] });
  const data = [
    at(4096, word(5120), 1024),
    at(5120, [], 1024),
    at(6144, [], 1024),
    at(7168, [], 1024),
    at(8192, word(7168), 16),
    at(8208, [], 1024),
    at(9232, [], 1024),
  ];
  const primary = wasm({ bodies: [body(NAMED(6144 + 4))], data, ...options.primary });
  const secondary = wasm({ imported: true, bodies: [body(NAMED(4096), NAMED(7168), NAMED(8208))], ...options.secondary });
  const map = `    Addr      Off     Size Out     In      Symbol
       -   275cf4    25c0e DATA
    1000   275cf5    185b0 .rodata
    1000   275cfd      400         /app/A.o:(.rodata.moving)
    1000   275cfd      400                 moving
    1400   275cfd      400         /app/A.o:(.rodata.follower)
    1400   275cfd      400                 follower
    1800   275cfd      400         /app/A.o:(.rodata.kept)
    1800   275cfd      400                 kept
    1c00   275cfd      400         /app/A.o:(.rodata.shared)
    1c00   275cfd      400                 shared
    2410   275cfd      400         /app/A.o:(.rodata.lonely)
    2410   275cfd      400                 lonely
    2000   28e2ad     c8f0 .data
    2000   28e2ad       10         /app/A.o:(.data.table)
    2000   28e2ad       10                 table
    2010   28e2ad      400         /app/A.o:(.data.thingMf)
    2010   28e2ad      400                 $e5ThingCMf
`;
  return { primary, secondary, map };
}

test("an object only the second module names moves, with what only the moved objects point at; the rest stays", () => {
  const { primary, secondary, map } = fixture();
  const plan = planDataMove({ primary, secondary, objects: parseLinkMap(map) });
  expect(plan.reason).toBeUndefined();
  expect(plan.objects.map((object) => object.symbol)).toEqual(["moving", "follower", "$e5ThingCMf"]);
  expect(plan.stats.bytes).toBe(1024 * 3);
  // moving and follower touch; metadata is next to the variable `table`, which stays.
  expect(plan.runs).toEqual([[4096, 6144], [8208, 9232]]);
});

/** Two read-only objects `a` (4096, 1 KB) and `b` (5128, 1 KB, 8 bytes of padding after `a`) and the variable `holder` (7168, 16 B). */
function pair({ first, second, holder }) {
  const data = [{ at: 4096, bytes: fill(1024, 3) }, { at: 5128, bytes: fill(1024, 4) }, { at: 7168, bytes: holder ?? fill(16, 0) }];
  const map = rows(
    "       -   275cf4    25c0e DATA",
    segmentRow(0x1000, 0x800, ".rodata"),
    objectRow(0x1000, 0x400, "/app/A.o", ".rodata.a", "a"),
    objectRow(0x1408, 0x400, "/app/A.o", ".rodata.b", "b"),
    segmentRow(0x1c00, 0x10, ".data"),
    objectRow(0x1c00, 0x10, "/app/A.o", ".data.holder", "holder"),
  );
  return {
    map,
    primary: wasm({ bodies: [body(...first.map(NAMED))], data }),
    secondary: wasm({ imported: true, bodies: [body(...second.map(NAMED))] }),
  };
}

test("an address one past the end of an object names that object, so it stays with the first module", () => {
  const { primary, secondary, map } = pair({ first: [5120], second: [4096, 5128] });
  const plan = planDataMove({ primary, secondary, objects: parseLinkMap(map) });
  expect(plan.objects.map((object) => object.symbol)).toEqual(["b"]);
  // Without that address both move, and the padding between them goes along.
  const both = pair({ first: [7168 + 4], second: [4096, 5128] });
  expect(planDataMove({ primary: both.primary, secondary: both.secondary, objects: parseLinkMap(both.map) }).runs).toEqual([[4096, 6152]]);
});

test("a word in an object that stays keeps what it points at, at any byte offset", () => {
  // The holder is a variable, so it stays, and holds the address of `a` at an unaligned offset.
  const holder = [9, ...word(4096 + 16), 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9];
  const { primary, secondary, map } = pair({ first: [7168 + 1], second: [4096, 5128], holder });
  const plan = planDataMove({ primary, secondary, objects: parseLinkMap(map) });
  expect(plan.objects.map((object) => object.symbol)).toEqual(["b"]);
});

test("the two modules validate and, instantiated together, leave memory as the first module had it", () => {
  const { primary, secondary, map } = fixture();
  const result = splitData({ primary, secondary, linkMap: map });
  expect(result.reason).toBeUndefined();
  expect(WebAssembly.validate(result.primary)).toBe(true);
  expect(WebAssembly.validate(result.secondary)).toBe(true);
  const before = memoryOf(primary);
  const after = memoryOf(result.primary, result.secondary);
  expect(after.size).toBe(before.size);
  for (const [address, byte] of before) expect(after.get(address)).toBe(byte);
  // The first module alone no longer holds what moved: the first byte of `moving` and of the metadata are zero.
  const alone = memoryOf(result.primary);
  expect(alone.has(4096 + 8)).toBe(false);
  expect(alone.has(8208 + 4)).toBe(false);
  // What stays is there: `kept`, `shared`, the variable and `lonely`.
  for (const address of [6144 + 5, 7168 + 5, 8192, 9232 + 5]) expect(alone.get(address)).toBe(before.get(address));
});

test("the second module's segments are the moved objects only: zero padding no object owns is moved with them, an object's own zeros are not", () => {
  const padded = (ownedGap) => {
    const data = [{ at: 4096, bytes: fill(1024, 7) }, { at: 5120 + 8, bytes: fill(1024, 8) }];
    const map = `    Addr      Off     Size Out     In      Symbol
       -   275cf4    25c0e DATA
    1000   275cf5    185b0 .rodata
    1000   275cfd      400         /app/A.o:(.rodata.a)
    1000   275cfd      400                 a
    1408   275cfd      400         /app/A.o:(.rodata.b)
    1408   275cfd      400                 b
${ownedGap ? "    1400   275cfd        8         /app/A.o:(.rodata.gap)\n    1400   275cfd        8                 gap\n" : ""}`;
    const primary = wasm({ bodies: [body(NAMED(4096 + 5000))], data });
    const secondary = wasm({ imported: true, bodies: [body(NAMED(4096), NAMED(5128))] });
    return planDataMove({ primary, secondary, objects: parseLinkMap(map) });
  };
  expect(padded(false).runs).toEqual([[4096, 5128 + 1024]]);
  expect(padded(true).runs).toEqual([[4096, 5120], [5128, 5128 + 1024]]);
});

test("a data count section is kept in step with the segments", () => {
  const { primary, secondary, map } = fixture({ primary: { dataCount: true } });
  expect(listSections(primary).some((entry) => entry.id === 12)).toBe(true);
  const result = splitData({ primary, secondary, linkMap: map });
  expect(WebAssembly.validate(result.primary)).toBe(true);
  expect(WebAssembly.validate(result.secondary)).toBe(true);
});

test("nothing moves when the map is not this module's, when the module has a passive segment, or when there is too little", () => {
  const { primary, secondary, map } = fixture();
  // A map of other addresses.
  const other = map.replace(/ 1000 /g, " 9000 ").replace(/ 1400 /g, " 9400 ");
  expect(splitData({ primary, secondary, linkMap: other }).reason).toMatch(/does not describe/);
  expect(splitData({ primary, secondary, linkMap: "no map here" }).reason).toMatch(/does not describe/);
  // A passive segment: memory.init names segments by index.
  const passive = wasm({ bodies: [body(NAMED(6148))], data: [{ at: 4096, bytes: fill(8, 1) }, { bytes: [1, 2, 3] }] });
  expect(splitData({ primary: passive, secondary, linkMap: map }).reason).toMatch(/passive/);
  // Only a few bytes could move.
  const tiny = wasm({ bodies: [body(NAMED(6148))], data: [{ at: 4096, bytes: fill(16, 1) }] });
  const tinyMap = "    Addr      Off     Size Out     In      Symbol\n       -   275cf4    25c0e DATA\n    1000   275cf5       10 .rodata\n    1000   275cfd       10         /a.o:(.rodata.s)\n    1000   275cfd       10                 s\n";
  const tinySecond = wasm({ imported: true, bodies: [body(NAMED(4096))] });
  expect(splitData({ primary: tiny, secondary: tinySecond, linkMap: tinyMap }).reason).toMatch(/could move/);
  // A module the scan cannot read is left alone.
  const simd = wasm({ imported: true, bodies: [body([0xfd, 0x0c, ...fill(16, 0)])] });
  expect(splitData({ primary, secondary: simd, linkMap: map }).reason).toMatch(/could not be analysed/);
});

test("moveData keeps every piece of the first module's segments at its address", () => {
  const { primary, secondary } = fixture();
  const result = moveData(primary, secondary, [[4096, 5120]]);
  const kept = readDataSegments(result.primary).segments;
  expect(kept.some((segment) => segment.offset === 4096)).toBe(false);
  expect(kept.map((segment) => segment.offset)).toContain(5120);
  const carried = readDataSegments(result.secondary).segments;
  expect(carried.map((segment) => [segment.offset, segment.size])).toEqual([[4096, 1024]]);
});

test("a string the linker made the tail of another is one object with it: the first module naming the tail keeps the whole", () => {
  // \`data-padding-top\` (a 1 KB literal here) with \`-top\`, which shares its last bytes, listed in the map as an object of its own.
  const tail = (first) => {
    const map = rows(
      "       -   275cf4    25c0e DATA",
      segmentRow(0x1000, 0x400, ".rodata"),
      objectRow(0x1000, 0x400, "/app/A.o", ".rodata..L.str.1024.data-padding-top", ".L.str.1024.data-padding-top"),
      objectRow(0x1000 + 0x3fb, 5, "/app/A.o", ".rodata..L.str.5.-top", ".L.str.5.-top"),
    );
    return {
      map,
      primary: wasm({ bodies: [body(...first.map(NAMED))], data: [{ at: 4096, bytes: fill(1024, 9) }] }),
      secondary: wasm({ imported: true, bodies: [body(NAMED(4096))] }),
    };
  };
  const shared = tail([4096 + 1019]);
  expect(planDataMove({ primary: shared.primary, secondary: shared.secondary, objects: parseLinkMap(shared.map) }).reason).toMatch(/could move/);
  const alone = tail([]);
  const plan = planDataMove({ primary: alone.primary, secondary: alone.secondary, objects: parseLinkMap(alone.map) });
  expect(plan.objects.map((object) => [object.address, object.size])).toEqual([[4096, 1024]]);
});

test("the map is checked against the text Swift puts in the name of a string literal's section", () => {
  const strings = Array.from({ length: 12 }, (_, index) => `literal-number-${index}`);
  const data = strings.map((text, index) => ({ at: 4096 + index * 32, bytes: [...Buffer.from(text), 0] }));
  const map = (shift) => rows(
    "       -   275cf4    25c0e DATA",
    segmentRow(0x1000, 12 * 32, ".rodata"),
    ...strings.map((text, index) => objectRow(0x1000 + index * 32 + shift, text.length + 1, "/app/A.o", `.rodata..L.str.${text.length + 1}.${text}`, `.L.str.${text.length + 1}.${text}`)),
  );
  const primary = wasm({ bodies: [body(NAMED(4096))], data });
  const secondary = wasm({ imported: true, bodies: [body(NAMED(4096 + 32))] });
  // The right map passes the check (and then finds too little to move); one that is 16 bytes off does not.
  expect(splitData({ primary, secondary, linkMap: map(0) }).reason).toMatch(/could move/);
  expect(splitData({ primary, secondary, linkMap: map(16) }).reason).toMatch(/does not describe/);
});

/** Three read-only objects of 1 KB that touch (4096, 5120 and 6144), the last two named by the second module only, and any
 * extra bytes of the first module's memory (`unmapped`: address and bytes the map gives to no object). */
function neighbours({ first, second, unmapped = [] }) {
  const map = rows(
    "       -   275cf4    25c0e DATA",
    segmentRow(0x1000, 0xc00, ".rodata"),
    objectRow(0x1000, 0x400, "/app/A.o", ".rodata.a", "a"),
    objectRow(0x1400, 0x400, "/app/A.o", ".rodata.b", "b"),
    objectRow(0x1800, 0x400, "/app/A.o", ".rodata.c", "c"),
  );
  const data = [4096, 5120, 6144].map((at) => ({ at, bytes: fill(1024, 5) })).concat(unmapped.map(([at, bytes]) => ({ at, bytes })));
  return {
    map,
    primary: wasm({ bodies: [body(...first.map(NAMED))], data }),
    secondary: wasm({ imported: true, bodies: [body(...second.map(NAMED))] }),
  };
}

test("an address that ends one object and starts the next names both, for the first module and not for the second", () => {
  // The first module holds 5120: the end of a, which a loop over a may stop at, and the start of b. a and b stay; c moves.
  const touching = neighbours({ first: [5120], second: [4096, 5120, 6144] });
  expect(planDataMove({ primary: touching.primary, secondary: touching.secondary, objects: parseLinkMap(touching.map) }).objects.map((object) => object.symbol)).toEqual(["c"]);
  // The second module naming 5120 names b alone: a is not carried along by it.
  const alone = neighbours({ first: [], second: [5120] });
  expect(planDataMove({ primary: alone.primary, secondary: alone.secondary, objects: parseLinkMap(alone.map) }).objects.map((object) => object.symbol)).toEqual(["b"]);
});

test("initialized bytes the map gives to no object keep what they point at", () => {
  // Nothing but a word at 9000, in no object, holds the address of a (4096); the second module names a and b.
  const word4096 = word(4096);
  const held = neighbours({ first: [6144 + 4], second: [4096, 5120], unmapped: [[9000, [...word4096, 1, 2, 3, 4]]] });
  expect(planDataMove({ primary: held.primary, secondary: held.secondary, objects: parseLinkMap(held.map) }).objects.map((object) => object.symbol)).toEqual(["b"]);
  const free = neighbours({ first: [6144 + 4], second: [4096, 5120], unmapped: [[9000, [1, 2, 3, 4, 1, 2, 3, 4]]] });
  expect(planDataMove({ primary: free.primary, secondary: free.secondary, objects: parseLinkMap(free.map) }).objects.map((object) => object.symbol)).toEqual(["a", "b"]);
});

test("a string at the start of the data names itself by an address below the data", () => {
  // The literal is the first object of the image (4096) and the first module holds 4076 + 20, which is how a String names it.
  const map = rows(
    "       -   275cf4    25c0e DATA",
    segmentRow(0x1000, 0x800, ".rodata"),
    objectRow(0x1000, 0x400, "/app/A.o", ".rodata..L.str.1024.first-literal", ".L.str.1024.first-literal"),
    objectRow(0x1400, 0x400, "/app/A.o", ".rodata.b", "b"),
  );
  const data = [{ at: 4096, bytes: fill(1024, 9) }, { at: 5120, bytes: fill(1024, 8) }];
  const secondary = wasm({ imported: true, bodies: [body(NAMED(4096), NAMED(5120))] });
  const named = wasm({ bodies: [body(NAMED(4076))], data });
  expect(planDataMove({ primary: named, secondary, objects: parseLinkMap(map) }).objects.map((object) => object.symbol)).toEqual(["b"]);
  const unnamed = wasm({ bodies: [body(NAMED(4056))], data });
  expect(planDataMove({ primary: unnamed, secondary, objects: parseLinkMap(map) }).objects.map((object) => object.symbol)).toEqual([".L.str.1024.first-literal", "b"]);
});
