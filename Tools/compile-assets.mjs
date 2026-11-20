#!/usr/bin/env bun
// Compile Xcode asset catalogs for the browser bundle.
//
// SwiftUI resolves `Color("Name")` and `Image("Name")` from the app's asset
// catalog. The browser build has no Xcode, so this reads every `*.colorset`
// and `*.imageset` under the given package root.
//
// Colors become one stylesheet:
//
//     :root { --asset-color-Name: light-dark(#F3F2F7, #121118); }
//
// A color set named `AccentColor` also becomes the app's tint (`--tint-color`), and a set that references a system
// color (`systemIndigoColor`) compiles to that color's light and dark values.
//
// `Color("Name")` on the web renders `var(--asset-color-Name, Name)` (see
// `Color.init(_:)`), so the same SwiftUI source works on both hosts. Supported
// catalog content: universal colors with an optional dark appearance, sRGB or
// Display P3 components written as floats ("0.953") or hex bytes ("0xF3"), and
// alpha. Contrast variants and device idioms are ignored.
//
// Images are copied into `<bundle>/catalog-assets/<Name><ext>` (the
// universal 1x file, or the first file of the set) and listed in
// `<bundle>/runtime-environment` as
//
//     SWIFTUIWEB_IMAGE_ASSETS=Name=catalog-assets/Name.svg;Other=...
//
// which `inject-app-head.mjs` turns into `<meta name="runtime-environment">`
// and the runtime hands to Swift through the WASI environment, so
// `Image("Name")` renders that file (see `_ImageAssets`).
//
// usage: compile-assets.mjs <package-root> <output.css> [<bundle-directory>]
// Writes nothing for a kind of asset the package does not have.
//
// The output (stdout, stderr, exit codes and generated files) is byte-identical to the checked-in
// goldens. Run the tests with: bun test ./Tools/test-compile-assets.mjs

import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

export const SKIPPED = new Set([".build", ".git", "node_modules", "DerivedData"]);
export const ASSET_DIRECTORY = "catalog-assets";
export const ENVIRONMENT_FILE = "runtime-environment";
export const IMAGE_VARIABLE = "SWIFTUIWEB_IMAGE_ASSETS";

// ---------------------------------------------------------------------------
// Text, path, number and repr helpers (str, Path, float, round, %g, %.Nf, repr).
// ---------------------------------------------------------------------------

// Unicode whitespace characters, used by stripWhitespace and splitLines.
const WHITESPACE_CHARS = "\\t\\n\\x0b\\f\\r\\x1c-\\x1f \\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const STRIP_EDGES = new RegExp(`^[${WHITESPACE_CHARS}]+|[${WHITESPACE_CHARS}]+$`, "g");

/** Strips leading and trailing Unicode whitespace. */
export function stripWhitespace(text) {
  return text.replace(STRIP_EDGES, "");
}

const LINE_BREAK = /\r\n|[\n\r\x0b\f\x1c\x1d\x1e\x85\u2028\u2029]/;

/** Splits on Unicode line breaks and drops the breaks. */
export function splitLines(text) {
  const parts = text.split(LINE_BREAK);
  if (parts.length > 0 && parts[parts.length - 1] === "") parts.pop();
  return parts;
}

/** Rounds to an integer, halves to the even neighbour; returns an integer-valued number. */
export function roundHalfEven(x) {
  if (!Number.isFinite(x)) throw new RangeError("cannot convert float to integer");
  const floor = Math.floor(x);
  const fraction = x - floor; // exact for doubles
  if (fraction < 0.5) return floor;
  if (fraction > 0.5) return floor + 1;
  return floor % 2 === 0 ? floor : floor + 1;
}

const FLOAT_LITERAL = /^[+-]?(?:(?:[0-9](?:_?[0-9])*)(?:\.(?:[0-9](?:_?[0-9])*)?)?|\.[0-9](?:_?[0-9])*)(?:[eE][+-]?[0-9](?:_?[0-9])*)?$/;

