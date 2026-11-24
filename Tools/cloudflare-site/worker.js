// The project site's Worker. It runs only for the hashed files (`runWorkerFirst` in cloudflare.config.ts: the .wasm, .js
// and .css); every other address (the prerendered pages, 404.html, _redirects, robots.txt) is served by the assets
// directly, with the _headers rules.
//
// The release build writes a brotli copy of each file at the highest quality (Tools/precompress-bundle.mjs, q11 with a
// 16 MB window), and stage.mjs uploads it next to the file as `<name>.br`. Cloudflare compresses static assets on the fly
// at a lower quality, which costs about a quarter more bytes on app.wasm, and it has no way to serve an uploaded copy. So
// for a reader that accepts brotli this Worker answers with the copy's bytes as they are: `Content-Encoding: br` and
// `encodeBody: "manual"` tell the runtime not to encode them again. Every other reader gets the plain file, which
// Cloudflare compresses as before (gzip for a client without brotli).
//
// _headers is not applied to a Worker's response, and the file's own rules do not match `<name>.br` either, so the
// headers come from the plain file: a HEAD request for it through the binding carries its Content-Type, the cache rule
// and the security headers, and only the body, its length and its ETag are the copy's.
//
// Update by difference (Documentation/DEPLOYMENT.md, Tools/dictionary-transport.mjs). A content-hashed module
// (`<stem>.<8 hex>.wasm`) names itself as a dictionary in every 200 and 304 answer (`Use-As-Dictionary`, and `Vary` lists
// `Available-Dictionary`). A reader that has an earlier module sends its hash in `Available-Dictionary` and accepts `dcb`;
// the Worker then answers with the build's `<module>.<64 hex>.dcb` file the same way it answers with the `.br` copy.
//
// The difference answers are off until the host is seen to deliver them unchanged: whether Cloudflare's network passes
// `Available-Dictionary` to a Worker and sends a `Content-Encoding: dcb` body byte for byte is checked on the live host, not
// assumed. Until then a reader that sends the header gets the brotli copy as before. A request that carries
// `SwiftUIWeb-Dictionary-Check: 1` (browsers never send it) gets the difference answer whatever the switch says, which is
// how `bun Tools/check-dictionary-host.mjs <site> <earlier modules> --header "SwiftUIWeb-Dictionary-Check: 1"` tests the
// host. To turn the answers on for every reader, set DICTIONARY_UPDATES to "on" (the Worker variable of that name, or the
// default below) after that check passes.

import { acceptsDcb, differenceName, isDictionaryModule, parseAvailableDictionary, useAsDictionary, VARY } from "../dictionary-transport.mjs";

const COMPRESSIBLE = /\.(wasm|js|css)$/;

const DEFAULT_DICTIONARY_UPDATES = "off";
const CHECK_HEADER = "SwiftUIWeb-Dictionary-Check";

const dictionaryUpdates = (request, env) =>
  request.headers.get(CHECK_HEADER) === "1" || (env.DICTIONARY_UPDATES ?? DEFAULT_DICTIONARY_UPDATES) === "on";

// Cloudflare rewrites the request's Accept-Encoding to "br, gzip" before the Worker sees it; the reader's own value is
// request.cf.clientAcceptEncoding.
const readerEncodings = (request) => request.cf?.clientAcceptEncoding ?? request.headers.get("Accept-Encoding") ?? "";

const acceptsBrotli = (request) =>
  readerEncodings(request)
    .split(",")
    .some((part) => {
      const [coding, ...parameters] = part.trim().toLowerCase().split(";");
      const q = parameters.map((parameter) => parameter.trim()).find((parameter) => parameter.startsWith("q="));
      return coding.trim() === "br" && (q === undefined || Number(q.slice(2)) > 0);
    });

// What every answer for the file says about negotiation. A module varies on the dictionary as well and, when it answers 200
// or 304, names itself as the dictionary for the next version.
const negotiationHeaders = (headers, status, path) => {
  if (!isDictionaryModule(path)) {
    headers.append("Vary", "Accept-Encoding");
    return;
  }
  headers.set("Vary", VARY);
  const dictionary = status === 200 || status === 304 ? useAsDictionary(path) : null;
  if (dictionary) headers.set("Use-As-Dictionary", dictionary);
};

const plainAnswer = async (request, env, path) => {
  const response = await env.ASSETS.fetch(request);
  const headers = new Headers(response.headers);
  negotiationHeaders(headers, response.status, path);
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
};

// The answer made of a precompressed copy (the file at `copyPath`): its body, length and ETag, the plain file's other
// headers. Null when there is no such copy (or no plain file), so the caller falls back.
const copyAnswer = async (request, env, url, copyPath, coding) => {
  const method = request.method;
  const copyURL = new URL(url);
  copyURL.pathname = copyPath;
  // The reader's conditional headers go to the copy, whose ETag is the one the reader was sent.
  const copy = await env.ASSETS.fetch(new Request(copyURL, { method, headers: request.headers }));
  if (copy.status !== 200 && copy.status !== 304) {
    copy.body?.cancel();
    return null;
  }
  const plain = await env.ASSETS.fetch(new Request(url, { method: "HEAD" }));
  if (plain.status !== 200) {
    copy.body?.cancel();
    return null;
  }

  const headers = new Headers(plain.headers);
  headers.set("Content-Encoding", coding);
  negotiationHeaders(headers, copy.status, url.pathname);
  for (const name of ["Content-Length", "ETag"]) {
    const value = copy.headers.get(name);
    if (value) headers.set(name, value);
    else headers.delete(name);
  }
  if (copy.status === 304) headers.delete("Content-Length");
  return new Response(method === "HEAD" || copy.status === 304 ? null : copy.body, {
    status: copy.status,
    headers,
    encodeBody: "manual",
  });
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method;
    if ((method !== "GET" && method !== "HEAD") || !COMPRESSIBLE.test(url.pathname)) return env.ASSETS.fetch(request);

    if (isDictionaryModule(url.pathname) && dictionaryUpdates(request, env)) {
      const hash = parseAvailableDictionary(request.headers.get("Available-Dictionary"));
      if (hash && acceptsDcb(readerEncodings(request))) {
        const answer = await copyAnswer(request, env, url, differenceName(url.pathname, hash), "dcb");
        if (answer) return answer;
      }
    }

    if (!acceptsBrotli(request)) return plainAnswer(request, env, url.pathname);
    return (await copyAnswer(request, env, url, `${url.pathname}.br`, "br")) ?? plainAnswer(request, env, url.pathname);
  },
};
