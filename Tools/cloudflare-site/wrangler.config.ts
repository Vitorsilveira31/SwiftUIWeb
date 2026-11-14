import { defineWranglerConfig } from "wrangler/experimental-config";

// Read by the Cloudflare CLI when it builds this static project through Wrangler; the Worker itself is in
// cloudflare.config.ts.
export default defineWranglerConfig({
  assetsDirectory: "public",
});
