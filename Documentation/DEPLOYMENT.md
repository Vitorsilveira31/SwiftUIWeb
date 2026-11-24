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
| `*.dcb` | Only with `SWIFTUIWEB_PREVIOUS_BUNDLES`: the difference between a module and an earlier one, for returning visitors: see [Update by difference](#update-by-difference). Hosts that cannot choose by request header leave them out |

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
  `index.html`. Copy `Tools/cloudflare-site` (`worker.js`, `cloudflare.config.ts`, `stage.mjs`) as a starting point. The same
  Worker can send a returning visitor a module's difference file (see [Update by difference](#update-by-difference)).
- **nginx.** `gzip_static on;` sends the `.gz` copies. `brotli_static on;` sends the `.br` copies, but it comes from the
  [ngx_brotli](https://github.com/google/ngx_brotli) module, which stock nginx does not include. Both keep the file's own
  `Content-Type`.
- **Caddy.** `file_server { precompressed br gzip }`.
- **Other hosts and CDNs.** Check whether the host can send an uploaded precompressed file with `Content-Encoding` (some
  call it "precompressed" or "static compression"). If it can only compress on the fly, upload the plain files and let it
  compress; the app works either way, it only downloads more.

### Update by difference

A visitor who comes back after a deploy has the previous `app.<hash>.wasm` in the browser's cache, and the new one is
mostly the same bytes. With HTTP Compression Dictionary Transport ([RFC 9842](https://www.rfc-editor.org/rfc/rfc9842))
the host sends only what changed: the earlier module is the dictionary, and the browser decodes the answer before
`fetch`, `XMLHttpRequest` and `WebAssembly.compileStreaming` see it, so the page and the app change nothing. It is for
apps that deploy often and have returning visitors, on a host that can choose its answer by request header. Measured on
2026-11-23 on the Board example's release build, between two builds that differ by a small source change, in Chromium
against `Tools/bun-server.ts`: the two modules take 27,822 bytes on the wire instead of 264,532 (their `.br` copies).

**Build.** Keep the modules of the build that is live, then name them when you build the next one. The variable takes
directories separated by `:` (absolute paths): an earlier bundle, or a folder with only its `.wasm` files.

```sh
cp -R .build/browser/<Product> /srv/previous/1.4          # before the next build replaces it
SWIFTUIWEB_PREVIOUS_BUNDLES=/srv/previous/1.4:/srv/previous/1.3 ./swiftweb build
```

The framework's own launcher (`Tools/run-browser.sh`, `make run`) reads the same variable on a release build, and
`bun Tools/delta-compress-bundle.mjs --bundle <bundle> --previous <directory>`, from the framework's checkout, runs the
step on a bundle that already exists.

To take the earlier modules from the site that is live instead of keeping them, `bun Tools/fetch-live-modules.mjs <site
URL> <directory>` reads the site's page and the scripts it names, downloads every content-hashed module it finds, and keeps
the ones whose bytes match the hash in their name; it writes nothing and exits 0 when the site cannot be read, so it can run
before every deploy. Name the directory in `SWIFTUIWEB_PREVIOUS_BUNDLES`.

For each `app.<hash>.wasm` (and `app-rest.<hash>.wasm`) of the bundle and each earlier module with the same name and other
bytes, the step writes `<module>.<64 hex digits>.dcb` next to the module, where the digits are the SHA-256 of the earlier
module. A file is kept only when it is at least 10 % smaller than the module's `.br` copy; the step prints one line per
decision and deletes the files an earlier run left. Name as many earlier builds as visitors may still have, one file each.
It runs after the precompressed copies, with Bun's own Brotli: no extra program is needed.

**What the host does.** For a request whose path is a content-hashed module (`<stem>.<8 hex>.wasm`):

- Every response for it, whole or difference, carries `Use-As-Dictionary: match="/<directory>/<stem>.*.wasm"` (the path with
  the hash replaced by `*`, so `app.*.wasm` does not match `app-rest.<hash>.wasm`) and `Vary: Accept-Encoding,
  Available-Dictionary`. The pattern has to be one a URL pattern reads literally, so a module under a directory named with
  anything but letters, digits, `_`, `~` and `-` gets no `Use-As-Dictionary`.
- A request that carries `Available-Dictionary: :<base64 of 32 bytes>:` and lists `dcb` in `Accept-Encoding` is answered
  with the difference file for that hash when there is one, with `Content-Encoding: dcb`, the module's `Content-Type` and the
  module's other headers (the year-long cache). The body is the file's bytes unchanged: `ff 44 43 42`, the 32 bytes of the
  hash, and the Brotli stream.

```text
hash = hex(base64decode(request["Available-Dictionary"]))       # only 64 hex digits [0-9a-f] may continue
if module(path) and hash and accepts(request["Accept-Encoding"], "dcb") and exists(path + "." + hash + ".dcb"):
    send(path + "." + hash + ".dcb", Content-Encoding: dcb)
else:
    send as before (the .br or .gz copy, or the plain file)
add Use-As-Dictionary and Vary: Accept-Encoding, Available-Dictionary
```

Never build a file name from the header's text: parse it, check that the result is 64 lowercase hex digits, and only then
use it. `Tools/dictionary-transport.mjs` holds these rules as pure functions (Web Crypto and typed arrays only), so a Worker
can import it; `Tools/bun-server.ts` is the reference. A host that cannot choose its answer by request header (a static
host that serves a file for a path) ignores the `.dcb` files and works as before: it only downloads more. Do not upload
them there. `Tools/cloudflare-site` stages them, and its Worker is ready to serve them but answers by difference only
for a request that carries its check header until `Tools/check-dictionary-host.mjs` passes on the host (its README).

**Check a host.** Whether a CDN or proxy passes `Available-Dictionary` through and delivers a `Content-Encoding: dcb` body
unchanged is a property of the host, not of the files. `bun Tools/check-dictionary-host.mjs <site URL> <directory of earlier
modules> [--header "Name: value"]...` asks the live site for each module that has an earlier module of the same stem in the
directory, without letting the client decode the body, and reports per module "difference served and correct" (the body
decodes with the earlier module to bytes that match the hash in the module's name), "no difference served" (any other
coding; the response's `Content-Encoding`, `Vary` and `Use-As-Dictionary` are printed) or "WRONG" (it says `dcb` and the
body does not decode, or `Vary` does not list `Available-Dictionary`, or `Use-As-Dictionary` is missing). It also requests
every module the ordinary way and checks its bytes against the name. It exits 1 when anything is WRONG.

**Limits.**

- The dictionary has to be in the visitor's cache: only a returning visitor whose cache still holds an earlier module you
  named gets a difference. A first visit, a cleared cache and a version older than the ones you named get the whole file.
- It needs a secure context (HTTPS, or `localhost`) and the same origin for the earlier and the new module.
- The browser stores the dictionary a moment after the response arrives, so a visitor who reloads at once may still get
  the whole file.
- The step compresses with a 16 MB window, the largest the `dcb` coding allows. It was measured on the Board's modules
  (under 0.5 MB each), and the `brotli` program with the same settings on a module of more than 6 MB (on 2026-11-23, a
  one-line change: 1 KB instead of 1.41 MB). A module that does not fit that window together with its earlier version is
  not measured.
- A change that moves most of the code (a compiler upgrade, a new optimization setting) leaves little in common; the step
  drops the file when it is not at least 10 % smaller, and the visitor gets the `.br` copy.

**Support.** The repository's test (`make dictionary-update-browser-test`) checks it in Chromium: the page's `fetch` with
`WebAssembly.instantiateStreaming`, a Worker's `fetch` with `WebAssembly.compileStreaming` and a Worker's synchronous
`XMLHttpRequest` with `new WebAssembly.Module` each receive a working new module through a `dcb` response of about the
difference file's size. A browser that does not send `Available-Dictionary` (WebKit, in the same test) gets the whole file,
the Brotli copy as before.

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
`Tools/cloudflare-site` deploys the project site with such a Worker and can serve as a reference. One setting differs
there: the site writes a real `index.html` for every route when it is staged, so it uses `notFoundHandling: "404-page"`
and an address that names no file gets a real 404 (`404.html`, which still starts the app).

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
