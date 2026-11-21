#!/usr/bin/env bun
// Checks SwiftUIWeb's source-level public API contract.
//
// The package contains a number of Embedded-only targets that cannot all be compiled by the host Swift toolchain at the
// same time. A compiler symbol graph is therefore not a useful CI contract for this repository: it would either silently
// omit Embedded declarations or force every optional executable and system library into the graph. This tool extracts the
// explicit public surface from the library sources, keeps availability annotations, and compares the deterministic result
// with the checked-in baseline (Documentation/API/public-api.json).
//
// This is intentionally a compatibility gate, not a replacement for Swift's access-control checker. Native and Embedded
// compilation remain authoritative for type correctness; this gate makes accidental public API drift visible in a small,
// reviewable JSON diff.
//
// usage: bun Tools/api-contract.mjs [--check] [--update] [--check-availability] [--output PATH]
import { existsSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import {
  compareStrings, compareTuples, filesWithSuffix, fromRoot, isMain, jsonDumps, stripWhitespace, readText, ROOT, rx, splitlines,
} from "./audit-support.mjs";

const BASELINE = join(ROOT, "Documentation", "API", "public-api.json");

// Keep this list aligned with the library products in Package.swift. Internal Clang bridges and executable examples
// deliberately do not form part of the consumer API contract.
export const PUBLIC_TARGETS = [
  "SwiftUIWeb", "SwiftUIWebCrypto", "SwiftUIWebTransferable", "WebFoundation", "WebOSLog", "SwiftUIWebUniformTypeIdentifiers",
  "SwiftUIWebPhotosUI", "SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebInternationalization", "SwiftUIWebCoreLocation",
  "SwiftUIWebNetworking", "SwiftUIWebSecurity", "SwiftUIWebFiber", "SwiftUIWebHTML", "SwiftUIWebBrowser", "SwiftUIWebWeb",
  "SwiftUIWebMapKit", "SwiftUIWebCharts", "SwiftUIWebAVFoundation", "SwiftUIWebAVKit", "SwiftUIWebMotion", "SwiftUIWebUserNotifications",
  "SwiftUIWebBrowserIO",
];

const ACCESS = rx(String.raw`\b(public|open)\b`, "g");
const ACCESS_ONCE = rx(String.raw`\b(?:public|open)\b`);
const KIND = rx(
  String.raw`\b(struct|class|enum|protocol|actor|typealias|func|var|let|init|subscript|associatedtype|macro|precedencegroup|operator)\b`,
  "g",
);
const ATTRIBUTE = rx(String.raw`@available\s*\(([^\)]*)\)`, "g");
const VAR_OR_LET = rx(String.raw`\b(?:var|let)\b`);
const SPACES = rx(String.raw`\s+`, "g");
const TRAILING_SEMICOLON = rx(String.raw`\s*;\s*$`);

/** Replaces comments and string contents with spaces while preserving line positions. */
export function maskNonCode(text) {
  const output = [];
  let index = 0;
  let state = "code";
  let rawHashes = 0;
  while (index < text.length) {
    const character = text[index];
    const following = index + 1 < text.length ? text[index + 1] : "";
    if (state === "line") {
      if (character === "\n") {
        output.push(character);
        state = "code";
      } else output.push(" ");
      index += 1;
      continue;
    }
    if (state === "block") {
      if (character === "*" && following === "/") {
        output.push(" ", " ");
        index += 2;
        state = "code";
      } else {
        output.push(character === "\n" ? "\n" : " ");
        index += 1;
      }
      continue;
    }
    if (state === "string" || state === "multiline" || state === "raw" || state === "raw-multiline") {
      const terminator = state === "raw-multiline"
        ? '"'.repeat(3) + "#".repeat(rawHashes)
        : state === "multiline" ? '"'.repeat(3) : state === "raw" ? '"' + "#".repeat(rawHashes) : '"';
      if (text.startsWith(terminator, index)) {
        for (let n = 0; n < terminator.length; n += 1) output.push(" ");
        index += terminator.length;
        state = "code";
        rawHashes = 0;
      } else {
        output.push(character === "\n" ? "\n" : " ");
        index += 1;
      }
      continue;
    }
    if (character === "/" && following === "/") {
      output.push(" ", " ");
      index += 2;
      state = "line";
      continue;
    }
    if (character === "/" && following === "*") {
      output.push(" ", " ");
      index += 2;
      state = "block";
      continue;
    }
    if (character === "#") {
      let hashes = 0;
      while (index + hashes < text.length && text[index + hashes] === "#") hashes += 1;
      if (index + hashes < text.length && text[index + hashes] === '"') {
        rawHashes = hashes;
        const triple = text.startsWith('"""', index + hashes);
        const delimiter = hashes + (triple ? 3 : 1);
        for (let n = 0; n < delimiter; n += 1) output.push(" ");
        index += delimiter;
        state = triple ? "raw-multiline" : "raw";
        continue;
      }
    }
    if (character === '"') {
      const triple = text.startsWith('"""', index);
      for (let n = 0; n < (triple ? 3 : 1); n += 1) output.push(" ");
      index += triple ? 3 : 1;
      state = triple ? "multiline" : "string";
      continue;
    }
    output.push(character);
    index += 1;
  }
  return output.join("");
}

export function normalize(signature) {
  signature = stripWhitespace(signature.replace(SPACES, " "));
  // Bodies/default implementations are not API. The first brace is the declaration body for the declarations we
  // collect; braces in generic constraints are intentionally uncommon and remain visible for review.
  signature = stripWhitespace(signature.split("{")[0]);
  return signature.replace(TRAILING_SEMICOLON, "");
}

/** The `@available(...)` arguments in the attribute lines above line `index` and on the line itself, deduplicated. */
export function availability(lines, index) {
  const values = [];
  const collect = (line) => {
    for (const match of line.matchAll(ATTRIBUTE)) values.push(stripWhitespace(match[1]));
  };
  let cursor = index - 1;
  while (cursor >= 0 && index - cursor <= 8) {
    const line = stripWhitespace(lines[cursor]);
    if (!line) break;
    collect(line);
    if (!line.startsWith("@")) break;
    cursor -= 1;
  }
  collect(lines[index]);
  return [...new Set(values)];
}

/** The first `needle` outside a parenthesized parameter list, or null. */
function topLevelIndex(value, needle) {
  let depth = 0;
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (character === "(") depth += 1;
    else if (character === ")") depth = Math.max(0, depth - 1);
    else if (character === needle && depth === 0) return index;
  }
  return null;
}

