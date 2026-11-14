#!/usr/bin/env bun
// Tests the commands of Tools/swiftuiweb-tools.mjs other than strip-wasm (Tools/test-strip-wasm.mjs): the capability
// matrix, the BrowserIO constants and the string-catalog translations, on the checked-in files and on temporary roots.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { applyTranslations, binaryAtoms, browserIOProtocol, featureMatrix } from "./swiftuiweb-tools.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const TOOLS = join(ROOT, "Tools/swiftuiweb-tools.sh");

function withDirectory(body) {
  const directory = mkdtempSync(join(tmpdir(), "swiftuiweb-tools-"));
  try { return body(directory); } finally { rmSync(directory, { recursive: true, force: true }); }
}

function put(root, path, text) {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), text);
}

const quiet = (body) => {
  const log = console.log;
  console.log = () => {};
  try { return body(); } finally { console.log = log; }
};

test("the checked-in matrix and BrowserIO constants are current", () => {
  quiet(() => {
    featureMatrix(["--check"], ROOT);
    browserIOProtocol(["--check"], ROOT);
    binaryAtoms(["--check"], ROOT);
  });
});

test("binary publication atoms and constants are generated for Swift and JavaScript from the list", () => withDirectory((root) => {
  const schema = { version: 2, ops: { ROOT: 1, ELEMENT_NS: 18 }, namespaces: { svg: 1 }, tags: ["div", "svg"], attributes: ["class", "data-x"], values: ["true", "a\"b\\c\u00e9"] };
  put(root, "Tools/binary-atoms.json", JSON.stringify(schema));
  assert.throws(() => binaryAtoms(["--check"], root), /STALE binary atom generated files: Sources\/.*Tools\/binary-atoms\.generated\.js/);
  mkdirSync(join(root, "Sources/SwiftUIWebHTML"), { recursive: true });
  quiet(() => binaryAtoms([], root));
  const swift = readFileSync(join(root, "Sources/SwiftUIWebHTML/BinaryAtoms.generated.swift"), "utf8");
  const javascript = readFileSync(join(root, "Tools/binary-atoms.generated.js"), "utf8");
  // The hash both ends compare covers the version and the atoms in order.
  const hash = (text) => { let h = 0x811c9dc5; for (const b of Buffer.from(text)) h = Math.imul(h ^ b, 0x01000193) >>> 0; return "0x" + h.toString(16).padStart(8, "0"); };
  const expected = hash("v2\ndiv\0svg\0class\0data-x\0true\0a\"b\\c\u00e9");
  assert.ok(swift.includes(`static let atomsHash: UInt32 = ${expected}`) && javascript.includes(`BINARY_ATOMS_HASH = ${expected}`));
  assert.ok(swift.includes("static let version: UInt16 = 2") && swift.includes("static let atomCount: UInt32 = 6"));
  assert.ok(swift.includes("static let opRoot: UInt32 = 1") && swift.includes("static let opElementNs: UInt32 = 18") && swift.includes("static let namespaceSvg: UInt32 = 1"));
  assert.ok(swift.includes(String.raw`"div\0svg\0class\0data-x\0true\0a\"b\\c\u{e9}"`));
  assert.ok(javascript.includes("ELEMENT_NS: 18,") && javascript.includes("svg: 1,") && javascript.includes(JSON.stringify("a\"b\\c\u00e9") + ","));
  quiet(() => binaryAtoms(["--check"], root));
  // A change to the list changes the hash, which is what makes a page and a worker from different builds refuse each other.
  put(root, "Tools/binary-atoms.json", JSON.stringify({ ...schema, values: ["true", "other"] }));
  assert.throws(() => binaryAtoms(["--check"], root), /STALE binary atom generated files/);
}));