/** Parses a float from text, throwing on text that is not a float literal. */
export function parseFloatText(text) {
  const special = /^([+-]?)(inf|infinity|nan)$/i.exec(text);
  if (special) {
    if (special[2].toLowerCase() === "nan") return Number.NaN;
    return special[1] === "-" ? -Infinity : Infinity;
  }
  if (!FLOAT_LITERAL.test(text)) throw new Error(`could not convert string to float: ${reprString(text)}`);
  return Number(text.replace(/_/g, ""));
}

/** Text of a parsed JSON value, as far as the catalog scripts need it. */
function displayText(value) {
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  if (typeof value === "boolean") return value ? "True" : "False";
  if (value === null) return "None";
  throw new TypeError("unsupported catalog value");
}

/** Truthiness of a parsed JSON value. */
export function isTruthy(value) {
  if (value === undefined || value === null || value === false) return false;
  if (typeof value === "number") return value !== 0;
  if (typeof value === "string") return value.length > 0;
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === "object") return Object.keys(value).length > 0;
  return true;
}

/** Reads a key of a parsed JSON object, falling back when it is absent. */
export function jsonGet(object, key, fallback) {
  if (object === null || typeof object !== "object" || Array.isArray(object)) {
    throw new TypeError(`'${object === null ? "NoneType" : Array.isArray(object) ? "list" : typeof object}' object has no attribute 'get'`);
  }
  return Object.hasOwn(object, key) ? object[key] : fallback;
}

function asList(value) {
  if (!Array.isArray(value)) throw new TypeError("catalog value is not a list");
  return value;
}

/** Quotes a string for diagnostics: single quotes unless the text has a single quote and no double quote. */
export function reprString(text) {
  const quote = text.includes("'") && !text.includes('"') ? '"' : "'";
  const hex = (cp, width) => cp.toString(16).padStart(width, "0");
  let out = "";
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (ch === quote || ch === "\\") out += "\\" + ch;
    else if (ch === "\t") out += "\\t";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (cp < 0x20 || cp === 0x7f) out += "\\x" + hex(cp, 2);
    else if (cp < 0x7f) out += ch;
    else if (!NON_PRINTABLE.test(ch)) out += ch;
    else if (cp <= 0xff) out += "\\x" + hex(cp, 2);
    else if (cp <= 0xffff) out += "\\u" + hex(cp, 4);
    else out += "\\U" + hex(cp, 8);
  }
  return quote + out + quote;
}

const NON_PRINTABLE = /[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Cn}\p{Zl}\p{Zp}\p{Zs}]/u;

/** Compares two strings by Unicode code points. */
export function compareCodePoints(a, b) {
  const x = Array.from(a, (ch) => ch.codePointAt(0));
  const y = Array.from(b, (ch) => ch.codePointAt(0));
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return x.length - y.length;
}

// Exact decimal expansion of a finite non-negative double: value = digits * 10**exponent.
function exactDecimal(value) {
  if (value === 0) return { digits: 0n, exponent: 0 };
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, value);
  const high = view.getUint32(0);
  const low = view.getUint32(4);
  const biased = (high >>> 20) & 0x7ff;
  let mantissa = (BigInt(high & 0xfffff) << 32n) | BigInt(low);
  let exponent;
  if (biased === 0) {
    exponent = -1074;
  } else {
    mantissa |= 1n << 52n;
    exponent = biased - 1075;
  }
  if (exponent >= 0) return { digits: mantissa << BigInt(exponent), exponent: 0 };
  return { digits: mantissa * 5n ** BigInt(-exponent), exponent };
}

// round_half_even(decimal / 10**position) as a BigInt, computed on the exact value.
function roundScaled(decimal, position) {
  const shift = decimal.exponent - position;
  if (shift >= 0) return decimal.digits * 10n ** BigInt(shift);
  const divisor = 10n ** BigInt(-shift);
  const quotient = decimal.digits / divisor;
  const remainder = decimal.digits % divisor;
  const twice = 2n * remainder;
  if (twice > divisor) return quotient + 1n;
  if (twice < divisor) return quotient;
  return quotient % 2n === 0n ? quotient : quotient + 1n;
}

