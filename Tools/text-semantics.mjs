// Text, path and number helpers for the Tools scripts. They reproduce the behaviour the scripts rely on where the
// JavaScript builtins differ: POSIX path normalization, realpath, relpath and commonpath, JSON text with ensure_ascii
// escapes and the default separators, string repr, executable lookup, universal-newline text reads and Unicode-aware regex classes.
import { accessSync, constants, lstatSync, readFileSync, readlinkSync, statSync, writeFileSync } from "node:fs";

// Thrown to end a tool with a message: the message goes to stderr and the exit code is 1.
export class ToolExit extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}

// --- posixpath -------------------------------------------------------------------------------------------

export const isAbs = (path) => path.startsWith("/");

export function join(first, ...rest) {
  let path = first;
  for (const part of rest) {
    if (part.startsWith("/")) path = part;
    else if (!path || path.endsWith("/")) path += part;
    else path += "/" + part;
  }
  return path;
}

export function split(path) {
  const cut = path.lastIndexOf("/") + 1;
  let head = path.slice(0, cut);
  const tail = path.slice(cut);
  if (head && head !== "/".repeat(head.length)) head = head.replace(/\/+$/, "");
  return [head, tail];
}

export const basename = (path) => path.slice(path.lastIndexOf("/") + 1);

export function normpath(path) {
  if (!path) return ".";
  let initialSlashes = path.startsWith("/") ? 1 : 0;
  if (initialSlashes && path.startsWith("//") && !path.startsWith("///")) initialSlashes = 2;
  const parts = [];
  for (const comp of path.split("/")) {
    if (comp === "" || comp === ".") continue;
    if (comp !== ".." || (!initialSlashes && parts.length === 0) || parts[parts.length - 1] === "..") {
      parts.push(comp);
    } else if (parts.length) {
      parts.pop();
    }
  }
  let result = parts.join("/");
  if (initialSlashes) result = "/".repeat(initialSlashes) + result;
  return result || ".";
}

export const abspath = (path) => normpath(isAbs(path) ? path : join(process.cwd(), path));

// posixpath.realpath (strict=False): symlinks are resolved component by component, and components that do
// not exist are kept lexically.
export function realpath(filename) {
  const [path] = joinRealpath("", filename, new Map());
  return abspath(path);
}

function joinRealpath(start, rest, seen) {
  let path = start;
  if (isAbs(rest)) {
    rest = rest.slice(1);
    path = "/";
  }
  while (rest) {
    const cut = rest.indexOf("/");
    let name;
    if (cut < 0) {
      name = rest;
      rest = "";
    } else {
      name = rest.slice(0, cut);
      rest = rest.slice(cut + 1);
    }
    if (!name || name === ".") continue;
    if (name === "..") {
      if (path) {
        const [head, tail] = split(path);
        path = tail === ".." ? join(head, "..", "..") : head;
      } else {
        path = "..";
      }
      continue;
    }
    const newpath = join(path, name);
    let isLink = false;
    try {
      isLink = lstatSync(newpath).isSymbolicLink();
    } catch {
      isLink = false;
    }
    if (!isLink) {
      path = newpath;
      continue;
    }
    if (seen.has(newpath)) {
      const resolved = seen.get(newpath);
      if (resolved !== null) {
        path = resolved;
        continue;
      }
      return [join(newpath, rest), false];
    }
    seen.set(newpath, null);
    const [resolved, ok] = joinRealpath(path, readlinkSync(newpath), seen);
    if (!ok) return [join(resolved, rest), false];
    path = resolved;
    seen.set(newpath, path);
  }
  return [path, true];
}

// posixpath.relpath(path, start) for non-empty paths.
export function relpath(path, start) {
  const startList = abspath(start).split("/").filter(Boolean);
  const pathList = abspath(path).split("/").filter(Boolean);
  let i = 0;
  while (i < startList.length && i < pathList.length && startList[i] === pathList[i]) i += 1;
  const relList = [...Array(startList.length - i).fill(".."), ...pathList.slice(i)];
  return relList.length ? relList.join("/") : ".";
}

