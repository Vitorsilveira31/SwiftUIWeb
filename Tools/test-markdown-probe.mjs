#!/usr/bin/env bun
// Regression test for the Embedded inline Markdown parser (`AttributedString(markdown:)`, Sources/SwiftUIWebFeatures/AttributedString.swift).
// The parser only exists on the Embedded/WASI profile, so no native test target reaches it: this builds Tools/markdown-probe for
// wasm-embedded and runs it under Node's WASI host. Two checks:
//   behavior  hand-written expectations for the link, emphasis and unmatched-bracket forms, plus invariants over a generated
//             corpus (the runs spell the characters, a link run implies a "](" in the input, nothing fails to parse);
//   bounds    inputs made of thousands of unmatched or nested brackets finish within a time budget (they took exponential time).
// Usage: bun Tools/test-markdown-probe.mjs
// SWIFTUIWEB_EMBEDDED_SDK names the Swift SDK (default swift-6.4.0-RELEASE_wasm-embedded). Without that SDK the test reports
// "skipped" and exits 0, so a host without the Embedded toolchain is told so rather than failing.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { WASI } from "node:wasi";

const ROOT = resolve(dirname(realpathSync(fileURLToPath(import.meta.url))), "..");
const PROBE = join(ROOT, "Tools", "markdown-probe");
const SDK = process.env.SWIFTUIWEB_EMBEDDED_SDK || "swift-6.4.0-RELEASE_wasm-embedded";
const SCRATCH = process.env.SWIFTUIWEB_MARKDOWN_PROBE_SCRATCH || join(ROOT, ".build", "markdown-probe");
const BOUND_MS = 3000;
const BOUND_N = 20000;

/** Runs the probe once in a fresh WASI instance and returns what it logged. */
async function runWasm(module, { mode, kind = 0, n = 0 }) {
  const wasi = new WASI({ version: "preview1", args: ["MarkdownProbe"], env: {}, preopens: {} });
  let memory = null;
  const chunks = [];
  const probe = {
    log_bytes: (pointer, count) => chunks.push(Buffer.from(memory.buffer, pointer, count).toString("utf8")),
    mode: () => (mode === "bench" ? 1 : 0),
    now_ms: () => performance.now(),
    bench_kind: () => kind,
    bench_n: () => n,
  };
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport, probe });
  memory = instance.exports.memory;
  wasi.start(instance);
  return chunks.join("");
}

// The probe escapes everything but printable ASCII (and the quote and backslash) as \uXXXXXXXX, so a quoted field has no inner quote.
const unescape = (quoted) => quoted.slice(1, -1).replace(/\\u([0-9a-f]{8})/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)));
const RUN_LINE = /^RUN ("[^"]*") link=(-|"[^"]*") strike=([sS]) underline=([uU]) font=(-?\d+)$/;

/** Per input: IN "<input>", CHARS "<text>" and one RUN line per run, or ERR. */
function parseCorpus(output) {
  const corpus = new Map();
  for (const block of output.split(/\n(?=IN ")/)) {
    const lines = block.trim().split("\n");
    const entry = { chars: "", runs: [], failed: lines.includes("ERR") };
    for (const line of lines.slice(1)) {
      if (line.startsWith("CHARS ")) entry.chars = unescape(line.slice(6));
      else if (line.startsWith("RUN ")) {
        const match = RUN_LINE.exec(line);
        assert.ok(match, `unreadable probe line: ${line}`);
        entry.runs.push({ text: unescape(match[1]), link: match[2] === "-" ? null : unescape(match[2]), strike: match[3] === "S", underline: match[4] === "U", font: Number(match[5]) });
      }
    }
    corpus.set(unescape(lines[0].slice(3)), entry);
  }
  return corpus;
}

// Font indexes follow the probe: 0 plain, 1 bold, 2 italic.
const run = (text, { link = null, strike = false, font = 0 } = {}) => ({ text, link, strike, underline: false, font });
const EXPECTED = [
  ["plain text", [run("plain text")]],
  ["*em* and **strong** and _u_ and __b__", [run("em", { font: 2 }), run(" and "), run("strong", { font: 1 }), run(" and "), run("u", { font: 2 }), run(" and "), run("b", { font: 1 })]],
  ["~~strike~~", [run("strike", { strike: true })]],
  ["[link](https://example.com)", [run("link", { link: "https://example.com" })]],
  ["[**bold link**](/x)", [run("bold link", { link: "/x", font: 1 })]],
  ["[nested [inner](/i) label](/outer)", [run("nested ", { link: "/outer" }), run("inner", { link: "/i" }), run(" label", { link: "/outer" })]],
  ["[a [b](c) d](e)", [run("a ", { link: "e" }), run("b", { link: "c" }), run(" d", { link: "e" })]],
  ["[a](b)c](d)", [run("a", { link: "b" }), run("c](d)")]],
  ["a [b c", [run("a [b c")]],
  ["[a](b", [run("[a](b")]],
  ["[a [b] c](d)", [run("[a [b] c](d)")]],
  ["the [ unmatched [ brackets ] (x)", [run("the [ unmatched [ brackets ] (x)")]],
  ["x [y [z] w", [run("x [y [z] w")]],
  ["[[[a]](b)]](c)", [run("[[[a]](b)]](c)")]],
];

// Inputs of the `bound` check; the kind numbers are the probe's. n x "[" · n x "[](" · n x "[" "a" n x "](x)" · n x "[" n x "](" · n x "[a]("
const BOUNDS = [[1, "[ x n"], [2, "[]( x n"], [4, "[ x n, a, ](x) x n"], [6, "[ x n, ]( x n"], [7, "[a]( x n"]];

function findWasm(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory() && !entry.isSymbolicLink()) {
      const found = findWasm(path);
      if (found) return found;
    } else if (entry.name === "MarkdownProbe.wasm" && path.toLowerCase().includes("release")) return path;
  }
  return null;
}

