#!/usr/bin/env bun
// Tests for Tools/precompress-bundle.mjs. Run: bun test ./Tools/test-precompress-bundle.mjs
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { brotliDecompressSync, gunzipSync } from "node:zlib";
import { MIN_BYTES, precompressBundle } from "./precompress-bundle.mjs";

describe("precompress-bundle", () => {
  test("writes brotli and gzip copies that decode to the original, for text and wasm of at least 1 KB", () => {
    const root = mkdtempSync(join(tmpdir(), "precompress-"));
    try {
      const text = Buffer.from("export const value = 1;\n".repeat(400));
      const wasm = Buffer.alloc(8192, 7);
      writeFileSync(join(root, "index.js"), text);
      writeFileSync(join(root, "app.wasm"), wasm);
      mkdirSync(join(root, "catalog-assets"));
      writeFileSync(join(root, "catalog-assets", "A.svg"), Buffer.from(`<svg>${"<rect/>".repeat(300)}</svg>`));

      const report = precompressBundle(root);
      assert.deepEqual(report.map(([file]) => file).sort(), ["app.wasm", "catalog-assets/A.svg", "index.js"]);
      for (const file of ["index.js", "app.wasm"]) {
        const original = readFileSync(join(root, file));
        assert.deepEqual(brotliDecompressSync(readFileSync(join(root, `${file}.br`))), original);
        assert.deepEqual(gunzipSync(readFileSync(join(root, `${file}.gz`))), original);
      }
      assert.ok(existsSync(join(root, "catalog-assets", "A.svg.br")));
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("skips small files, already compressed formats, files that do not shrink and the copies themselves", () => {
    const root = mkdtempSync(join(tmpdir(), "precompress-"));
    try {
      writeFileSync(join(root, "small.js"), "x".repeat(MIN_BYTES - 1));
      writeFileSync(join(root, "font.woff2"), Buffer.alloc(4096, 1));
      writeFileSync(join(root, "random.js"), randomBytes(4096));
      writeFileSync(join(root, "app.wasm.br"), Buffer.alloc(4096, 2));
      const report = precompressBundle(root);
      assert.deepEqual(report, []);
      assert.deepEqual(
        ["font.woff2.br", "small.js.br", "random.js.br", "app.wasm.br.br"].filter((file) => existsSync(join(root, file))),
        [],
      );
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
