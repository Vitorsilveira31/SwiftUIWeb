#!/usr/bin/env bun
// The small build tools behind Tools/swiftuiweb-tools.sh: the capability matrix, the BrowserIO operation constants,
// Wasm metadata stripping and string-catalog translations. Every command prints one result line (or JSON) on stdout
// and fails with `swiftuiweb-tools: <reason>` on stderr and status 1.
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dumps, parseJson, readJson } from "./format-compat.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const USAGE = `Usage: swiftuiweb-tools <command> [options]

Commands:
  feature-matrix [--check|--write]  Validate/render the capability matrix
  browser-io-protocol [--check|--write]
                                    Validate/generate BrowserIO operation constants
  binary-atoms [--check|--write]    Validate/generate the binary publication atoms and constants
  strip-wasm <input.wasm> [output.wasm]
                                    Remove name/DWARF sections from a Wasm module
  apply-translations <catalog.xcstrings> <language> <translations.json> [plurals.json]
                                    Write a language's translations into a string catalog
`;

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const isUInt32 = (value) => typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= 0xffffffff;
/** `--check` or `--write` (or nothing); anything else is a usage error. */
function mode(command, options) {
  if (options.length > 1 || (options.length === 1 && options[0] !== "--check" && options[0] !== "--write")) {
    throw new Error(`${command} accepts only --check or --write`);
  }
  return options[0]?.slice(2) ?? "validate";
}

// --- feature-matrix ---------------------------------------------------------------------------------------------------

const MANIFEST_PATH = "Tests/FeatureMatrix/manifest.json";
const MATRIX_PATH = "Documentation/FEATURE_MATRIX.md";
const STATUSES = ["supported", "fallback", "unsupported", "no-op"];

const safeRelativePath = (path) => path !== "" && !path.startsWith("/") && !path.split("/").includes("..");

function loadFeatures(root) {
  const document = readJson(join(root, MANIFEST_PATH));
  if (document.schemaVersion !== 1) throw new Error(`${MANIFEST_PATH}: unsupported feature matrix schema`);
  if (!Array.isArray(document.features)) throw new Error(`${MANIFEST_PATH}: \`features\` must be an array`);
  const seen = new Set();
  return document.features.map((entry, index) => {
    const id = entry?.id;
    if (typeof id !== "string" || id === "") throw new Error(`${MANIFEST_PATH}: feature ${index} has an invalid id`);
    if (seen.has(id)) throw new Error(`${MANIFEST_PATH}: invalid or duplicate feature id: \`${id}\``);
    seen.add(id);
    if (typeof entry.status !== "string") throw new Error(`${id}: status must be a string`);
    if (!STATUSES.includes(entry.status)) throw new Error(`${id}: status must be one of ${STATUSES.join(", ")}`);
    if (!Array.isArray(entry.evidence) || entry.evidence.length === 0) throw new Error(`${id}: evidence is required`);
    for (const path of entry.evidence) {
      if (typeof path !== "string" || path === "") throw new Error(`${id}: evidence paths must be strings`);
      if (!safeRelativePath(path)) throw new Error(`${id}: evidence path must stay within the repository: ${path}`);
      if (!existsSync(join(root, path))) throw new Error(`${id}: missing evidence ${path}`);
    }
    return { id, status: entry.status, evidence: entry.evidence };
  });
}

function renderMatrix(features) {
  return [
    "# SwiftUIWeb feature matrix",
    "",
    "This is the runtime contract for the canonical Embedded Swift + browser host. `supported` means the capability is exercised by the host; `fallback` means the semantic API remains available with a documented browser/native substitute; `unsupported` is an explicit capability result; `no-op` is an intentional side-effect-free modifier. Every row must retain executable source evidence.",
    "",
    "| Feature | Embedded status | Evidence |",
    "| --- | --- | --- |",
    ...features.map(({ id, status, evidence }) => `| \`${id}\` | **${status}** | ${evidence.map((item) => `\`${item}\``).join(", ")} |`),
    "",
    "The matrix is checked by `make feature-matrix`; it deliberately does not infer support from a source-name match or from a native-only build.",
    "",
  ].join("\n");
}

export function featureMatrix(options, root) {
  const action = mode("feature-matrix", options);
  const features = loadFeatures(root);
  const rendered = renderMatrix(features);
  if (action === "check" && readFileSync(join(root, MATRIX_PATH), "utf8") !== rendered) {
    throw new Error(`${MATRIX_PATH} is stale; run \`make feature-matrix-write\``);
  }
  if (action === "write") writeFileSync(join(root, MATRIX_PATH), rendered);
  console.log(`PASS feature matrix (${features.length} explicit capabilities)`);
}

