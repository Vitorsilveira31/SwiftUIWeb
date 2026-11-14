#!/usr/bin/env bun
/**
 * Compile string catalogs into a Swift table for the web build.
 *
 * SwiftUI looks `Text("key")` and `String(localized:)` up in the app's string
 * catalog (`Localizable.xcstrings`) or `<language>.lproj/Localizable.strings`.
 * Xcode does that natively; the browser build has no bundle lookup, so this reads
 * the same files and writes a Swift source that registers every translation with
 * `LocalizationTable` at launch, as one constant string per language, sorted by key, so
 * the strings are static data rather than code that builds a dictionary:
 *
 *     bun Tools/compile-strings.mjs Sources/Shared/Resources -o Sources/Shared/Generated/LocalizedStrings.generated.swift
 *
 * Supported: `.xcstrings` with `stringUnit` values and plural variations, and
 * classic `.strings` files (`"key" = "value";`, block and line comments, `\n`,
 * `\"`, `\\`, `\U` escapes). Device variations and substitutions are skipped.
 * The generated file is wrapped in `#if WEB`, so native builds ignore it.
 *
 * Keeps a stable CLI, messages and exit codes, and writes byte-identical generated Swift.
 * Paths are handled as parts (suffix and stem rules), and text is read with universal newlines.
 */

import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PROG = "compile-strings.mjs";
const SKIPPED = new Set([".build", ".git", "node_modules", "DerivedData"]);

const PLURAL_MARKER = "\x01";
const CATEGORY_END = "\x02";
// None of \x01-\x04 may appear in a key, a value, or a plural category: the runtime splits on them.
const SEPARATOR = /[\x01-\x04]/;

// `\s` here is the Unicode whitespace set: \x1c-\x1f and \x85 are in, U+FEFF is out.
const WS = String.raw`[\t\n\x0b\x0c\r\x1c-\x1f \x85\xa0  -     　]`;
const STRINGS_ENTRY = new RegExp(
  String.raw`"((?:[^"\\]|\\[^\n])*)"${WS}*=${WS}*"((?:[^"\\]|\\[^\n])*)"${WS}*;`,
  "gu",
);
const BLOCK_COMMENT = /\/\*[\s\S]*?\*\//g;
// (?m)^\s*//.*$: the `^`/`$` anchors only look at "\n", unlike JS `m`.
const LINE_COMMENT = new RegExp(String.raw`(?<![^\n])${WS}*\/\/[^\n]*(?![^\n])`, "gu");
const UNESCAPE = /\\(U[0-9A-Fa-f]{4}|u[0-9A-Fa-f]{4}|[^\n])/gu;
const SIMPLE_ESCAPES = new Map([
  ["n", "\n"],
  ["t", "\t"],
  ["r", "\r"],
  ['"', '"'],
  ["\\", "\\"],
]);
const DECIMAL_SUFFIX = /%\p{Nd}+\$/gu;
const LONE_SURROGATE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;
const NEGATIVE_NUMBER = /^-\p{Nd}+$|^-\p{Nd}*\.\p{Nd}+$/u;
// A development language such as "en", "pt-BR", "zh-Hans" or "es_419": the only text that becomes a Swift literal.
const LANGUAGE_TAG = /^[A-Za-z0-9_-]+$/;

// ---------------------------------------------------------------------------
// Helpers with the text, path and value rules the tool needs

/** Truthiness of the JSON values this tool sees. */
function isTruthy(value) {
  if (value === null || value === undefined || value === false) return false;
  if (value === true) return true;
  if (typeof value === "number") return value !== 0 && !Number.isNaN(value);
  if (typeof value === "string") return value.length > 0;
  if (Array.isArray(value)) return value.length > 0;
  if (value instanceof Map) return value.size > 0;
  return Object.keys(value).length > 0;
}