/** Fixed-point text of a finite value with `places` decimals. */
export function formatFixed(value, places) {
  const sign = value < 0 || Object.is(value, -0) ? "-" : "";
  const digits = roundScaled(exactDecimal(Math.abs(value)), -places).toString().padStart(places + 1, "0");
  const whole = digits.slice(0, digits.length - places);
  const fraction = digits.slice(digits.length - places);
  return sign + (places > 0 ? `${whole}.${fraction}` : whole);
}

/** Text of a value in the C `%g` form (precision 6). */
export function formatG(value) {
  if (Number.isNaN(value)) return "nan";
  if (!Number.isFinite(value)) return value < 0 ? "-inf" : "inf";
  const sign = value < 0 || Object.is(value, -0) ? "-" : "";
  const magnitude = Math.abs(value);
  if (magnitude === 0) return sign + "0";
  const precision = 6;
  const decimal = exactDecimal(magnitude);
  let exponent = decimal.digits.toString().length - 1 + decimal.exponent;
  let digits = roundScaled(decimal, exponent - (precision - 1));
  if (digits >= 10n ** BigInt(precision)) {
    exponent += 1;
    digits /= 10n;
  }
  const text = digits.toString();
  if (exponent < -4 || exponent >= precision) {
    const fraction = text.slice(1).replace(/0+$/, "");
    const mantissa = fraction ? `${text[0]}.${fraction}` : text[0];
    const exponentDigits = Math.abs(exponent).toString().padStart(2, "0");
    return `${sign}${mantissa}e${exponent < 0 ? "-" : "+"}${exponentDigits}`;
  }
  const places = precision - 1 - exponent;
  const padded = text.padStart(places + 1, "0");
  const whole = padded.slice(0, padded.length - places);
  const fraction = padded.slice(padded.length - places).replace(/0+$/, "");
  return sign + (fraction ? `${whole}.${fraction}` : whole);
}

/** Normalizes a path: drops empty and "." components, keeps "..". */
export function normalizePath(text) {
  const absolute = text.startsWith("/");
  const body = text
    .split("/")
    .filter((part) => part !== "" && part !== ".")
    .join("/");
  if (absolute) return "/" + body;
  return body === "" ? "." : body;
}

/** Parent directory of a normalized path string. */
export function parentOf(path) {
  if (path === "/" || path === ".") return path;
  const index = path.lastIndexOf("/");
  if (index < 0) return ".";
  return index === 0 ? "/" : path.slice(0, index);
}

/** Last component of a normalized path string. */
export function nameOf(path) {
  if (path === "/" || path === ".") return "";
  return path.slice(path.lastIndexOf("/") + 1);
}

/** Extension of a file name, with its leading dot. */
export function suffixOf(name) {
  const index = name.lastIndexOf(".");
  return index > 0 && index < name.length - 1 ? name.slice(index) : "";
}

/** Joins a directory and a name into a normalized path string. */
export function joinPath(directory, name) {
  if (name.startsWith("/")) return normalizePath(name);
  if (name === "") return normalizePath(directory);
  const joined = directory === "." ? name : directory.endsWith("/") ? directory + name : `${directory}/${name}`;
  return normalizePath(joined);
}

/** Reads UTF-8 text strictly: a BOM is kept, and CRLF and CR become LF. */
export function readText(path) {
  return UTF8.decode(readFileSync(path)).replace(/\r\n?/g, "\n");
}

const UTF8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

/** Writes UTF-8 text with no newline translation. */
export function writeText(path, text) {
  writeFileSync(path, text, "utf8");
}