// --- browser-io-protocol ----------------------------------------------------------------------------------------------

const SCHEMA_PATH = "Documentation/BrowserIO/PROTOCOL.json";
const SWIFT_PATH = "Sources/SwiftUIWebBrowserIO/BrowserIOProtocol.generated.swift";
const JAVASCRIPT_PATH = "Tools/BrowserIO/protocol.generated.mjs";
const GENERATED = "// Generated by swiftuiweb-tools browser-io-protocol; do not edit.\n";

const swiftName = (name) => name[0].toLowerCase() + name.slice(1);

/** The `operations` (positive UInt32 IDs) or `events` (status codes of at least 100) object of the schema: unique values, identifier names. */
function loadCodes(table, kind, minimum) {
  if (!isObject(table)) throw new Error(`${SCHEMA_PATH}: ${kind}s must be an object`);
  const seen = new Set();
  return Object.entries(table).map(([name, code]) => {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error(`${SCHEMA_PATH}: invalid ${kind} name \`${name}\``);
    if (!isUInt32(code) || code < minimum) {
      throw new Error(kind === "operation" ? `BrowserIO operation \`${name}\` must have a positive UInt32 ID` : `BrowserIO event \`${name}\` must have a status code of at least 100`);
    }
    if (seen.has(code)) throw new Error(kind === "operation" ? "BrowserIO operation IDs must be unique" : "BrowserIO event codes must be unique");
    seen.add(code);
    return [name, code];
  });
}

function renderProtocol({ version, operations, events }) {
  const swift = `${GENERATED}@usableFromInline enum _BrowserIOProtocol {\n  @usableFromInline static let version: UInt32 = ${version}\n`
    + operations.map(([name, id]) => `  @usableFromInline static let ${swiftName(name)}: UInt32 = ${id}\n`).join("")
    + "}\n"
    // Host status codes arrive as Int32, the type of every BrowserIO callback status.
    + (events.length ? `@usableFromInline enum _BrowserIOEvent {\n${events.map(([name, code]) => `  @usableFromInline static let ${swiftName(name)}: Int32 = ${code}\n`).join("")}}\n` : "");
  const table = (title, entries) => `export const ${title} = Object.freeze({\n${entries.map(([name, code]) => `  ${name}: ${code},\n`).join("")}});\n`;
  const javascript = `${GENERATED}export const BROWSER_IO_PROTOCOL_VERSION = ${version};\n${table("BrowserIOOperation", operations)}`
    + (events.length ? table("BrowserIOEvent", events) : "");
  return [[SWIFT_PATH, swift], [JAVASCRIPT_PATH, javascript]];
}

export function browserIOProtocol(options, root) {
  const action = mode("browser-io-protocol", options);
  const document = readJson(join(root, SCHEMA_PATH));
  if (!isUInt32(document.version) || document.version === 0) throw new Error(`${SCHEMA_PATH}: protocol version must be a positive UInt32`);
  if (!isObject(document.operations)) throw new Error(`${SCHEMA_PATH}: operations must be an object`);
  if (Object.keys(document.operations).length === 0) throw new Error(`${SCHEMA_PATH}: operations must not be empty`);
  const outputs = renderProtocol({
    version: document.version,
    operations: loadCodes(document.operations, "operation", 1),
    events: document.events === undefined ? [] : loadCodes(document.events, "event", 100),
  });
  if (action !== "check") {
    for (const [path, content] of outputs) writeFileSync(join(root, path), content);
    console.log("Generated BrowserIO protocol constants");
    return;
  }
  const read = (path) => (existsSync(join(root, path)) ? readFileSync(join(root, path), "utf8") : null);
  const stale = outputs.filter(([path, content]) => read(path) !== content).map(([path]) => path);
  if (stale.length) throw new Error(`STALE BrowserIO generated files: ${stale.join(", ")}`);
  console.log("PASS BrowserIO protocol generation");
}

// --- binary-atoms -----------------------------------------------------------------------------------------------------

const ATOMS_PATH = "Tools/binary-atoms.json";
const ATOMS_SWIFT_PATH = "Sources/SwiftUIWebHTML/BinaryAtoms.generated.swift";
const ATOMS_JAVASCRIPT_PATH = "Tools/binary-atoms.generated.js";