/** Drops implementation syntax without losing function defaults. */
function headerPrefix(value) {
  // A semicolon separates independent declarations on the same source line. The caller scans every `public` occurrence, so
  // retaining only this part makes each baseline entry represent exactly one declaration.
  const semicolon = topLevelIndex(value, ";");
  if (semicolon !== null) value = value.slice(0, semicolon);
  // Stored/computed property initializers are implementation details. Do not split function signatures at `=` because
  // default arguments are part of their source-level API and are parenthesized.
  const equals = topLevelIndex(value, "=");
  if (VAR_OR_LET.test(value) && equals !== null) value = value.slice(0, equals);
  return value;
}

const count = (text, character) => text.split(character).length - 1;

/**
 * Collects a possibly wrapped declaration header. A small lexical scanner rather than a Swift parser: it tracks the
 * delimiters that distinguish a wrapped signature from its implementation and never consumes the next declaration after a
 * one-line property or protocol requirement.
 */
export function declaration(lines, start, column = 0) {
  const first = stripWhitespace(lines[start].slice(column));
  const parts = [headerPrefix(first)];
  let parentheses = count(first, "(") - count(first, ")");
  // A complete one-line property, typealias, or declaration separated by a semicolon is finished before the next line.
  if (
    topLevelIndex(first, ";") !== null ||
    (parentheses <= 0 && topLevelIndex(first, "=") !== null && VAR_OR_LET.test(first)) ||
    (first.includes("{") && parentheses <= 0)
  ) return normalize(parts.join(" "));

  let cursor = start + 1;
  while (cursor < lines.length && cursor - start < 24) {
    const current = stripWhitespace(lines[cursor]);
    if (!current) {
      if (parentheses <= 0) break;
      cursor += 1;
      continue;
    }
    if (parentheses <= 0 && (current.startsWith("}") || ACCESS_ONCE.test(current))) break;
    parts.push(headerPrefix(current));
    parentheses += count(current, "(") - count(current, ")");
    if (
      parentheses <= 0 &&
      (topLevelIndex(current, "{") !== null || topLevelIndex(current, ";") !== null ||
        (VAR_OR_LET.test(parts.join(" ")) && topLevelIndex(current, "=") !== null))
    ) break;
    cursor += 1;
  }
  return normalize(parts.join(" "));
}

function collectTarget(target) {
  const sourceRoot = join(ROOT, "Sources", target);
  if (!existsSync(sourceRoot) || !statSync(sourceRoot).isDirectory()) {
    throw new RuntimeFailure(`public target has no source directory: ${target}`);
  }
  const entries = new Map();
  for (const path of filesWithSuffix(sourceRoot, ".swift")) {
    const original = readText(path);
    const originalLines = splitlines(original);
    const maskedLines = splitlines(maskNonCode(original));
    maskedLines.forEach((line, index) => {
      for (const access of line.matchAll(ACCESS)) {
        KIND.lastIndex = access.index + access[0].length;
        const kindMatch = KIND.exec(line);
        if (!kindMatch || kindMatch[1] === "extension") continue;
        // `public extension Foo` is a namespace for explicitly public members, not a standalone symbol.
        const prefix = stripWhitespace(line.slice(0, access.index));
        if (prefix.endsWith("extension")) continue;
        const signature = declaration(maskedLines, index, access.index);
        if (!signature) continue;
        const values = [target, fromRoot(path), signature, availability(originalLines, index)];
        entries.set(JSON.stringify(values), values);
      }
    });
  }
  return [...entries.values()]
    .sort(compareTuples)
    .map(([entryTarget, file, signature, available]) => ({ target: entryTarget, file, signature, availability: available }));
}

