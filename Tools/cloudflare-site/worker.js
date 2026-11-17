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

const COMPRESSIBLE = /\.(wasm|js|css)$/;

// Cloudflare rewrites the request's Accept-Encoding to "br, gzip" before the Worker sees it; the reader's own value is
// request.cf.clientAcceptEncoding.
const acceptsBrotli = (request) =>
  (request.cf?.clientAcceptEncoding ?? request.headers.get("Accept-Encoding") ?? "")
    .split(",")
    .some((part) => {
      const [coding, ...parameters] = part.trim().toLowerCase().split(";");
      const q = parameters.map((parameter) => parameter.trim()).find((parameter) => parameter.startsWith("q="));
      return coding.trim() === "br" && (q === undefined || Number(q.slice(2)) > 0);
    });

const withVary = (response) => {
  const headers = new Headers(response.headers);
  headers.append("Vary", "Accept-Encoding");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const method = request.method;
    if ((method !== "GET" && method !== "HEAD") || !COMPRESSIBLE.test(url.pathname)) return env.ASSETS.fetch(request);
    if (!acceptsBrotli(request)) return withVary(await env.ASSETS.fetch(request));

    const copyURL = new URL(url);
    copyURL.pathname += ".br";
    // The reader's conditional headers go to the copy, whose ETag is the one the reader was sent.
    const copy = await env.ASSETS.fetch(new Request(copyURL, { method, headers: request.headers }));
    if (copy.status !== 200 && copy.status !== 304) {
      copy.body?.cancel();
      return withVary(await env.ASSETS.fetch(request));
    }
    const plain = await env.ASSETS.fetch(new Request(url, { method: "HEAD" }));
    if (plain.status !== 200) {
      copy.body?.cancel();
      return withVary(await env.ASSETS.fetch(request));
    }

    const headers = new Headers(plain.headers);
    headers.set("Content-Encoding", "br");
    headers.append("Vary", "Accept-Encoding");
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
  },
};
