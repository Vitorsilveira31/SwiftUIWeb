// The contract of updates by difference (HTTP Compression Dictionary Transport, RFC 9842), in one place: which files take
// part, how a difference file is named, and how a server reads the request headers. Tools/delta-compress-bundle.mjs
// writes the files and Tools/bun-server.ts serves them; a Worker or another host imports this file to do the same.
//
// The functions are pure: strings and typed arrays only, no file system and no Node or Bun API (the SHA-256 is Web Crypto),
// so the same file runs in a browser, a Worker, Bun and Node.
//
// How it works: a response for a module carries `Use-As-Dictionary`, and the browser keeps the module's bytes. A later request
// for a module whose URL matches carries `Available-Dictionary: :<base64 SHA-256 of those bytes>:` and `dcb` in
// `Accept-Encoding`. The server may then answer with the difference file named after that hash: `Content-Encoding: dcb`, 36
// header bytes (`ff 44 43 42` and the 32 bytes of the SHA-256) and a Brotli stream compressed with the earlier module as
// its dictionary. The browser decodes it, and `fetch`, `XMLHttpRequest` and `WebAssembly.compileStreaming` see the new
// module's own bytes.
// Run the tests with: bun test ./Tools/test-dictionary-transport.mjs

/** The four bytes a `dcb` body starts with, then the 32 bytes of the dictionary's SHA-256. */
export const DCB_MAGIC = Object.freeze([0xff, 0x44, 0x43, 0x42]);
export const DCB_HEADER_LENGTH = 36;
export const HASH_HEX_LENGTH = 64;
/** The response headers every response for a participating module carries, whole or difference. */
export const VARY = "Accept-Encoding, Available-Dictionary";

// A module is `<stem>.<8 lowercase hex digits>.wasm` (Tools/hash-release-bundle.mjs), under a directory or not. The stem
// has no dot, so `app.*.wasm` cannot match another module's name; every character is one a URL pattern takes literally.
const MODULE = /^((?:[A-Za-z0-9_~-]+\/)*)([A-Za-z0-9_-]+)\.([0-9a-f]{8})\.wasm$/;
const HEX_64 = /^[0-9a-f]{64}$/;
const DIFFERENCE = /^(.+\.wasm)\.[0-9a-f]{64}\.dcb$/;
const BYTE_SEQUENCE = /^:([A-Za-z0-9+/]{43}=):$/;

/** The parts of a participating module's path (relative or absolute), or null when the file does not take part. */
export function moduleParts(path) {
  if (typeof path !== "string") return null;
  const absolute = path.startsWith("/");
  const match = MODULE.exec(absolute ? path.slice(1) : path);
  if (!match) return null;
  return { directory: (absolute ? "/" : "") + match[1], stem: match[2], hash: match[3] };
}

/** Whether the file takes part in updates by difference: the content-hashed modules `<stem>.<8 hex>.wasm`. */
export function isDictionaryModule(path) {
  return moduleParts(path) !== null;
}

/** Whether `value` is a SHA-256 as 64 lowercase hex digits. */
export function isHashHex(value) {
  return typeof value === "string" && HEX_64.test(value);
}

/** The name of the file that updates `moduleFile` from the module whose SHA-256 is `previousHashHex`: `<module>.<hex>.dcb`. */
export function differenceName(moduleFile, previousHashHex) {
  if (!isDictionaryModule(moduleFile)) throw new Error(`${moduleFile} is not a content-hashed module`);
  if (!isHashHex(previousHashHex)) throw new Error("the previous module's hash must be 64 lowercase hex digits");
  return `${moduleFile}.${previousHashHex}.dcb`;
}

/** Whether `name` is the name of a difference file (any module, any previous hash). */
export function isDifferenceName(name) {
  const match = typeof name === "string" ? DIFFERENCE.exec(name) : null;
  return match !== null && isDictionaryModule(match[1]);
}

