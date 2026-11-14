#!/usr/bin/env bun
// Test actual Embedded compiler capabilities and inventory migration risks.
//
// A successful capability probe is NOT a successful SwiftUIWeb application build.
// No standard-Swift fallback, disabled diagnostics, source rewriting, or fake
// success is used. Native macro/tool binaries do not count as browser runtime.
//
// Usage:
//   embedded-preflight.mjs [--swiftc SWIFTC] [--swift SWIFT] [--target TARGET] [--output OUTPUT]
//                          [--compile-core] [--sdk SDK]
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstatSync, mkdirSync, readFileSync, readdirSync, rmSync, writeSync } from "node:fs";
import { constants as osConstants } from "node:os";
import { dirname, join as joinNative } from "node:path";
import { fileURLToPath } from "node:url";
import {
  BOUNDARY,
  LINE_START,
  FloatValue,
  SPACE,
  WORD_CHARS,
  abspath,
  isFile,
  normalizeNewlines,
  dumpsJson,
  listRepr,
  stripWhitespace,
  readText,
  realpath,
  which,
  writeText,
} from "./text-semantics.mjs";

const ROOT = realpath(joinNative(dirname(realpath(fileURLToPath(import.meta.url))), ".."));

export const GUARD = "#if !hasFeature(Embedded)\n#error(\"This probe must be compiled in real Embedded Swift mode\")\n#endif\n";

// Source text of each probe as the probe literals write it (`\\.` in the literal is `\.` in Swift).
const lines = (...rows) => rows.join("\n") + "\n";

