// Loads a WebAssembly side module into a running main module: the application of a hot build (Tools/dev-direct-build.mjs,
// `--hot`) into the module that holds the framework and the standard library. It is the part of a dynamic linker the page
// needs, and only a development build ever calls it.
//
// The side module is position independent (a `dylink.0` section, `wasm-ld --shared`). It imports the main module's memory
// and table, a base address for its data and one for its functions, every function it calls in the main module, and a
// global per address it takes (`GOT.mem`, `GOT.func`). Loading it is:
//
//   1. memory for its data from the main module's allocator, and table slots for its functions;
//   2. its imports from the main module's exports (the main module of a hot build exports every symbol);
//   3. after it is instantiated, the globals of the addresses it defines itself;
//   4. `__wasm_apply_data_relocs`, which writes the absolute addresses into its data;
//   5. the linker's own bytes back over every location-relative field (`relativeFields`): that function also adds the
//      memory base to a difference between two addresses of the module, which must not move, and Swift's metadata is made
//      of such differences (a generic type found by its mangled name traps without this);
//   6. its types, protocols and conformances registered with the Swift runtime, which finds them by walking the
//      sections of the images it knows;
//   7. its constructors.

const LOCREL_I32 = 23;
/** The relocation types that carry an addend (the format of a `reloc.*` section). */
const WITH_ADDEND = new Set([3, 4, 5, 8, 9, 11, 14, 15, 16, 17, 21, 22, 23, 24, 25]);
const SWIFT_SECTIONS = [['swift5_protocols', 'swift_registerProtocols'], ['swift5_protocol_conformances', 'swift_registerProtocolConformances'], ['swift5_type_metadata', 'swift_registerTypeMetadataRecords']];

function reader(bytes, start = 0) {
  let offset = start;
  return {
    get offset() { return offset; }, set offset(value) { offset = value; },
    byte: () => bytes[offset++],
    leb() { let result = 0, shift = 0, byte; do { byte = bytes[offset++]; result |= (byte & 0x7f) << shift; shift += 7; } while (byte & 0x80); return result >>> 0; },
    sleb() { let result = 0, shift = 0, byte; do { byte = bytes[offset++]; result |= (byte & 0x7f) << shift; shift += 7; } while (byte & 0x80); if (shift < 32 && (byte & 0x40)) result |= -1 << shift; return result; },
  };
}

/** `{ memorySize, memoryAlign, tableSize }` from the `dylink.0` section of a side module. */
export function dylinkInfo(module) {
  const [section] = WebAssembly.Module.customSections(module, 'dylink.0');
  if (!section) throw new Error('not a side module: it has no dylink.0 section');
  const bytes = new Uint8Array(section), input = reader(bytes);
  const info = { memorySize: 0, memoryAlign: 0, tableSize: 0 };
  while (input.offset < bytes.length) {
    const kind = input.leb(), size = input.leb(), end = input.offset + size;
    if (kind === 1) { info.memorySize = input.leb(); info.memoryAlign = input.leb(); info.tableSize = input.leb(); }
    input.offset = end;
  }
  return info;
}

/**
 * The location-relative fields of a side module's data (R_WASM_MEMORY_ADDR_LOCREL_I32, which `wasm-ld --emit-relocs`
 * keeps in `reloc.DATA`): `{ memoryOffset, bytes }`, where each lands below the memory base and the four bytes the linker
 * wrote there.
 */
export function relativeFields(bytes) {
  const input = reader(bytes, 8);
  const segments = [], sites = [];
  let payload = -1;
  while (input.offset < bytes.length) {
    const id = input.byte(), size = input.leb(), end = input.offset + size;
    if (id === 11) {
      payload = input.offset;
      const count = input.leb();
      for (let i = 0; i < count; i++) {
        const flags = input.leb();
        let memoryOffset = 0;
        if (flags === 2) input.leb();
        if (flags !== 1) {
          for (;;) {
            const opcode = input.byte();
            if (opcode === 0x0b) break;
            if (opcode === 0x23) input.leb(); else if (opcode === 0x41) memoryOffset += input.sleb(); else if (opcode !== 0x6a) throw new Error(`unexpected opcode ${opcode} in a data segment's offset`);
          }
        }
        const length = input.leb();
        segments.push({ start: input.offset - payload, length, memoryOffset, passive: flags === 1 });
        input.offset += length;
      }
    } else if (id === 0) {
      const nameLength = input.leb(), name = new TextDecoder().decode(bytes.subarray(input.offset, input.offset + nameLength));
      input.offset += nameLength;
      if (name === 'reloc.DATA') {
        input.leb();
        const count = input.leb();
        for (let i = 0; i < count; i++) {
          const type = input.byte(), at = input.leb();
          input.leb();
          if (WITH_ADDEND.has(type)) input.sleb();
          if (type === LOCREL_I32) sites.push(at);
        }
      }
    }
    input.offset = end;
  }
  return sites.map((at) => {
    const segment = segments.find((candidate) => at >= candidate.start && at + 4 <= candidate.start + candidate.length);
    if (!segment || segment.passive) throw new Error('a location-relative field is outside the data segments');
    return { memoryOffset: segment.memoryOffset + (at - segment.start), bytes: bytes.slice(payload + at, payload + at + 4) };
  });
}