/** True for a regular file, following symlinks; false on any OS error. */
export function isFile(path) {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function readJson(path) {
  return JSON.parse(readText(path));
}

// ---------------------------------------------------------------------------
// Compiler.
// ---------------------------------------------------------------------------

/** Converts one color component to a float. */
export function component(value) {
  const text = stripWhitespace(displayText(value));
  if (text.toLowerCase().startsWith("0x")) {
    const match = /^0[xX]_?([0-9a-fA-F]+(?:_[0-9a-fA-F]+)*)$/.exec(text);
    if (!match) throw new Error(`invalid literal for int() with base 16: ${reprString(text)}`);
    return Number(BigInt("0x" + match[1])) / 255;
  }
  return parseFloatText(text);
}

function clampUnit(value) {
  // min(1.0, v) then max(0.0, ...): both keep the first argument on ties.
  const top = value < 1 ? value : 1;
  return top > 0 ? top : 0;
}

function hex2(number) {
  return number.toString(16).toUpperCase().padStart(2, "0");
}

/**
 * Apple's system colors by the name a catalog uses in `"reference": "systemIndigoColor"`: light and dark values, the
 * same ones `Color.indigo` and its siblings use in the framework.
 */
const SYSTEM_COLORS = new Map([
  ["Red", ["#FF3B30", "#FF453A"]],
  ["Orange", ["#FF9500", "#FF9F0A"]],
  ["Yellow", ["#FFCC00", "#FFD60A"]],
  ["Green", ["#34C759", "#30D158"]],
  ["Mint", ["#00C7BE", "#63E6E2"]],
  ["Teal", ["#30B0C7", "#40C8E0"]],
  ["Cyan", ["#32ADE6", "#64D2FF"]],
  ["Blue", ["#007AFF", "#0A84FF"]],
  ["Indigo", ["#5856D6", "#5E5CE6"]],
  ["Purple", ["#AF52DE", "#BF5AF2"]],
  ["Pink", ["#FF2D55", "#FF375F"]],
  ["Brown", ["#A2845E", "#AC8E68"]],
]);

/** CSS color of a color entry, or null when it has none. */
export function cssColor(color) {
  if (!Object.hasOwn(color, "components")) {
    // A reference to one of Apple's system colors (`systemIndigoColor`): its light and dark values.
    const match = /^system([A-Za-z]+)Color$/.exec(String(jsonGet(color, "reference", "")));
    const pair = match === null ? undefined : SYSTEM_COLORS.get(match[1]);
    if (pair === undefined) return null; // no components and no known reference: the system default, nothing to compile
    return `light-dark(${pair[0]}, ${pair[1]})`;
  }
  const c = color.components;
  const [red, green, blue] = ["red", "green", "blue"].map((key) => {
    if (!Object.hasOwn(c, key)) throw new Error(`KeyError: ${reprString(key)}`);
    return component(c[key]);
  });
  const alpha = component(jsonGet(c, "alpha", 1));
  const space = jsonGet(color, "color-space", "srgb");
  const [r, g, b] = [red, green, blue].map((v) => Math.max(0, Math.min(255, roundHalfEven(v * 255))));
  if ((space === "display-p3" || space === "p3") && !(r === 0 && g === 0 && b === 0)) {
    const parts = [red, green, blue]
      .map((v) => formatFixed(clampUnit(v), 4).replace(/0+$/, "").replace(/\.+$/, ""))
      .join(" ");
    return `color(display-p3 ${parts}` + (alpha < 1 ? ` / ${formatG(alpha)})` : ")");
  }
  if (alpha >= 1) return `#${hex2(r)}${hex2(g)}${hex2(b)}`;
  return `rgb(${r} ${g} ${b} / ${formatG(alpha)})`;
}

/** Whether a catalog entry is the dark appearance. */
export function isDark(entry) {
  return asList(jsonGet(entry, "appearances", [])).some(
    (a) => jsonGet(a, "appearance", undefined) === "luminosity" && jsonGet(a, "value", undefined) === "dark",
  );
}

/** Whether a catalog entry has an appearance besides the default one. */
export function hasOtherAppearance(entry) {
  return asList(jsonGet(entry, "appearances", [])).some(
    (a) =>
      jsonGet(a, "appearance", undefined) !== "luminosity" ||
      !["dark", "light"].includes(jsonGet(a, "value", undefined)),
  );
}

/** CSS value of a color set's Contents.json, or null when there is none. */
export function colorsetValue(path) {
  const entries = asList(jsonGet(readJson(path), "colors", []));
  let light = null;
  let dark = null;
  for (const entry of entries) {
    if (!Object.hasOwn(entry, "color") || hasOtherAppearance(entry)) continue;
    if (isDark(entry)) {
      dark = dark || cssColor(entry.color);
    } else if (light === null) {
      light = cssColor(entry.color);
    }
  }
  light = light || dark;
  if (light === null) return null;
  return dark === null || dark === light ? light : `light-dark(${light}, ${dark})`;
}

/** The namespace folders above an asset, e.g. `dough/`. */
export function namespacePrefix(contents) {
  const names = [];
  let folder = parentOf(parentOf(contents));
  while (folder !== parentOf(folder) && !nameOf(folder).endsWith(".xcassets")) {
    const meta = joinPath(folder, "Contents.json");
    let document;
    try {
      document = JSON.parse(readText(meta));
    } catch {
      document = undefined; // OSError or ValueError: the folder provides no namespace
    }
    if (document !== undefined) {
      const provides = jsonGet(jsonGet(document, "properties", {}), "provides-namespace", false);
      if (isTruthy(provides)) names.push(nameOf(folder));
    }
    folder = parentOf(folder);
  }
  return names
    .reverse()
    .map((name) => `${name}/`)
    .join("");
}

/** `css_identifier(name)`: a CSS identifier for an asset name. */
export function cssIdentifier(name) {
  let out = "";
  for (const ch of name) {
    // CSS reads only hex escapes for code points (`\` + the character itself is not one); the trailing space ends the escape.
    out += /[A-Za-z0-9_-]/.test(ch) ? ch : "\\" + ch.codePointAt(0).toString(16) + " ";
  }
  return out;
}

function compareParts(a, b) {
  const x = a.split("/");
  const y = b.split("/");
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    const order = compareCodePoints(x[i], y[i]);
    if (order !== 0) return order;
  }
  return x.length - y.length;
}

