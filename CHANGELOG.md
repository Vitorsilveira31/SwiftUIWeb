# Changelog

Every release, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/). Before 1.0 a minor version may break source compatibility; each break
is described in [`Documentation/MIGRATION.md`](Documentation/MIGRATION.md).

## Unreleased

The first public release.

### Added

- A SwiftUI-shaped API (`View`, `@State`, `@Observable`, `NavigationStack`, `List`, `TabView`, controls, presentation,
  animation) compiled with Embedded Swift to WebAssembly and rendered as DOM laid out by CSS.
- The Fiber runtime: view identity, keyed child matching, dependency tracking and binary patches applied to the page,
  with the Swift side running in a Web Worker by default.
- Browser counterparts of Apple frameworks: Charts, MapKit (MapLibre), AVFoundation and AVKit, PhotosUI, CoreLocation,
  UserNotifications, Security (keychain over IndexedDB), and `WebFoundation`, a Foundation-shaped module that runs on
  every host.
- The source lowerer (`Tools/SwiftUIWebLowering`), the launcher (`Tools/swiftuiweb-run.swift`) and the SwiftPM command
  plugin that build an application for the browser.
- Examples, a component playground and a measured comparison with React.

### Security

- `openURL` opens other sites in a window that cannot navigate the application's tab back through `window.opener`.
- Keychain queries must name their item class (`errSecParam` otherwise, as on Apple platforms): `SecItemDelete([:])`
  no longer deletes every item. An item larger than the browser's store keeps (1 MiB) is refused with `errSecAllocate`
  instead of reported saved and lost on reload; `0` and `1` in a query match `false` and `true`, as Security.framework
  compares them; a stored record whose lengths do not fit is skipped instead of trapping the unlock.
- Markup refuses SVG's `set` and `animate` elements, which can animate an `href` to `javascript:` past the URL check,
  and `link`.
- `WebSecurity.Session.state()` refuses redirects, so a status endpoint that redirects to a sign-in page reads as
  `.unknown`, not `.active`.
- A commented-out Content-Security-Policy in `head.html` no longer removes the page's policy.
- Far dates, huge numbers and other values an application can receive from the network no longer trap the browser build,
  where `Int` is 32 bits: `JSONSerialization` numbers past 2^31, `NumberFormatter`, `NSNumber.intValue`,
  `Measurement.formatted()`, `Calendar` arithmetic, cookie expiry dates after 2038, `Text` with a `%.2f` specifier,
  `Font.custom(size:)`, `ShapeStyle.opacity(.nan)`, a `TimelineView` schedule that started long ago, chart axes and
  selections of `Int` values, media durations in the AVKit controls, and `Path` arcs of millions of turns.
  `make hostile-values-browser-test` checks them nightly, with a seeded JSON fuzz.
- A runtime `Regex` no longer exhausts the browser's stack on long input: a repeated single character is matched in a
  loop, and a match that would backtrack past a depth limit fails instead of stopping the application. A case-insensitive
  class no longer traps on a character whose case mapping is longer (`ß`).
- `URL.appendingPathComponent(_:)` percent-encodes the component as Foundation does, so `"42?role=admin"` stays one path
  segment instead of starting a query.
- A string interpolated into `Text` can no longer place an image in it with object-replacement characters; a stored tab
  order that repeats a tab no longer traps `TabView`; a hover style value cannot add a rule line with a line break.
- The page's binary publication reader refuses a count that runs past the publication instead of looping on it;
  `Tools/test-binary-publication-fuzz.mjs` builds thousands of damaged publications in a browser.
- Shaka Player, bundled for adaptive media, is 5.3, the current major release; `Tools/test-adaptive-media-browser.mjs` plays a
  real HLS stream through it and checks renditions, audio languages and subtitles. Dependabot keeps the pinned actions and
  packages current.
- Formats read from data are bounded: a printf width, precision or argument position is capped at 100,000 instead of
  allocating or trapping, and a trailing `%` is text. A runtime `Regex` has a step budget and a nesting limit, so a
  pattern such as `(a+)+$` fails instead of freezing the tab; NSPredicate `MATCHES` raises for a nested quantifier on a
  long subject.
- Values from the page, storage, files and servers no longer trap the 32-bit browser build or grow without bound: media
  times, bit rates, spring velocities, mesh grids, grid spans, gradients, dash patterns, chart values, steppers at the end
  of `Int`, text runs, hover shadows, symbol effects, viewport sizes, BrowserIO lengths, `Content-Length`, keychain ids,
  timeouts and waits past 24.8 days. `IndexSet` keeps ranges, so `IndexSet(integersIn: 3...)` is one entry.
- Identities stay apart: ids with `/` or `#`, rows, tabs and picker options with repeated ids, database and object
  store names, prefetch keys, string arrays in `UserDefaults`, and `NSMutableDictionary` keys whose hashes collide. The
  page publisher's hashes are seeded for each run, so text chosen to collide cannot keep a stale node.
- Foundation parsing is as strict as Apple's: `UUID(uuidString:)`, `Data(base64Encoded:)`, `removingPercentEncoding`
  (nil for invalid UTF-8), `URL.query`, `URLComponents.url`, cookie domain matching, `UTType` for `mp4` and wildcard
  MIME types; `NotificationCenter` observers honour their sender and a nil name.
- Escaping where a value meets markup or CSS: map URLs drop credentials and keys, map attributions, font family names,
  colour strings (`url(...)` is refused), image paint URLs, file names in the importer and exporter, `<style>` in markup,
  console output (`%c` in app text), number format options, mesh and media JSON.
- Host hardening: diagnostic address switches work only on a development host; a screen cannot set the referrer policy or
  arbitrary `<link>` relations; the media host creates only media elements; an opaque origin loads no feature module; an
  application database cannot open the keychain's store; downloads stop at their size limit; picked files over 64 MiB are
  refused; transfer URLs are unguessable and the registry is bounded.
- Tools: the lowerer and `sync-tree` never write or delete through a symbolic link, and the in-place restore keeps a file
  edited since the lowering; the launcher refuses resource links that leave the package; local dev and test servers
  answer only loopback host names; the dev proxy does not follow redirects; the toolchain installer in CI must be signed
  by Swift's team. `Documentation/EMBEDDED_SOURCE_LOWERING.md` lists where a lowered program behaves differently.
