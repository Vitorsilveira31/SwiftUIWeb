// Run: bun test ./Tools/test-embedded-capabilities.mjs
// Covers embedded-capabilities.mjs: the table shape, the lexical counts on a fixture tree (both regex families, with
// the Unicode word boundaries), and lenient UTF-8 decoding (invalid bytes are dropped rather than replaced).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { areaCounts, markdownTable } from "./embedded-capabilities.mjs";

const TOOLS = dirname(fileURLToPath(import.meta.url));
const ROOT = join(TOOLS, "..");

test("the markdown table has a header, a separator and one row per area", () => {
  const lines = markdownTable(ROOT);
  assert.equal(lines[0], "| Area | Embedded boundary hits | unavailable/unsupported hits |");
  assert.equal(lines[1], "|---|---:|---:|");
  assert.equal(lines.length, 2 + 17);
  for (const line of lines.slice(2)) assert.match(line, /^\| .+ \| \d+ \| \d+ \|$/);
});

test("the command prints the same table to stdout", () => {
  const result = spawnSync(process.execPath, [join(TOOLS, "embedded-capabilities.mjs")], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, markdownTable(ROOT).join("\n") + "\n");
});

test("counts use word boundaries and ignore case for unavailable, unsupported and no-op", () => {
  const root = mkdtempSync(join(tmpdir(), "swui-caps-"));
  try {
    mkdirSync(join(root, "Sources/A"), { recursive: true });
    writeFileSync(
      join(root, "Sources/A/File.swift"),
      [
        "#if !hasFeature(Embedded)",
        "#if hasFeature(Embedded)",
        "// UNAVAILABLE in standard Swift",
        "let x = unsupported + no-op",
        "let y = preunsupported and unsupportedX",
        "let z = nounavailable",
      ].join("\n"),
    );
    const counts = areaCounts(root, ["Sources/A/File.swift", "Sources/Missing.swift"]);
    assert.deepEqual(counts, { boundary: 2, bad: 3 });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("invalid UTF-8 bytes are dropped, so a word split by one still counts as the word", () => {
  const root = mkdtempSync(join(tmpdir(), "swui-caps-bytes-"));
  try {
    mkdirSync(join(root, "Tools"), { recursive: true });
    const file = join(root, "Tools/feature-loader.js");
    // "un" + invalid byte + "supported" decodes (with the byte dropped) to "unsupported"; a trailing truncated sequence is dropped.
    writeFileSync(file, Buffer.from([0x75, 0x6e, 0xff, 0x73, 0x75, 0x70, 0x70, 0x6f, 0x72, 0x74, 0x65, 0x64, 0x20, 0xc3]));
    assert.deepEqual(areaCounts(root, ["Tools/feature-loader.js"]), { boundary: 0, bad: 1 });
    // A valid multi-byte character is kept and does not split a word boundary.
    writeFileSync(file, Buffer.from("caf\u00e9 hasFeature(Embedded) \u00ff unsupported", "utf8"));
    assert.deepEqual(areaCounts(root, ["Tools/feature-loader.js"]), { boundary: 1, bad: 1 });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
