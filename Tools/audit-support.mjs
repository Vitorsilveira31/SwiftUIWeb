// Shared helpers of the static audits and gates under Tools/ (api-contract, swiftui-api-parity, architecture-audit,
// audit-docs, ...). They give the audits one text model: strict or lossy UTF-8 decoding, line splitting on every
// Unicode line boundary, a fixed JSON layout and code-point ordering, so the audits find and print the same things.
import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

// Resolved through symlinks, so the paths the audits print are the real ones.
const REPOSITORY = realpathSync(resolve(dirname(fileURLToPath(import.meta.url)), ".."));

/** The repository root. `SWIFTUIWEB_AUDIT_ROOT` points an audit at a fixture tree (the regression tests use it). */
export const ROOT = process.env.SWIFTUIWEB_AUDIT_ROOT ? realpathSync(resolve(process.env.SWIFTUIWEB_AUDIT_ROOT)) : REPOSITORY;

const strict = new TextDecoder("utf-8", { fatal: true });
const lossy = new TextDecoder("utf-8", { fatal: false });

/** UTF-8 text of a file; invalid bytes throw, and a leading BOM is kept as U+FEFF. */
export function readText(path) {
  return strict.decode(readFileSync(path));
}

/** UTF-8 text of a file; invalid bytes are dropped (`Path.read_text(errors="ignore")`). */
export function readTextLossy(path) {
  const bytes = readFileSync(path);
  try {
    return strict.decode(bytes);
  } catch {
    return lossy.decode(bytes).replaceAll("�", "");
  }
}

/** Splits text on every Unicode line boundary and drops the boundaries. */
export function splitlines(text) {
  const lines = [];
  let start = 0;
  for (let index = 0; index < text.length; index += 1) {
    const code = text.charCodeAt(index);
    const breaks =
      code === 0x0a || code === 0x0b || code === 0x0c || code === 0x0d || (code >= 0x1c && code <= 0x1e) ||
      code === 0x85 || code === 0x2028 || code === 0x2029;
    if (!breaks) continue;
    lines.push(text.slice(start, index));
    if (code === 0x0d && text.charCodeAt(index + 1) === 0x0a) index += 1;
    start = index + 1;
  }
  if (start < text.length) lines.push(text.slice(start));
  return lines;
}

/** Orders two strings by code point. */
export function compareStrings(a, b) {
  if (a === b) return 0;
  const left = [...a];
  const right = [...b];
  const length = Math.min(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const difference = left[index].codePointAt(0) - right[index].codePointAt(0);
    if (difference !== 0) return difference;
  }
  return left.length - right.length;
}

/** Orders two arrays element by element, comparing strings by code point. */
export function compareTuples(a, b) {
  const length = Math.min(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    const x = a[index];
    const y = b[index];
    const difference = Array.isArray(x) ? compareTuples(x, y) : typeof x === "number" ? x - y : compareStrings(x, y);
    if (difference !== 0) return difference;
  }
  return a.length - b.length;
}

export const sortedStrings = (values) => [...values].sort(compareStrings);

function escapeString(value, ensureAscii) {
  let out = '"';
  for (const character of value) {
    const code = character.codePointAt(0);
    if (character === '"') out += '\\"';
    else if (character === "\\") out += "\\\\";
    else if (character === "\n") out += "\\n";
    else if (character === "\r") out += "\\r";
    else if (character === "\t") out += "\\t";
    else if (character === "\b") out += "\\b";
    else if (character === "\f") out += "\\f";
    else if (code < 0x20) out += `\\u${code.toString(16).padStart(4, "0")}`;
    else if (ensureAscii && code > 0x7e && code !== 0x7f) {
      if (code > 0xffff) {
        const offset = code - 0x10000;
        const high = 0xd800 + (offset >> 10);
        const low = 0xdc00 + (offset & 0x3ff);
        out += `\\u${high.toString(16)}\\u${low.toString(16)}`;
      } else out += `\\u${code.toString(16).padStart(4, "0")}`;
    } else if (ensureAscii && code === 0x7f) out += "\\u007f";
    else out += character;
  }
  return `${out}"`;
}

/**
 * JSON text in the layout of the golden files. With `ensureAscii`, non-ASCII characters (U+007F included) are written
 * as `\uXXXX`. Integers only. Object keys keep their insertion order.
 */
export function jsonDumps(value, { indent = 2, ensureAscii = true } = {}) {
  const write = (item, depth) => {
    if (item === null) return "null";
    if (item === true) return "true";
    if (item === false) return "false";
    if (typeof item === "number") {
      if (!Number.isInteger(item)) throw new Error(`jsonDumps writes integers only, got ${item}`);
      return String(item);
    }
    if (typeof item === "string") return escapeString(item, ensureAscii);
    const inner = "\n" + " ".repeat(indent * (depth + 1));
    const outer = "\n" + " ".repeat(indent * depth);
    if (Array.isArray(item)) {
      if (item.length === 0) return "[]";
      return `[${inner}${item.map((element) => write(element, depth + 1)).join(`,${inner}`)}${outer}]`;
    }
    const keys = Object.keys(item);
    if (keys.length === 0) return "{}";
    return `{${inner}${keys.map((key) => `${escapeString(key, ensureAscii)}: ${write(item[key], depth + 1)}`).join(`,${inner}`)}${outer}}`;
  };
  return write(value, 0);
}