// name -> [purpose, Swift source]; insertion order is the probe order.
export const PROBES = {
  "embedded-mode": [
    "mode",
    '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { n &+ 1 }',
  ],
  "typed-class-storage": [
    "state/environment",
    lines(
      "",
      "class Base {}",
      "final class Box<T>: Base { let value: T; init(_ value: T) { self.value = value } }",
      '@inline(never) func read(_ value: Base) -> Int32 { (value as? Box<Int32>)?.value ?? -1 }',
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { read(Box(n)) }',
    ),
  ],
  "class-type-identity": [
    "typed storage identity",
    lines(
      "",
      "final class Token<T> {}",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 {',
      "  ObjectIdentifier(Token<Int>.self) == ObjectIdentifier(Token<String>.self) ? -1 : n",
      "}",
    ),
  ],
  "stored-keypath": [
    "ForEach(id: \\.id), Binding",
    lines(
      "",
      "struct Model { var value: Int32 }",
      "@inline(never) func read(_ model: Model, _ path: KeyPath<Model, Int32>) -> Int32 { model[keyPath: path] }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { read(Model(value: n), \\.value) }',
    ),
  ],
  "computed-keypath": [
    "@Environment(\\.colorScheme)",
    lines(
      "",
      "struct Environment { var raw: Int32; var value: Int32 { get { raw } set { raw = newValue } } }",
      "@inline(never) func read(_ value: Environment, _ path: KeyPath<Environment, Int32>) -> Int32 { value[keyPath: path] }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { read(Environment(raw: n), \\.value) }',
    ),
  ],
  "writable-keypath": [
    "nested bindings and keyframe tracks",
    lines(
      "",
      "struct Model { var value: Int32 }",
      "@inline(never) func write(_ model: inout Model, _ key: WritableKeyPath<Model,Int32>, _ value: Int32) { model[keyPath:key] = value }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { var m=Model(value: 0); write(&m, \\.value, n); return m.value }',
    ),
  ],
  "reference-writable-keypath": [
    "@Bindable class model projections",
    lines(
      "",
      "final class Model { var value: Int32 = 0 }",
      "@inline(never) func write(_ model: Model, _ key: ReferenceWritableKeyPath<Model,Int32>, _ value: Int32) { model[keyPath:key] = value }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { let m=Model(); write(m, \\.value, n); return m.value }',
    ),
  ],
  "dynamic-member-keypath": [
    "$binding.property",
    lines(
      "",
      "@dynamicMemberLookup struct Projection<Root> {",
      "  let root: Root",
      "  subscript<Value>(dynamicMember key: KeyPath<Root, Value>) -> Value { root[keyPath:key] }",
      "}",
      "struct Model { var value: Int32 }",
      "@inline(never) func project(_ n: Int32) -> Int32 { Projection(root: Model(value:n)).value }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { project(n) }',
    ),
  ],
  "weak-reference": [
    "current renderer subscription and callback lifetimes",
    lines(
      "",
      "final class Owner { var value: Int32; init(_ value:Int32) { self.value=value } }",
      "final class Slot { weak var owner: Owner?; init(_ owner: Owner) { self.owner=owner } }",
      "@inline(never) func read(_ slot: Slot) -> Int32 { slot.owner?.value ?? -1 }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { let o=Owner(n); let s=Slot(o); return withExtendedLifetime(o) { read(s) } }',
    ),
  ],
  "any-value": [
    "remaining erased animation and table values",
    lines(
      "",
      "@inline(never) func read(_ value: Any) -> Int32 { value as? Int32 ?? -1 }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { read(n) }',
    ),
  ],
  "any-hashable": [
    "remaining ScrollPosition compatibility API",
    lines(
      "",
      "@inline(never) func equal(_ a: AnyHashable,_ b: AnyHashable) -> Bool { a == b }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { equal(AnyHashable(n),AnyHashable(n)) ? n : -1 }',
    ),
  ],
  codable: [
    "current JSON, typed storage, location and notification APIs",
    lines(
      "",
      "struct Record: Codable { var value: Int32 }",
      '@_cdecl("probe") public func probe(_ n: Int32) -> Int32 { Record(value:n).value }',
    ),
  ],
  reflection: [
    "remaining metadata/description call sites",
    lines(
      "",
      "@inline(never) func count(_ value: Any) -> Int32 { Int32(Mirror(reflecting:value).children.count) }",
      "struct Record { var value:Int32 }",
      '@_cdecl("probe") public func probe(_ n:Int32) -> Int32 { count(Record(value:n)) }',
    ),
  ],
  "untyped-throws": [
    "current async transport error signatures",
    lines(
      "",
      "enum Problem: Error { case failed }",
      "@inline(never) func operation(_ n:Int32) throws -> Int32 { if n < 0 { throw Problem.failed }; return n }",
      '@_cdecl("probe") public func probe(_ n:Int32) -> Int32 { do { return try operation(n) } catch { return -1 } }',
    ),
  ],
  "typed-throws": [
    "possible implementation mechanism, not an API substitution",
    lines(
      "",
      "enum Problem: Error { case failed }",
      "@inline(never) func operation(_ n:Int32) throws(Problem) -> Int32 { if n < 0 { throw .failed }; return n }",
      '@_cdecl("probe") public func probe(_ n:Int32) -> Int32 { do { return try operation(n) } catch { return -1 } }',
    ),
  ],
};

// Mechanisms used by the existing public surface or current implementation.
// Each can be removed from this list only together with the corresponding
// migration and behavior tests, not merely to make this preflight green.
export const REQUIRED = new Set(Object.keys(PROBES).filter((name) => name !== "typed-throws"));

// Lexical inventory only. Literal interpolation code is deliberately omitted.
export function maskCommentsAndLiterals(source) {
  const chars = source.split("");
  const n = source.length;
  let i = 0;
  const erase = (start, end) => {
    for (let k = start; k < end; k += 1) {
      if (chars[k] !== "\n") chars[k] = " ";
    }
  };
  while (i < n) {
    if (source.startsWith("//", i)) {
      let end = source.indexOf("\n", i);
      end = end < 0 ? n : end;
      erase(i, end);
      i = end;
    } else if (source.startsWith("/*", i)) {
      const start = i;
      i += 2;
      let depth = 1;
      while (i < n && depth) {
        if (source.startsWith("/*", i)) {
          depth += 1;
          i += 2;
        } else if (source.startsWith("*/", i)) {
          depth -= 1;
          i += 2;
        } else {
          i += 1;
        }
      }
      erase(start, i);
    } else {
      let raw = 0;
      let j = i;
      while (j < n && source[j] === "#") {
        raw += 1;
        j += 1;
      }
      if (j < n && source[j] === '"') {
        const start = i;
        const quotes = source.startsWith('"""', j) ? 3 : 1;
        j += quotes;
        const closing = '"'.repeat(quotes) + "#".repeat(raw);
        while (j < n) {
          if (source.startsWith(closing, j)) {
            j += closing.length;
            break;
          }
          if (!raw && source[j] === "\\") j += 2;
          else j += 1;
        }
        erase(start, Math.min(j, n));
        i = j;
      } else {
        i += 1;
      }
    }
  }
  return chars.join("");
}

const PATTERNS = {
  "foundation-import": String.raw`${LINE_START}${SPACE}*(?:@_exported${SPACE}+)?import${SPACE}+(?:(?:struct|class|enum|protocol|func|typealias)${SPACE}+)?Foundation${BOUNDARY}`,
  "keypath-type": String.raw`${BOUNDARY}(?:KeyPath|WritableKeyPath|ReferenceWritableKeyPath|PartialKeyPath|AnyKeyPath)${BOUNDARY}`,
  "keypath-literal": String.raw`\\(?:[A-Za-z_][${WORD_CHARS}<>]*${SPACE}*)?\.`,
  "weak-unowned": String.raw`${BOUNDARY}(?:weak|unowned)${BOUNDARY}`,
  "any-hashable": String.raw`${BOUNDARY}AnyHashable${BOUNDARY}`,
  codable: String.raw`${BOUNDARY}(?:Codable|Encodable|Decodable|Encoder|Decoder|CodingKey)${BOUNDARY}`,
  reflection: String.raw`${BOUNDARY}Mirror${SPACE}*\(|String${SPACE}*\(${SPACE}*(?:describing|reflecting)${SPACE}*:`,
  "embedded-conditional": String.raw`#(?:if|elseif)${BOUNDARY}[^\n]*hasFeature\(Embedded\)`,
};

// Every *.swift entry below dir: directory symlinks are not followed,
// file symlinks are included.
function swiftFiles(dir) {
  const found = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return found;
  }
  for (const entry of entries) {
    const path = joinNative(dir, entry.name);
    if (entry.isDirectory()) found.push(...swiftFiles(path));
    if (entry.name.endsWith(".swift")) found.push(path);
  }
  return found;
}

