# Migration guide

This page lists the changes that need an edit in an application, release by release, with what to write instead. It
starts at the first public release; nothing before it is covered.

SwiftUIWeb follows SwiftUI's names and behavior, so most entries here are cases where the framework moved closer to
Apple's API. A change to the look of a component (its base rule in `Tools/styles.css`) is listed as well, with a
before/after comparison.

## Unreleased

### Security fixes that change behaviour

- `SecItemCopyMatching`, `SecItemUpdate` and `SecItemDelete` return `errSecParam` for a query without `kSecClass`, as
  Apple's keychain does. Add `kSecClass: kSecClassGenericPassword` to such a query.
- `WebSecurity.Session.state()` no longer follows redirects: a status endpoint that redirects reads as
  `.unknown(status: 0)`. Point `statusURL` at the address that answers.
- `Date.distantPast` and `Date.distantFuture` are Apple's (the first moments of years 1 and 4001) instead of about
  ±9.2e18 seconds.
- In the browser build, `JSONSerialization` gives a whole number past `Int`'s 32 bits as a `Double` (it trapped):
  read it with `as? Double` or decode it with `JSONDecoder` into an `Int64`.
- `Calendar.date(byAdding:value:to:)` returns nil when the year or month it computes is past `Int`'s range.
- `URL.appendingPathComponent(_:)` percent-encodes the component (`?` is `%3F`, `#` is `%23`, `%` is `%25`), as
  Foundation does. Code that passed a component with a query to get a query gets one segment now: use
  `appending(queryItems:)`.
- A runtime `Regex` that would backtrack more than 600 levels deep (a group repeated about 150 times) finds
  no match instead of stopping the application.
- `NSNumber.intValue` saturates at `Int`'s range and is 0 for NaN.
- `SecItemAdd` and `SecItemUpdate` return `errSecAllocate` for an item whose data and attributes pass 1 MiB, the most the
  browser's secure store keeps for one item (it used to report success and drop the item when persisting).
- Object-replacement characters (U+FFFC) are removed from strings interpolated into `Text` and from
  `LocalizedStringKey(_:)`; interpolate an `Image` to set one in the line.
- A runtime `Regex` matches `^` and `$` only at the ends of the input, and `.` does not match a line break, as Swift's
  `Regex` does: add `(?m)` or `(?s)` for the other meaning. A match past 2,000,000 steps finds nothing, and a
  pattern with more than 100 nested groups does not compile (`Regex(_:)` throws).
- `UUID(uuidString:)` takes only the 8-4-4-4-12 form of ASCII hex digits; `Data(base64Encoded:)` refuses white space and
  missing padding; `removingPercentEncoding` is nil for bytes that are not UTF-8. Strip white space and add the padding
  before decoding lenient input.
- `CharacterSet.whitespaces`/`.newlines` are Unicode's (a no-break space, U+2028), and
  `components(separatedBy: "\n")` splits a `"\r\n"` pair, as Foundation does.
- `NotificationCenter.addObserver(forName:object:queue:using:)` delivers only the given sender's notifications, and a nil
  name receives every notification.
- `URLComponents.url` is nil for a host with characters a host cannot have, or a path without a leading `/` when there
  is a host; `URL.query` ignores a `?` inside the fragment.