/** Equality of JSON values: objects compare without regard to key order, arrays element by element. */
export function jsonEqual(a, b) {
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((item, index) => jsonEqual(item, b[index]));
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every((key) => Object.hasOwn(b, key) && jsonEqual(a[key], b[key]));
  }
  return a === b;
}

/**
 * Every file below `directory`, sorted by path components (see comparePaths). Symlinked
 * directories are not entered (`**` does not follow them); a symlink to a file counts as a file. `skip(name, path)` prunes a
 * directory.
 */
export function walkFiles(directory, skip = () => false) {
  const found = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) {
        if (!skip(entry.name, path)) walk(path);
      } else if (entry.isFile()) found.push(path);
      else if (entry.isSymbolicLink()) {
        try {
          if (statSync(path).isFile()) found.push(path);
        } catch {
          // A dangling link is not a file.
        }
      }
    }
  };
  if (existsSync(directory) && statSync(directory).isDirectory()) walk(directory);
  return found.sort(comparePaths);
}

/** Orders two paths by their components. */
export function comparePaths(a, b) {
  return compareTuples(a.split(sep), b.split(sep));
}

/** `Path.suffix`: the last extension of the file name, or "". */
export function suffixOf(path) {
  const name = path.split(sep).pop();
  const dot = name.lastIndexOf(".");
  return dot <= 0 || dot === name.length - 1 ? "" : name.slice(dot);
}

/** Files below `directory` whose name ends with `suffix`, sorted by path. */
export const filesWithSuffix = (directory, suffix) => walkFiles(directory).filter((path) => path.endsWith(suffix));

/** Path relative to the repository root, `/` separated (`str(path.relative_to(ROOT))` on POSIX). */
export const fromRoot = (path) => relative(ROOT, path).split(sep).join("/");

/** True when this module is the entry point of the process. */
export const isMain = (metaUrl) => process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(metaUrl);

// ---- Unicode-aware regular expressions ----------------------------------------------------------------------------------------
// In this dialect `\w`, `\s`, `\d` and `\b` are Unicode-aware. `rx` takes a pattern
// in that dialect and returns the JavaScript `RegExp` (always with the `u` flag) that matches the same text.
const WORD = "\\p{L}\\p{N}_";
const SPACE_CHARACTERS = " \\t\\n\\r\\f\\v\\x1c-\\x1f\\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
export const SPACE_CLASS = `[${SPACE_CHARACTERS}]`;
const BOUNDARY = `(?:(?<=[${WORD}])(?![${WORD}])|(?<![${WORD}])(?=[${WORD}]))`;

export function rx(source, flags = "") {
  let out = "";
  let inClass = false;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === "\\") {
      const next = source[index + 1];
      index += 1;
      if (next === "w") out += inClass ? WORD : `[${WORD}]`;
      else if (next === "W") out += inClass ? (() => { throw new Error("\\W inside a class"); })() : `[^${WORD}]`;
      else if (next === "s") out += inClass ? SPACE_CHARACTERS : SPACE_CLASS;
      else if (next === "S") out += inClass ? (() => { throw new Error("\\S inside a class"); })() : `[^${SPACE_CHARACTERS}]`;
      else if (next === "d") out += "\\p{Nd}";
      else if (next === "b" && !inClass) out += BOUNDARY;
      else out += `\\${next}`;
      continue;
    }
    if (character === "[" && !inClass) inClass = true;
    else if (character === "]" && inClass) inClass = false;
    out += character;
  }
  return new RegExp(out, flags.includes("u") ? flags : `${flags}u`);
}

/** Removes the whitespace matched by SPACE_CLASS from both ends. */
export const stripWhitespace = (text) => text.replace(new RegExp(`^${SPACE_CLASS}+|${SPACE_CLASS}+$`, "gu"), "");

/**
 * Runs named test cases one after another, prints `ok`/`FAIL` per case and sets the exit status. The cases are plain
 * functions that throw (`node:assert`) when they fail; a case may be async.
 */
export async function runCases(cases, label = "") {
  let failed = 0;
  for (const [name, run] of Object.entries(cases)) {
    try {
      await run();
      console.log(`ok   ${name}`);
    } catch (error) {
      failed += 1;
      console.log(`FAIL ${name}\n     ${String(error?.stack ?? error).split("\n").join("\n     ")}`);
    }
  }
  const total = Object.keys(cases).length;
  console.log(`${label ? label + ": " : ""}${total - failed}/${total} passed`);
  if (failed > 0) process.exitCode = 1;
}
