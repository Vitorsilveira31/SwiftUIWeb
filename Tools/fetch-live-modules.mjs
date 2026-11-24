#!/usr/bin/env bun
// Downloads the content-hashed WebAssembly modules (`<stem>.<8 hex>.wasm`) a deployed site serves, into a directory. The
// directory is what the next build names in SWIFTUIWEB_PREVIOUS_BUNDLES, so a visitor who has the live modules in the browser's
// cache is sent only the difference (Documentation/DEPLOYMENT.md, "Update by difference").
//
// The site is read the way a browser reads it: the page names the modules it loads and the scripts that name the rest (the
// second module's name is inside a script, not in the page), so the page's text is searched for module names and for the names
// of same-origin content-hashed scripts (`<stem>.<8 hex>.js`), and those scripts are searched in turn, breadth first. Both the
// number of files read and the bytes read from each are capped.
//
// A module is kept only when the 8 hex digits in its name are the first 8 of the SHA-256 of its bytes, which is how
// Tools/hash-release-bundle.mjs names it; any other file is reported and dropped. The module files a previous run left in the
// directory are removed once the page has been read, so the directory holds what is live now.
//
// It must never fail a deploy: a site that cannot be reached, answers with an error or names no module gives a message and
// exits 0 without writing anything. Exit 2 only for wrong arguments.
//
// usage: fetch-live-modules.mjs <site URL> <directory>
// Run the tests with: bun test ./Tools/test-fetch-live-modules.mjs
import { existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { isDictionaryModule, moduleParts, sha256Hex } from "./dictionary-transport.mjs";

/** The most files (the page and its scripts) read to look for names. */
export const MAX_FILES = 40;
/** The most bytes read from the page or from one script. */
export const MAX_TEXT_BYTES = 8 * 1024 * 1024;
/** The most bytes taken from one module. */
export const MAX_MODULE_BYTES = 128 * 1024 * 1024;
export const REQUEST_TIMEOUT_MS = 20000;

// A reference is a path that is not the end of a longer one: `./app.1234abcd.wasm`, `/modules/app.1234abcd.wasm`,
// `"app.1234abcd.wasm"`. A name preceded by `:`, `/` or a name character (`https://cdn.example/app.1234abcd.wasm`, `x.app...`)
// is not matched whole, so a module of another origin or another name is not mistaken for one of the site's.
const PREFIX = String.raw`(?<![A-Za-z0-9_~.:/-])(?:\.\/|\/)?(?:[A-Za-z0-9_~-]+\/)*[A-Za-z0-9_-]+`;
const MODULE_REFERENCE = new RegExp(String.raw`${PREFIX}\.[0-9a-f]{8}\.wasm(?![A-Za-z0-9_-])`, "g");
const SCRIPT_REFERENCE = new RegExp(String.raw`${PREFIX}\.[0-9a-f]{8}\.js(?![A-Za-z0-9_-])`, "g");

const unique = (values) => [...new Set(values)];

/** The content-hashed module paths `text` mentions, as written (`app.1234abcd.wasm`, `./x/app.1234abcd.wasm`). */
export function moduleReferences(text) {
  return unique((text.match(MODULE_REFERENCE) ?? []).filter((reference) => isDictionaryModule(reference.replace(/^\.\//, ""))));
}

/** The content-hashed script paths `text` mentions (`<stem>.<8 hex>.js`), as written. */
export function scriptReferences(text) {
  return unique(text.match(SCRIPT_REFERENCE) ?? []);
}

/** The absolute URL `reference` names in the file at `fileURL` (as a browser resolves it), or null when it is not a URL. */
export function resolveReference(reference, fileURL) {
  try {
    return new URL(reference, fileURL);
  } catch {
    return null;
  }
}

/**
 * The base URL the page's references resolve against, as a browser uses it: the page's first `<base href>` resolved against
 * the page's address, or the address when there is none.
 */
export function documentBase(html, pageURL) {
  // The value may be quoted with either mark or, as HTML allows, unquoted (up to a space or the end of the tag).
  const match = /<base\s[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/i.exec(html);
  const href = match ? (match[1] ?? match[2] ?? match[3]) : undefined;
  return (href !== undefined && resolveReference(href, pageURL)) || pageURL;
}

/** Reads at most `limit` bytes of the response body and cancels the rest. */
export async function readLimited(response, limit) {
  if (!response.body) return new Uint8Array(0);
  const chunks = [];
  let total = 0;
  const reader = response.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    const take = Math.min(value.length, limit - total);
    chunks.push(take === value.length ? value : value.subarray(0, take));
    total += take;
    if (total >= limit) {
      await reader.cancel();
      break;
    }
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

function moduleFiles(directory) {
  const found = [];
  const walk = (path, prefix) => {
    for (const entry of readdirSync(path, { withFileTypes: true })) {
      const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.isDirectory()) walk(join(path, entry.name), relative);
      else if (entry.isFile() && isDictionaryModule(relative)) found.push(relative);
    }
  };
  if (existsSync(directory) && statSync(directory).isDirectory()) walk(directory, "");
  return found;
}

/**
 * Reads the page at `siteURL` and the scripts it leads to, and returns the modules they name:
 * `{ base, references, get }` (`references` maps the path of each module, relative to the site's origin root, to its absolute
 * URL, resolved against the file that names it), or `{ message }` when the page cannot be read. `get(url)` is the request
 * function with its timeout.
 */
export async function discoverModules(siteURL, { fetch: request = globalThis.fetch, timeoutMs = REQUEST_TIMEOUT_MS, maxFiles = MAX_FILES, maxTextBytes = MAX_TEXT_BYTES } = {}) {
  const get = (url, init = {}) => request(url, { redirect: "follow", signal: AbortSignal.timeout(timeoutMs), ...init });

  let page;
  let pageText;
  try {
    page = await get(siteURL);
    if (!page.ok) {
      await page.body?.cancel();
      return { message: `${siteURL} answered ${page.status}` };
    }
    pageText = new TextDecoder().decode(await readLimited(page, maxTextBytes));
  } catch (error) {
    return { message: `${siteURL} cannot be reached (${error.message})` };
  }
  const base = new URL(page.url || siteURL);
  const sameOrigin = (url) => url.origin === base.origin && (url.protocol === "http:" || url.protocol === "https:");

  // Breadth first: the page, then the scripts it names, then the scripts those name, up to the cap on files. A reference is
  // resolved against the base of the file that names it (the page's base element, or the page's final URL; a script's
  // response URL), as a browser does.
  const references = new Map();
  const scripts = new Set();
  const queue = [];
  const note = (text, fileURL) => {
    for (const reference of moduleReferences(text)) {
      const url = resolveReference(reference, fileURL);
      if (url && sameOrigin(url)) references.set(url.pathname.slice(1), url.href);
    }
    for (const reference of scriptReferences(text)) {
      const url = resolveReference(reference, fileURL);
      if (url && sameOrigin(url) && !scripts.has(url.href)) {
        scripts.add(url.href);
        queue.push(url.href);
      }
    }
  };
  note(pageText, documentBase(pageText, base));
  let read = 1;
  while (queue.length > 0 && read < maxFiles) {
    const url = queue.shift();
    read += 1;
    try {
      const response = await get(url);
      if (!response.ok) {
        await response.body?.cancel();
        continue;
      }
      note(new TextDecoder().decode(await readLimited(response, maxTextBytes)), new URL(response.url || url));
    } catch {
      // A script that cannot be read only hides the names inside it.
    }
  }

  return { base, references, get };
}

/**
 * Reads the site and writes its modules into `directory`. Returns `{ kept, dropped, message }`: the relative paths kept
 * (with their sizes), the references dropped (with the reason), and a sentence when nothing was kept. Never throws for a
 * site that cannot be read.
 */
export async function fetchLiveModules(siteURL, directory, options = {}) {
  const { maxFiles = MAX_FILES, maxModuleBytes = MAX_MODULE_BYTES } = options;
  const result = { kept: [], dropped: [], message: "" };
  const site = await discoverModules(siteURL, options);
  if (site.message) {
    result.message = `${site.message}: no module fetched`;
    return result;
  }
  const { references, get } = site;

  // The directory holds what is live now: the files of an earlier run go before the new ones are written.
  const root = resolve(directory);
  for (const path of moduleFiles(root)) rmSync(join(root, path), { force: true });

  for (const [path, href] of references) {
    if (result.kept.length + result.dropped.length >= maxFiles) break;
    const parts = moduleParts(path);
    try {
      const response = await get(new URL(href));
      if (!response.ok) {
        await response.body?.cancel();
        result.dropped.push({ path, reason: `answered ${response.status}` });
        continue;
      }
      const bytes = await readLimited(response, maxModuleBytes + 1);
      if (bytes.length > maxModuleBytes) {
        result.dropped.push({ path, reason: `larger than ${maxModuleBytes} bytes` });
        continue;
      }
      const hash = await sha256Hex(bytes);
      if (!hash.startsWith(parts.hash)) {
        result.dropped.push({ path, reason: `its SHA-256 starts with ${hash.slice(0, 8)}, not with the ${parts.hash} in its name` });
        continue;
      }
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), bytes);
      result.kept.push({ path, bytes: bytes.length });
    } catch (error) {
      result.dropped.push({ path, reason: error.message });
    }
  }
  if (result.kept.length === 0) {
    result.message = references.size === 0 ? `${siteURL} names no content-hashed module: no module fetched` : `no module of ${siteURL} could be kept`;
  }
  return result;
}

/** Whether `value` is an http or https URL. */
export function isWebURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

export async function main(argv = process.argv.slice(2), options = {}) {
  if (argv.length !== 2 || !isWebURL(argv[0])) {
    console.error("usage: fetch-live-modules.mjs <site URL: http or https> <directory>");
    return 2;
  }
  try {
    const { kept, dropped, message } = await fetchLiveModules(argv[0], argv[1], options);
    for (const { path, bytes } of kept) console.log(`live module ${path} (${bytes} bytes)`);
    for (const { path, reason } of dropped) console.log(`live module ${path} dropped: ${reason}`);
    if (message) console.log(`fetch-live-modules: ${message}`);
  } catch (error) {
    console.log(`fetch-live-modules: ${error.message}: no module fetched`);
  }
  return 0;
}

if (import.meta.main) process.exit(await main());