- `String(format:)` and `String.localizedStringWithFormat` cap a width, precision or position at 100,000.
- `HTTPCookieStorage.cookies(for:)` returns the page's cookies only for the page's own host (script cannot see a
  cookie's Domain attribute, so each one is host-only), never for a subdomain.
- `UTType(filenameExtension: "mp4")` is `.mpeg4Movie` and `UTType(mimeType: "video/*")` is nil, as Apple's.
- `IndexSet(integersIn: ..<n)` starts at 0, as Foundation's; it started at `Int.min`.
- `Color("...")` with `url(`, `image`, `element(` or unbalanced parentheses is transparent.
- A chart mark whose category the domain does not list is left out instead of drawn at the first position.
- A document path drops `.` and `..` segments; `?tab-selection=` with a tag that is not a tab is ignored.
- A screen's head entries cannot set `<meta name="referrer">` or a `<link>` other than icon, apple-touch-icon,
  manifest, canonical, alternate, preconnect and dns-prefetch. The `?swuidiag`, `?sync-gates=0` and similar switches work
  only on localhost.
- `WebIndexedDB` keeps the browser database of every store whose database and store names have no `.`. A pair where
  either name has a `.` (which could share a database with another pair) is stored under a new name; a record saved
  under the old name by an earlier release is moved to the new one the first time it is read.
- `Image("name")` loads an asset, a path of the app's own site, or a `data:`/`blob:` URL; a remote URL
  (`Image("https://...")`) loads nothing, as SwiftUI's `Image(_:)` never fetches one. Use `AsyncImage(url:)`.
- `.redacted(reason: .placeholder)` writes placeholder characters instead of the text into the page, and
  `.redacted(reason: .privacy)` does so for views marked `privacySensitive()`; `privacySensitive()` returns
  `some View`, as SwiftUI's.
- `WebElementHandle.setAttribute` ignores event handlers (`on…`), `srcdoc` and URLs with a scheme that could run
  script; media sources take http(s), `blob:`, `data:` or a relative path.
- Another tab's storage changes reach `@AppStorage` and storage observers once its whole write has landed (its
  revision), not key by key.
- `URLRequest.cachePolicy` reaches the browser: the reload policies send `cache: "no-store"` or `"no-cache"`.
- The lowerer's cache entries carry a check; entries written by an earlier release are rebuilt once.
- `Text("\\(value, specifier: "%.2f")")` writes the double's exact digits, as `String(format:)` does: `%.2f` of 1e20 is
  every digit, `%.20f` of 0.1 is `0.10000000000000000555`.
- `.number` and the other number styles with the default locale format in the visitor's locale (`3,000,000,000`
  in English), as Apple's `.current` does; they wrote `3000000000` because the default locale read as en_US_POSIX.
- A `fileMover` answer must echo the request's `data-file-mover-token` (`moved:tok=<token>;...`); a host of your own
  that answers moves must pass it back.
- Web Storage: a revision another script made unreadable is replaced by a fresh one instead of failing every write.
- `fileImporter` fails for a file above 64 MiB. `url(for:)` of a transferable payload keeps the 128 most recent
  payloads.
- `[String]` values written to `UserDefaults` use a framed form that keeps elements containing U+001F; values written by
  earlier releases still read.
- The OAuth callback page leaves the code in Web Storage; read it, check your `state` and remove the key (see
  `Documentation/Security/WEB_SECURITY.md`).
- In-place lowering (`SWIFTUIWEB_LOWER_IN_PLACE=1`) skips symbolic links, and its restore keeps a file edited since the
  lowering (and the state, until it is settled by hand).

### Looks that changed

- **`TabView(.sidebarAdaptable)` on a phone: the floating bottom bar follows the color scheme.** It was always the light
  glass (`rgb(250 250 250 / 0.72)`) with black labels, so in a dark scheme it was a light capsule on a dark page and the
  selected tab (the near-white primary color) could not be read on it. It is now the same glass as the automatic bar, dark in a dark
  scheme (`rgb(38 38 40 / 0.78)`), and its labels take the page's text color. A tab with no symbol sets its title at 14px
  instead of the 12px that sits under an icon. Checked by rendering the bar's real markup before and after, in light and dark,
  with and without symbols; nothing in an application needs to change.

- **A sidebar in a `NavigationSplitView` is a source list, not a bordered card.** The rows lost their frame and the
  hairlines between them, are rounded, and the selected row is filled with the tint (16%) instead of being underlined;
  the icons take the tint and sit in one fixed column so the labels line up, the column is a tinted gray, and a label
  that does not fit is cut with an ellipsis instead of wrapping. A section's rows lose the grouped card's rounded frame.
  A `Gauge` is drawn as a rounded bar filled with the tint (the browser's own green `<progress>` showed through in
  Chromium). Checked by rendering the Food Truck example's panels before and after, next to the same screens on an iPad;
  nothing in an application needs to change.
- **The asset catalog's `AccentColor` is the app's tint.** It sets `--tint-color` on the page, as Xcode's global accent
  color does, so `Color.accentColor`, tinted symbols, pickers, gauges and charts use it instead of the theme's near-black.
  A color set that names a system color (`"reference": "systemIndigoColor"`) compiles to that color's light and dark
  values; before, such a set was dropped. An app with no `AccentColor` looks as before, and `.tint(_:)` still overrides it.
  `.tint(.accentColor)` no longer makes the tint refer to itself (the browser drew a green progress bar for it).
