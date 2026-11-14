// Shaka Player for adaptive (HLS/DASH) media, served from the application's own origin.
// The bundle build compiles this file with the exact version pinned in package.json (its integrity
// hash is in bun.lock), so a strict Content-Security-Policy (`script-src 'self'`) can play adaptive
// video without trusting a third-party CDN. `avfoundation.js` imports it on first use.
import shaka from "shaka-player/dist/shaka-player.compiled.js";

export default shaka;
