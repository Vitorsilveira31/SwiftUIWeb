# First paint

A SwiftUIWeb page shows nothing until the browser has downloaded the runtime and the application's wasm, compiled the module,
run it and committed the first screen. On a fast machine that is tens of milliseconds; on a phone on a slow network it is
seconds of white page. First paint puts the first screen's markup and styles into `index.html` at build time, so the browser
paints it as soon as the HTML and the stylesheet arrive, before a byte of wasm. When the runtime mounts it takes over without a
flash, a layout shift or a lost click.

It is opt-in: `SWIFTUIWEB_FIRST_PAINT=1` on a release build (the launcher, `make run`, the SwiftPM plugin). No Swift API
changes. An application that does not ask gets the page it gets today.

Measurements, the byte cost and the limits are at the end ("Measured", "Limits").

## 1. How the first screen is produced

Two ways were weighed.

**A. Run the release bundle in headless Chromium and serialize what it shows.** The build serves the finished bundle, loads the
route, waits for `html[data-embedded-mounted="true"]` and for the page to stop committing, and reads `#embedded-app-root`'s
markup, the layout rules the runtime adopted (CSS_LAYOUT.md: adopted stylesheets, the framework's static layout rules, the
`sl<N>` blocks Swift styled the window root with, `data-cl-<N>` selectors) and the `<style>` elements the runtime added.

**B. Render through the native static renderer** (`make snapshot`), which prints the Fiber HTML without a browser.

**Chosen: A.** What B prints is the semantic markup only. The geometry that makes the frame look like the frame is the
browser's and the page JavaScript's: layout blocks are emitted by `css-layout.js`/`layout-host.js` into adopted stylesheets, the
scheme, the viewport and the platform report are read by the runtime, and the binary transport builds the DOM the runtime really
shows. A native snapshot would be a second implementation of all that, and the first place it differed from the browser would be
a flash. With A the prerendered nodes are the nodes the runtime itself produced, so the only open question is whether the
screen is the same under the conditions of a visitor, which the verify step (section 6) answers pixel by pixel. The cost is that
the build needs a headless Chromium (Playwright, the repository's test tool): the step is opt-in and fails if Chromium is missing.

Pipeline, in `Tools/run-browser-embedded.sh`, one block after the CSP is sealed and before the precompressed copies are written:

```
build → rewrite-release-index → … → hash-release-bundle → seal-csp → first-paint → precompress
```

`Tools/first-paint.mjs build <bundle>` serves the sealed bundle on a free port of 8180-8199 and:

1. captures the route twice and refuses a screen that differs from itself (a clock, random ids, a request that answers
   differently each time);
2. writes the capture into index.html;
3. compares the prerendered frame with the runtime's at a ladder of widths (section 6) to find the range it is valid for, and
   with another language to find out whether it depends on it;
4. writes the conditions into the page and verifies the page as it ships.

What it adds sits between `<!--first-paint:begin-->` and `<!--first-paint:end-->` (`first-paint.mjs strip` removes it exactly):
a `<style id="first-paint-style">` in the head; `<div id="embedded-app-root" data-first-paint …>` with the markup, and one
inline script (section 4), first in the body; the script's hash in the page's CSP.

The markup is the root's `innerHTML` cleaned of what only the runtime reads: every `data-*` attribute that no selector of any
stylesheet mentions is dropped (event ids, node ids, fiber ids, `data-testid`s). Attributes a stylesheet selects on stay, so
the CSS matches exactly what it matched at capture. Inline `style` attributes stay.

## 2. Which screens

The route the page is opened at, `SWIFTUIWEB_FIRST_PAINT_ROUTE` (default `/`), captured at one viewport
(`SWIFTUIWEB_FIRST_PAINT_VIEWPORT`, default `1280x1200`). One route per build: a screen that depends on the address (a deep
link, a query) opts in by naming its route. A page opened at another address is not prerendered unless it is the captured
one (`index.html` is the same file for every address, so the captured route should be the one most visitors open; the
prerender of `/` is shown, then replaced, at `/other` if the runtime opens another screen there, which is a mismatch the
verify step cannot see: use the option for apps that serve one route).

The conditions under which the capture is shown are written on the root and checked by the inline script before the first
paint:

- `data-first-paint-media`: the width range the capture was verified for (contiguous ladder steps around the capture width,
  `(min-width:…) and (max-width:…)`) and `(max-height:<capture height>)`: a viewport taller than the capture would show rows the
  capture does not have;
- `data-first-paint-lang`: set when the screen differs between English and Portuguese (the build compares them), so the
  capture is shown only to browsers of the capture's language;
- no stored state: if `localStorage` has any entry the page is a returning visitor's, whose first screen the app may restore
  from storage (a language, an appearance, a session), and the prerender is dropped. The capture is of an empty profile.

Where a condition fails the script takes the prerender away before the first paint and the page is exactly what it was without
the feature.

## 3. How the runtime takes over

**A replace.** The first commit does, in one task, in this order: remove `<style id="first-paint-style">`, remove `data-first-paint`,
empty the root, then the commit's own `root.appendChild(content)` into the empty root (the fast path a first publication
already takes), then the syncs (layout rules adopted, theme, focus…). The browser paints between tasks, never inside one, so
the page goes from the prerendered frame to the runtime's frame with no frame that holds neither. The hook is `takeFirstPaint` in
`Tools/first-paint-host.js` (about 40 lines), called from one place, the first commit in `embedded-dom.js`.

