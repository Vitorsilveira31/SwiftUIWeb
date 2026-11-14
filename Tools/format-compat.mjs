// Number and text formats that the measurement tools' outputs depend on (checked-in JSON, the text other tools
// parse, exit codes): float-aware JSON with the golden layout, float repr, `round(x, 2)` and two-decimal output
// (ties go to the even digit, judged on the exact binary value), and a small argparse-style parser.
//
// JavaScript has a single number type, so a value that must stay a float even when it holds a whole number
// (`100.0`, `4.0`) is wrapped in `Float`. `Float` coerces to its number in arithmetic and comparisons.
import { readdirSync, readFileSync, realpathSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";

export class Float {
  constructor(value) {
    this.value = Number(value);
  }
  valueOf() {
    return this.value;
  }
  toString() {
    return floatRepr(this.value);
  }
}

export const float = (value) => new Float(value);
export const isNumber = (value) => (typeof value === "number" && !Number.isNaN(value)) || value instanceof Float;
export const isFloat = (value) => value instanceof Float || (typeof value === "number" && !Number.isInteger(value));

/** Float text: shortest round-trip digits, exponent form below 1e-4 and from 1e16. */
export function floatRepr(value) {
  if (Number.isNaN(value)) return "nan";
  if (!Number.isFinite(value)) return value > 0 ? "inf" : "-inf";
  if (value === 0) return Object.is(value, -0) ? "-0.0" : "0.0";
  const [mantissa, exponentText] = Math.abs(value).toExponential().split("e");
  const digits = mantissa.replace(".", "");
  const exponent = Number(exponentText);
  const sign = value < 0 ? "-" : "";
  const decimalPoint = exponent + 1;
  if (decimalPoint <= -4 || decimalPoint > 16) {
    const head = digits.length > 1 ? `${digits[0]}.${digits.slice(1)}` : digits;
    const magnitude = Math.abs(exponent);
    return `${sign}${head}e${exponent < 0 ? "-" : "+"}${String(magnitude).padStart(2, "0")}`;
  }
  if (decimalPoint <= 0) return `${sign}0.${"0".repeat(-decimalPoint)}${digits}`;
  if (digits.length <= decimalPoint) return `${sign}${digits}${"0".repeat(decimalPoint - digits.length)}.0`;
  return `${sign}${digits.slice(0, decimalPoint)}.${digits.slice(decimalPoint)}`;
}

/** `str(x)` for the values the tools print. */
export function displayText(value) {
  if (value === null || value === undefined) return "None";
  if (value === true) return "True";
  if (value === false) return "False";
  if (value instanceof Float) return value.toString();
  if (typeof value === "number") return Number.isInteger(value) ? String(value) : floatRepr(value);
  return String(value);
}

/** Fixed-point text with `digits` decimals: `toFixed` breaks an exact tie upwards, this rounds it to the even digit. */
export function fixed(value, digits) {
  const number = Number(value);
  if (!Number.isFinite(number)) return number > 0 ? "inf" : number < 0 ? "-inf" : "nan";
  const rounded = number.toFixed(digits);
  const exact = Math.abs(number).toFixed(Math.min(100, digits + 40));
  const point = exact.indexOf(".");
  const tail = exact.slice(point + 1 + digits);
  if (/^50*$/.test(tail)) {
    const kept = exact.slice(0, point + 1 + digits).replace(/\.$/, "");
    const lastDigit = Number(kept[kept.length - 1]);
    if (lastDigit % 2 === 0) return (number < 0 ? "-" : "") + kept;
  }
  return rounded;
}

/** `round(value, digits)` as a float. */
export function roundTo(value, digits) {
  return new Float(Number(fixed(value, digits)));
}

/** `datetime.now(timezone.utc).isoformat()`. */
export function isoNow(date = new Date()) {
  return date.toISOString().replace(/\.(\d{3})Z$/, ".$1000+00:00");
}

const ORDER = Symbol("keyOrder");
const integerKey = /^(0|[1-9]\d*)$/;

function parseNumber(text, float) {
  if (float) return new Float(Number(text));
  const number = Number(text);
  return Number.isSafeInteger(number) ? number : BigInt(text);
}

/** `json.loads`, keeping the int/float distinction (as `Float`) and the key order of integer-like keys. */
export function parseJson(text) {
  let i = 0;
  const fail = (what) => {
    throw new SyntaxError(`${what} at position ${i}`);
  };
  const space = () => {
    while (i < text.length && " \t\n\r".includes(text[i])) i += 1;
  };
  const value = () => {
    space();
    const c = text[i];
    if (c === "{") {
      i += 1;
      const object = {};
      const keys = [];
      space();
      if (text[i] === "}") {
        i += 1;
        return object;
      }
      for (;;) {
        space();
        if (text[i] !== '"') fail("Expecting property name");
        const key = string();
        space();
        if (text[i] !== ":") fail("Expecting ':' delimiter");
        i += 1;
        // defineProperty, not assignment: a "__proto__" key must stay an ordinary own property.
        Object.defineProperty(object, key, { value: value(), enumerable: true, writable: true, configurable: true });
        keys.push(key);
        space();
        if (text[i] === ",") {
          i += 1;
          continue;
        }
        if (text[i] === "}") {
          i += 1;
          break;
        }
        fail("Expecting ',' delimiter");
      }
      if (keys.some((key) => integerKey.test(key))) {
        Object.defineProperty(object, ORDER, { value: [...new Set(keys)], enumerable: false });
      }
      return object;
    }
    if (c === "[") {
      i += 1;
      const list = [];
      space();
      if (text[i] === "]") {
        i += 1;
        return list;
      }
      for (;;) {
        list.push(value());
        space();
        if (text[i] === ",") {
          i += 1;
          continue;
        }
        if (text[i] === "]") {
          i += 1;
          return list;
        }
        fail("Expecting ',' delimiter");
      }
    }
    if (c === '"') return string();
    for (const [word, result] of [["true", true], ["false", false], ["null", null]]) {
      if (text.startsWith(word, i)) {
        i += word.length;
        return result;
      }
    }
    const match = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(text.slice(i, i + 400));
    if (!match) fail("Expecting value");
    i += match[0].length;
    return parseNumber(match[0], match[2] !== undefined || match[3] !== undefined);
  };
  const string = () => {
    const start = i;
    i += 1;
    while (i < text.length && text[i] !== '"') i += text[i] === "\\" ? 2 : 1;
    if (i >= text.length) fail("Unterminated string");
    i += 1;
    return JSON.parse(text.slice(start, i));
  };
  const result = value();
  space();
  if (i !== text.length) fail("Extra data");
  return result;
}

export const readJson = (path) => parseJson(readFileSync(path, "utf8"));

function quote(string, ensureAscii) {
  let out = '"';
  for (const char of string) {
    const code = char.codePointAt(0);
    if (char === '"') out += '\\"';
    else if (char === "\\") out += "\\\\";
    else if (char === "\n") out += "\\n";
    else if (char === "\r") out += "\\r";
    else if (char === "\t") out += "\\t";
    else if (char === "\b") out += "\\b";
    else if (char === "\f") out += "\\f";
    else if (code < 0x20) out += `\\u${code.toString(16).padStart(4, "0")}`;
    else if (ensureAscii && code > 0x7e) {
      if (code > 0xffff) {
        const offset = code - 0x10000;
        out += `\\u${(0xd800 + (offset >> 10)).toString(16)}\\u${(0xdc00 + (offset & 0x3ff)).toString(16)}`;
      } else out += `\\u${code.toString(16).padStart(4, "0")}`;
    } else out += char;
  }
  return `${out}"`;
}

/**
 * `json.dumps(value, ...)`. Options: `indent` (number of spaces), `sortKeys`, `ensureAscii` (default true) and
 * `separators` ([item, key]). Plain objects keep their insertion order; use a `Map` for integer-like keys that
 * must keep a specific order.
 */
export function dumps(value, { indent = null, sortKeys = false, ensureAscii = true, separators = null } = {}) {
  const [itemSeparator, keySeparator] = separators ?? (indent === null ? [", ", ": "] : [",", ": "]);
  const write = (v, depth) => {
    if (v === null || v === undefined) return "null";
    if (v === true) return "true";
    if (v === false) return "false";
    if (v instanceof Float) return Number.isFinite(v.value) ? floatRepr(v.value) : Number.isNaN(v.value) ? "NaN" : v.value > 0 ? "Infinity" : "-Infinity";
    if (typeof v === "number") return Number.isInteger(v) ? String(v) : floatRepr(v);
    if (typeof v === "bigint") return String(v);
    if (typeof v === "string") return quote(v, ensureAscii);
    const pad = indent === null ? "" : `\n${" ".repeat(indent * (depth + 1))}`;
    const close = indent === null ? "" : `\n${" ".repeat(indent * depth)}`;
    if (Array.isArray(v)) {
      if (v.length === 0) return "[]";
      return `[${pad}${v.map((item) => write(item, depth + 1)).join(itemSeparator + pad)}${close}]`;
    }
    let entries = v instanceof Map ? [...v.entries()] : (v[ORDER] ?? Object.keys(v)).map((key) => [key, v[key]]);
    if (sortKeys) entries = entries.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    if (entries.length === 0) return "{}";
    return `{${pad}${entries.map(([key, item]) => quote(String(key), ensureAscii) + keySeparator + write(item, depth + 1)).join(itemSeparator + pad)}${close}}`;
  };
  return write(value, 0);
}

/** A number kept as an int unless the original was a float: arithmetic whose result is a float if either side is. */
export function arithmetic(left, right, operation) {
  const result = operation(Number(left), Number(right));
  return left instanceof Float || right instanceof Float ? new Float(result) : result;
}

/** Lexicographic path-parts order, which is how `sorted(Path.rglob(...))` orders. */
export function compareParts(a, b) {
  const left = a.split("/");
  const right = b.split("/");
  for (let index = 0; index < Math.min(left.length, right.length); index += 1) {
    if (left[index] !== right[index]) return left[index] < right[index] ? -1 : 1;
  }
  return left.length - right.length;
}

/**
 * A small `argparse`: options as `{ names, dest, type: "flag"|"string"|"int", choices, required, default, help }`
 * and positionals as `{ name, nargs: "+" | undefined }`. On a mistake it prints the usage and
 * `prog: error: ...` to stderr and exits with 2, as argparse does.
 */
export function parseArguments({ prog, description = "", options = [], positionals = [] }, argv) {
  const usageLine = () => {
    const parts = [`usage: ${prog} [-h]`];
    for (const option of options) {
      const name = option.names[0];
      const long = option.names.find((candidate) => candidate.startsWith("--")) ?? option.names[0];
      const metavar = option.type === "flag" ? "" : ` ${option.choices ? `{${option.choices.join(",")}}` : long.replace(/^-+/, "").replaceAll("-", "_").toUpperCase()}`;
      parts.push(option.required ? `${name}${metavar}` : `[${name}${metavar}]`);
    }
    for (const positional of positionals) parts.push(positional.nargs === "+" ? `${positional.name} [${positional.name} ...]` : positional.name);
    return parts.join(" ");
  };
  const fail = (message) => {
    process.stderr.write(`${usageLine()}\n${prog}: error: ${message}\n`);
    process.exit(2);
  };
  const help = () => {
    const lines = [usageLine(), "", description.trim(), "", "options:", "  -h, --help  show this help message and exit"];
    for (const option of options) lines.push(`  ${option.names.join(", ")}  ${option.help ?? ""}`.trimEnd());
    process.stdout.write(`${lines.join("\n")}\n`);
    process.exit(0);
  };
  const result = {};
  for (const option of options) result[option.dest] = option.default ?? (option.type === "flag" ? false : undefined);
  const rest = [];
  const known = new Map();
  for (const option of options) for (const name of option.names) known.set(name, option);
  const resolve = (flag) => {
    if (known.has(flag)) return known.get(flag);
    const candidates = [...known.keys()].filter((name) => name.startsWith(flag));
    const owners = new Set(candidates.map((name) => known.get(name)));
    if (flag.startsWith("--") && owners.size === 1) return known.get(candidates[0]);
    if (owners.size > 1) fail(`ambiguous option: ${flag} could match ${candidates.join(", ")}`);
    return null;
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "-h" || arg === "--help") help();
    if (arg === "--") {
      rest.push(...argv.slice(index + 1));
      break;
    }
    if (arg.startsWith("-") && arg.length > 1 && !/^-\d/.test(arg)) {
      const equals = arg.indexOf("=");
      const flag = equals > 0 && arg.startsWith("--") ? arg.slice(0, equals) : arg;
      const option = resolve(flag);
      if (!option) fail(`unrecognized arguments: ${arg}`);
      if (option.type === "flag") {
        if (equals > 0 && arg.startsWith("--")) fail(`argument ${option.names.join("/")}: ignored explicit argument '${arg.slice(equals + 1)}'`);
        result[option.dest] = true;
        continue;
      }
      let raw;
      if (equals > 0 && arg.startsWith("--")) raw = arg.slice(equals + 1);
      else {
        index += 1;
        if (index >= argv.length || (argv[index].startsWith("-") && argv[index].length > 1 && !/^-\d/.test(argv[index]))) {
          fail(`argument ${option.names.join("/")}: expected one argument`);
        }
        raw = argv[index];
      }
      if (option.type === "int") {
        if (!/^\s*[+-]?\d+\s*$/.test(raw)) fail(`argument ${option.names.join("/")}: invalid int value: '${raw}'`);
        raw = Number(raw);
      }
      if (option.choices && !option.choices.includes(raw)) {
        fail(`argument ${option.names.join("/")}: invalid choice: '${raw}' (choose from ${option.choices.join(", ")})`);
      }
      result[option.dest] = raw;
    } else rest.push(arg);
  }
  const missing = options.filter((option) => option.required && result[option.dest] === undefined).map((option) => option.names.join("/"));
  const extra = [];
  let cursor = 0;
  for (const positional of positionals) {
    if (positional.nargs === "+") {
      if (cursor >= rest.length) missing.push(positional.name);
      else result[positional.name] = rest.slice(cursor);
      cursor = rest.length;
    } else if (cursor >= rest.length) missing.push(positional.name);
    else {
      result[positional.name] = rest[cursor];
      cursor += 1;
    }
  }
  if (missing.length) fail(`the following arguments are required: ${missing.join(", ")}`);
  extra.push(...rest.slice(cursor));
  if (extra.length) fail(`unrecognized arguments: ${extra.join(" ")}`);
  result.fail = fail;
  return result;
}

/**
 * Every entry below `root` (files and directories) as a `/`-separated path relative to it, in
 * `sorted(Path.rglob("*"))` order. Directory links are not followed. `prune(name)` keeps the walk out of a
 * directory (the directory itself is still listed).
 */
export function rglob(root, prune = () => false) {
  const found = [];
  const visit = (directory, prefix) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
      found.push(relativePath);
      if (entry.isDirectory() && !prune(entry.name)) visit(join(directory, entry.name), relativePath);
    }
  };
  visit(root, "");
  return found.sort(compareParts);
}

/** `Path.resolve()`: absolute, with symbolic links resolved as far as the path exists. */
export function resolveReal(path) {
  const absolute = resolve(path);
  try {
    return realpathSync(absolute);
  } catch {
    const parent = dirname(absolute);
    return parent === absolute ? absolute : join(resolveReal(parent), basename(absolute));
  }
}