async function main() {
  const sdks = spawnSync("swift", ["sdk", "list"], { encoding: "utf8" });
  if (sdks.status !== 0 || !sdks.stdout.split("\n").map((line) => line.trim()).includes(SDK)) {
    console.log(`markdown probe: skipped (Swift SDK ${SDK} is not installed)`);
    return;
  }
  const build = spawnSync(
    "swift",
    ["build", "--package-path", PROBE, "--scratch-path", SCRATCH, "--swift-sdk", SDK, "-c", "release", "--product", "MarkdownProbe"],
    { encoding: "utf8", maxBuffer: 1 << 28 },
  );
  if (build.status !== 0) {
    process.stderr.write(`${build.stdout}\n${build.stderr}\n`);
    throw new Error("markdown probe: swift build failed");
  }
  const wasmPath = findWasm(SCRATCH);
  assert.ok(wasmPath && existsSync(wasmPath), "MarkdownProbe.wasm was not produced");

  const corpus = parseCorpus(await runWasm(await WebAssembly.compile(readFileSync(wasmPath)), { mode: "corpus" }));
  for (const [input, expected] of EXPECTED) {
    const got = corpus.get(input);
    assert.ok(got, `the corpus lacks ${JSON.stringify(input)}`);
    assert.deepEqual(got.runs, expected, `runs of ${JSON.stringify(input)}`);
  }
  console.log(`ok   behavior: ${EXPECTED.length} expected inputs`);
  for (const [input, got] of corpus) {
    assert.ok(!got.failed, `${JSON.stringify(input)} failed to parse`);
    assert.equal(got.runs.map((entry) => entry.text).join(""), got.chars, `the runs do not spell the characters of ${JSON.stringify(input)}`);
    if (got.runs.some((entry) => entry.link !== null)) assert.ok(input.includes("]("), `a link without "](" in ${JSON.stringify(input)}`);
  }
  console.log(`ok   invariants: ${corpus.size} inputs`);

  for (const [kind, label] of BOUNDS) {
    // Each bound runs in its own process: a parser that never finishes (or overflows) is killed after 30 s and fails the test.
    const child = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "--bench-child", wasmPath, String(kind), String(BOUND_N)], { encoding: "utf8", timeout: 30000 });
    assert.ok(child.status === 0 && !child.error, `${label}: did not finish normally (30 s limit; ${child.error?.code ?? child.signal ?? child.stderr.trim().split("\n")[0]})`);
    const elapsed = Number(/ms=(\d+)/.exec(child.stdout)?.[1]);
    assert.ok(Number.isFinite(elapsed) && elapsed < BOUND_MS, `${label}: took ${elapsed} ms (budget ${BOUND_MS}) - ${child.stdout.trim()}`);
    console.log(`ok   bound: ${label} (n = ${BOUND_N}) in ${elapsed} ms`);
  }
  console.log("markdown probe: ok");
}

const childAt = process.argv.indexOf("--bench-child");
if (childAt < 0) await main();
else {
  const [wasm, kind, n] = process.argv.slice(childAt + 1);
  process.stdout.write(await runWasm(await WebAssembly.compile(readFileSync(wasm)), { mode: "bench", kind: Number(kind), n: Number(n) }));
}
