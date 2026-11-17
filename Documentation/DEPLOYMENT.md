# Deploying an app

A SwiftUIWeb app is a folder of static files. Build it once, upload the folder to any static host, and configure the host
to answer the app's routes with `index.html`.

## 1. Build the release bundle

From your package:

```sh
./swiftweb build
```

The bundle is written to `.build/browser/<Product>` (the command prints the path). For the counter app of the README:

| File | What it is |
|---|---|
| `index.html` | The page: the stylesheet, the loader and the Content-Security-Policy as a `<meta>` tag |
| `app.<hash>.wasm` | Your app and the framework, compiled with Embedded Swift |
| `app-rest.<hash>.wasm` | In a split build (the release default; not with `SWIFTUIWEB_WASM_SPLIT=0`): the functions the first screen does not run, loaded right after it. Serve it like `app.<hash>.wasm` |
| `index.<hash>.js`, `render-worker.<hash>.js`, `runtime-shared.<hash>.js`, `runtime-deferred.<hash>.js`, `feature-loader.<hash>.js` | The JavaScript host that runs the WebAssembly in a Web Worker and applies its updates to the DOM (`runtime-shared` holds the modules the page and the worker both use; `runtime-deferred` the page hosts the first screen does not run, loaded right after it) |
| `styles.<hash>.css` | The framework's stylesheet, with your `Resources/app.css` |
| `*.br`, `*.gz` | Brotli (quality 11) and gzip (level 9) copies of every text and `.wasm` file of at least 1 KB, for the host to send as they are: see [Serve the precompressed copies](#serve-the-precompressed-copies) |

Every file except `index.html` has a content hash in its name, so it can be cached forever. Build logs are kept next to
the bundles, in `.build/browser-logs/<Product>`, and are not part of what you upload.

To try the release bundle locally exactly as it will be served:

```sh
./swiftweb run
```

## 2. What the host must do

| Requirement | Why |
|---|---|
| Serve the app at the root of its domain (`https://app.example.com/`, not `https://example.com/app/`) | The page loads its files relative to `<base href="/">`. A sub-path is not supported yet. |
| Answer every route of the app with `index.html` (a rewrite, not a redirect) | The app does its own routing: `/settings` or `/en/components/slider` must load the page, which then reads the address. |
| Send `.wasm` files as `application/wasm` | Browsers compile WebAssembly while it downloads only with this type. |
| Cache `*.<hash>.*` files for a year (`Cache-Control: public, max-age=31536000, immutable`) and `index.html` not at all (`no-cache`) | A new deploy changes the hashes, so returning visitors get the new files at once. |
| Serve the `.br`/`.gz` copies with `Content-Encoding` (or, failing that, compress on the fly) | The `.wasm` file shrinks to about a quarter with the build's copy, to about a third with a host's on-the-fly compression. |
| HTTPS | Web Crypto (the keychain), `Secure` cookies and service features need a secure origin. |

The security headers that a `<meta>` tag cannot set (`frame-ancestors`, HSTS, `nosniff`, `Referrer-Policy`,
`Permissions-Policy`, `Cross-Origin-Opener-Policy`) are listed with their reasons in
[`Security/WEB_SECURITY.md`](Security/WEB_SECURITY.md).

`Tools/bun-server.ts`, the development server behind `./swiftweb dev` and `./swiftweb run`, does all of the above and can
serve as a reference.

### Serve the precompressed copies

The framework's size work reaches every app, but what reaches the reader is what the host sends. The release build
compresses each file once at the highest settings (`Tools/precompress-bundle.mjs`: brotli quality 11 with a 16 MB window,
gzip level 9). A host that compresses on each request uses a faster, weaker setting, and sends noticeably more. Measured on
the project site (Cloudflare Workers, 2026-11-17), for the same bundle:

| File (uncompressed) | Cloudflare on the fly | The build's `.br` |
|---|---:|---:|
| `app.<hash>.wasm` (1,710,834 bytes) | 608,088 (brotli), 617,778 (zstd, what Chrome gets) | 463,015 (−24%) |
| `app-rest.<hash>.wasm` (1,108,215) | 386,331 | 293,582 (−24%) |
| `index.<hash>.js` (304,820) | 97,960 | 83,238 (−15%) |
| `styles.<hash>.css` (136,158) | 22,637 | 18,097 (−20%) |

So, for a request for `<file>` whose `Accept-Encoding` allows `br` (or `gzip`) and that has a `<file>.br` (or `.gz`) next
to it, the host should answer with that copy's bytes unchanged, plus:

- `Content-Encoding: br` (or `gzip`);
- the **original** file's `Content-Type` (`application/wasm`, `text/javascript`, `text/css`), not one guessed from `.br`;
- `Vary: Accept-Encoding`, so a cache does not give the brotli bytes to a client without brotli;
- the original file's other headers (the year-long cache of a hashed file, the security headers).

Any other request gets the plain file. The host must not compress the copy again. `Tools/bun-server.ts` does this, and so
does the project site's Worker (below).

- **Cloudflare Workers.** Static assets cannot serve an uploaded `.br` in place of a file, so a small Worker does it.
  `Tools/cloudflare-site/worker.js` runs first only for the hashed files (`runWorkerFirst: ["/*.wasm", "/*.js", "/*.css"]`),
  reads the reader's own `Accept-Encoding` from `request.cf.clientAcceptEncoding` (Cloudflare rewrites the header before the
  Worker sees it), fetches `<path>.br` through the assets binding and returns it with `Content-Encoding: br` and
  `encodeBody: "manual"` (otherwise the runtime would encode the bytes again), with the headers of a `HEAD` for the plain
  file (assets fetched through the binding carry the `_headers` rules; a Worker's own response does not). Upload the
  `.br` copies of those files with the bundle; leave out the `.br` of any file you rewrite after the build, such as
  `index.html`. Copy `Tools/cloudflare-site` (`worker.js`, `cloudflare.config.ts`, `stage.mjs`) as a starting point.
- **nginx.** `gzip_static on;` sends the `.gz` copies. `brotli_static on;` sends the `.br` copies, but it comes from the
  [ngx_brotli](https://github.com/google/ngx_brotli) module, which stock nginx does not include. Both keep the file's own
  `Content-Type`.
- **Caddy.** `file_server { precompressed br gzip }`.
- **Other hosts and CDNs.** Check whether the host can send an uploaded precompressed file with `Content-Encoding` (some
  call it "precompressed" or "static compression"). If it can only compress on the fly, upload the plain files and let it
  compress; the app works either way, it only downloads more.

## 3. Host examples

These are starting points; check your host's documentation for the current syntax.

**Netlify.** Publish the bundle folder and add a `_redirects` file to it (in `Resources/`, so every build copies it):

```text
/*  /index.html  200
```

and a `_headers` file next to it for the security headers:

```text
/*
  Content-Security-Policy: frame-ancestors 'none'
  Strict-Transport-Security: max-age=63072000; includeSubDomains
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Cross-Origin-Opener-Policy: same-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
```

Trim `Permissions-Policy` to what the app does not use.

**Cloudflare Workers** serves the bundle as static assets with `notFoundHandling: "single-page-application"`, which answers
unknown paths with `index.html`, and serves `.wasm` with the right type. It reads the same `_headers` file as Netlify, in the
assets directory, which can also give the hashed files their long cache. It compresses on the fly; to send the build's
`.br` copies instead, put a small Worker in front of the assets (see [Serve the precompressed copies](#serve-the-precompressed-copies)).
`Tools/cloudflare-site` deploys the project site this way and can serve as a reference.

**nginx:**

```nginx
# In the http block: hashed files are cached for a year, everything else is revalidated.
map $uri $myapp_cache {
  # The quotes are required: nginx reads an unquoted { as the start of a block.
  "~*\.[0-9a-f]{8}\.(wasm|js|css)$" "public, max-age=31536000, immutable";
  default "no-cache";
}

server {
  root /srv/myapp;
  # The build writes a .gz copy of every file; nginx sends it to browsers that accept gzip.
  gzip_static on;
  # With the ngx_brotli module, the .br copies too (smaller): brotli_static on;
  # One set of add_header lines: nginx drops the server's headers in a location that adds its own.
  add_header Cache-Control $myapp_cache;
  add_header Content-Security-Policy "frame-ancestors 'none'";
  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains";
  add_header X-Content-Type-Options nosniff;
  add_header Referrer-Policy strict-origin-when-cross-origin;
  add_header Cross-Origin-Opener-Policy same-origin;
  add_header Permissions-Policy "camera=(), microphone=(), geolocation=()";
  location / {
    try_files $uri /index.html;
  }
}
```

nginx's own `mime.types` (1.21 or later) already sends `.wasm` as `application/wasm`. On an older one, add the line
`application/wasm wasm;` to that file: a `types { }` block in the configuration replaces the whole table, and every other
file would lose its type.

**GitHub Pages** has no rewrites: copy `index.html` to `404.html` so unknown paths still load the app, and use a custom
domain or a user site (`<user>.github.io`), since a project site lives under a sub-path.

## 4. Before you ship

- Run the app's own tests and open the release bundle in Chrome, Safari and Firefox.
- Send the security headers above, and check them in the browser's network panel on the deployed page.
- Put the first screen into `index.html` with `SWIFTUIWEB_FIRST_PAINT=1` if a fast first paint matters: see
  [`Architecture/FIRST_PAINT.md`](Architecture/FIRST_PAINT.md).
- A release downloads only what the first screen runs before it shows, and the rest behind it. Check that the build log
  has no "app.wasm is NOT split" warning (it needs Binaryen and a headless Chromium on the build machine): see
  [`Architecture/WASM_SPLIT.md`](Architecture/WASM_SPLIT.md).
- Check what the bundle weighs with `make bundle-sizes BUNDLE=<folder>` from a SwiftUIWeb checkout, and what the
  WebAssembly is made of in [`Performance/WASM_SIZE.md`](Performance/WASM_SIZE.md).