/** FNV-1a over the UTF-8 bytes: the hash both ends compare before they trust each other's atom indices. */
function fnv32(text) {
  let hash = 0x811c9dc5;
  for (const byte of Buffer.from(text, "utf8")) hash = Math.imul(hash ^ byte, 0x01000193) >>> 0;
  return hash;
}

/** A Swift string literal for `text`: quotes, backslashes and anything that is not printable ASCII escaped. */
function swiftLiteral(text) {
  let out = "";
  for (const character of text) {
    const code = character.codePointAt(0);
    if (character === '"' || character === "\\") out += "\\" + character;
    else if (code === 0) out += "\\0";
    else if (code < 0x20 || code >= 0x7f) out += `\\u{${code.toString(16)}}`;
    else out += character;
  }
  return `"${out}"`;
}

/** The ops or namespaces of the schema: identifier names, unique integers from 1 to 255. */
function loadNames(table, kind) {
  if (!isObject(table) || Object.keys(table).length === 0) throw new Error(`${ATOMS_PATH}: ${kind}s must be a non-empty object`);
  const seen = new Set();
  return Object.entries(table).map(([name, value]) => {
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(name)) throw new Error(`${ATOMS_PATH}: invalid ${kind} name \`${name}\``);
    if (!Number.isInteger(value) || value < 1 || value > 255) throw new Error(`${ATOMS_PATH}: ${kind} \`${name}\` must be an integer from 1 to 255`);
    if (seen.has(value)) throw new Error(`${ATOMS_PATH}: ${kind} values must be unique`);
    seen.add(value);
    return [name, value];
  });
}

/** `ELEMENT_NS` as `elementNs`, `svg` as `svg`. */
const camelCase = (name) => name.toLowerCase().replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());

function renderAtoms({ version, ops, namespaces, atoms }) {
  const hash = fnv32(`v${version}\n${atoms.join("\0")}`);
  const hex = `0x${hash.toString(16).padStart(8, "0")}`;
  const header = "// Generated by swiftuiweb-tools binary-atoms; do not edit.\n";
  const swift = `${header}/// The binary publication format shared with Tools/binary-publication.js (Documentation/Architecture/BINARY_PATCHES.md).\n`
    + `enum _BinaryFormat {\n  static let version: UInt16 = ${version}\n  static let atomsHash: UInt32 = ${hex}\n  static let atomCount: UInt32 = ${atoms.length}\n`
    + ops.map(([name, value]) => `  static let op${camelCase(name)[0].toUpperCase()}${camelCase(name).slice(1)}: UInt32 = ${value}\n`).join("")
    + namespaces.map(([name, value]) => `  static let namespace${camelCase(name)[0].toUpperCase()}${camelCase(name).slice(1)}: UInt32 = ${value}\n`).join("")
    + `  /// The atoms in index order, separated by NUL.\n  static let atoms: StaticString = ${swiftLiteral(atoms.join("\0"))}\n}\n`;
  const javascript = `${header}export const BINARY_VERSION = ${version};\nexport const BINARY_ATOMS_HASH = ${hex};\n`
    + `export const BINARY_OPS = Object.freeze({\n${ops.map(([name, value]) => `  ${name}: ${value},\n`).join("")}});\n`
    + `export const BINARY_NAMESPACES = Object.freeze({\n${namespaces.map(([name, value]) => `  ${name}: ${value},\n`).join("")}});\n`
    + `// Tests and tools only: the runtime takes the atoms from the publications (Documentation/Architecture/BINARY_PATCHES.md), so a\n`
    + `// bundle drops this list.\nexport const BINARY_ATOMS = /* @__PURE__ */ Object.freeze([\n${atoms.map((atom) => `  ${JSON.stringify(atom)},\n`).join("")}]);\n`;
  return [[ATOMS_SWIFT_PATH, swift], [ATOMS_JAVASCRIPT_PATH, javascript]];
}

