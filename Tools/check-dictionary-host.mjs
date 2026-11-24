#!/usr/bin/env bun
// Checks on a live host that update by difference works (Documentation/DEPLOYMENT.md, "Update by difference"): that the host
// passes `Available-Dictionary` to whatever chooses the answer and delivers a `Content-Encoding: dcb` body byte for byte.
//
// The modules of the site are found the way Tools/fetch-live-modules.mjs finds them. The directory holds earlier modules, what
// that tool downloaded before the last deploy. For every live module that has an earlier module of the same stem (and other
// bytes) the check asks for the live module with `Available-Dictionary` naming the earlier one and `Accept-Encoding: br, dcb`,
// and keeps the body as it arrives (a client would decode `dcb`; this one must not). Each such request ends in one of:
//
//   difference served and correct   `Content-Encoding: dcb`, the 36-byte header names the earlier module, `Vary` lists
//                                   `Available-Dictionary`, `Use-As-Dictionary` is there, and the body decoded with the earlier
//                                   module gives bytes whose SHA-256 starts with the 8 hex digits of the module's name
//   no difference served            not `dcb`, and the body, decoded by its own coding (`br`, `gzip` or none), hashes to the
//                                   module's name: the response's `Content-Encoding`, `Vary` and `Use-As-Dictionary` are printed
//                                   (the host may simply not answer by difference, which works and downloads more)
//   WRONG                           it says `dcb` but the body does not decode to the module, or a header is missing; or it
//                                   says another coding (named), or its bytes are not the module
//
// Each live module is also requested the ordinary way (`Accept-Encoding: br`), and the bytes the client decodes must match
// the hash in the name, so a host that breaks the plain path is caught too. A module with no earlier counterpart is reported
// and skipped. The exit code is 0 when nothing is WRONG, and 1 otherwise (also when the site cannot be read or names no module,
// since nothing was checked). Exit 2: wrong arguments.
//
// `--header "Name: value"` adds a header to the difference requests (not to the ordinary ones). The project site's Worker answers
// by difference whatever its switch says when the request carries `SwiftUIWeb-Dictionary-Check: 1`.
//
// usage: check-dictionary-host.mjs <site URL> <directory of earlier modules> [--header "Name: value"]...
// Run the tests with: bun test ./Tools/test-check-dictionary-host.mjs
import { join, resolve } from "node:path";
import { readFileSync } from "node:fs";
import { brotliDecompressSync, gunzipSync } from "node:zlib";
import { decodeDifference, listModules } from "./delta-compress-bundle.mjs";
import { availableDictionaryValue, moduleParts, sha256Hex } from "./dictionary-transport.mjs";
import { discoverModules, isWebURL, MAX_MODULE_BYTES, readLimited } from "./fetch-live-modules.mjs";

/** Parses `Name: value` into `[name, value]`, or null when it is not a header line. */
export function parseHeaderLine(line) {
  const index = line.indexOf(":");
  const name = line.slice(0, index).trim();
  const value = line.slice(index + 1).trim();
  return index > 0 && /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(name) && !/[\r\n]/.test(value) ? [name, value] : null;
}

export function parseArguments(argv) {
  const options = { site: null, directory: null, headers: [] };
  const positional = [];
  for (let index = 0; index < argv.length; index++) {
    if (argv[index] === "--header") {
      const header = index + 1 < argv.length ? parseHeaderLine(argv[index + 1]) : null;
      if (!header) return null;
      options.headers.push(header);
      index += 1;
    } else if (argv[index].startsWith("--")) return null;
    else positional.push(argv[index]);
  }
  if (positional.length !== 2 || !isWebURL(positional[0])) return null;
  [options.site, options.directory] = positional;
  return options;
}

const varyNames = (value) => (value ?? "").split(",").map((name) => name.trim().toLowerCase());
const shown = (headers, name) => `${name}: ${headers.get(name) ?? "(none)"}`;

/** The bytes a client reads from `body` under the lowercase `coding`. Throws for a coding this check does not decode. */
export function decodeBody(body, coding) {
  if (coding === "" || coding === "identity") return body;
  if (coding === "br") return brotliDecompressSync(body);
  if (coding === "gzip") return gunzipSync(body);
  throw new Error(`the coding ${coding} is not one this check decodes`);
}

/** The ordinary request for a module: what the client decodes must hash to the name. Returns `{ ok, detail }`. */
export async function checkPlain(get, url, parts) {
  try {
    const response = await get(url, { headers: { "Accept-Encoding": "br" } });
    if (response.status !== 200) {
      await response.body?.cancel();
      return { ok: false, detail: `answered ${response.status}` };
    }
    const bytes = await readLimited(response, MAX_MODULE_BYTES);
    const hash = await sha256Hex(bytes);
    return hash.startsWith(parts.hash)
      ? { ok: true, detail: `${bytes.length} bytes, ${shown(response.headers, "Content-Encoding")}` }
      : { ok: false, detail: `the bytes decoded from ${shown(response.headers, "Content-Encoding")} hash to ${hash.slice(0, 8)}, not ${parts.hash}` };
  } catch (error) {
    return { ok: false, detail: error.message };
  }
}