function listDirectory(directory) {
  try {
    return readdirSync(directory, { withFileTypes: true });
  } catch {
    return [];
  }
}

// Every `*<suffix>/Contents.json` below the root, sorted: directories are not followed through
// symlinks, names in SKIPPED anywhere below the root are dropped, and matches sort by path parts.
function findContents(root, suffix) {
  const found = [];
  const visit = (directory) => {
    const entries = listDirectory(directory);
    for (const entry of entries) {
      if (entry.isDirectory() && !SKIPPED.has(entry.name)) visit(joinPath(directory, entry.name));
    }
    for (const entry of entries) {
      if (!entry.name.endsWith(suffix)) continue;
      const candidate = joinPath(directory, entry.name);
      if (!isDirectory(candidate)) continue;
      const contents = joinPath(candidate, "Contents.json");
      if (existsSync(contents)) found.push(contents);
    }
  };
  visit(root);
  return found.sort(compareParts);
}

/** `catalog_entries(root, suffix)`: [name, contents] pairs in sorted order. */
export function catalogEntries(root, suffix) {
  return findContents(root, suffix).map((contents) => [
    namespacePrefix(contents) + nameOf(parentOf(contents)).slice(0, -suffix.length),
    contents,
  ]);
}

/** `compile_assets(root)`: name to CSS text, returned as a Map to keep insertion order. */
export function compileAssets(root) {
  const values = new Map();
  for (const [name, contents] of catalogEntries(root, ".colorset")) {
    const value = colorsetValue(contents);
    if (value !== null) values.set(name, value);
  }
  return values;
}

function fileField(entry, key, fallback) {
  const value = jsonGet(entry, key, fallback);
  if (typeof value !== "string") throw new TypeError("expected str for file name");
  return value;
}

/** Real path of an existing file or folder with symlinks resolved, or null. */
function realPath(path) {
  try {
    return realpathSync(path);
  } catch {
    return null;
  }
}