export function binaryAtoms(options, root) {
  const action = mode("binary-atoms", options);
  const document = readJson(join(root, ATOMS_PATH));
  if (!Number.isInteger(document.version) || document.version < 1 || document.version > 0xffff) throw new Error(`${ATOMS_PATH}: version must be a positive UInt16`);
  const atoms = [];
  const seen = new Set();
  for (const kind of ["tags", "attributes", "values"]) {
    if (!Array.isArray(document[kind])) throw new Error(`${ATOMS_PATH}: ${kind} must be an array`);
    for (const atom of document[kind]) {
      if (typeof atom !== "string" || atom.includes("\0")) throw new Error(`${ATOMS_PATH}: ${kind} must hold strings without NUL`);
      if (seen.has(atom)) throw new Error(`${ATOMS_PATH}: atom ${JSON.stringify(atom)} is listed twice`);
      seen.add(atom);
      atoms.push(atom);
    }
  }
  if (atoms.length === 0) throw new Error(`${ATOMS_PATH}: there are no atoms`);
  const outputs = renderAtoms({ version: document.version, ops: loadNames(document.ops, "op"), namespaces: loadNames(document.namespaces, "namespace"), atoms });
  if (action !== "check") {
    for (const [path, content] of outputs) writeFileSync(join(root, path), content);
    console.log("Generated binary publication atoms");
    return;
  }
  const read = (path) => (existsSync(join(root, path)) ? readFileSync(join(root, path), "utf8") : null);
  const stale = outputs.filter(([path, content]) => read(path) !== content).map(([path]) => path);
  if (stale.length) throw new Error(`STALE binary atom generated files: ${stale.join(", ")}`);
  console.log("PASS binary atom generation");
}

// --- strip-wasm -------------------------------------------------------------------------------------------------------

const WASM_MAGIC = Buffer.from("\0asm\x01\0\0\0", "latin1");

function u32Leb(data, offset, limit) {
  let value = 0;
  for (let index = 0; index < 5; index += 1) {
    if (offset >= limit) throw new Error("truncated unsigned LEB128");
    const byte = data[offset++];
    if (index === 4 && (byte & 0xf0) !== 0) throw new Error("overflowing unsigned LEB128");
    value += (byte & 0x7f) * 2 ** (7 * index);
    if ((byte & 0x80) === 0) return [value, offset];
  }
  throw new Error("invalid unsigned LEB128");
}

/** The module without its `name` and `.debug_*` custom sections, and the sections it dropped (`{ name, bytes }`, header included). */
export function stripWasm(data) {
  if (!data.subarray(0, 8).equals(WASM_MAGIC)) throw new Error("expected a WebAssembly v1 module, not an archive/object container");
  const kept = [WASM_MAGIC];
  const removed = [];
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let offset = 8;
  while (offset < data.length) {
    const start = offset;
    const [length, payload] = u32Leb(data, offset + 1, data.length);
    const end = payload + length;
    if (end > data.length) throw new Error("section extends beyond the module");
    let name = null;
    if (data[start] === 0) {
      const [size, nameStart] = u32Leb(data, payload, end);
      if (nameStart + size > end) throw new Error("custom section name extends beyond the section");
      try {
        name = decoder.decode(data.subarray(nameStart, nameStart + size));
      } catch (error) {
        throw new Error(`custom section name is not UTF-8: ${error.message}`);
      }
    }
    if (name === "name" || name?.startsWith(".debug_")) removed.push({ name, bytes: end - start });
    else kept.push(data.subarray(start, end));
    offset = end;
  }
  return [Buffer.concat(kept), removed];
}

/** Strips `source` into `target` (the same path rewrites in place); a module with nothing to remove is left untouched when it is rewritten in place. */
function stripWasmFile(source, target) {
  const raw = readFileSync(source);
  const [result, removed] = stripWasm(raw);
  const report = (after) => ({ wasm: target, before: raw.length, after, removed });
  if (removed.length === 0 && existsSync(target) && realpathSync(target) === realpathSync(source)) {
    return report(raw.length);
  }
  mkdirSync(dirname(target), { recursive: true });
  const temporary = join(dirname(target), `.strip-wasm-${process.pid}-${process.hrtime.bigint()}.tmp`);
  try {
    writeFileSync(temporary, result);
    chmodSync(temporary, statSync(source).mode & 0o777);
    renameSync(temporary, target);
  } catch (error) {
    rmSync(temporary, { force: true });
    throw error;
  }
  return report(result.length);
}

function stripWasmCommand(options) {
  if (options.length < 1 || options.length > 2) throw new Error("usage: swiftuiweb-tools strip-wasm <input.wasm> [output.wasm]");
  try {
    console.log(dumps(stripWasmFile(options[0], options[1] ?? options[0])));
  } catch (error) {
    throw new Error(`Wasm stripping failed: ${error.message}`);
  }
}