- **A custom symbol with a content hash in its file name draws as a symbol.** The release step names a compiled catalog
  symbol `name.symbol.<hash>.svg`; the renderer only knew `name.symbol.svg`, so such a symbol was a picture at the
  SVG's own size (a donut as tall as the screen) instead of a tinted glyph sized by the text.

- **A sheet with no detents sizes to its content in Safari.** `.presentation-content` had `flex: 1`, whose basis is 0%, and
  Safari closed such a sheet up on its padding (a bar with nothing in it) while Chromium sized it to its content. The basis is
  now the content's own height (`flex: 1 1 auto`), so both engines draw the same sheet; a sheet with detents still fills its
  panel. Checked by opening the same sheet in Chromium and WebKit (576 by 334 in both) and by the presentation browser tests.

### API and behaviour found by the example apps

The small example apps ("Small apps" in `Examples/README.md`) are fifteen apps, each in its own `Examples/` folder, of ordinary iOS 17 SwiftUI compiled for the browser. Closing what it found added API and changed
some existing behaviour to match SwiftUI.

Added, with Apple's signatures: the C math functions (`sin`, `cos`, `tan`, `atan2`, `log2`, `hypot`...);
`Calendar.isDate(_:inSameDayAs:)`, `isDate(_:equalTo:toGranularity:)`, `dateInterval(of:for:)`, `range(of:in:for:)`,
`date(bySettingHour:minute:second:of:)`, the standalone symbol arrays and `DateInterval`;
`NotificationCenter.notifications(named:object:)`; `Path.addLines`, `addArc(tangent1End:tangent2End:radius:)`,
`strokedPath` and `contains`; `GraphicsContext.addFilter`, `concatenate` and `GraphicsContext.BlendMode`;
`colorInvert()`; `Button(_:systemImage:action:)`; `ContentUnavailableView.search`; `gridCellColumns`,
`gridCellAnchor`, `gridCellUnsizedAxes`, `gridColumnAlignment`; `ToolbarItemPlacement.bottomBar`; `ShapeStyle.bar`;
`Bindable(_:)`; `AppStorage` for `URL`, `Data` and `Int`-backed enums; `inlinePresentationIntent`;
`Image: Transferable`; `AVPlayerItem.didPlayToEndTimeNotification` and `failedToPlayToEndTimeNotification`;
`lineLimit` with a range. The lowerer accepts a key path passed as `whereSeparator:`, `where:`, `while:` or `by:`
and `Bindable(model).member`.

Behaviour that changed:

- **Time zone and week.** In the browser `TimeZone.current`, `Calendar.current` and the default `\.timeZone` are
  the browser's (they were fixed at UTC, so calendar arithmetic and date formatting disagreed by the local offset).
  `Calendar.firstWeekday` and `minimumDaysInFirstWeek` follow the browser's locale. Code that relied on UTC
  arithmetic sets `calendar.timeZone = .gmt` explicitly.
- **`convertFromSnakeCase`.** The Embedded key conversion capitalizes each word as Foundation does:
  `temperature_2m` is `temperature2M`, not `temperature2m`. A property named for the old spelling is renamed.
- **`String(format:)`.** Every arity goes through one printf engine: flags (`+`, `-`, `0`, `#`), width, precision
  and `%e %g %x %X %o %c` work with one to ten arguments. `import SwiftUIWebCore` alone no longer provides it; it
  is in `WebFoundation`.
- **`OpenURLAction.Result`** is a struct with static members, as in SwiftUI, and has `systemAction(_:)`. The
  default `openURL` action opens the URL (it discarded it). A `switch` over the old enum cases becomes `==`.
- **`overlay` and `background` builders are not escaping**, and a shape used as a background or overlay of a view
  with a `frame` is laid out in that frame, not in the window.
- **`.environment(\.colorScheme, .dark)`** makes its subtree dark (`data-color-scheme` with
  `data-color-scheme-scope`); it used to change the environment value only.
- **A `Label` in a toolbar item shows its icon only**, with the title as the accessible name, as in a navigation
  bar on iOS. `.labelStyle(.titleAndIcon)` on the label keeps both.