/** True when a real path is the folder itself or lies inside it (both real paths). */
function isWithin(path, folder) {
  const rel = relative(folder, path);
  return rel === "" || (rel !== ".." && !rel.startsWith(".." + sep) && !isAbsolute(rel));
}

/**
 * The file a catalog entry names inside its image set folder, or null. The name must be a plain file name, and both
 * the set folder and the file must resolve (through symlinks) inside the package root and the set respectively, so
 * a catalog cannot publish bytes from outside the package. Rejected entries are reported on stderr and skipped.
 */
function containedFile(contents, name, root) {
  const folder = parentOf(contents);
  if (name === "") return null;
  if (name === "." || name === ".." || /[/\\]/.test(name)) {
    console.error(
      `compile-assets: skipping ${reprString(name)} in ${reprString(nameOf(folder))}; a file name must be a plain name inside its set`,
    );
    return null;
  }
  const path = joinPath(folder, name);
  if (!isFile(path)) return null;
  const setReal = realPath(folder);
  const rootReal = realPath(root);
  if (setReal === null || rootReal === null || !isWithin(setReal, rootReal)) {
    console.error(`compile-assets: skipping image set ${reprString(nameOf(folder))}; it resolves outside the package`);
    return null;
  }
  const fileReal = realPath(path);
  if (fileReal === null || !isWithin(fileReal, setReal)) {
    console.error(`compile-assets: skipping ${reprString(name)} in ${reprString(nameOf(folder))}; it resolves outside its set`);
    return null;
  }
  return path;
}

/** File of an image set named by its Contents.json, or null, with its scale (1 unless the set gives it). The universal 2x
 * file wins when the set has one: a browser window is usually twice as dense as its CSS pixels, where Food Truck's header,
 * drawn from the 1x files, was half as sharp as on iPad. The page draws it at its size in points (`srcset`, by the `@2x`
 * its name keeps). Then the 1x file, then the first one. */
export function imagesetSource(contents, root) {
  const entries = asList(jsonGet(readJson(contents), "images", []));
  const candidates = entries.filter((e) => isTruthy(jsonGet(e, "filename", undefined)));
  const universal = (scale) =>
    candidates.filter((e) => jsonGet(e, "idiom", "universal") === "universal" && jsonGet(e, "scale", "1x") === scale);
  // Each entry is tried once, in that order (an entry that leaves its set is reported once).
  const doubled = new Set(universal("2x"));
  for (const entry of new Set([...doubled, ...universal("1x"), ...candidates])) {
    const path = containedFile(contents, fileField(entry, "filename", undefined), root);
    if (path !== null) return { path, scale: doubled.has(entry) ? 2 : 1 };
  }
  return null;
}

/** File of an image set named by its Contents.json, or null (`imagesetSource`). */
export function imagesetFile(contents, root) {
  return imagesetSource(contents, root)?.path ?? null;
}

/** File of a symbol set named by its Contents.json, or null. */
export function symbolsetFile(contents, root) {
  const entries = asList(jsonGet(readJson(contents), "symbols", []));
  for (const entry of entries) {
    const path = containedFile(contents, fileField(entry, "filename", ""), root);
    if (path !== null) return path;
  }
  return null;
}

function search(pattern, text, flags = "su") {
  return new RegExp(pattern, flags).exec(text);
}

// `\b` is Unicode-aware here (word characters are letters, numbers and underscore).
const WORD_BOUNDARY = String.raw`(?:(?<=[\p{L}\p{N}_])(?![\p{L}\p{N}_])|(?<![\p{L}\p{N}_])(?=[\p{L}\p{N}_]))`;

