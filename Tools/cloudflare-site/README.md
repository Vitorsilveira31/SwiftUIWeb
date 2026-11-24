# The project site on Cloudflare

The project site (`Examples/ShowcaseSite`) is served by a Cloudflare Worker named `swiftuiweb`: it serves the release
bundle as static assets, on `swiftuiweb.<account subdomain>.workers.dev`, and its only code (`worker.js`) sends the
build's own brotli copy of the hashed files.

| File | What it does |
|---|---|
| `cloudflare.config.ts` | The Worker: its name, the `workers.dev` route, its script and the `ASSETS` binding, and the assets handling: `runWorkerFirst` for the `.wasm`, `.js` and `.css` files (every other address is answered by the assets alone), `notFoundHandling: "404-page"` (every route is a real file, so an address that names no file gets a real 404, `404.html`, which still boots the app) and `htmlHandling: "drop-trailing-slash"` (`/en/purpose` is served, and `/en/purpose/` is redirected to it, matching the addresses the app writes and the canonical links) |
| `worker.js` | For a hashed file and a reader that accepts brotli (`request.cf.clientAcceptEncoding`, since Cloudflare rewrites `Accept-Encoding`), answers with the bytes of its `.br` copy, `Content-Encoding: br` and `encodeBody: "manual"`, and the plain file's other headers (its `Content-Type` and the `_headers` rules, which Cloudflare does not apply to a Worker's own response); every other reader gets the plain file, compressed by Cloudflare. Workers static assets compress on the fly at a lower quality and cannot serve an uploaded precompressed file by themselves. For a content-hashed module (`<stem>.<8 hex>.wasm`) every 200 and 304 answer also carries `Use-As-Dictionary` and `Vary: Accept-Encoding, Available-Dictionary`, and the Worker can answer a returning visitor with the module's difference file, behind a switch (see [Update by difference](#update-by-difference)) |
| `wrangler.config.ts` | The assets directory (`public`). The Cloudflare CLI builds a static project through Wrangler and keeps this setting there |
| `_headers` | The security headers of `Documentation/Security/WEB_SECURITY.md` and a one-year cache for the hashed files |
| `stage.mjs` | Copies a release bundle into `public` with the `.br` copy of each `.wasm`, `.js` and `.css` file (what `worker.js` serves), and the difference files (`<module>.<64 hex>.dcb`) of the modules it stages, without the `.gz` copies and the other `.br` copies (`index.html` is rewritten by the prerender), the build logs and the build's dotfiles, and adds `_headers`, then writes one prerendered `index.html` per address (`pt`/`en` times each page and catalog entry: its own title, description, canonical and `hreflang`, and a `<noscript>` with its heading), `404.html`, `robots.txt`, `sitemap.xml`, `_redirects` and `favicon.svg` (when the bundle has no icon) |
| `package.json`, `bun.lock` | The pinned Cloudflare CLI (`cf`) and Wrangler |

## Deploy from a workstation

The Cloudflare CLI needs Node.js 22.18 or later. Sign in once with `cf auth login` (any `cf` on the `PATH`, or
`Tools/cloudflare-site/node_modules/.bin/cf` after a stage), then, from the repository root:

```sh
make cloudflare-site-check    # builds the site and validates the Worker, uploads nothing
make cloudflare-site-deploy   # builds the site and deploys it
```