/**
 * Instantiates the side module `bytes` inside `main` (an instance whose exports hold every symbol). Returns the side
 * module's instance. A symbol the main module does not have is an error that names it.
 */
export function loadSideModule(main, bytes) {
  const exports = main.exports, table = exports.__indirect_function_table, memory = exports.memory;
  const module = new WebAssembly.Module(bytes);
  const info = dylinkInfo(module), relative = relativeFields(bytes);
  const align = 1 << info.memoryAlign;
  const allocated = info.memorySize ? exports.malloc(info.memorySize + align) : 0;
  if (info.memorySize && !allocated) throw new Error('the main module could not allocate the side module\'s data');
  const memoryBase = info.memorySize ? (allocated + align - 1) & ~(align - 1) : 0;
  if (info.memorySize) new Uint8Array(memory.buffer, memoryBase, info.memorySize).fill(0);
  const tableBase = table.length;
  if (info.tableSize) table.grow(info.tableSize);

  const indexes = new Map();
  const indexOf = (fn) => {
    let index = indexes.get(fn);
    if (index === undefined) { index = table.length; table.grow(1); table.set(index, fn); indexes.set(fn, index); }
    return index;
  };
  const global = (value, mutable) => new WebAssembly.Global({ value: 'i32', mutable }, value);
  const env = Object.create(null), gotMemory = Object.create(null), gotFunction = Object.create(null);
  const ownMemory = [], ownFunction = [], missing = [];
  Object.assign(env, { memory, __indirect_function_table: table, __stack_pointer: exports.__stack_pointer, __memory_base: global(memoryBase, false), __table_base: global(tableBase, false) });
  for (const wanted of WebAssembly.Module.imports(module)) {
    const symbol = exports[wanted.name];
    if (wanted.module === 'env') {
      if (wanted.name in env) continue;
      if (symbol === undefined) missing.push(wanted.name); else env[wanted.name] = symbol;
    } else if (wanted.module === 'GOT.mem') {
      const slot = global(0, true);
      if (symbol instanceof WebAssembly.Global) slot.value = symbol.value; else ownMemory.push([wanted.name, slot]);
      gotMemory[wanted.name] = slot;
    } else if (wanted.module === 'GOT.func') {
      const slot = global(0, true);
      if (typeof symbol === 'function') slot.value = indexOf(symbol); else ownFunction.push([wanted.name, slot]);
      gotFunction[wanted.name] = slot;
    }
  }
  if (missing.length > 0) throw new Error(`the main module lacks ${missing.length} symbol(s) the side module uses: ${missing.slice(0, 5).join(', ')}`);

  const side = new WebAssembly.Instance(module, { env, 'GOT.mem': gotMemory, 'GOT.func': gotFunction });
  for (const [name, slot] of ownMemory) {
    const symbol = side.exports[name];
    if (!(symbol instanceof WebAssembly.Global)) throw new Error(`neither module defines the data symbol ${name}`);
    slot.value = memoryBase + symbol.value;
  }
  for (const [name, slot] of ownFunction) {
    const symbol = side.exports[name];
    if (typeof symbol !== 'function') throw new Error(`neither module defines the function ${name}`);
    slot.value = indexOf(symbol);
  }
  side.exports.__wasm_apply_data_relocs?.();
  for (const field of relative) new Uint8Array(memory.buffer, memoryBase + field.memoryOffset, 4).set(field.bytes);
  for (const [section, register] of SWIFT_SECTIONS) {
    const start = side.exports[`__start_${section}`], stop = side.exports[`__stop_${section}`];
    if (start instanceof WebAssembly.Global && stop instanceof WebAssembly.Global && stop.value > start.value) exports[register](memoryBase + start.value, memoryBase + stop.value);
  }
  side.exports.__wasm_call_ctors?.();
  return side;
}

/** Whether `module` is the main module of a hot build: it exports its symbols and leaves the application's entry out. */
export function isHotMainModule(module) {
  let allocator = false;
  for (const entry of WebAssembly.Module.exports(module)) {
    if (entry.name === 'embedded_browser_start') return false;
    if (entry.name === 'swift_registerProtocolConformances') allocator = true;
  }
  return allocator;
}

/** The functions the main module of a hot build imports from the application, bound to whatever side module `current()` is. */
export function applicationImports(module, current) {
  const env = Object.create(null);
  for (const wanted of WebAssembly.Module.imports(module)) {
    if (wanted.module === 'env' && wanted.kind === 'function') env[wanted.name] = (...values) => current().exports[wanted.name](...values);
  }
  return env;
}

/** One object with the exports of both modules, the application's first: what the host calls as the instance's exports. */
export function mergedExports(main, side, into = Object.create(null)) {
  for (const key of Object.keys(into)) delete into[key];
  Object.assign(into, main.exports, side.exports);
  return into;
}