/** SVG text of a symbol template, or null. */
export function symbolSvg(template) {
  const text = readText(template);
  // Templates exported with only the Small size (or re-saved by an editor, which reorders attributes and adds
  // whitespace) have no `Regular-M` group: take the Medium glyph when present, else the Small one.
  let size = null;
  let group = null;
  for (const candidate of ["M", "S"]) {
    const match = search(
      String.raw`<g${WORD_BOUNDARY}([^>]*?)${WORD_BOUNDARY}id="Regular-${candidate}"([^>]*)>(.*?)</g>`,
      text,
    );
    if (match) {
      size = candidate;
      group = match;
      break;
    }
  }
  if (group === null) return null;
  const transform = search(String.raw`transform="matrix\(1 0 0 1 ([\d.\-]+) ([\d.\-]+)\)"`, group[1] + group[2], "u");
  // Templates written by older SF Symbols versions have one unsuffixed margin pair for the glyph.
  const left = search(
    String.raw`id="left-margin(?:-Regular-${size})?"[^>]*?${WORD_BOUNDARY}x1="([\d.\-]+)"`,
    text,
  );
  const right = search(
    String.raw`id="right-margin(?:-Regular-${size})?"[^>]*?${WORD_BOUNDARY}x1="([\d.\-]+)"`,
    text,
  );
  if (!(left && right)) return null;
  const [tx, ty] = transform ? [parseFloatText(transform[1]), parseFloatText(transform[2])] : [0.0, 0.0];
  const groupBody = group[3];
  // `class` marks secondary/tertiary layers and is absent from single-layer glyphs.
  const paths = [...groupBody.matchAll(new RegExp(String.raw`<path(?:[^>]*?class="([^"]*)")?[^>]*?\sd="([^"]+)"`, "gu"))].map(
    (m) => [m[1] ?? "", m[2]],
  );
  if (paths.length === 0) return null;
  const numbers = [];
  for (const [, d] of paths) {
    for (const m of d.matchAll(/-?\d+\.?\d*/g)) numbers.push(parseFloatText(m[0]));
  }
  const ys = numbers.filter((_, index) => index % 2 === 1);
  if (ys.length === 0) throw new Error("min() arg is an empty sequence");
  let low = ys[0];
  let high = ys[0];
  for (const y of ys) {
    if (y < low) low = y;
    if (y > high) high = y;
  }
  let top = low + ty;
  let bottom = high + ty;
  if (!transform) {
    // An edited template draws absolute and relative path commands, so its numbers are not coordinates: frame
    // the glyph by the template's own cap-line and baseline guides.
    const cap = search(String.raw`id="Capline-${size}"[^>]*?${WORD_BOUNDARY}y1="([\d.\-]+)"`, text);
    const base = search(String.raw`id="Baseline-${size}"[^>]*?${WORD_BOUNDARY}y1="([\d.\-]+)"`, text);
    if (cap && base) {
      top = parseFloatText(cap[1]);
      bottom = parseFloatText(base[1]);
    }
  }
  const x0 = parseFloatText(left[1]);
  const x1 = parseFloatText(right[1]);
  const body = paths.map(([classes, d]) => {
    const opacity = classes.includes("secondary") ? "0.5" : classes.includes("tertiary") ? "0.25" : "1";
    return `<path d="${d}" fill="currentColor" fill-opacity="${opacity}"/>`;
  });
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${formatG(x0)} ${formatG(top)} ${formatG(x1 - x0)} ${formatG(bottom - top)}">` +
    `<g transform="matrix(1 0 0 1 ${formatG(tx)} ${formatG(ty)})">${body.join("")}</g></svg>`
  );
}

/** `compile_images(root)`: name to file, returned as a Map. */
export function compileImages(root) {
  const images = new Map();
  for (const [name, contents] of catalogEntries(root, ".imageset")) {
    const source = imagesetSource(contents, root);
    if (source !== null) images.set(name, source.scale === 2 ? { path: source.path, scale: 2 } : source.path);
  }
  for (const [name, contents] of catalogEntries(root, ".symbolset")) {
    const path = symbolsetFile(contents, root);
    if (path !== null) images.set(name, path);
  }
  return images;
}

/** Renders the generated file from its values. */
export function render(values) {
  const lines = ["/* Generated by Tools/compile-assets.mjs from the asset catalog. */", ":root {"];
  for (const [name, value] of values) lines.push(`  --asset-color-${cssIdentifier(name)}: ${value};`);
  // The catalog's `AccentColor` is the app's global tint, as Xcode's ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME
  // makes it: `Color.accentColor`, tinted controls and symbols read `--tint-color`, and `.tint(_:)` still overrides it.
  if (values.has("AccentColor")) lines.push("  --tint-color: var(--asset-color-AccentColor);");
  lines.push("}");
  return lines.join("\n") + "\n";
}

