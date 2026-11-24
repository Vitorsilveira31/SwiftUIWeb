#!/usr/bin/env bun
// Writes the difference files that let a host update a visitor's cached wasm module by sending only what changed
// (HTTP Compression Dictionary Transport; Tools/dictionary-transport.mjs holds the contract and Documentation/DEPLOYMENT.md
// the host side).
//
// For each content-hashed module of the bundle (`app.3f9a1c2e.wasm`) and each module with the same stem and other bytes in a
// `--previous` directory (an earlier bundle, or a folder with just its `.wasm` files), it writes
// `<module>.<SHA-256 of the previous module>.dcb` beside the module: 36 header bytes and the module compressed with Brotli
// (quality 11, 16 MB window) using the previous module as the dictionary. A file is kept only when it is at least 10 % smaller
// than what a visitor without the earlier module downloads, the module's `.br` copy (Brotli quality 11 of the module when
// there is none); otherwise it is deleted and the decision is printed. Every file kept is decoded again and compared with
// the module before the step reports it.
//
// Run it last, after Tools/precompress-bundle.mjs. Difference files an earlier run left in the bundle are removed first.
// Brotli with a dictionary is Bun's own `node:zlib`; no `brotli` program is needed.
//
// usage: delta-compress-bundle.mjs --bundle <bundle-directory> --previous <directory> [--previous <directory> ...]
// Run the tests with: bun test ./Tools/test-delta-compress-bundle.mjs
import { existsSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { brotliCompressSync, brotliDecompressSync, constants } from "node:zlib";
import { brotli } from "./precompress-bundle.mjs";
import { dcbBody, differenceName, isDictionaryModule, isDifferenceName, moduleParts, readDcbHeader, sha256Hex, DCB_HEADER_LENGTH } from "./dictionary-transport.mjs";

/** A difference file is kept when it is at most this share of the module's Brotli copy: at least 10 % smaller. */
export const KEEP_AT_MOST = 0.9;

function listFiles(root) {
  const files = [];
  const walk = (directory, prefix) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) walk(join(directory, entry.name), relativePath);
      else if (entry.isFile()) files.push(relativePath);
    }
  };
  if (existsSync(root) && statSync(root).isDirectory()) walk(root, "");
  return files.sort();
}

/** The participating modules below `directory`, as paths relative to it. */
export function listModules(directory) {
  return listFiles(resolve(directory)).filter(isDictionaryModule);
}

/** Brotli of `bytes` with `dictionary` as the shared dictionary: quality 11, a 16 MB window. */
export function compressWithDictionary(bytes, dictionary) {
  return brotliCompressSync(bytes, {
    dictionary,
    params: {
      [constants.BROTLI_PARAM_QUALITY]: 11,
      [constants.BROTLI_PARAM_LGWIN]: 24,
      [constants.BROTLI_PARAM_SIZE_HINT]: bytes.length,
      [constants.BROTLI_PARAM_MODE]: constants.BROTLI_MODE_GENERIC,
    },
  });
}

/** Throws when this runtime's `node:zlib` ignores the dictionary, which would write files no browser can decode. */
export function assertDictionarySupport() {
  const sample = new Uint8Array(4096).map((_, index) => (index * 2654435761 >>> 24) & 0xff);
  const compressed = brotliCompressSync(sample, { dictionary: sample, params: { [constants.BROTLI_PARAM_QUALITY]: 5 } });
  if (compressed.length > 256) {
    throw new Error("this runtime's node:zlib ignores the Brotli dictionary option; run the step with Bun 1.4 or later (`bun Tools/delta-compress-bundle.mjs`)");
  }
}

/** The bytes a difference file holds for `moduleBytes` against `previousBytes`: header and Brotli stream. */
export async function differenceFor(moduleBytes, previousBytes) {
  const hash = await sha256Hex(previousBytes);
  return { hash, body: dcbBody(hash, compressWithDictionary(moduleBytes, previousBytes)) };
}

/** Decodes a difference file with the previous module and returns the module's bytes; throws when the header or the stream is wrong. */
export function decodeDifference(body, previousBytes, expectedHash) {
  if (readDcbHeader(body) !== expectedHash) throw new Error("the difference file's header does not name the previous module");
  return brotliDecompressSync(body.subarray(DCB_HEADER_LENGTH), { dictionary: previousBytes });
}