class RuntimeFailure extends Error {}

export function buildManifest() {
  const symbols = [];
  for (const target of PUBLIC_TARGETS) symbols.push(...collectTarget(target));
  return {
    schema: 1,
    package: "SwiftUIWeb",
    swiftToolsVersion: "6.4",
    defaultAvailability: "macOS 13",
    targets: [...PUBLIC_TARGETS],
    symbols,
  };
}

const KNOWN_PLATFORMS = new Set(["iOS", "macOS", "watchOS", "tvOS", "visionOS", "macCatalyst", "swift"]);
const PLATFORM_NAME = rx(String.raw`^[A-Za-z][A-Za-z0-9_]*$`);

export function validateAvailability(manifest) {
  const errors = [];
  for (const symbol of manifest.symbols) {
    for (const annotation of symbol.availability) {
      if (!stripWhitespace(annotation)) {
        errors.push(`${symbol.target}:${symbol.signature}: empty @available annotation`);
        continue;
      }
      const pieces = annotation.split(",").map(stripWhitespace).filter(Boolean);
      if (pieces.length === 0) {
        errors.push(`${symbol.target}:${symbol.signature}: malformed @available annotation`);
        continue;
      }
      for (const piece of pieces) {
        const platform = piece.split(SPACES)[0];
        if (platform === "*" || platform === "unavailable" || platform === "deprecated" || piece.includes(":")) continue;
        if (!KNOWN_PLATFORMS.has(platform) && !PLATFORM_NAME.test(platform)) {
          errors.push(`${symbol.target}:${symbol.signature}: unknown availability platform '${platform}'`);
        }
      }
    }
  }
  return errors;
}

export const canonical = (value) => jsonDumps(value, { indent: 2, ensureAscii: false }) + "\n";

const USAGE = "usage: api-contract.mjs [-h] [--check] [--update] [--check-availability] [--output OUTPUT]";

function parseArguments(argv) {
  const args = { check: false, update: false, checkAvailability: false, output: BASELINE };
  const fail = (message) => {
    console.error(`${USAGE}\napi-contract.mjs: error: ${message}`);
    process.exit(2);
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--check") args.check = true;
    else if (argument === "--update") args.update = true;
    else if (argument === "--check-availability") args.checkAvailability = true;
    else if (argument === "--output") {
      if (index + 1 >= argv.length) fail("argument --output: expected one argument");
      args.output = argv[(index += 1)];
    } else if (argument.startsWith("--output=")) args.output = argument.slice("--output=".length);
    else if (argument === "-h" || argument === "--help") {
      console.log(`${USAGE}\n\nChecks SwiftUIWeb's source-level public API contract.`);
      process.exit(0);
    } else fail(`unrecognized arguments: ${argument}`);
  }
  if (args.check && args.update) fail("--check and --update are mutually exclusive");
  return args;
}

function main() {
  const args = parseArguments(process.argv.slice(2));
  try {
    const manifest = buildManifest();
    const availabilityErrors = validateAvailability(manifest);
    if (availabilityErrors.length > 0) {
      for (const error of availabilityErrors) console.error(`api-contract: ${error}`);
      return 1;
    }
    const rendered = canonical(manifest);
    const output = isAbsolute(args.output) ? args.output : join(ROOT, args.output);
    if (args.update) {
      mkdirSync(dirname(output), { recursive: true });
      writeFileSync(output, rendered, "utf8");
      console.log(`Wrote public API baseline: ${output}`);
      return 0;
    }
    if (args.check || existsSync(output)) {
      const expected = existsSync(output) ? readText(output) : "";
      if (expected !== rendered) {
        console.error(`Public API drift detected: ${output}`);
        console.error("Run `make api-diff-update` after reviewing the intentional change.");
        return 1;
      }
    }
    console.log(`Public API contract: ${manifest.symbols.length} declarations across ${PUBLIC_TARGETS.length} targets`);
    return 0;
  } catch (error) {
    if (error instanceof RuntimeFailure || error?.code === "ENOENT" || error?.code === "EACCES" || error instanceof TypeError) {
      // TypeError is what a strict UTF-8 decode throws.
      console.error(`api-contract: ${error.message}`);
      return 2;
    }
    throw error;
  }
}

if (isMain(import.meta.url)) process.exit(main());
