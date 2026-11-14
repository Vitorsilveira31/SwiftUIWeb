#!/usr/bin/env bun
// Audit the Embedded Codable lowering and its runtime support types.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(realpathSync(fileURLToPath(import.meta.url))), "..");
const LOWERER = join(ROOT, "Tools", "swiftuiweb-lowering.sh");

function lower(source) {
  const folder = mkdtempSync(join(tmpdir(), "embedded-codable-"));
  try {
    const temp = folder;
    const sourceRoot = join(temp, "source");
    const workspace = join(temp, "workspace");
    mkdirSync(join(sourceRoot, "Sources"), { recursive: true });
    writeFileSync(join(sourceRoot, "Sources/Fixture.swift"), source);
    const args = [
      "--apply",
      "--root",
      sourceRoot,
      "--product",
      "Fixture",
      "--lower-codable",
      "--workspace",
      workspace,
    ];
    const result = spawnSync(LOWERER, args, { encoding: "utf8" });
    if (result.error) throw result.error;
    if (result.status !== 0) {
      throw new Error(
        `Command '${[LOWERER, ...args].join(" ")}' returned non-zero exit status ${result.status}.\n${result.stderr}`,
      );
    }
    const report = JSON.parse(result.stdout);
    return [readFileSync(join(workspace, "Sources/Fixture.swift"), "utf8"), report.rules];
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
}

const source = `import SwiftUIWeb
struct User: Codable, Sendable {
 let id: Int
 let name: String
 let tags: [String]
 let nickname: String?
}
enum Role: String, Codable { case admin, user }
`;
const [out, counts] = lower(source);
assert.ok(!out.replaceAll("EmbeddedCodable", "").includes("Codable"));
assert.ok(out.includes("struct User: EmbeddedCodable"));
assert.ok(out.includes("enum Role: String, EmbeddedCodable"));
assert.ok(out.includes("Self(id:"));
// Fields decode through _embeddedField, which reads a missing key as null so an
// optional member decodes to nil.
assert.ok(out.includes('_embeddedField(Optional<String>.self, object, "nickname")'));
assert.equal(counts["codable-to-embedded"], 2);
const transfer = readFileSync(join(ROOT, "Sources/SwiftUIWebTransferable/Transferable.swift"), "utf8");
assert.ok(transfer.includes("Transferable & EmbeddedCodable"));
assert.ok(
  !transfer
    .split("#else\npublic struct CodableRepresentation")[0]
    .includes("Codable JSON encoding is unavailable on this target"),
);
const storage = readFileSync(join(ROOT, "Sources/SwiftUIWebBrowser/WebStorage.swift"), "utf8");
assert.ok(storage.includes("WebIndexedDBStore<Value: EmbeddedCodable>"));
assert.ok(storage.includes("_EmbeddedIndexedEnvelope"));
console.log("embedded Codable + Transferable audit: PASS");

const advanced = `
struct Renamed: Codable { let userID: Int; let name: String
 enum CodingKeys: String, CodingKey { case userID = "user_id"; case name }
}
final class Box: Codable { let value: String
 init(value: String) { self.value = value }
}
enum Event: Codable {
 case ping
 case message(String)
 case progress(value: Int, total: Int)
}
`;
const [aout, acounts] = lower(advanced);
assert.ok(aout.includes('"user_id": try self.userID._embeddedJSONValue()'));
assert.ok(aout.includes("final class Box: EmbeddedCodable"));
assert.ok(aout.includes("case .message(let v0)") && aout.includes('"_0"'));
assert.ok(aout.includes("case .progress(let v0, let v1)"));
assert.equal(acounts["codable-to-embedded"], 3);
const codec = readFileSync(join(ROOT, "Sources/SwiftUIWebTransferable/EmbeddedCodable.swift"), "utf8");
assert.ok(codec.includes("T._embeddedDecodeJSONValue(object[key] ?? .null)"));
assert.ok(codec.includes("_embeddedBase64Encode") && codec.includes("extension Data: EmbeddedCodable"));
const date = readFileSync(join(ROOT, "Sources/SwiftUIWebTransferable/Date.swift"), "utf8");
assert.ok(date.includes("extension Date: EmbeddedCodable"));
console.log("advanced Embedded Codable parity audit: PASS");