// posixpath.commonpath for absolute paths (the only form the scripts use).
export function commonpath(paths) {
  const splitPaths = paths.map((path) => path.split("/").filter((comp) => comp && comp !== "."));
  const common = [];
  const shortest = Math.min(...splitPaths.map((parts) => parts.length));
  for (let i = 0; i < shortest; i += 1) {
    const comp = splitPaths[0][i];
    if (!splitPaths.every((parts) => parts[i] === comp)) break;
    common.push(comp);
  }
  return "/" + common.join("/");
}

export function isFile(path) {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

// shutil.which(cmd) with the default mode (exists, executable, not a directory).
export function which(cmd) {
  const accessCheck = (name) => {
    try {
      if (statSync(name).isDirectory()) return false;
      accessSync(name, constants.F_OK | constants.X_OK);
      return true;
    } catch {
      return false;
    }
  };
  if (cmd.includes("/")) return accessCheck(cmd) ? cmd : null;
  let path = process.env.PATH;
  if (path === undefined) path = "/usr/bin:/bin";
  if (!path) return null;
  const seen = new Set();
  for (const dir of path.split(":")) {
    if (seen.has(dir)) continue;
    seen.add(dir);
    const name = join(dir, cmd);
    if (accessCheck(name)) return name;
  }
  return null;
}

// --- text, repr and json ----------------------------------------------------------------------------------

// Unicode whitespace (the characters for which isspace() is true), the set \s matches here.
export const SPACE = "[\\t\\n\\v\\f\\r \\x1c-\\x1f\\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000]";
// \w here: Unicode letters, numbers and underscore.
export const WORD_CHARS = String.raw`\p{L}\p{N}_`;
export const WORD = `[${WORD_CHARS}]`;
// \b here: a boundary between a word character and a non-word character, Unicode aware.
export const BOUNDARY = `(?:(?<!${WORD})(?=${WORD})|(?<=${WORD})(?!${WORD}))`;
// ^ in multiline mode: the start of the text or just after a newline. (JavaScript's m flag also accepts
// CR and the two Unicode line separators, which this does not.)
export const LINE_START = "(?<=^|\\n)";

// Universal newlines for text reads: CRLF and lone CR become LF.
export function normalizeNewlines(text) {
  return text.replace(/\r\n?/g, "\n");
}

// Strict UTF-8 text read; a BOM is kept.
export function readText(file) {
  const bytes = readFileSync(file);
  return normalizeNewlines(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes));
}

export function writeText(file, text) {
  writeFileSync(file, text, "utf8");
}

// read_text(errors='ignore'): invalid UTF-8 sequences are dropped instead of replaced.
export function readTextIgnoringErrors(file) {
  const bytes = readFileSync(file);
  try {
    return normalizeNewlines(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes));
  } catch {
    return normalizeNewlines(decodeUtf8Dropping(bytes));
  }
}

// WHATWG-style UTF-8 decoding that drops each invalid maximal subpart instead of replacing it.
function decodeUtf8Dropping(bytes) {
  let out = "";
  let i = 0;
  const n = bytes.length;
  while (i < n) {
    const lead = bytes[i];
    if (lead < 0x80) {
      out += String.fromCharCode(lead);
      i += 1;
      continue;
    }
    let need;
    let lo = 0x80;
    let hi = 0xbf;
    let cp;
    if (lead >= 0xc2 && lead <= 0xdf) {
      need = 1;
      cp = lead & 0x1f;
    } else if (lead >= 0xe0 && lead <= 0xef) {
      need = 2;
      cp = lead & 0x0f;
      if (lead === 0xe0) lo = 0xa0;
      if (lead === 0xed) hi = 0x9f;
    } else if (lead >= 0xf0 && lead <= 0xf4) {
      need = 3;
      cp = lead & 0x07;
      if (lead === 0xf0) lo = 0x90;
      if (lead === 0xf4) hi = 0x8f;
    } else {
      i += 1;
      continue;
    }
    let j = i + 1;
    let ok = true;
    for (let k = 0; k < need; k += 1, j += 1) {
      if (j >= n || bytes[j] < lo || bytes[j] > hi) {
        ok = false;
        break;
      }
      lo = 0x80;
      hi = 0xbf;
      cp = (cp << 6) | (bytes[j] & 0x3f);
    }
    if (ok) out += String.fromCodePoint(cp);
    i = j;
  }
  return out;
}