// sorted() of pathlib paths compares their parts tuples.
function comparePathParts(a, b) {
  const pa = a.split("/");
  const pb = b.split("/");
  for (let i = 0; i < Math.min(pa.length, pb.length); i += 1) {
    if (pa[i] !== pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return pa.length - pb.length;
}

export function inventory(root = ROOT) {
  const matches = Object.fromEntries(Object.keys(PATTERNS).map((kind) => [kind, []]));
  const files = swiftFiles(joinNative(root, "Sources")).map((path) => abspath(path)).sort(comparePathParts);
  for (const path of files) {
    const clean = maskCommentsAndLiterals(readText(path));
    for (const [kind, pattern] of Object.entries(PATTERNS)) {
      for (const match of clean.matchAll(new RegExp(pattern, "gu"))) {
        const line = countNewlines(clean, match.index) + 1;
        matches[kind].push({ path: path.slice(root.length + 1), line });
      }
    }
  }
  return {
    scope: "LEXICAL_ALL_CONDITIONAL_BRANCHES_NOT_COMPILER_REACHABILITY",
    counts: Object.fromEntries(Object.entries(matches).map(([kind, list]) => [kind, list.length])),
    matches,
    caveat:
      "Both active and inactive branches are counted. Literal interpolation is omitted. This is a review index, not a linked dependency graph.",
  };
}

function countNewlines(text, end) {
  let count = 0;
  for (let i = 0; i < end; i += 1) {
    if (text[i] === "\n") count += 1;
  }
  return count;
}

const USAGE = "usage: embedded-preflight.mjs [-h] [--swiftc SWIFTC] [--swift SWIFT] [--target TARGET]\n" +
  "                            [--output OUTPUT] [--compile-core] [--sdk SDK]\n";
const DESCRIPTION =
  "Test actual Embedded compiler capabilities and inventory migration risks.\n\n" +
  "A successful capability probe is NOT a successful SwiftUIWeb application build.\n" +
  "No standard-Swift fallback, disabled diagnostics, source rewriting, or fake\n" +
  "success is used. Native macro/tool binaries do not count as browser runtime.\n";

// argparse-compatible option parsing for the flags this CLI defines.
function parseArguments(argv, env) {
  const options = [
    { name: "--swiftc", key: "swiftc", takesValue: true },
    { name: "--swift", key: "swift", takesValue: true },
    { name: "--target", key: "target", takesValue: true },
    { name: "--output", key: "output", takesValue: true },
    { name: "--compile-core", key: "compileCore", takesValue: false },
    { name: "--sdk", key: "sdk", takesValue: true },
    { name: "--help", key: "help", takesValue: false },
  ];
  const values = {
    swiftc: env.SWIFTC ?? "swiftc",
    swift: env.SWIFT ?? "swift",
    target: "wasm32-unknown-none-wasm",
    output: joinNative(ROOT, ".build/embedded-preflight"),
    compileCore: false,
    sdk: env.WASM_SDK ?? null,
    help: false,
  };
  const extras = [];
  const fail = (message) => {
    throw new UsageError(message);
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "-h") {
      values.help = true;
      continue;
    }
    if (!arg.startsWith("--")) {
      extras.push(arg);
      continue;
    }
    const equals = arg.indexOf("=");
    const name = equals >= 0 ? arg.slice(0, equals) : arg;
    const inline = equals >= 0 ? arg.slice(equals + 1) : undefined;
    let option = options.find((candidate) => candidate.name === name);
    if (!option) {
      const prefixed = options.filter((candidate) => candidate.name.startsWith(name));
      if (prefixed.length > 1) {
        fail(`ambiguous option: ${name} could match ${prefixed.map((candidate) => candidate.name).join(", ")}`);
      }
      option = prefixed[0];
    }
    if (!option) {
      extras.push(arg);
      continue;
    }
    if (!option.takesValue) {
      if (inline !== undefined) fail(`argument ${option.name}: ignored explicit argument '${inline}'`);
      values[option.key] = true;
      continue;
    }
    let value = inline;
    if (value === undefined) {
      const next = argv[i + 1];
      const looksLikeOption = next !== undefined && next.startsWith("-") && next !== "-" &&
        !/^-\d+$|^-\d*\.\d+$/.test(next);
      if (next === undefined || looksLikeOption) fail(`argument ${option.name}: expected one argument`);
      value = next;
      i += 1;
    }
    values[option.key] = value;
  }
  if (extras.length) fail(`unrecognized arguments: ${extras.join(" ")}`);
  return values;
}

class UsageError extends Error {}

// subprocess.run(..., text=True, capture_output=True, timeout=...) plus the log and result bookkeeping of the script.
function execute(output, name, command, env = undefined, timeout = 90) {
  const start = performance.now();
  const strings = command.map(String);
  let code;
  let stdout;
  let stderr;
  const result = spawnSync(strings[0], strings.slice(1), {
    cwd: ROOT,
    env,
    encoding: "utf8",
    timeout: timeout * 1000,
    maxBuffer: 1024 * 1024 * 1024,
    stdio: ["inherit", "pipe", "pipe"],
  });
  if (result.error) {
    code = -1;
    stdout = "";
    if (result.error.code === "ETIMEDOUT") {
      stderr = `Command ${listRepr(strings)} timed out after ${timeout} seconds`;
    } else if (result.error.code === "ENOENT") {
      stderr = `[Errno 2] No such file or directory: '${strings[0]}'`;
    } else if (result.error.code === "EACCES") {
      stderr = `[Errno 13] Permission denied: '${strings[0]}'`;
    } else {
      stderr = String(result.error.message);
    }
  } else {
    code = result.status ?? -signalNumber(result.signal);
    stdout = normalizeNewlines(result.stdout ?? "");
    stderr = normalizeNewlines(result.stderr ?? "");
  }
  writeText(joinNative(output, `${name}.log`), "$ " + dumpsJson(strings) + "\n" + stdout + "\n" + stderr);
  return {
    command: strings,
    exit_code: code,
    stdout,
    stderr,
    seconds: new FloatValue((performance.now() - start) / 1000),
  };
}

// A signal-terminated child is reported with the negated signal number.
function signalNumber(signal) {
  return signal ? osConstants.signals[signal] ?? 0 : 0;
}

function fileDigest(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

export function main(argv = process.argv.slice(2), env = process.env) {
  let args;
  try {
    args = parseArguments(argv, env);
  } catch (error) {
    if (error instanceof UsageError) {
      writeSync(2, USAGE + `embedded-preflight.mjs: error: ${error.message}\n`);
      return 2;
    }
    throw error;
  }
  if (args.help) {
    writeSync(1, USAGE + "\n" + DESCRIPTION);
    return 0;
  }
  // A link at the output path would send the files written here (and the removals below) to wherever it points.
  if (lstatSync(args.output, { throwIfNoEntry: false })?.isSymbolicLink()) {
    writeSync(2, USAGE + `embedded-preflight.mjs: error: the output folder is a symbolic link: ${args.output}\n`);
    return 2;
  }
  const output = realpath(args.output);
  mkdirSync(output, { recursive: true });
  writeText(
    joinNative(output, "result.json"),
    dumpsJson({
      scope: "COMPILER_CAPABILITIES_AND_SOURCE_INVENTORY",
      status: "RUNNING_NOT_VALIDATED",
      full_framework_embedded: false,
    }) + "\n",
  );
  const compiler = which(args.swiftc);
  const results = [];
  let version = "MISSING";
  if (compiler) {
    const probe = spawnSync(compiler, ["--version"], { encoding: "utf8", stdio: ["inherit", "pipe", "pipe"] });
    version = stripWhitespace(normalizeNewlines(probe.stdout ?? ""));
    for (const [name, [purpose, source]] of Object.entries(PROBES)) {
      const sourcePath = joinNative(output, `${name}.swift`);
      writeText(sourcePath, GUARD + source + "\n");
      const objectPath = joinNative(output, `${name}.o`);
      // lstat: a folder at this name is not ours to remove, and a link is removed as a link, never followed.
      const stale = lstatSync(objectPath, { throwIfNoEntry: false });
      if (stale && !stale.isDirectory()) rmSync(objectPath, { force: true });
      const check = execute(output, name, [
        compiler,
        "-swift-version",
        "6",
        "-enable-experimental-feature",
        "Embedded",
        "-wmo",
        "-Osize",
        "-parse-as-library",
        "-target",
        args.target,
        "-emit-object",
        sourcePath,
        "-o",
        objectPath,
      ]);
      const objectExists = isFile(objectPath);
      results.push({
        ...check,
        name,
        purpose,
        required_by_current_source: REQUIRED.has(name),
        status: check.exit_code === 0 && objectExists ? "COMPILED_NOT_EXECUTED" : "UNSUPPORTED_OR_FAILED",
        object_sha256: objectExists ? fileDigest(objectPath) : null,
      });
      writeSync(1, `${name}: ${results[results.length - 1].status}\n`);
    }
  } else {
    results.push({ name: "compiler", status: "MISSING", required_by_current_source: true });
  }
  let core = { status: "NOT_REQUESTED" };
  if (args.compileCore) {
    const swift = which(args.swift);
    if (!swift || !args.sdk) {
      core = {
        status: "BLOCKED",
        reason: "Provide a matching Swift executable and --sdk Embedded SDK ID; no SDK is guessed.",
      };
    } else {
      const childEnv = { ...env, SWIFTUIWEB_EMBEDDED: "1" };
      delete childEnv.SWIFTUIWEB_EMBEDDED_RESTRICTIONS;
      core = execute(
        output,
        "actual-core",
        [swift, "build", "--swift-sdk", args.sdk, "--target", "SwiftUIWebCore", "-c", "release", "--scratch-path", joinNative(output, "core-build"), "-v"],
        childEnv,
        600,
      );
      core.status = core.exit_code === 0 ? "COMPILED_LIBRARY_NOT_LINKED_OR_EXECUTED" : "FAIL";
      core.scope = "ACTUAL_SWIFTUIWEBCORE_TARGET_NOT_COMPLETE_APP_OR_BROWSER";
    }
  }
  const blockers = results
    .filter((check) => check.required_by_current_source && check.status !== "COMPILED_NOT_EXECUTED")
    .map((check) => check.name);
  const status = blockers.length || core.status === "FAIL" || core.status === "BLOCKED"
    ? "BLOCKED"
    : "CAPABILITY_PROBES_PASSED_NOT_PRODUCT_VALIDATION";
  const report = {
    schema_version: 1,
    scope: "COMPILER_CAPABILITIES_AND_SOURCE_INVENTORY",
    status,
    swiftc: version,
    target: args.target,
    full_framework_embedded: false,
    keypath_qualification:
      "Swift 6.4 release and main snapshots have different Embedded restrictions. Actual probe results, not version guesses, decide capability.",
    required_failures: blockers,
    probes: results,
    core,
    source_inventory: inventory(),
    known_unfinished_work: [
      "SwiftUIWebBrowser still has no complete Embedded BrowserSession implementation.",
      "Remaining weak ownership, reflection, Codable and observation paths need supported replacements with lifecycle/API tests.",
      "Passing geometry or runtime-primitives fixtures does not establish complete framework or application parity.",
      "The complete deployed Embedded bundle has not been built or measured by this preflight.",
    ],
  };
  const resultPath = joinNative(output, "result.json");
  writeText(resultPath, dumpsJson(report, 2) + "\n");
  writeSync(
    1,
    dumpsJson({ status, required_failures: blockers, core: core.status, report: resultPath }, 2) + "\n",
  );
  return status === "BLOCKED" ? 1 : 0;
}

if (process.argv[1] && realpath(process.argv[1]) === realpath(fileURLToPath(import.meta.url))) {
  process.exitCode = main();
}