test("an invalid binary atom list is rejected", () => withDirectory((root) => {
  const base = { version: 1, ops: { ROOT: 1 }, namespaces: { svg: 1 }, tags: ["div"], attributes: ["class"], values: ["true"] };
  const reject = (schema, message) => {
    put(root, "Tools/binary-atoms.json", JSON.stringify(schema));
    assert.throws(() => binaryAtoms(["--check"], root), message);
  };
  reject({ ...base, version: 0 }, /version must be a positive UInt16/);
  reject({ ...base, tags: "div" }, /tags must be an array/);
  reject({ ...base, values: ["div"] }, /atom "div" is listed twice/);
  reject({ ...base, values: ["a\0b"] }, /values must hold strings without NUL/);
  reject({ ...base, tags: [], attributes: [], values: [] }, /there are no atoms/);
  reject({ ...base, ops: { ROOT: 1, END: 1 } }, /op values must be unique/);
  reject({ ...base, ops: { ROOT: 256 } }, /op `ROOT` must be an integer from 1 to 255/);
  reject({ ...base, namespaces: { "1bad": 1 } }, /invalid namespace name `1bad`/);
  assert.throws(() => binaryAtoms(["--bogus"], root), /accepts only --check or --write/);
}));

test("BrowserIO constants are generated for Swift and JavaScript from the schema", () => withDirectory((root) => {
  put(root, "Documentation/BrowserIO/PROTOCOL.json", JSON.stringify({ version: 3, operations: { FetchStart: 1, indexedDBTransaction: 7 }, events: { Progress: 100 } }));
  assert.throws(() => browserIOProtocol(["--check"], root), /STALE BrowserIO generated files: Sources\/.*Tools\/BrowserIO\/protocol\.generated\.mjs/);
  mkdirSync(join(root, "Sources/SwiftUIWebBrowserIO"), { recursive: true });
  mkdirSync(join(root, "Tools/BrowserIO"), { recursive: true });
  quiet(() => browserIOProtocol([], root));
  assert.equal(
    readFileSync(join(root, "Sources/SwiftUIWebBrowserIO/BrowserIOProtocol.generated.swift"), "utf8"),
    "// Generated by swiftuiweb-tools browser-io-protocol; do not edit.\n"
      + "@usableFromInline enum _BrowserIOProtocol {\n  @usableFromInline static let version: UInt32 = 3\n"
      + "  @usableFromInline static let fetchStart: UInt32 = 1\n  @usableFromInline static let indexedDBTransaction: UInt32 = 7\n}\n"
      + "@usableFromInline enum _BrowserIOEvent {\n  @usableFromInline static let progress: Int32 = 100\n}\n",
  );
  assert.equal(
    readFileSync(join(root, "Tools/BrowserIO/protocol.generated.mjs"), "utf8"),
    "// Generated by swiftuiweb-tools browser-io-protocol; do not edit.\nexport const BROWSER_IO_PROTOCOL_VERSION = 3;\n"
      + "export const BrowserIOOperation = Object.freeze({\n  FetchStart: 1,\n  indexedDBTransaction: 7,\n});\n"
      + "export const BrowserIOEvent = Object.freeze({\n  Progress: 100,\n});\n",
  );
  quiet(() => browserIOProtocol(["--check"], root));
}));

test("an invalid BrowserIO schema is rejected", () => withDirectory((root) => {
  const reject = (schema, message) => {
    put(root, "Documentation/BrowserIO/PROTOCOL.json", JSON.stringify(schema));
    assert.throws(() => browserIOProtocol(["--check"], root), message);
  };
  reject({ version: 0, operations: { a: 1 } }, /protocol version must be a positive UInt32/);
  reject({ version: 1, operations: {} }, /operations must not be empty/);
  reject({ version: 1, operations: { "1bad": 1 } }, /invalid operation name `1bad`/);
  reject({ version: 1, operations: { bad: 0 } }, /operation `bad` must have a positive UInt32 ID/);
  reject({ version: 1, operations: { a: 1, b: 1 } }, /operation IDs must be unique/);
  reject({ version: 1, operations: { a: 1 }, events: { e: 99 } }, /event `e` must have a status code of at least 100/);
  reject({ version: 1, operations: { a: 1 }, events: { e: 100, f: 100 } }, /event codes must be unique/);
  assert.throws(() => browserIOProtocol(["--bogus"], root), /accepts only --check or --write/);
}));