Both build the release bundle with `Tools/run-browser.sh site` first, after downloading the modules the live site serves
(`Tools/fetch-live-modules.mjs`, from `SITE_ORIGIN` or the site's own address, into `.build/cloudflare-site-previous`) and
naming them in `SWIFTUIWEB_PREVIOUS_BUNDLES`, so the build writes the difference files from them. That download reaches the
network; a site that cannot be read only means the build writes no difference files. The deploy records the commit's short
hash as the message of the new Worker version.

## Deploy from GitHub Actions

`.github/workflows/deploy-site.yml` runs `make cloudflare-site-deploy` for every commit on `main` and on demand. It needs
two repository secrets:

- `CLOUDFLARE_API_TOKEN`: an API token made from the "Edit Cloudflare Workers" template, limited to the one account;
- `CLOUDFLARE_ACCOUNT_ID`: the account's ID (`cf auth whoami` shows it).

The job installs Binaryen and headless Chromium, which a release build needs to optimize the module (`wasm-opt`) and to
split it by its first screen (`Documentation/Architecture/WASM_SPLIT.md`). Without them the build still succeeds and warns,
and the site ships one module that is neither optimized nor split.

## Check a deploy

```sh
curl -s -o /dev/null -w '%{size_download}\n' -H 'Accept-Encoding: br' https://swiftuiweb.<account subdomain>.workers.dev/app.<hash>.wasm  # the size of app.<hash>.wasm.br
curl -sI https://swiftuiweb.<account subdomain>.workers.dev/                        # index.html with the _headers
curl -sI https://swiftuiweb.<account subdomain>.workers.dev/en/components/slider    # a route: index.html as well
```

## Update by difference

A returning visitor can be sent only the difference between the module in the browser's cache and the new one
(`Documentation/DEPLOYMENT.md`, "Update by difference"). The Worker is ready for it and the answers are off until the host is
checked: whether Cloudflare's network passes `Available-Dictionary` to the Worker and delivers a `Content-Encoding: dcb`
body byte for byte has to be seen on the live host.

- The switch is `DICTIONARY_UPDATES` (a Worker variable, with the default `DEFAULT_DICTIONARY_UPDATES` at the top of
  `worker.js`, `"off"`). With `"on"`, a request for a module that has a valid `Available-Dictionary`, accepts `dcb` (by
  `request.cf.clientAcceptEncoding`) and has a difference file for that hash is answered with the file's bytes, length and
  ETag, `Content-Encoding: dcb`, and the plain file's other headers. Any other request gets the brotli copy as before.
- Whatever the switch says, a request that carries `SwiftUIWeb-Dictionary-Check: 1` is answered by difference. Browsers never
  send that header, so the host can be checked while visitors still get the brotli copy.
- Every module answer carries `Use-As-Dictionary` and `Vary: Accept-Encoding, Available-Dictionary` whatever the switch says.

To check the host after a deploy, give the checker the modules the site served before it (the directory the build
downloaded, `.build/cloudflare-site-previous`, which the next stage replaces; or run `bun Tools/fetch-live-modules.mjs
<site> <directory>` before the deploy):

```sh
bun Tools/check-dictionary-host.mjs https://swiftuiweb.<account subdomain>.workers.dev .build/cloudflare-site-previous --header "SwiftUIWeb-Dictionary-Check: 1"
```

For each module it prints "difference served and correct", "no difference served" (with the response's `Content-Encoding`,
`Vary` and `Use-As-Dictionary`) or "WRONG", and exits 1 on any WRONG. When every module with an earlier version is served
correctly, turn the answers on: set `DICTIONARY_UPDATES` to `on` for the Worker (or change the default in `worker.js`) and
deploy. If the host does not deliver `dcb` unchanged, leave it off: the site works as before.

## What the Worker answers

Checked with `wrangler dev` on the staged files and this config (nothing uploaded): `/` is answered by `index.html` (a redirect to `/en/purpose` would choose English before the app
picks the reader's language), `/en` and `/pt` are 301s to their first page, an address without a language (`/benefits`, `/components/slider`) is a page of its own whose canonical link names the English one, `/en/purpose/` is a 307 to `/en/purpose`, every route answers 200
with its own title, an unknown address answers a real 404 with `404.html`, and `robots.txt`, `sitemap.xml` and `favicon.svg` have their own
content types instead of `index.html`.

Checked with `cf dev` the same way: a hashed file asked for with `Accept-Encoding: br` answers the bytes of its `.br` copy
with `Content-Encoding: br`, its own `Content-Type` (`application/wasm`, `text/javascript`, `text/css`), the one-year
cache, the security headers and `Vary: Accept-Encoding`, and a 304 for its ETag; a reader without brotli gets the plain file
(gzip, or nothing for `identity`); a hashed name with no file answers the 404 page; the app mounts in Chromium and WebKit
with no console error and fetches `app-rest.<hash>.wasm` once. The local server picks the first of `gzip`/`br` in the
browser's `Accept-Encoding`, so a browser there gets the copy transcoded to gzip; Cloudflare's network keeps the Worker's
`br` for any reader that accepts it.
