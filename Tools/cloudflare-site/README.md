# The project site on Cloudflare

The project site (`Examples/ShowcaseSite`) is served by a Cloudflare Worker named `swiftuiweb` that has no code: it
serves the release bundle as static assets, on `swiftuiweb.<account subdomain>.workers.dev`.

| File | What it does |
|---|---|
| `cloudflare.config.ts` | The Worker: its name, the `workers.dev` route, and the assets handling: `notFoundHandling: "404-page"` (every route is a real file, so an address that names no file gets a real 404, `404.html`, which still boots the app) and `htmlHandling: "drop-trailing-slash"` (`/en/purpose` is served, and `/en/purpose/` is redirected to it, matching the addresses the app writes and the canonical links) |
| `wrangler.config.ts` | The assets directory (`public`). The Cloudflare CLI builds a static project through Wrangler and keeps this setting there |
| `_headers` | The security headers of `Documentation/Security/WEB_SECURITY.md` and a one-year cache for the hashed files |
| `stage.mjs` | Copies a release bundle into `public`, without the `.br`/`.gz` copies (Cloudflare compresses on its own), the build logs and the build's dotfiles, and adds `_headers`, then writes one prerendered `index.html` per address (`pt`/`en` times each page and catalog entry: its own title, description, canonical and `hreflang`, and a `<noscript>` with its heading), `404.html`, `robots.txt`, `sitemap.xml`, `_redirects` and `favicon.svg` (when the bundle has no icon) |
| `package.json`, `bun.lock` | The pinned Cloudflare CLI (`cf`) and Wrangler |

## Deploy from a workstation

The Cloudflare CLI needs Node.js 22.18 or later. Sign in once with `cf auth login` (any `cf` on the `PATH`, or
`Tools/cloudflare-site/node_modules/.bin/cf` after a stage), then, from the repository root:

```sh
make cloudflare-site-check    # builds the site and validates the Worker, uploads nothing
make cloudflare-site-deploy   # builds the site and deploys it
```

Both build the release bundle with `Tools/run-browser.sh site` first. The deploy records the commit's short hash as the
message of the new Worker version.

## Deploy from GitHub Actions

`.github/workflows/deploy-site.yml` runs `make cloudflare-site-deploy` for every commit on `main` and on demand. It needs
two repository secrets:

- `CLOUDFLARE_API_TOKEN`: an API token made from the "Edit Cloudflare Workers" template, limited to the one account;
- `CLOUDFLARE_ACCOUNT_ID`: the account's ID (`cf auth whoami` shows it).

## Check a deploy

```sh
curl -sI https://swiftuiweb.<account subdomain>.workers.dev/                        # index.html with the _headers
curl -sI https://swiftuiweb.<account subdomain>.workers.dev/en/components/slider    # a route: index.html as well
```

## What the Worker answers

Checked with `wrangler dev` on the staged files and this config (nothing uploaded): `/` is answered by `index.html` (a redirect to `/en/purpose` would choose English before the app
picks the reader's language), `/en` and `/pt` are 301s to their first page, an address without a language (`/benefits`, `/components/slider`) is a page of its own whose canonical link names the English one, `/en/purpose/` is a 307 to `/en/purpose`, every route answers 200
with its own title, an unknown address answers a real 404 with `404.html`, and `robots.txt`, `sitemap.xml` and `favicon.svg` have their own
content types instead of `index.html`.