function removeStale(root) {
  const removed = [];
  for (const path of listFiles(root)) {
    if (!isDifferenceName(path.slice(path.lastIndexOf("/") + 1))) continue;
    rmSync(join(root, path));
    removed.push(path);
  }
  return removed;
}

/**
 * Writes the difference files of `bundle` against the modules in `previousDirectories`. Returns
 * `{ removed, previous, decisions }`: the stale files removed, how many previous modules were found, and one decision per
 * pair `{ module, from, hash, bytes, reference, kept, reason }`.
 */
export async function deltaCompressBundle(bundle, previousDirectories) {
  assertDictionarySupport();
  const root = resolve(bundle);
  if (!existsSync(root) || !statSync(root).isDirectory()) throw new Error(`${bundle} is not a directory`);
  const removed = removeStale(root);
  const modules = listModules(root);
  const decisions = [];
  let previous = 0;
  const seen = new Set();
  for (const directory of previousDirectories) {
    for (const path of listModules(directory)) {
      const parts = moduleParts(path);
      const bytes = readFileSync(join(resolve(directory), path));
      const hash = await sha256Hex(bytes);
      const key = `${parts.directory}${parts.stem} ${hash}`;
      if (seen.has(key)) continue;
      seen.add(key);
      previous += 1;
      for (const module of modules) {
        const current = moduleParts(module);
        if (current.directory !== parts.directory || current.stem !== parts.stem) continue;
        const moduleBytes = readFileSync(join(root, module));
        if (Buffer.compare(moduleBytes, bytes) === 0) continue;
        decisions.push(await decide(root, module, moduleBytes, path, bytes, hash));
      }
    }
  }
  return { removed, previous, decisions };
}

async function decide(root, module, moduleBytes, from, previousBytes, hash) {
  const sibling = join(root, `${module}.br`);
  const reference = existsSync(sibling) ? statSync(sibling).size : brotli(moduleBytes, ".wasm").length;
  const { body } = await differenceFor(moduleBytes, previousBytes);
  const decision = { module, from, hash, bytes: body.length, reference, kept: false, reason: "" };
  if (body.length > reference * KEEP_AT_MOST) {
    decision.reason = `less than 10 % smaller than the ${existsSync(sibling) ? ".br copy" : "Brotli copy"}`;
    return decision;
  }
  const decoded = decodeDifference(body, previousBytes, hash);
  if (Buffer.compare(decoded, moduleBytes) !== 0) throw new Error(`${module}: decoding the difference file against ${from} does not give the module back`);
  writeFileSync(join(root, differenceName(module, hash)), body);
  decision.kept = true;
  return decision;
}

export function describe(decision) {
  const share = Math.round((decision.bytes / decision.reference) * 100);
  const detail = `${decision.bytes} bytes against ${decision.reference} (${share} %)`;
  const origin = `from ${decision.from} (${decision.hash.slice(0, 12)})`;
  return decision.kept
    ? `${decision.module}: difference ${origin}: ${detail}, kept`
    : `${decision.module}: difference ${origin}: ${detail}, dropped: ${decision.reason}`;
}

export function parseArguments(argv) {
  const options = { bundle: null, previous: [] };
  for (let index = 0; index < argv.length; index++) {
    const flag = argv[index];
    const value = argv[index + 1];
    if ((flag !== "--bundle" && flag !== "--previous") || value === undefined || value.startsWith("--")) return null;
    if (flag === "--bundle") options.bundle = value;
    else options.previous.push(value);
    index += 1;
  }
  return options.bundle === null || options.previous.length === 0 ? null : options;
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseArguments(argv);
  if (options === null) {
    console.error("usage: delta-compress-bundle.mjs --bundle <bundle-directory> --previous <directory> [--previous <directory> ...]");
    return 2;
  }
  try {
    for (const directory of options.previous) {
      if (!existsSync(directory)) console.log(`difference: ${directory} does not exist, skipped`);
    }
    const { removed, previous, decisions } = await deltaCompressBundle(options.bundle, options.previous);
    for (const path of removed) console.log(`difference: removed ${path} from an earlier run`);
    if (previous === 0) {
      console.log("difference: no earlier module found in the --previous directories; no difference file written");
      return 0;
    }
    if (decisions.length === 0) console.log("difference: every earlier module is identical to the bundle's, or has no module of its name here; no difference file written");
    for (const decision of decisions) console.log(describe(decision));
    return 0;
  } catch (error) {
    console.error(`difference: ${error instanceof Error ? error.message : error}`);
    return 1;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main();
}