/** `install_images(images, bundle)`: copies the files, returns name -> bundle-relative path. */
export function installImages(images, bundle) {
  const manifest = new Map();
  if (images.size === 0) return manifest;
  const target = joinPath(bundle, ASSET_DIRECTORY);
  mkdirSync(target, { recursive: true });
  for (const [name, entry] of images) {
    // A 2x file keeps `@2x` in its name: the page draws it at half its pixels (embedded-dom.js, `densityOf`).
    const source = typeof entry === "string" ? entry : entry.path, density = typeof entry === "string" ? "" : "@2x";
    // The manifest is written as NAME=path;NAME=path lines, so a name or extension must not carry those separators or a newline.
    if (/[\x00-\x1f=;\\]/.test(name)) {
      console.error(
        `compile-assets: skipping image set ${reprString(name)}; names cannot contain control characters, '=', ';' or backslashes`,
      );
      continue;
    }
    if (/[\x00-\x1f=;\\]/.test(suffixOf(nameOf(source)))) {
      console.error(`compile-assets: skipping image set ${reprString(name)}; its file extension has control characters or separators`);
      continue;
    }
    // A namespaced name ("dough/yellow-full") is one file in the bundle; the manifest maps the name to it.
    const stem = name.replaceAll("/", "__");
    let destination;
    if (nameOf(parentOf(source)).endsWith(".symbolset")) {
      const svg = symbolSvg(source);
      if (svg === null) {
        console.error(`compile-assets: skipping symbol set ${reprString(name)}; no Regular-M glyph found`);
        continue;
      }
      destination = joinPath(target, `${stem}.symbol.svg`);
      writeText(destination, svg);
    } else {
      destination = joinPath(target, stem + density + suffixOf(nameOf(source)).toLowerCase());
      copyFileSync(source, destination);
    }
    manifest.set(name, `${ASSET_DIRECTORY}/${nameOf(destination)}`);
  }
  return manifest;
}

/** `environment_line(manifest)`: the environment line for a manifest. */
export function environmentLine(manifest) {
  return IMAGE_VARIABLE + "=" + [...manifest].map(([name, path]) => `${name}=${path}`).join(";");
}

/** `write_environment(bundle, lines)`: replaces lines with the same key, keeps the others. */
export function writeEnvironment(bundle, lines) {
  const path = joinPath(bundle, ENVIRONMENT_FILE);
  const existing = isFile(path) ? splitLines(readText(path)).filter((line) => stripWhitespace(line) !== "") : [];
  const kept = existing.filter(
    (line) => !lines.some((added) => line.startsWith(added.split("=")[0] + "=")),
  );
  writeText(path, [...kept, ...lines].join("\n") + "\n");
}

/** `main(argv) -> int`; argv[0] is the script name. */
export function main(argv) {
  if (argv.length !== 3 && argv.length !== 4) {
    console.error("usage: compile-assets.mjs <package-root> <output.css> [<bundle-directory>]");
    return 2;
  }
  const root = normalizePath(argv[1]);
  const values = compileAssets(root);
  if (values.size > 0) {
    writeText(normalizePath(argv[2]), render(values));
    console.log(`Compiled ${values.size} asset-catalog colors`);
  }
  if (argv.length === 4) {
    const bundle = normalizePath(argv[3]);
    const manifest = installImages(compileImages(root), bundle);
    if (manifest.size > 0) {
      writeEnvironment(bundle, [environmentLine(manifest)]);
      console.log(`Copied ${manifest.size} asset-catalog images`);
    }
  }
  return 0;
}

function isEntryPoint() {
  return process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isEntryPoint()) {
  process.exitCode = main(["compile-assets.mjs", ...process.argv.slice(2)]);
}
