#!/usr/bin/env bun
// Tests for Tools/dictionary-transport.mjs. Run: bun test ./Tools/test-dictionary-transport.mjs
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { describe, test } from "node:test";
import {
  acceptsDcb, availableDictionaryValue, dcbBody, dcbHeader, DCB_HEADER_LENGTH, differenceName, isDictionaryModule, isDifferenceName,
  parseAvailableDictionary, readDcbHeader, sha256Hex, useAsDictionary, VARY,
} from "./dictionary-transport.mjs";

const HASH = createHash("sha256").update("earlier module").digest("hex");

describe("dictionary-transport: which files take part", () => {
  test("the content-hashed modules do, under a directory or not", () => {
    for (const name of ["app.3f9a1c2e.wasm", "app-rest.0123abcd.wasm", "modules/app_2.3f9a1c2e.wasm", "/a/b/app.3f9a1c2e.wasm"]) assert.equal(isDictionaryModule(name), true, name);
  });

  test("anything else does not", () => {
    for (const name of [
      "app.wasm", "app.3f9a1c2E.wasm", "app.3f9a1c2.wasm", "app.3f9a1c2e0.wasm", "app.3f9a1c2e.wasm.br", "app.3f9a1c2e.js", ".3f9a1c2e.wasm",
      "x.app.3f9a1c2e.wasm", `app.3f9a1c2e.wasm.${HASH}.dcb`, "a b/app.3f9a1c2e.wasm", "a.b/app.3f9a1c2e.wasm", "../app.3f9a1c2e.wasm", "", undefined, null,
    ]) assert.equal(isDictionaryModule(name), false, String(name));
  });
});

describe("dictionary-transport: names", () => {
  test("a difference file is the module's name, the previous hash and .dcb", () => {
    assert.equal(differenceName("app.3f9a1c2e.wasm", HASH), `app.3f9a1c2e.wasm.${HASH}.dcb`);
    assert.equal(isDifferenceName(`app.3f9a1c2e.wasm.${HASH}.dcb`), true);
    assert.equal(isDifferenceName(`dir/app-rest.3f9a1c2e.wasm.${HASH}.dcb`), true);
    for (const name of ["app.3f9a1c2e.wasm", `app.wasm.${HASH}.dcb`, `app.3f9a1c2e.wasm.${HASH.slice(1)}.dcb`, `app.3f9a1c2e.wasm.${HASH.toUpperCase()}.dcb`, `app.3f9a1c2e.wasm.${HASH}.br`, undefined]) {
      assert.equal(isDifferenceName(name), false, String(name));
    }
  });

  test("refuses a name or a hash that is not what the contract says", () => {
    assert.throws(() => differenceName("app.wasm", HASH));
    assert.throws(() => differenceName("app.3f9a1c2e.wasm", HASH.toUpperCase()));
    assert.throws(() => differenceName("app.3f9a1c2e.wasm", "../../etc/passwd"));
  });
});

describe("dictionary-transport: Use-As-Dictionary", () => {
  test("the pattern is the path with the hash replaced by *", () => {
    assert.equal(useAsDictionary("/app.3f9a1c2e.wasm"), 'match="/app.*.wasm"');
    assert.equal(useAsDictionary("/app-rest.3f9a1c2e.wasm"), 'match="/app-rest.*.wasm"');
    assert.equal(useAsDictionary("/dir/sub/app.3f9a1c2e.wasm"), 'match="/dir/sub/app.*.wasm"');
  });

  test("the pattern of one module does not match another module's path", () => {
    const pattern = new RegExp(`^${useAsDictionary("/dir/app.3f9a1c2e.wasm").slice(7, -1).replace(/\./g, "\\.").replace("*", ".*")}$`);
    assert.equal(pattern.test("/dir/app.99999999.wasm"), true);
    assert.equal(pattern.test("/dir/app-rest.99999999.wasm"), false);
    assert.equal(pattern.test("/other/app.99999999.wasm"), false);
  });

  test("a path with a character that is special in a URL pattern gets no header", () => {
    for (const path of ["/a*/app.3f9a1c2e.wasm", "/a+/app.3f9a1c2e.wasm", "/a?/app.3f9a1c2e.wasm", "/a(b)/app.3f9a1c2e.wasm", "/a{b}/app.3f9a1c2e.wasm", "/a:b/app.3f9a1c2e.wasm",
      "/a\\b/app.3f9a1c2e.wasm", "/a%2Fb/app.3f9a1c2e.wasm", '/a"b/app.3f9a1c2e.wasm', "/a b/app.3f9a1c2e.wasm", "/a\nb/app.3f9a1c2e.wasm"]) {
      assert.equal(useAsDictionary(path), null, JSON.stringify(path));
    }
  });

  test("other files, relative paths and non-strings get none", () => {
    for (const path of ["/app.wasm", "/index.js", "app.3f9a1c2e.wasm", "", undefined, null, 5]) assert.equal(useAsDictionary(path), null, String(path));
  });
});