/** The first argument when it is truthy, else the second. */
function firstTruthy(a, b) {
  return isTruthy(a) ? a : b;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Whether a JSON object has the key; throws a TypeError for values that are not objects. */
function containsKey(container, key) {
  if (isPlainObject(container)) return Object.hasOwn(container, key);
  if (Array.isArray(container)) return container.includes(key);
  if (typeof container === "string") return container.includes(key);
  throw new TypeError(`argument of type '${typeName(container)}' is not iterable`);
}

function typeName(value) {
  if (value === null) return "NoneType";
  if (Array.isArray(value)) return "list";
  return typeof value;
}

/** The value of a key of a JSON object, or undefined when absent. Throws unless `obj` is an object. */
function dictGet(obj, key) {
  if (!isPlainObject(obj)) throw new TypeError(`'${typeName(obj)}' object has no attribute 'get'`);
  return Object.hasOwn(obj, key) ? obj[key] : undefined;
}

/** Code-point order (the same as UTF-8 byte order) for strings. */
function compareStrings(a, b) {
  return Buffer.compare(utf8Bytes(a), utf8Bytes(b));
}

/** UTF-8 bytes of a string; raises on lone surrogates. */
function utf8Bytes(text) {
  if (LONE_SURROGATE.test(text)) {
    throw new Error("'utf-8' codec can't encode character: surrogates not allowed");
  }
  return Buffer.from(text, "utf8");
}

/** Components of a POSIX path string. */
function pathParts(text) {
  const parts = [];
  if (text.startsWith("//") && !text.startsWith("///")) parts.push("//");
  else if (text.startsWith("/")) parts.push("/");
  for (const part of text.split("/")) {
    if (part !== "" && part !== ".") parts.push(part);
  }
  return parts;
}

/** The file system path for a parts list produced by pathParts(). */
function fsPath(parts) {
  if (parts.length === 0) return ".";
  if (parts[0] === "/" || parts[0] === "//") return parts[0] + parts.slice(1).join("/");
  return parts.join("/");
}

/** Last component of a path string. */
function pathName(parts) {
  const last = parts[parts.length - 1];
  return parts.length > 0 && last !== "/" && last !== "//" ? last : "";
}

/** Extension of a file name, with its leading dot. */
function nameSuffix(name) {
  const index = name.lastIndexOf(".");
  return index > 0 && index < name.length - 1 ? name.slice(index) : "";
}

/** File name without its extension. */
function nameStem(name) {
  const suffix = nameSuffix(name);
  return suffix ? name.slice(0, name.length - suffix.length) : name;
}

/** Paths sort by their parts tuples, not by the joined string. */
function comparePathParts(a, b) {
  const shared = Math.min(a.length, b.length);
  for (let index = 0; index < shared; index++) {
    const order = compareStrings(a[index], b[index]);
    if (order !== 0) return order;
  }
  return a.length - b.length;
}

// ---------------------------------------------------------------------------
// Parsing

/** Reads a file as strict UTF-8 text, keeping a leading BOM. */
function readText(path) {
  // ignoreBOM keeps a leading BOM; fatal rejects bad UTF-8.
  const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
  // Universal newlines: "\r\n" and lone "\r" become "\n", as read_text() does.
  return decoder.decode(readFileSync(path)).replace(/\r\n?/g, "\n");
}

function bucket(tables, language) {
  let entries = tables.get(language);
  if (entries === undefined) {
    entries = new Map();
    tables.set(language, entries);
  }
  return entries;
}

/** A JSON object value becomes a Map , anything else stays as parsed. */
function storedJsonValue(value) {
  return isPlainObject(value) ? new Map(Object.entries(value)) : value;
}

/** The catalog's sourceLanguage must be a language tag string: it is written into the generated Swift source. */
function languageTag(value, path) {
  if (typeof value !== "string" || !LANGUAGE_TAG.test(value)) {
    throw new Error(
      `ValueError: ${path}: sourceLanguage must be a language tag such as "en" or "pt-BR", not ${JSON.stringify(value)}`,
    );
  }
  return value;
}

/**
 * Returns [development, tables]: the catalog's sourceLanguage (a validated language tag)
 * and Map<language, Map<key, string | Map<category, string>>>.
 */
export function parseCatalog(path) {
  const data = JSON.parse(readText(path));
  const declared = dictGet(data, "sourceLanguage");
  const development = declared === undefined ? "en" : languageTag(declared, path);
  const tables = new Map();
  const strings = dictGet(data, "strings") === undefined ? {} : data.strings;
  if (!isPlainObject(strings)) throw new TypeError("'strings' must be an object");
  for (const [key, entry] of Object.entries(strings)) {
    const localizationsValue = dictGet(entry, "localizations");
    const localizations = isTruthy(localizationsValue) ? localizationsValue : {};
    if (!isPlainObject(localizations)) throw new TypeError("'localizations' must be an object");
    for (const [language, localization] of Object.entries(localizations)) {
      if (containsKey(localization, "substitutions")) continue;
      const unitValue = dictGet(localization, "stringUnit");
      const unit = unitValue ?? null;
      const variationsValue = dictGet(localization, "variations");
      const variations = isTruthy(variationsValue) ? variationsValue : {};
      const plural = dictGet(variations, "plural");
      if (unit !== null) {
        const value = dictGet(unit, "value");
        bucket(tables, language).set(key, value === undefined ? "" : storedJsonValue(value));
      } else if (isTruthy(plural)) {
        if (!isPlainObject(plural)) throw new TypeError("'plural' must be an object");
        const forms = new Map();
        for (const [category, variation] of Object.entries(plural)) {
          if (!containsKey(variation, "stringUnit")) continue;
          const stringUnit = dictGet(variation, "stringUnit");
          if (!isPlainObject(stringUnit)) throw new TypeError("'stringUnit' must be an object");
          const text = dictGet(stringUnit, "value");
          if (text === undefined) throw new KeyError("value");
          forms.set(category, text);
        }
        if (forms.size > 0) bucket(tables, language).set(key, forms);
      }
    }
  }
  return [development, tables];
}

class KeyError extends Error {
  constructor(key) {
    super(`KeyError: ${JSON.stringify(key)}`);
    this.name = "KeyError";
  }
}

/** Unescapes `.strings` escapes; `\U`/`\u` must be followed by four hex digits. */
export function unescape(text) {
  return text.replace(UNESCAPE, (_match, code) => {
    if (code[0] === "u" || code[0] === "U") {
      if (code.length === 1) {
        throw new Error("ValueError: invalid literal for int() with base 16: ''");
      }
      return String.fromCodePoint(parseInt(code.slice(1), 16));
    }
    return SIMPLE_ESCAPES.get(code) ?? code;
  });
}

/** Returns Map<key, value> in file order; later duplicates overwrite earlier ones. */
export function parseStrings(path) {
  let text = readText(path).replace(BLOCK_COMMENT, "");
  text = text.replace(LINE_COMMENT, "");
  const entries = new Map();
  for (const match of text.matchAll(STRINGS_ENTRY)) {
    entries.set(unescape(match[1]), unescape(match[2]));
  }
  return entries;
}

/** Walks every entry below the root as path parts; symlinked directories are not entered. */
function rglob(rootParts) {
  const found = [];
  const walk = (parts) => {
    let entries;
    try {
      entries = readdirSync(fsPath(parts), { withFileTypes: true });
    } catch (error) {
      if (["ENOENT", "ENOTDIR", "EACCES", "EPERM"].includes(error.code)) return;
      throw error;
    }
    for (const entry of entries) {
      const child = [...parts, entry.name];
      found.push(child);
      if (entry.isDirectory() && !SKIPPED.has(entry.name)) walk(child);
    }
  };
  walk(rootParts);
  return found;
}

function isFile(parts) {
  try {
    return statSync(fsPath(parts)).isFile();
  } catch {
    return false;
  }
}

/** Returns [development, tables]; development falls back to "en". */
export function collect(roots) {
  let development = null;
  const tables = new Map();
  for (const root of roots) {
    const rootParts = pathParts(root);
    const files = isFile(rootParts) ? [rootParts] : rglob(rootParts).sort(comparePathParts);
    for (const parts of files) {
      if (parts.some((part) => SKIPPED.has(part))) continue;
      const name = pathName(parts);
      const suffix = nameSuffix(name);
      const stem = nameStem(name);
      if (suffix === ".xcstrings" && stem === "Localizable") {
        const [dev, found] = parseCatalog(fsPath(parts));
        development = firstTruthy(development, dev);
        for (const [language, entries] of found) {
          const target = bucket(tables, language);
          for (const [key, value] of entries) target.set(key, value);
        }
      } else if (suffix === ".strings" && stem === "Localizable") {
        const parent = parts.slice(0, -1);
        const parentName = pathName(parent);
        if (nameSuffix(parentName) === ".lproj") {
          let language = nameStem(parentName);
          if (language === "Base") {
            development = firstTruthy(development, "en");
            language = development;
          }
          const target = bucket(tables, language);
          for (const [key, value] of parseStrings(fsPath(parts))) target.set(key, value);
        }
      }
    }
  }
  return [firstTruthy(development, "en"), tables];
}

// ---------------------------------------------------------------------------
// Rendering

/** A development-language value that equals its key adds nothing: lookup falls back to the key. */
export function sameAsKey(key, value) {
  return typeof value === "string" && value.replace(DECIMAL_SUFFIX, "%") === key;
}

/** Plural forms share the value slot: marker, then `category END text` per form, sorted by category. */
export function storedValue(value) {
  if (value instanceof Map) {
    const forms = [...value.entries()].sort(([a], [b]) => compareStrings(a, b));
    return forms
      .map(([category, text]) => {
        if (typeof category !== "string" || typeof text !== "string") {
          throw new TypeError("plural forms must be strings");
        }
        return PLURAL_MARKER + category + CATEGORY_END + text;
      })
      .join("");
  }
  if (typeof value !== "string") throw new TypeError(`value of type ${typeName(value)} is not a string`);
  return value;
}

/** Swift literal for a string: escapes as Swift does, control characters as \u{HEX}. */
export function swiftLiteral(text) {
  // Only strings are literal text: an array or object would otherwise be iterated element by element into the source.
  if (typeof text !== "string") throw new TypeError(`value of type ${typeName(text)} is not a string`);
  let out = "";
  for (const ch of text) {
    const code = ch.codePointAt(0);
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (code < 32) out += "\\u{" + code.toString(16).toUpperCase() + "}";
    else out += ch;
  }
  return '"' + out + '"';
}

/** `entries` + the language's alphanumeric parts, capitalised. */
export function tableName(language) {
  const words = language.split(/[^0-9A-Za-z]+/).filter((part) => part !== "");
  return "entries" + words.map((part) => part[0].toUpperCase() + part.slice(1).toLowerCase()).join("");
}

export function render(development, tables, module = "SwiftUIWeb") {
  const filtered = new Map();
  for (const [language, entries] of tables) {
    const kept = new Map();
    for (const [key, value] of entries) {
      if (!(language === development && sameAsKey(key, value))) kept.set(key, value);
    }
    if (kept.size > 0) filtered.set(language, kept);
  }
  const languages = [...filtered.keys()].sort(compareStrings);
  // One StaticString per language: records `key KEY_END value RECORD_END` sorted
  // by the key's UTF-8 bytes, which `register(language:sorted:)` binary-searches.
  // A string literal is static data; an array or dictionary literal of the same
  // entries is initialised by code (tens of KB of it in the release bundle).
  const lines = [
    "// Generated by swiftuiweb Tools/compile-strings.mjs from the string catalogs. Do not edit.",
    "#if WEB",
    `@_spi(Generated) import ${module}`,
    "",
    "/// Registers the app's translations; call once before the first render.",
    "public enum GeneratedLocalizations {",
    "  public static func install() {",
    `    LocalizationTable.developmentLanguage = ${swiftLiteral(development)}`,
  ];
  for (const language of languages) {
    lines.push(
      `    LocalizationTable.register(language: ${swiftLiteral(language)}, sorted: ${tableName(language)})`,
    );
  }
  lines.push("  }", "");
  languages.forEach((language, index) => {
    lines.push(`  private static let ${tableName(language)}: StaticString = """`);
    const records = [...filtered.get(language).entries()]
      .map(([key, value]) => ({ key, value, bytes: utf8Bytes(key) }))
      .sort((a, b) => Buffer.compare(a.bytes, b.bytes));
    records.forEach(({ key, value }, position) => {
      const parts = [key];
      if (typeof value === "string") {
        parts.push(value);
      } else if (value instanceof Map) {
        for (const [category, text] of value) parts.push(category, text);
      } else {
        throw new TypeError(`value of type ${typeName(value)} has no items`);
      }
      for (const part of parts) {
        if (typeof part !== "string") throw new TypeError("record parts must be strings");
        if (SEPARATOR.test(part)) throw new Error(`ValueError: control separator inside ${JSON.stringify(part)}`);
      }
      const text = storedValue(value);
      const last = position + 1 === records.length;
      // A trailing backslash joins the lines, so records stay one per line.
      lines.push(
        "    " +
          swiftLiteral(key).slice(1, -1) +
          "\\u{3}" +
          swiftLiteral(text).slice(1, -1) +
          (last ? "" : "\\u{4}\\"),
      );
    });
    lines.push('    """');
    if (index + 1 < languages.length) lines.push("");
  });
  lines.push("}", "#endif", "");
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Command line (argparse-compatible for the cases this tool has)

const OPTION_STRINGS = ["-h", "--help", "-o", "--output", "--module"];
const LONG_OPTIONS = ["--help", "--module", "--output"];
const USAGE_TEXT =
  `usage: ${PROG} [-h] -o OUTPUT [--module MODULE]\n` +
  `${" ".repeat(PROG.length + 8)}sources [sources ...]\n`;
const DESCRIPTION = [
  "Compile string catalogs into a Swift table for the web build.",
  "",
  "SwiftUI looks `Text(\"key\")` and `String(localized:)` up in the app's string",
  "catalog (`Localizable.xcstrings`) or `<language>.lproj/Localizable.strings`.",
  "Xcode does that natively; the browser build has no bundle lookup, so this reads",
  "the same files and writes a Swift source that registers every translation with",
  "`LocalizationTable` at launch, as one constant string per language, sorted by key, so",
  "the strings are static data rather than code that builds a dictionary:",
  "",
  "    bun Tools/compile-strings.mjs Sources/Shared/Resources -o Sources/Shared/Generated/LocalizedStrings.generated.swift",
  "",
  "Supported: `.xcstrings` with `stringUnit` values and plural variations, and",
  "classic `.strings` files (`\"key\" = \"value\";`, `/* */` and `//` comments, `\\n`,",
  "`\\\"`, `\\\\`, `\\U` escapes). Device variations and substitutions are skipped.",
  "The generated file is wrapped in `#if WEB`, so native builds ignore it.",
].join("\n");
const HELP_TEXT =
  USAGE_TEXT +
  "\n" +
  DESCRIPTION +
  "\n\n" +
  "positional arguments:\n" +
  "  sources               catalog files or directories to scan\n" +
  "\n" +
  "options:\n" +
  "  -h, --help            show this help message and exit\n" +
  "  -o OUTPUT, --output OUTPUT\n" +
  "  --module MODULE       module the generated table imports; an app that\n" +
  "                        aliases SwiftUI to SwiftUIWeb passes SwiftUI\n";

class UsageError extends Error {}

/** Like argparse: `-o X`, `-oX`, `-o=X`, `--output X`, `--output=X`, unique long prefixes. */
function matchOption(token) {
  if (OPTION_STRINGS.includes(token)) return { option: token, explicit: null };
  const equals = token.indexOf("=");
  if (equals >= 0 && OPTION_STRINGS.includes(token.slice(0, equals))) {
    return { option: token.slice(0, equals), explicit: token.slice(equals + 1) };
  }
  if (token.startsWith("--")) {
    const head = equals >= 0 ? token.slice(0, equals) : token;
    const matches = LONG_OPTIONS.filter((option) => option.startsWith(head));
    if (matches.length === 1) {
      return { option: matches[0], explicit: equals >= 0 ? token.slice(equals + 1) : null };
    }
    return null;
  }
  if (token.startsWith("-")) {
    const short = token.slice(0, 2);
    if (short === "-h" || short === "-o") return { option: short, explicit: token.slice(2), attached: true };
  }
  return null;
}

/** argparse classifies these as option-like ('O'), so they cannot be an option's value. */
function looksLikeOption(token) {
  return token === "--" || (token.length > 1 && token.startsWith("-") && !NEGATIVE_NUMBER.test(token) && !token.includes(" "));
}

function looksLikePositional(token, dashdash) {
  return dashdash || !token.startsWith("-") || token === "-" || NEGATIVE_NUMBER.test(token) || token.includes(" ");
}

/** Returns { help: true } or { sources, output, module }; throws UsageError like argparse. */
function parseArguments(argv) {
  const sources = [];
  const extras = [];
  let output = null;
  let module = "SwiftUIWeb";
  let sourcesDone = false;
  let dashdash = false;
  for (let index = 0; index < argv.length; index++) {
    const token = argv[index];
    if (!dashdash && token === "--") {
      dashdash = true;
      // Once sources are full, argparse keeps the separator in the unrecognised arguments.
      if (sourcesDone) extras.push(token);
      continue;
    }
    if (looksLikePositional(token, dashdash)) {
      // The first run of positionals fills `sources`; any later ones are unrecognised.
      if (sourcesDone) extras.push(token);
      else sources.push(token);
      continue;
    }
    if (sources.length > 0) sourcesDone = true;
    const match = matchOption(token);
    if (match === null) {
      extras.push(token);
      continue;
    }
    if (match.option === "-h" || match.option === "--help") {
      // argparse: an attached single-dash value (-hX) still shows help, because the help action
      // runs before the stray character is reported; `-h=X`, `--help=X` and `-h=` are errors.
      const attachedHelp = match.attached === true && !match.explicit.startsWith("-");
      if (match.explicit !== null && !attachedHelp) {
        throw new UsageError(`argument -h/--help: ignored explicit argument '${match.explicit}'`);
      }
      return { help: true };
    }
    let value = match.explicit;
    if (value === null) {
      const next = argv[index + 1];
      if (next === undefined || looksLikeOption(next)) {
        const name = match.option === "--module" ? "--module" : "-o/--output";
        throw new UsageError(`argument ${name}: expected one argument`);
      }
      value = next;
      index++;
    }
    if (match.option === "--module") module = value;
    else output = value;
  }
  const missing = [];
  if (sources.length === 0) missing.push("sources");
  if (output === null) missing.push("-o/--output");
  if (missing.length > 0) throw new UsageError(`the following arguments are required: ${missing.join(", ")}`);
  if (extras.length > 0) throw new UsageError(`unrecognized arguments: ${extras.join(" ")}`);
  return { sources, output, module };
}

function writeOutput(path, text) {
  if (LONE_SURROGATE.test(text)) {
    // The file is truncated before the encoder fails on the lone surrogate.
    writeFileSync(path, "");
    throw new Error("UnicodeEncodeError: 'utf-8' codec can't encode character: surrogates not allowed");
  }
  writeFileSync(path, text);
}

export function main(argv) {
  let parsed;
  try {
    parsed = parseArguments(argv);
  } catch (error) {
    if (!(error instanceof UsageError)) throw error;
    process.stderr.write(`${USAGE_TEXT}${PROG}: error: ${error.message}\n`);
    return 2;
  }
  if (parsed.help) {
    process.stdout.write(HELP_TEXT);
    return 0;
  }
  const [development, tables] = collect(parsed.sources);
  if (tables.size === 0) {
    process.stderr.write("no Localizable catalogs found\n");
    return 1;
  }
  const outputParts = pathParts(parsed.output);
  mkdirSync(fsPath(outputParts.slice(0, -1)), { recursive: true });
  writeOutput(fsPath(outputParts), render(development, tables, parsed.module));
  const total = [...tables.values()].reduce((count, entries) => count + entries.size, 0);
  process.stdout.write(`Compiled ${total} translations in ${tables.size} languages\n`);
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invokedDirectly) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.name}: ${error.message}\n`);
    process.exitCode = 1;
  }
}