test("the feature matrix is validated against its evidence and rendered", () => withDirectory((root) => {
  const manifest = (features) => put(root, "Tests/FeatureMatrix/manifest.json", JSON.stringify({ schemaVersion: 1, features }));
  put(root, "Sources/Maps.swift", "");
  manifest([{ id: "maps", status: "fallback", evidence: ["Sources/Maps.swift"] }]);
  mkdirSync(join(root, "Documentation"), { recursive: true });
  assert.throws(() => featureMatrix(["--check"], root));
  quiet(() => featureMatrix(["--write"], root));
  const rendered = readFileSync(join(root, "Documentation/FEATURE_MATRIX.md"), "utf8");
  assert.match(rendered, /^# SwiftUIWeb feature matrix\n\nThis is the runtime contract/);
  assert.match(rendered, /\| --- \| --- \| --- \|\n\| `maps` \| \*\*fallback\*\* \| `Sources\/Maps\.swift` \|\n\nThe matrix is checked by `make feature-matrix`/);
  assert.ok(rendered.endsWith("build.\n"));
  quiet(() => featureMatrix(["--check"], root));
  manifest([{ id: "maps", status: "supported", evidence: ["Sources/Maps.swift"] }]);
  assert.throws(() => featureMatrix(["--check"], root), /Documentation\/FEATURE_MATRIX\.md is stale/);

  const reject = (feature, message) => {
    manifest(Array.isArray(feature) ? feature : [feature]);
    assert.throws(() => featureMatrix([], root), message);
  };
  reject({ id: "x", status: "supported", evidence: ["../outside"] }, /evidence path must stay within the repository: \.\.\/outside/);
  reject({ id: "x", status: "supported", evidence: ["/outside"] }, /must stay within the repository/);
  reject({ id: "x", status: "supported", evidence: ["Sources/Missing.swift"] }, /x: missing evidence Sources\/Missing\.swift/);
  reject({ id: "x", status: "maybe", evidence: ["Sources/Maps.swift"] }, /x: status must be one of supported, fallback, unsupported, no-op/);
  reject({ id: "x", status: "supported", evidence: [] }, /x: evidence is required/);
  reject({ id: "", status: "supported", evidence: ["Sources/Maps.swift"] }, /feature 0 has an invalid id/);
  const twice = { id: "x", status: "supported", evidence: ["Sources/Maps.swift"] };
  reject([twice, twice], /invalid or duplicate feature id: `x`/);
}));

const catalog = () => ({ sourceLanguage: "pt-BR", strings: { "Criar obra": {}, "%lld obras": {} } });

test("translations and plural forms are written and unknown keys are reported", () => {
  const strings = catalog();
  const unknown = applyTranslations(
    strings, "en", { "Criar obra": "Create work", Typo: "x" },
    { "%lld obras": { en: { one: "%lld work", other: "%lld works" } } },
  );
  assert.deepEqual(unknown, ["Typo"]);
  assert.equal(strings.strings["Criar obra"].localizations.en.stringUnit.value, "Create work");
  assert.equal(strings.strings["Criar obra"].localizations.en.stringUnit.state, "translated");
  assert.equal(strings.strings["%lld obras"].localizations.en.variations.plural.one.stringUnit.value, "%lld work");
  assert.equal(Object.hasOwn(strings.strings, "Typo"), false);
});

test("a plural key ignores a plain translation and existing localizations are kept", () => {
  const strings = catalog();
  applyTranslations(strings, "en", { "%lld obras": "ignored" }, { "%lld obras": { en: { other: "%lld works" } } });
  assert.equal(strings.strings["%lld obras"].localizations.en.stringUnit, undefined);
  const kept = { strings: { b: { localizations: { "pt-BR": { stringUnit: { value: "b" } } } }, 1: {} } };
  applyTranslations(kept, "en", { b: "B", 1: "one" }, {});
  assert.ok(kept.strings.b.localizations["pt-BR"]);
  assert.equal(kept.strings.b.localizations.en.stringUnit.value, "B");
});

test("apply-translations rewrites the catalog in Xcode's layout and reports unknown keys", () => withDirectory((directory) => {
  // "2" and "1" sort before "b" as JavaScript keys: the catalog order must survive.
  const path = join(directory, "Localizable.xcstrings");
  writeFileSync(path, '{\n  "sourceLanguage" : "pt-BR",\n  "strings" : {\n    "b" : {\n      "comment" : "é"\n    },\n    "2" : {},\n    "1" : {},\n    "empty" : {}\n  },\n  "version" : "1.0"\n}\n');
  put(directory, "t.json", JSON.stringify({ b: "B", 2: "two", 1: "one", "it's": "x", 'a"b': "y" }));
  put(directory, "p.json", JSON.stringify({ empty: { en: { one: "1 item", other: "%lld items" } } }));
  const result = spawnSync(TOOLS, ["apply-translations", path, "en", join(directory, "t.json"), join(directory, "p.json")], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `applied 5 translations and 1 plurals; keys not in the catalog: 2\n  unknown: "it's"\n  unknown: 'a"b'\n`);
  const unit = (value) => `{\n          "stringUnit": {\n            "state": "translated",\n            "value": "${value}"\n          }\n        }`;
  assert.equal(
    readFileSync(path, "utf8"),
    `{\n  "sourceLanguage": "pt-BR",\n  "strings": {\n    "b": {\n      "comment": "é",\n      "localizations": {\n        "en": ${unit("B")}\n      }\n    },\n`
      + `    "2": {\n      "localizations": {\n        "en": ${unit("two")}\n      }\n    },\n    "1": {\n      "localizations": {\n        "en": ${unit("one")}\n      }\n    },\n`
      + '    "empty": {\n      "localizations": {\n        "en": {\n          "variations": {\n            "plural": {\n              "one": {\n                "stringUnit": {\n                  "state": "translated",\n                  "value": "1 item"\n                }\n              },\n'
      + '              "other": {\n                "stringUnit": {\n                  "state": "translated",\n                  "value": "%lld items"\n                }\n              }\n            }\n          }\n        }\n      }\n    }\n  },\n  "version": "1.0"\n}\n',
  );
}));

test("the command line rejects unknown commands, missing files and a catalog without strings", () => withDirectory((directory) => {
  const run = (...args) => spawnSync(TOOLS, args, { encoding: "utf8" });
  assert.equal(run().status, 1);
  assert.equal(run("--help").status, 0);
  assert.match(run("feature-matrix", "-h").stdout, /^Usage: swiftuiweb-tools <command> \[options\]/);
  const unknown = run("nope");
  assert.equal(unknown.status, 1);
  assert.match(unknown.stderr, /^swiftuiweb-tools: unknown command `nope`/);
  assert.equal(run("apply-translations", "a", "b").status, 1);
  put(directory, "empty.json", "{}");
  put(directory, "array.json", "[]");
  const noStrings = run("apply-translations", join(directory, "empty.json"), "en", join(directory, "empty.json"));
  assert.match(noStrings.stderr, /the catalog has no `strings` object/);
  const notObject = run("apply-translations", join(directory, "empty.json"), "en", join(directory, "array.json"));
  assert.match(notObject.stderr, /array\.json: translations must be a JSON object/);
  assert.match(run("apply-translations", join(directory, "missing"), "en", join(directory, "empty.json")).stderr, /missing/);
}));