Reusing the prerendered nodes (hydration) was rejected: the runtime tracks nodes through ids it assigns in its own build
(`data-embedded-node-id`, token tables, the layout host's per-element state), and the prerender deliberately has none of them.
Matching two trees node by node would be a second reconciler, and every difference it did not notice would be a control whose
event goes nowhere. A replace cannot have that bug. The price is a rebuild of the first screen's nodes, which the runtime did
anyway.

The prerendered rules are removed in the same task, so the layout rules of the runtime (same selectors, other numbering) never
meet them.

## 4. Before the mount

The prerender is a picture: no handlers (an inline `onclick` is forbidden by the CSP and nothing wires the runtime's event
delegation to it before the mount). What a person can do to it meanwhile:

- **Click.** A small inline script (about 1 KB, hashed into the CSP) sits right after the root and records, in the capture
  phase, a click on a button, link or control as a path of child indexes from the root plus the target's tag and text, and
  calls `preventDefault` (so a prerendered `<a>` does not navigate the page away). When the runtime has mounted, in a microtask
  after the mounting commit (the runtime ignores events while it commits), it replays each recorded click, `element.click()`, on
  the element at the same path if its tag and text are the same. An early click is not lost: it happens when the screen can act
  on it, as React replays discrete events after hydration. Order is kept.
- **Text fields.** They are real inputs, so typing works; the script records the last value per path, and after the takeover the
  runtime sets it and dispatches `input`, so what the person typed reaches the Swift state.
- **Focus and keyboard.** Controls are focusable as controls: Enter or Space on a button records and replays like a click. The
  caret and focus of a field are not carried over to the runtime's element (a limit of a replace).
- **`inert`** was rejected: an inert subtree gets no pointer events, so nothing could be recorded and a person who tapped would
  see nothing happen for the whole load. **`pointer-events: none`** for the same reason.
- **Assistive technology** reads the markup as the page; the markup carries the accessibility attributes the runtime wrote. When
  the runtime replaces it, the page it replaces it with is the same.
- **Scroll.** The document scrolls, not the root, so a scroll position survives the swap.

## 5. What must not be prerendered

A capture holds what the first screen shows on an empty profile in a fresh browser. It is only valid for what does not change
between the build and the view. The build refuses or restricts, by testing, rather than by guessing:

- **A screen that differs from itself** (a clock, a relative date, `UUID()`, shuffling, a request that answers differently): the
  capture is taken twice and compared; a difference fails the build.
- **Data from the network that the app shows at start**: if the page shows a loading state at capture, that is what is
  captured, and the runtime then shows the loading state too, then the data (the same as without the feature); if the capture
  holds data from a request, it holds data from build time. Do not enable it for such a screen unless the first frame is the same
  for everyone, and read the verify step's output: it compares with the runtime's first settled frame.
- **Language and appearance**: the build compares the prerender with the runtime under another language (pt-BR) and in dark;
  appearance is a CSS variable, so one capture serves both schemes and is verified in both; a language-dependent screen is
  shown to the capture's language only.
- **Viewport**: the verified width range and the capture height (section 2).
- **Stored state**: a returning visitor gets no prerender.
- **Cookies, a session, a login**: not known to the page before the wasm runs. An app whose first screen depends on them
  should not enable the feature.

Images, fonts and other resources in the markup are requested by the browser at first paint, like any markup. A screen whose
first frame holds a late-decoded image is verified after its images have loaded.

## 6. Turning it off, and verify

- **Per build:** `SWIFTUIWEB_FIRST_PAINT=1` turns it on (release builds). Absent or `0`: the page without the prerender.
  `SWIFTUIWEB_FIRST_PAINT_ROUTE`, `SWIFTUIWEB_FIRST_PAINT_VIEWPORT`, `SWIFTUIWEB_FIRST_PAINT_VERIFY=0` (never for shipping).
- **Verify (default on whenever the feature is on):** the bundle is loaded with the wasm request blocked (only index.html and its
  stylesheet paint: the prerendered frame) and again with the prerender stripped from the response (only the runtime paints), at
  the same viewport, and the two frames are compared **pixel for pixel, tolerance 0**:
  - the width ladder 320, 390, 480, 600, 768, 1024, 1280, 1440, 1920, 2560, 3840 at 800 px of height, light: finds the
    contiguous range around the capture width where the frames are identical; a capture that differs from the runtime at its
    own width fails the build;
  - after the conditions are written, every ladder step inside the range in light and in dark, the capture's own height, and the
    other language when the capture is not language-bound.
  Any difference fails the build with the pixel count and the bounding box.
- **A deliberately wrong capture is caught**: `Tools/test-first-paint-browser.mjs` changes a text and a rule of a good capture
  and requires the verify step to fail.

## 7. Content-Security-Policy

Nothing is weakened. The prerender needs no `unsafe-eval`, no new origin and no `unsafe-inline` for scripts:

- the markup is document content;
- the `<style>` is inline style, which the shipped policy already allows (`style-src … 'unsafe-inline'`; the runtime sets style
  attributes), and so are the markup's `style` attributes;
- the one inline script is allowed by its **hash**, added to `script-src` like the bootstrap's. An application with its own
  policy gets the hash added to its `script-src`; a policy with no `script-src` makes the step fail with a message. A policy
  that forbids inline styles makes the verify step fail (the prerendered frame would be unstyled).

`Tools/test-csp-bundles.mjs` keeps checking that no bundle evaluates a string, and the browser test fails on any violation.

## Limits

- **One capture per build**: one route, one viewport height, one width range, one language. Phones get the prerender only if the
  capture is valid at phone widths (the Board is; the project site is valid from 1280 px up: below that its layout differs and
  those visitors get the page without the prerender). Several captures keyed by viewport would cover more.
- Not carried over: the focus and caret of a field the person was typing in.
- No hydration: the first screen's nodes are rebuilt (as they were without the feature).
- Screens whose first frame needs the network are not prerendered in a useful way (section 5).
- The step needs headless Chromium at build time (about 45 s for the Board, 40 s for the site, most of it the width ladder).
- Run only on release builds.

## Measured

The numbers below were measured on an M-series Mac in the Showcase release build. They are indicative, not a contract.

Release bundles, headless Chromium 1280x800, a fresh context per run with an empty cache, 15 runs per cell, median (min–max). "Slow" is
CDP `Network.emulateNetworkConditions` at 1.6 Mbps down, 750 Kbps up, 150 ms RTT; "4x" is `Emulation.setCPUThrottlingRate`. The
bundle is served by `Tools/bun-server.ts` with its precompressed copies. Probe: `Tools/first-paint-measure.mjs`
(`make first-paint-measure`). "Before" is the same bundle without the prerender. LCP is the board's text in all runs (it equals FCP).
"Mounted" is `html[data-embedded-mounted]`, the runtime up and wired. CLS is the sum of `layout-shift` entries over the whole load,
which includes the handover.

Board benchmark app (`Tests/Apps/BoardBenchmarkApp`; capture at 1280x1200, valid for every width from 320 px up):

| network | CPU | FCP before → after | LCP before → after | mounted before → after | CLS |
|---|---|---|---|---|---|
| fast | 1x | 72 (68–76) → **32** (24–36) | 72 → 32 | 64.2 (61–67) → 69.6 (66–78) | 0 → 0 |
| fast | 4x | 168 (156–172) → **84** (80–88) | 168 → 84 | 153.4 (143–159) → 171.4 (165–177) | 0 → 0 |
| slow | 1x | 2992 (2984–2996) → **592** (588–604) | 2992 → 592 | 2985 (2977–2990) → 2971 (2965–2983) | 0 → 0 |
| slow | 4x | 3048 (3028–3056) → **636** (620–652) | 3048 → 636 | 3036 (3015–3042) → 3017 (3000–3038) | 0 → 0 |

Project site (`Examples/ShowcaseSite`, built with `SWIFTUIWEB_FIRST_PAINT=1`; valid from 1280 px, English, no stored state):

| network | CPU | FCP before → after | mounted before → after | CLS |
|---|---|---|---|---|
| fast | 1x | 112 (104–128) → **32** (32–40) | 101.6 (91–117) → 104.5 (101–113) | 0 → 0 |
| fast | 4x | 272 (260–288) → **108** (104–120) | 247 (239–266) → 290 (281–306) | 0 → 0 |
| slow | 1x | 4332 (4324–4344) → **596** (592–608) | 4321 → 4308 | 0 → 0 |
| slow | 4x | 4452 (4440–4476) → **652** (636–672) | 4428 → 4396 | 0 → 0 |

What it costs, stated plainly: on a fast network the runtime is mounted later, by about 5 ms (Board, CPU 1x) to 18 ms (Board, CPU
4x) and 43 ms (site, CPU 4x): the browser parses, styles, lays out and paints the prerendered markup before the page's script
gets the thread. On a slow network the mount time does not change (the wasm arrives when it arrives) and the page is on screen
5 times sooner. The bytes: the Board's `index.html` grows by 56 KB (42 KB of markup, 13 KB of layout rules), which is +2.6 KB
brotli and +3.4 KB gzip on the wire (`index.html.br` 1753 → 4341 bytes); the site's by 210 KB (193 KB of markup), about +9 KB
brotli.

The handover, checked three ways: **no layout shift** (CLS 0 in every run above, Chromium); **identical frames** (the prerendered
frame and the runtime's first settled frame are compared pixel for pixel at every ladder width inside the verified range, in light and dark, and again by the browser
test in Chromium and WebKit, Worker and main thread: 0 pixels differ); **no transient frame** (a probe records, at every animation
frame, what the root holds and where the controls are: across 44 loads (36 in Chromium at CPU 1x and 4x on fast and slow networks, 8 in WebKit) every load had
exactly two states, the prerender and the runtime's, with the same geometry in both, and no empty frame after the board appeared).