// --- apply-translations -----------------------------------------------------------------------------------------------

const unit = (value) => ({ stringUnit: { state: "translated", value } });

/** Quoted text of a key, as the diagnostics print it. */
function reprString(text) {
  const quote = text.includes("'") && !text.includes('"') ? '"' : "'";
  const escaped = text.replace(/[\\'"\x00-\x1f\x7f]/g, (ch) => {
    if (ch === quote || ch === "\\") return `\\${ch}`;
    if (ch === '"' || ch === "'") return ch;
    return { "\n": "\\n", "\r": "\\r", "\t": "\\t" }[ch] ?? `\\x${ch.charCodeAt(0).toString(16).padStart(2, "0")}`;
  });
  return quote + escaped + quote;
}

/** Merges translations into `catalog` in place and returns the keys it does not have. Keys of `plurals` win over a plain translation. */
export function applyTranslations(catalog, language, translations, plurals) {
  if (!isObject(catalog.strings)) throw new Error("the catalog has no `strings` object");
  const { strings } = catalog;
  const has = (key) => Object.hasOwn(strings, key);
  const localizations = (key) => {
    if (!isObject(strings[key])) strings[key] = {};
    if (!isObject(strings[key].localizations)) strings[key].localizations = {};
    return strings[key].localizations;
  };
  const unknown = [...Object.keys(translations), ...Object.keys(plurals)].filter((key) => !has(key));
  for (const [key, text] of Object.entries(translations)) {
    if (has(key) && !Object.hasOwn(plurals, key)) localizations(key)[language] = unit(text);
  }
  for (const [key, perLanguage] of Object.entries(plurals)) {
    if (!has(key)) continue;
    if (!isObject(perLanguage)) throw new Error(`plurals for ${JSON.stringify(key)} must be an object`);
    for (const [lang, forms] of Object.entries(perLanguage)) {
      if (!isObject(forms)) throw new Error(`plural forms of ${JSON.stringify(key)}/${lang} must be an object`);
      localizations(key)[lang] = { variations: { plural: Object.fromEntries(Object.entries(forms).map(([category, text]) => [category, unit(text)])) } };
    }
  }
  return unknown;
}

function applyTranslationsCommand(options) {
  if (options.length !== 3 && options.length !== 4) {
    throw new Error("usage: swiftuiweb-tools apply-translations <catalog.xcstrings> <language> <translations.json> [plurals.json]");
  }
  const [catalogPath, language, translationsPath, pluralsPath] = options;
  const load = (path, what) => {
    let value;
    try {
      value = parseJson(readFileSync(path, "utf8"));
    } catch (error) {
      throw new Error(`${path}: ${error.message}`);
    }
    if (!isObject(value)) throw new Error(`${path}: ${what} must be a JSON object`);
    return value;
  };
  const catalog = load(catalogPath, "the catalog");
  const translations = load(translationsPath, "translations");
  const plurals = pluralsPath === undefined ? {} : load(pluralsPath, "plurals");
  const unknown = applyTranslations(catalog, language, translations, plurals);
  // Xcode's layout: key order kept, two-space indent, non-ASCII text as is.
  writeFileSync(catalogPath, `${dumps(catalog, { indent: 2, ensureAscii: false, separators: [",", ": "] })}\n`);
  console.log(`applied ${Object.keys(translations).length} translations and ${Object.keys(plurals).length} plurals; keys not in the catalog: ${unknown.length}`);
  for (const key of unknown.slice(0, 20)) console.log(`  unknown: ${reprString(key)}`);
}

// --- command line -----------------------------------------------------------------------------------------------------

if (import.meta.main) {
  const [command, ...options] = process.argv.slice(2);
  const commands = {
    "feature-matrix": featureMatrix,
    "browser-io-protocol": browserIOProtocol,
    "binary-atoms": binaryAtoms,
    "strip-wasm": stripWasmCommand,
    "apply-translations": applyTranslationsCommand,
  };
  try {
    if (command === undefined) throw new Error(USAGE);
    if (command === "--help" || command === "-h" || options.includes("--help") || options.includes("-h")) {
      process.stdout.write(USAGE);
    } else if (Object.hasOwn(commands, command)) {
      commands[command](options, ROOT);
    } else {
      throw new Error(`unknown command \`${command}\`\n\n${USAGE}`);
    }
  } catch (error) {
    console.error(`swiftuiweb-tools: ${error.message}`);
    process.exit(1);
  }
}