// Strips the whitespace set above from both ends.
export const stripWhitespace = (text) => text.replace(new RegExp(`^${SPACE}+|${SPACE}+$`, "gu"), "");

// repr(str) for the strings the scripts print.
export function reprString(text) {
  const quote = text.includes("'") && !text.includes('"') ? '"' : "'";
  let out = quote;
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (ch === quote || ch === "\\") out += "\\" + ch;
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (cp < 0x20 || (cp >= 0x7f && cp <= 0xa0)) out += "\\x" + cp.toString(16).padStart(2, "0");
    else out += ch;
  }
  return out + quote;
}

// repr(list of str), as str(TimeoutExpired.cmd) prints it.
export const listRepr = (items) => "[" + items.map(reprString).join(", ") + "]";

// A value serialised as a float, so it keeps its float text even when it is whole.
export class FloatValue {
  constructor(value) {
    this.value = value;
  }
}

// repr(float): shortest round-trip digits, fixed notation for exponents in [-4, 16), else d.ddde+XX.
export function reprFiniteFloat(value) {
  if (value === 0) return Object.is(value, -0) ? "-0.0" : "0.0";
  const negative = value < 0;
  const [mantissa, exponentText] = Math.abs(value).toExponential().split("e");
  const exponent = Number.parseInt(exponentText, 10);
  const digits = mantissa.replace(".", "");
  let out;
  if (exponent >= -4 && exponent < 16) {
    if (exponent >= 0) {
      const whole = digits.slice(0, exponent + 1).padEnd(exponent + 1, "0");
      const fraction = digits.slice(exponent + 1);
      out = whole + (fraction ? "." + fraction : ".0");
    } else {
      out = "0." + "0".repeat(-exponent - 1) + digits;
    }
  } else {
    const fraction = digits.length > 1 ? "." + digits.slice(1) : "";
    out = digits[0] + fraction + "e" + (exponent < 0 ? "-" : "+") + String(Math.abs(exponent)).padStart(2, "0");
  }
  return (negative ? "-" : "") + out;
}

// json.dumps string encoding: ensure_ascii escapes every character outside printable ASCII.
function jsonString(text) {
  return JSON.stringify(text).replace(/[\u007f-￿]/g, (ch) => "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0"));
}

// json.dumps(value) when indent is null (separators ", " and ": "), json.dumps(value, indent=N) otherwise.
export function dumpsJson(value, indent = null, level = 0) {
  if (value === null || value === undefined) return "null";
  if (value === true) return "true";
  if (value === false) return "false";
  if (value instanceof FloatValue) return reprFiniteFloat(value.value);
  if (typeof value === "number") return String(value);
  if (typeof value === "string") return jsonString(value);
  const wrap = (open, close, items) => {
    if (indent === null) return open + items.join(", ") + close;
    const inner = "\n" + " ".repeat(indent * (level + 1));
    const outer = "\n" + " ".repeat(indent * level);
    return open + inner + items.join("," + inner) + outer + close;
  };
  if (Array.isArray(value)) {
    if (!value.length) return "[]";
    return wrap("[", "]", value.map((item) => dumpsJson(item, indent, level + 1)));
  }
  const entries = Object.entries(value);
  if (!entries.length) return "{}";
  return wrap(
    "{",
    "}",
    entries.map(([key, item]) => jsonString(key) + ": " + dumpsJson(item, indent, level + 1)),
  );
}