/**
 * The `Use-As-Dictionary` value for a response to `requestPath` (a URL path), or null when it should carry none: the file does
 * not take part, or a directory of the path has a character outside `[A-Za-z0-9_~-]` (a dot, `%` and `*` included), which
 * keeps the pattern to what a URL pattern reads literally. The pattern is the
 * path with the hash replaced by `*`: `/dir/app.3f9a1c2e.wasm` gives `match="/dir/app.*.wasm"`, which does not match
 * `/dir/app-rest.<hash>.wasm`.
 */
export function useAsDictionary(requestPath) {
  if (typeof requestPath !== "string" || !requestPath.startsWith("/")) return null;
  const parts = moduleParts(requestPath);
  return parts === null ? null : `match="${parts.directory}${parts.stem}.*.wasm"`;
}

/**
 * The SHA-256 an `Available-Dictionary` header names, as 64 lowercase hex digits; null for anything else (a missing header,
 * wrong length, characters outside base64, no colons, a non-canonical encoding, more than one item). Only `[0-9a-f]{64}` comes out,
 * so the result can go into a file name.
 */
export function parseAvailableDictionary(value) {
  if (typeof value !== "string") return null;
  const match = BYTE_SEQUENCE.exec(value.trim());
  if (!match) return null;
  let binary;
  try {
    binary = atob(match[1]);
  } catch {
    return null;
  }
  if (binary.length !== 32 || btoa(binary) !== match[1]) return null;
  let hex = "";
  for (let index = 0; index < 32; index++) hex += binary.charCodeAt(index).toString(16).padStart(2, "0");
  return hex;
}

/** The `Available-Dictionary` value for a SHA-256 given as 64 hex digits (what a browser sends). */
export function availableDictionaryValue(hashHex) {
  if (!isHashHex(hashHex)) throw new Error("the hash must be 64 lowercase hex digits");
  let binary = "";
  for (let index = 0; index < 32; index++) binary += String.fromCharCode(parseInt(hashHex.slice(index * 2, index * 2 + 2), 16));
  return `:${btoa(binary)}:`;
}

/** Whether an `Accept-Encoding` value lists `dcb`: a token match, and not refused with `q=0`. */
export function acceptsDcb(value) {
  if (typeof value !== "string") return false;
  for (const item of value.split(",")) {
    const [coding, ...parameters] = item.trim().toLowerCase().split(";");
    if (coding.trim() !== "dcb") continue;
    const quality = parameters.map((parameter) => parameter.trim()).find((parameter) => parameter.startsWith("q="));
    if (quality === undefined || Number(quality.slice(2)) > 0) return true;
  }
  return false;
}

/** The 36 bytes a `dcb` body starts with for the dictionary whose SHA-256 is `hashHex`. */
export function dcbHeader(hashHex) {
  if (!isHashHex(hashHex)) throw new Error("the hash must be 64 lowercase hex digits");
  const header = new Uint8Array(DCB_HEADER_LENGTH);
  header.set(DCB_MAGIC, 0);
  for (let index = 0; index < 32; index++) header[4 + index] = parseInt(hashHex.slice(index * 2, index * 2 + 2), 16);
  return header;
}

/** The SHA-256 a `dcb` body names (64 hex digits), or null when the bytes do not start with a valid header. */
export function readDcbHeader(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < DCB_HEADER_LENGTH) return null;
  for (let index = 0; index < DCB_MAGIC.length; index++) if (bytes[index] !== DCB_MAGIC[index]) return null;
  let hex = "";
  for (let index = 4; index < DCB_HEADER_LENGTH; index++) hex += bytes[index].toString(16).padStart(2, "0");
  return hex;
}

/** `header + brotliStream`: the body of a difference file. */
export function dcbBody(hashHex, brotliStream) {
  const body = new Uint8Array(DCB_HEADER_LENGTH + brotliStream.length);
  body.set(dcbHeader(hashHex), 0);
  body.set(brotliStream, DCB_HEADER_LENGTH);
  return body;
}

/** The SHA-256 of `bytes` as 64 lowercase hex digits (Web Crypto). */
export async function sha256Hex(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  let hex = "";
  for (const byte of digest) hex += byte.toString(16).padStart(2, "0");
  return hex;
}