describe("dictionary-transport: Available-Dictionary", () => {
  test("a structured-field byte sequence of 32 bytes gives its 64 lowercase hex digits", () => {
    const value = `:${Buffer.from(HASH, "hex").toString("base64")}:`;
    assert.equal(parseAvailableDictionary(value), HASH);
    assert.equal(parseAvailableDictionary(`  ${value}  `), HASH);
    assert.equal(availableDictionaryValue(HASH), value);
  });

  test("anything else gives null, and nothing but 64 hex digits ever comes out", () => {
    const good = Buffer.from(HASH, "hex").toString("base64");
    const hostile = [
      undefined, null, "", ":", "::", `${good}`, `:${good}`, `${good}:`, `:${good}:, :${good}:`, `:${good}:;x=1`, `: ${good}:`, `:${good} :`,
      `:${Buffer.alloc(31).toString("base64")}:`, `:${Buffer.alloc(33).toString("base64")}:`, `:${Buffer.alloc(64).toString("base64")}:`,
      `:${good.slice(0, -1)}:`, `:${good}=:`, `:${good.replace("=", "")}:`, `:${good.slice(0, 10)}!${good.slice(11)}:`,
      `:${good.replaceAll("+", "-").replaceAll("/", "_")}x:`, ":../../../etc/passwd:", ":%2e%2e%2f:", ":a/b+c=:", `:${"A".repeat(10000)}:`, "\u0000", `:${good}:\n:${good}:`, 42, {},
    ];
    for (const value of hostile) assert.equal(parseAvailableDictionary(value), null, JSON.stringify(value));
    // A canonical encoding of every kind of byte stays inside [0-9a-f]{64}.
    for (let seed = 0; seed < 200; seed++) {
      const bytes = Buffer.from(createHash("sha256").update(String(seed)).digest());
      const hex = parseAvailableDictionary(`:${bytes.toString("base64")}:`);
      assert.match(hex, /^[0-9a-f]{64}$/);
      assert.equal(hex, bytes.toString("hex"));
    }
  });

  test("a non-canonical base64 (unused trailing bits set) is refused", () => {
    const good = Buffer.from(HASH, "hex").toString("base64");
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const last = good[good.length - 2];
    const other = alphabet[(alphabet.indexOf(last) + 1) % 64];
    const variant = `${good.slice(0, -2)}${other}=`;
    assert.notEqual(variant, good);
    assert.equal(parseAvailableDictionary(`:${variant}:`), null);
  });
});

describe("dictionary-transport: Accept-Encoding", () => {
  test("lists dcb as a token, case-insensitively, with or without a quality", () => {
    for (const value of ["dcb", "gzip, deflate, br, zstd, dcb, dcz", "br,dcb;q=0.5", "DCB", " dcb ; q=1", "dcb;q=0.001", "dcb;level=1"]) assert.equal(acceptsDcb(value), true, value);
  });

  test("does not list it when it is absent, refused with q=0, or only part of another token", () => {
    for (const value of ["", "gzip, br", "dcz", "dcb;q=0", "dcb;q=0.0", "dcb ; q=0.000", "xdcb", "dcbx", "*", "identity", "br;dcb", undefined, null]) assert.equal(acceptsDcb(value), false, String(value));
    assert.equal(acceptsDcb("dcb;q=0, dcb"), true);
  });
});

describe("dictionary-transport: the 36-byte header", () => {
  test("is ff 44 43 42 and the 32 bytes of the SHA-256", () => {
    const header = dcbHeader(HASH);
    assert.equal(header.length, DCB_HEADER_LENGTH);
    assert.equal(DCB_HEADER_LENGTH, 36);
    assert.deepEqual([...header.subarray(0, 4)], [0xff, 0x44, 0x43, 0x42]);
    assert.equal(Buffer.from(header.subarray(4)).toString("hex"), HASH);
    assert.equal(readDcbHeader(header), HASH);
  });

  test("a body is the header followed by the stream; a short or wrong header reads as null", () => {
    const body = dcbBody(HASH, new Uint8Array([1, 2, 3]));
    assert.equal(body.length, 39);
    assert.deepEqual([...body.subarray(36)], [1, 2, 3]);
    assert.equal(readDcbHeader(body), HASH);
    assert.equal(readDcbHeader(body.subarray(0, 35)), null);
    const wrong = body.slice();
    wrong[1] = 0;
    assert.equal(readDcbHeader(wrong), null);
    assert.throws(() => dcbHeader("abc"));
  });

  test("the SHA-256 is the one a browser reports", async () => {
    assert.equal(await sha256Hex(new TextEncoder().encode("earlier module")), HASH);
  });
});

test("Vary names both request headers", () => {
  assert.equal(VARY, "Accept-Encoding, Available-Dictionary");
});
