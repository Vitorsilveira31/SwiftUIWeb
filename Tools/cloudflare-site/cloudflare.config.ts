import { defineConfig } from "cf/config";

// The project site (Examples/ShowcaseSite) on Cloudflare: a Worker with no code that serves the release bundle as static
// assets. `make cloudflare-site-stage` copies the bundle into ./public, the assets directory that wrangler.config.ts
// names (the Cloudflare CLI builds a static project through Wrangler and keeps that setting there).
export default defineConfig({
  worker: {
    name: "swiftuiweb",
    compatibilityDate: "2026-11-13",
    // Every route is a real file (stage.mjs writes one prerendered index.html per address), so an address that names no
    // file is a real 404: 404.html, which still boots the app.
    // The addresses have no trailing slash (the app's own, the canonical links, the sitemap): `drop-trailing-slash` serves
    // `/en/purpose` from `en/purpose/index.html` and sends `/en/purpose/` to it, where the default would do the opposite.
    assets: { notFoundHandling: "404-page", htmlHandling: "drop-trailing-slash" },
    workersDev: true,
  },
});