/** The difference request for `url` against the earlier module `previousBytes`. Returns `{ status, detail }`. */
export async function checkDifference(get, url, parts, previousBytes, extraHeaders = []) {
  const previousHash = await sha256Hex(previousBytes);
  const headers = { "Accept-Encoding": "br, dcb", "Available-Dictionary": availableDictionaryValue(previousHash) };
  for (const [name, value] of extraHeaders) headers[name] = value;
  let response;
  let body;
  try {
    // decompress: false keeps the body as sent, whatever its coding (an unknown coding such as dcb is never decoded).
    response = await get(url, { headers, decompress: false });
    if (response.status !== 200) {
      await response.body?.cancel();
      return { status: "wrong", detail: `answered ${response.status}` };
    }
    body = await readLimited(response, MAX_MODULE_BYTES);
  } catch (error) {
    return { status: "wrong", detail: error.message };
  }
  const coding = (response.headers.get("Content-Encoding") ?? "").trim().toLowerCase();
  const summary = [shown(response.headers, "Content-Encoding"), shown(response.headers, "Vary"), shown(response.headers, "Use-As-Dictionary")].join("; ");
  if (coding !== "dcb") {
    // Not a difference: the module must come through the answer's own coding, or the host has not answered by difference.
    let decoded;
    try {
      decoded = decodeBody(body, coding);
    } catch (error) {
      return { status: "wrong", detail: `${summary}; ${error.message}` };
    }
    const hash = await sha256Hex(decoded);
    return hash.startsWith(parts.hash)
      ? { status: "none", detail: summary }
      : { status: "wrong", detail: `${summary}; the decoded bytes hash to ${hash.slice(0, 8)}, not ${parts.hash}` };
  }

  const problems = [];
  const vary = varyNames(response.headers.get("Vary"));
  for (const name of ["Accept-Encoding", "Available-Dictionary"]) {
    if (!vary.includes(name.toLowerCase())) problems.push(`Vary does not list ${name} (${shown(response.headers, "Vary")})`);
  }
  if (!response.headers.get("Use-As-Dictionary")) problems.push("Use-As-Dictionary is missing");
  const length = response.headers.get("Content-Length");
  if (length !== null && Number(length) !== body.length) problems.push(`Content-Length says ${length}, the body has ${body.length} bytes`);
  try {
    const decoded = decodeDifference(body, previousBytes, previousHash);
    const hash = await sha256Hex(decoded);
    if (!hash.startsWith(parts.hash)) problems.push(`the decoded bytes hash to ${hash.slice(0, 8)}, not ${parts.hash}`);
  } catch (error) {
    problems.push(`the body does not decode with the earlier module: ${error.message}`);
  }
  return problems.length > 0
    ? { status: "wrong", detail: problems.join("; ") }
    : { status: "correct", detail: `${body.length} bytes` };
}

/**
 * Runs the whole check. Returns `{ results, exitCode }`; each result is `{ module, from, status, detail }` with `status` one of
 * "correct", "none", "wrong", "skipped" (the difference requests) or "plain-ok" and "plain-wrong" (the ordinary request).
 */
export async function checkHost(siteURL, directory, { headers = [], ...options } = {}) {
  const results = [];
  const site = await discoverModules(siteURL, options);
  if (site.message) return { results, message: `${site.message}: nothing checked`, exitCode: 1 };
  const { references, get } = site;
  if (references.size === 0) return { results, message: `${siteURL} names no content-hashed module: nothing checked`, exitCode: 1 };

  const root = resolve(directory);
  const earlier = listModules(root).map((path) => ({ path, parts: moduleParts(path) }));
  for (const [path, href] of references) {
    const parts = moduleParts(path);
    const url = new URL(href);
    const plain = await checkPlain(get, url, parts);
    results.push({ module: path, from: null, status: plain.ok ? "plain-ok" : "plain-wrong", detail: plain.detail });

    const counterparts = earlier.filter((item) => item.parts.directory === parts.directory && item.parts.stem === parts.stem && item.path !== path);
    if (counterparts.length === 0) {
      results.push({ module: path, from: null, status: "skipped", detail: `no earlier module of the same stem in ${directory}` });
      continue;
    }
    for (const item of counterparts) {
      const previousBytes = new Uint8Array(readFileSync(join(root, item.path)));
      const outcome = await checkDifference(get, url, parts, previousBytes, headers);
      results.push({ module: path, from: item.path, ...outcome });
    }
  }
  const wrong = results.some((result) => result.status === "wrong" || result.status === "plain-wrong");
  return { results, message: "", exitCode: wrong ? 1 : 0 };
}

const LABEL = {
  correct: "difference served and correct",
  none: "no difference served",
  wrong: "WRONG",
  skipped: "skipped",
  "plain-ok": "ordinary request correct",
  "plain-wrong": "WRONG (ordinary request)",
};

export const describeResult = (result) => `${result.module}${result.from ? ` from ${result.from}` : ""}: ${LABEL[result.status]}: ${result.detail}`;

export async function main(argv = process.argv.slice(2), options = {}) {
  const parsed = parseArguments(argv);
  if (parsed === null) {
    console.error('usage: check-dictionary-host.mjs <site URL: http or https> <directory of earlier modules> [--header "Name: value"]...');
    return 2;
  }
  const { results, message, exitCode } = await checkHost(parsed.site, parsed.directory, { ...options, headers: parsed.headers });
  for (const result of results) console.log(describeResult(result));
  if (message) console.log(`check-dictionary-host: ${message}`);
  else if (!results.some((result) => ["correct", "none", "wrong"].includes(result.status))) console.log("check-dictionary-host: no module had an earlier counterpart, so no difference was requested");
  return exitCode;
}

if (import.meta.main) process.exit(await main());