- **`minimumScaleFactor` shrinks a one-line text** to fit before truncating (it had no effect).
- **A link run in a `Text`** takes the tint colour and calls the `openURL` environment action.
- **`Canvas` has no background** (visual change to the base rule `.draw-canvas`, which painted the muted colour):
  a `Canvas` over other content no longer hides it. An application that relied on the grey gives the canvas a
  `.background`.
- **A NavigationStack that is the window's root** places its title in the bar row; it was drawn below the content.
- `GraphicsContext.blendMode` is a `GraphicsContext.BlendMode`; the view-level `BlendMode` gained `sourceAtop`,
  `destinationOver` and `destinationOut`, and `Material` gained the bar material.
- `Tools/run-browser-embedded.sh` builds a consumer from a checkout with any directory name.
- **`.spring()` and `.spring` no longer bounce.** As in SwiftUI, the response/damping spelling is the disfavored
  overload, so the unlabelled spring is `spring(duration: 0.5, bounce: 0)`, critically damped (it was
  `spring(response: 0.5, dampingFraction: 0.825)`, which overshoots). `.interactiveSpring()` is likewise
  `interactiveSpring(duration: 0.15, extraBounce: 0, blendDuration: 0.25)`. Added `.interactiveSpring` and
  `.interpolatingSpring`. Code that wants the old overshoot writes `.spring(response: 0.5, dampingFraction: 0.825)`.
- **The overloads SwiftUI disfavors are disfavored here too** (`@_disfavoredOverload`), so a call that more than
  one overload accepts resolves as in SwiftUI: the `StringProtocol` title spellings of `Toggle`, `Section`, `Menu`,
  `Picker`, `Stepper`, `DatePicker`, `MultiDatePicker`, `SecureField`, `NavigationLink`, `LabeledContent`,
  `GroupBox`, `ControlGroup`, `ProgressView`, `ContentUnavailableView`, `ColorPicker`, `ShareLink`'s
  `SharePreview`, `TableColumn` and `Tab`, and of `alert`, `confirmationDialog`, `searchable`, `badge`, `help`
  and the accessibility modifiers, give way to the `LocalizedStringKey` ones; `GeometryProxy.frame(in:)`, `DragGesture`
  and `SpatialTapGesture` with a `CoordinateSpace` give way to the `CoordinateSpaceProtocol` ones; `Shape.fill(style:)`,
  `tint(_: Color?)`, `URLSession.data(for:)`, `data(from:)` and `upload(for:from:)` (to the `delegate:` spellings), the
  `Stepper` and `Slider` spellings with `onEditingChanged:` before `label:`, and the optional-selection `TabSection`
  initializers; and as in the SDK `Color(_: UIColor)`, `ForEach` over a binding, `overlayPreferenceValue`,
  `backgroundPreferenceValue`, `dropDestination(for:action:isTargeted:)`, `Layout.callAsFunction` and `NSLocking.withLock`.
  `Slider(value:in:label:onEditingChanged:)` is no longer disfavored. `make swiftui-parity` checks the
  attribute against the SDK (`disfavored`, gated).
- **Presentations and pushes move as on iOS** (visual change to the entry and exit rules of `.sheet-panel`,
  `.full-screen-cover`, `.alert-panel`, `.confirmation-dialog`, `.popover-card` and `.navigation-destination`).
  They played short web-style fades (0.16 to 0.22 s, sliding 0.5 to 1 rem). Now, along UIKit's presentation curve
  (`cubic-bezier(0.32, 0.72, 0, 1)`): a sheet rises from below the screen in 0.5 s while the page dims behind it,
  and goes back down in 0.4 s; a full-screen cover rises from the bottom edge; an alert or a confirmation dialog
  settles from 1.15 times its size in 0.4 s and fades out; a popover grows in 0.3 s and fades out; a push slides the
  new screen in from the trailing edge in 0.5 s while the screen it covers moves a third of the way out behind it,
  and a pop plays that backwards. A destination that arrives with its stack (a tab, a sheet, a path set at once) no
  longer slides by itself. Toasts and tooltips keep their motion. Before: a sheet faded up 1 rem in 0.22 s and a pushed
  screen faded in from 0.5 rem in 0.18 s, over a blank stack; after: both travel their whole distance, with the screen
  underneath in view.
