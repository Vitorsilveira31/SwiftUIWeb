// lottie-web for `MotionView` (SwiftUIWebMotion), served from the application's own origin.
// The bundle build compiles this file with the exact version pinned in package.json (its integrity hash is in bun.lock),
// so a strict Content-Security-Policy (`script-src 'self'`) can play Lottie animations without trusting a third-party CDN.
// The light player draws SVG only and has no After Effects expressions, which lottie-web evaluates with `eval`: the page's
// CSP refuses that. `lottie-host.js` imports this file the first time a `MotionView` is on the page.
//
// On load lottie-web looks for elements of class `lottie` or `bodymovin` and plays them by themselves; a `MotionView`
// never carries those classes, so only the host starts animations.
import lottie from "lottie-web/build/player/esm/lottie_light.min.js";

export default lottie;
