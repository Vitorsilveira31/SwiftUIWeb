# Migration guide

This page lists the changes that need an edit in an application, release by release, with what to write instead. It
starts at the first public release; nothing before it is covered.

SwiftUIWeb follows SwiftUI's names and behavior, so most entries here are cases where the framework moved closer to
Apple's API. A change to the look of a component (its base rule in `Tools/styles.css`) is listed as well, with a
before/after comparison.

## Unreleased

### A sidebar's section titles keep their height (visual change)

- **A `TabSection` title in a sidebar no longer shrinks when the sidebar's tabs do not fit.** The sidebar list is a column of
  fixed height that scrolls, and a section title (`min-height: 0`, `overflow: hidden`) was a flexible item, so a list taller
  than the window squeezed each title to a few points and cut its text (9 of 24 points in a sidebar of 16 tabs and four
  sections), while the tabs kept their height. The title no longer shrinks (`flex: none`); the list scrolls instead. A
  sidebar whose tabs fit is unchanged.

### Lazy grid layout fixes (visual change)

- **A fixed item beside an adaptive one keeps its track.** `LazyVGrid(columns: [GridItem(.fixed(90)), GridItem(.adaptive(minimum: 120))])`
  laid out only the adaptive repetitions and dropped the 90 point column (7 tracks in a 1000 wide grid). It now lays out the
  fixed track and then as many adaptive tracks as fit in the width it leaves, as SwiftUI does (8 tracks). The template is
  `90px repeat(auto-fill, minmax(...))`; grids with only one kind of item are unchanged. A second adaptive item
  is a single track (it was dropped).
- **A `LazyHGrid` with adaptive rows is laid out in WebKit as in Chromium.** WebKit sized the grid's width from a pass that
  counted one row, so four rows of 100 wide cells gave 424 wide columns and a grid 3.4 times too long (11008 against 3232,
  with a scroll extent that changed while scrolling). The grid now has a percentage height (`height: 100%`, definite where
  its parent's height is), which both engines resolve to the same rows. Chromium is unchanged.
- **A cell of a lazy grid with an adaptive item takes the alignment of the column it is rendered in.**
  `LazyVGrid(columns: [GridItem(.fixed(90), alignment: .leading), GridItem(.adaptive(minimum: 120), alignment: .trailing)])`
  aligned a cell by its index modulo the two items, so with three columns the third cell of a row was leading and the
  fourth cell (the fixed column of the next row) trailing. The page now reads how many columns the browser made and aligns each
  cell as the item of its column does, and again when the window or the grid changes size. Grids whose items all align the
  same way, and grids without an adaptive item, are unchanged.

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

### Native builds format numbers and fold text as Foundation does

A native build (`swift test`, tools) has no browser, and the number format styles and `folding(options:locale:)` used
to hand back the raw value there: `28_300.formatted(.number.locale(Locale(identifier: "pt_BR")))` was `28300` and
`"Maré".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)` was `Maré`. They now give Apple's
Foundation output: `28.300`, `R$ 1.027,00` (with a no-break space) for `1027.formatted(.currency(code: "BRL"))` in
pt_BR, `74%` for `0.736.formatted(.percent.precision(.fractionLength(0)))`, and `mare`. The browser build is unchanged
(`Intl.NumberFormat` and the browser's folding) and none of this code reaches `app.wasm`.

- **Locales.** The native tables hold en_US, en_GB, pt_BR, pt_PT, de, fr, es, it, ja and en_US_POSIX, with Apple's
  currency symbols and fraction digits. Another region of those languages writes as the language's main one (es_MX
  as es); another language as Foundation's root locale (`1234.5`, `INF`). `Locale.current` has no visitor outside a
  browser and formats as en_US.
- **Folding** follows Foundation's rules on macOS, checked against it for every Unicode scalar: `.caseInsensitive`
  is Unicode case folding (`Straße` is `strasse`, `ﬁ` is `fi`), and `.diacriticInsensitive` drops the marks of Latin,
  Greek and Cyrillic letters while other scripts keep theirs (kana voicing, Hebrew points). Tests that expected the
  raw value natively expect Foundation's text now.

### A view's state is installed before its body and its actions

A view's `@State` and `@StateObject` used to join the view's identity when something first read them during a render.
An action that ran before that (`onAppear`, a button's action) read the value its own value of the view was created
with, and a property the body reads only later (behind a condition, or inside a `GeometryReader`) took the initial value
of whichever value of the view the parent made on that render. With a state assigned in `init` (`_engine =
State(wrappedValue: makeEngine())`) a parent that rendered again therefore left the action and the body on different
objects: a player whose `onAppear` started one engine while its picture showed another. Now, as in SwiftUI, every
`@State` and `@StateObject` of a view is installed before its body is first evaluated, so the body and the view's actions
share the storage of the view's identity, and a later value of the view keeps it: its initial value is discarded.

Nothing changes in an application unless it relied on the old behaviour, for example a view value that a parent
re-creates expecting its new initial value to replace the state: give the view another `.id(_:)` for that, as in
SwiftUI. The source lowering writes `_installState()` for each view that keeps state (`state-installation`); a view
nested in a private type, or a state declared inside an `#if` in the view, is still installed on its first read.

### The framework's modifiers declare `some View`

About a hundred modifiers declared a concrete result: `zIndex(_:)`, `blur(radius:)`, `scaleEffect(_:)`, `toolbar(_:for:)`,
`listStyle(_:)` and the others built on the same modifier returned `ModifiedContent<Self, _SemanticCompatibilityModifier>`,
and the browser's own ones (`webHoverUnderline()`, `documentHead(_:)`, `path(_:)`, `onKeyDown(perform:)`, the photo
picker) a `ModifiedContent` of their modifier. They declare `some View` now, as SwiftUI declares the ones it has.
`modifier(_:)` still returns `ModifiedContent<Self, Modifier>`.

- Code that spelled the concrete type (a property typed `ModifiedContent<Text, _SemanticCompatibilityModifier>`) writes
  `some View`, or `AnyView` where a type has to be named.
- `onDelete(perform:)` and `onMove(perform:)` come before those modifiers, as in SwiftUI
  (`ForEach(rows) { ... }.onDelete { ... }.listRowInsets(insets)`): after one of them the result is no longer a
  `DynamicViewContent`.

Behind that result every modified view of the framework is one type, which is what makes a release smaller
(`Performance/WASM_SIZE.md`). A modified view is still told from another by what it modifies and by its modifiers, so its
state and its `onAppear` follow the rules they did. One case differs: a generic view that holds a modified view (the
application's `Card<Content>` or the framework's `DisclosureGroup`, around `Header().padding()`) is named by its own
type whatever that content modifies, as it already was when it held several children. Its content is still replaced
when it becomes a view of another type; the holder itself, and a state of its own, are kept. Where the holder has to
become another view when its content does, give it an `.id(_:)`.

### Looks that changed

- **A `DOMViewRepresentable` takes the frame it is offered**, as a `UIViewRepresentable` without an intrinsic size
  does: a component in a 200 by 200 frame is 200 by 200 (it shrank to what its component drew, and sat centred in the
  frame). A component that should keep its own size gets a `.frame` of that size.
- **Charts look like Swift Charts on iPad** (measured on Food Truck's forecast). A mark with no style of its own takes
  the app's accent colour (`--tint-color`: the catalog's `AccentColor` or `.tint(_:)`), not blue; a gradient blends in
  OKLab, so its middle is lighter, as on iPad; axis labels are 10-point text in the secondary label colour; grid lines
  and ticks are 0.5-point separator lines, dashed (3 on 3) across the x axis; the plot keeps only the room its labels
  need (the y labels' column is as wide as its widest label, half a label above, 17 points below), and a date axis's
  labels start at their marks, the last one left out when it would run past the plot. A chart that relied on the
  blue default writes `.foregroundStyle(.blue)`.
- **`listItemTint(_:)` tints a list row's icon** (it had no effect): Food Truck's city rows in the sidebar,
  `.listItemTint(.secondary)`, have grey icons, as on iPad. It now returns `some View`, as in SwiftUI.
- **System colors are Apple's current palette** (iOS 26 and macOS 26): `Color.indigo` is `#6155F5` (dark `#6D7CFF`),
  `.blue` `#0088FF`, `.red` `#FF383C`, `.orange` `#FF8D28`, `.purple` `#CB30E0`, `.mint`, `.teal`, `.cyan`, `.brown`
  and the dark yellow and gray changed too, and so did the catalog references (`"reference": "systemIndigoColor"`) and
  `UIColor.systemBlue`. Food Truck's indigo accent was a darker purple than on iPad. An application that wants the old
  value writes it: `Color(red: 0.345, green: 0.337, blue: 0.839)` for the old indigo.
- **A sidebar has iPad's metrics.** In a NavigationSplitView's sidebar a `Label` puts its icon in a 30-point column,
  7 points before its title, so titles line up; the icon is 26 points with a 1.5-point line; a section header has
  18.75 points above its text and 9.5 below, in the secondary label colour at medium weight; the first row starts
  6 points lower. Labels elsewhere are unchanged.
- **A NavigationSplitView's columns meet** (visual change to the base rules `.navigation-split-view`, which put a
  16-pixel gap between the columns, and `.navigation-sidebar` and `.navigation-sidebar + .navigation-detail`, which drew
  1-pixel dividers). As on
  iPad, the detail starts at the sidebar's edge: Food Truck's header and cards sat 17 pixels away from the sidebar,
  behind a grey line. An application that wants the space pads the detail (`.padding(.leading, 16)`).
- **A `Canvas` has no border or rounded corners** (visual change to the base rule `.draw-canvas`, which drew a 1-pixel
  border in the border colour and `--radius-lg` corners). A `Canvas` is what its renderer draws, as in SwiftUI: Food
  Truck's animated header showed a frame and rounded corners the iPad does not. Before, a canvas over a card showed a
  thin grey outline with 8-point corners; now its drawing reaches its edges. An application that wants the old look
  writes it: `.clipShape(RoundedRectangle(cornerRadius: 8))` and
  `.overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))`.
- **`containerShape(_:)` shapes the views below it.** `ContainerRelativeShape` was a rectangle; it now takes the
  corner radius of the nearest `containerShape`, and a `.background()` without a shape fills that shape, as in SwiftUI
  (Food Truck's cards, `.background()` in a Grid that declares a 12-point rounded rectangle, are rounded). Without a
  `containerShape` above them, `ContainerRelativeShape` is a rectangle and a background leaves the view's own corners
  alone (a button's, a clip's).
- **Catalog images use their 2x file.** An image set with a universal 2x file whose size the asset compiler can read
  (PNG, JPEG, GIF, WebP) is copied to `catalog-assets/@2x/`, and the image is laid out at its size in points
  (`width` and `height` from `SWIFTUIWEB_IMAGE_SIZES`; canvas images and image paints are scaled by the density): images
  are as sharp as on a Retina screen and keep their size on every screen. Other sets are unchanged.
- **An automatic chart domain follows the marks its axis asks for.** With `AxisMarks(values: .automatic(minimumStride:
  desiredCount: roundLowerBound:))` the domain is rounded to the step those marks use, and the step is the round one
  whose count is closest to the one asked for, as in Swift Charts: Food Truck's forecast spans 55 to 85 °F marked every
  5 (it spanned 50 to 90, every 10). A chart without custom marks keeps its domain.
- **An empty background or overlay leaves its view alone.** `.background { if isHovering { … } }` while not hovering
  (or a background of `EmptyView()`) collapsed the view it decorates to 0×0 and stopped clicks on it: the stylesheet's
  rules for the background layer (`contain: size`, no hit testing) picked the layer as the first child, which is the
  view itself when the layer renders nothing. They now apply only when a layer is there, as do an overlay's. An
  application that kept an `else { Color.clear }` for this can drop it.
- **On a phone the page scrolls the document.** The screen's ScrollView scrolled inside a box of the window's height, so
  the page ended above a phone browser's bottom bar and the bars never shrank. On a touch screen the vertical ScrollView
  that fills the bottom of the window now hands its scrolling to the document: the page runs under the browser's bars,
  which shrink as it scrolls, and what sits above the scroll view (a header) stays at the top of the screen, as before.
  Nothing to change in an application: the scroll view's offset, `scrollPosition`, `ScrollViewReader`, lazy stacks and
  each tab's offset behave as they did. A window whose scroll view sits in a NavigationStack, a sidebar-adaptable
  TabView, a GeometryReader or a user-defined Layout keeps the scroll view's own scrolling. With a mouse nothing changes.
- **A push fades the new page in under a mouse.** A push slid the new screen across the whole window in half a second,
  as UIKit does on a phone. In a window driven by a mouse (`hover: hover` and `pointer: fine`) the new page now fades
  in where it lands, rising 12 pixels over 280 ms, over a page that stays put, and a pop fades it out, as web pages
  open one. A touch screen keeps the slide.
- **`AsyncImage(url:scale:transaction:content:)`.** The phase changes in the transaction given, so an animation in it
  plays the loaded image's transition (`image.transition(.opacity)` fades it in over its placeholder), as in SwiftUI.
- **An `AsyncImage` whose image the browser already holds shows it.** A loader created for a URL already on the page (a
  story on two cards) could fire its load before it joined the page, where the host never saw it, and the view stayed
  on its placeholder. A loader that joins the page loaded now reports its load, once.
- **A text under a `scaleEffect` keeps its width.** A one-line text in a scaled view (a card grown under the pointer)
  was measured at its drawn size against its unscaled box, taken for cut and capped narrower, and kept an ellipsis
  after the scale went back.
- **A pushed screen has no back button on the web.** `NavigationStack` drew a back button on every pushed screen, as
  an app's navigation bar does. A website has none: every push is an entry of the page's history, so the browser's
  back (or the phone's back gesture) pops it, and the bar now shows only the items the screen declares. A screen that
  should offer another way out declares it (a close button, a toolbar item); `navigationBarBackButtonHidden(_:)` has
  nothing left to hide. The compact `NavigationSplitView` keeps its back to the list, which is not a history entry.
- **A scroll view runs under a bottom `safeAreaInset`, as in SwiftUI.** The content and the inset were stacked, so a
  `ScrollView` ended where a floating bottom bar began and nothing scrolled under it. When the inset's content is a
  vertical scroll view (through its background, overlay, frame or padding), it now keeps its full height and the inset
  paints over it; the layout measures the inset and ends the scroll content with that room
  (`--safe-area-inset-extent`), so its last row still scrolls clear of the bar. Other content keeps the track above the
  inset.
- **A `LazyVGrid` column is never wider than the grid.** With `GridItem(.adaptive(minimum:))` and a minimum larger than
  the width the grid is offered (`.adaptive(minimum: 400)` in a 350-point phone column), the one column kept the
  minimum and the cells ran past the right edge of the screen. The column now takes the grid's width, as in SwiftUI;
  where the minimum fits, nothing changes. A `LazyHGrid`'s rows keep the plain minimum.
- **A lazy stack ends at its last row.** The spacer that stands in for the rows outside a `LazyVStack`'s or
  `LazyHStack`'s window took the stack's spacing even when it stood in for none, so every lazy stack ended (and began)
  with an extra gap. An empty spacer now takes no room and no spacing, as in SwiftUI.
- **A mobile tab's scroll view ends clear of the floating bar.** The last content of the shown tab scrolled under the
  bottom bar (the clearance rule waited for a marker nothing set). The layout now adds `--tab-content-clearance` (96
  points plus the home indicator by default) to the bottom of the outer vertical scroll view's content, as the iOS tab
  bar insets it; a scroll view inside it, a screen that hides the bar and the sidebar layout keep none.
- **Plain buttons and links keep the look around them.** Under `.buttonStyle(.plain)` a `Button` drew its label in the
  control font and colour and a `NavigationLink` in the tint, so a list mixing them read in two colours and two sizes.
  Both now inherit the font and foreground style, as in SwiftUI; a plain link also highlights and hit-tests its
  label's `contentShape` as a plain button does. A destructive plain or borderless button is red text, not a red fill.
- **`rectangle.portrait.and.arrow.right` draws a sign-out glyph** (Lucide's `log-out`) instead of the fallback dot.
- **Links do not underline under the pointer.** A `NavigationLink` underlined its label on hover, so every poster or
  card behind one underlined its titles, and a `Link` with a text label did too. Neither underlines in SwiftUI; an
  underline now shows only when the app asks for it (`.underline()`, `.buttonStyle(.link)` or the hover underline
  modifier).
- **A shape background or overlay is drawn at the size of the view it decorates.** In
  `.frame(width: 92, height: 92).background(.green, in: Circle())` the circle's path was computed for the window, so it
  came out about half the frame. A background with a shape, and an overlay on top of it, are now offered the frame's
  size, as in SwiftUI.
- **`stroke(style:)` and `stroke(lineWidth:)` draw in the foreground style.** A shape outlined without a colour was drawn
  in the page's text colour (`CanvasText`), so a `.foregroundStyle(.green)` on it was ignored. It now takes the
  foreground style, as in SwiftUI.
- **A resizable image takes the frame it is offered.** `Image(...).resizable().frame(width: 300, height: 200)` drew the
  picture with `object-fit: contain` at its own ratio, so a 4:3 picture was 300 by 225, past its frame and lower than the
  layers around it. `resizable()` now stretches the image to its frame, as in SwiftUI; `aspectRatio`, `scaledToFit` and
  `scaledToFill` still keep the ratio.
- **Transforms compose.** A `scaleEffect` or `rotationEffect` replaced an `.offset` (or another effect) on the same view,
  so `.offset(y: 540).scaleEffect(1)` drew the view at the top. The effects now apply in the order of the modifiers, as
  in SwiftUI.
- **A ZStack paints its children in order, the last on top.** CSS paints a positioned or transformed box after in-flow
  ones, so an earlier layer with an `.offset`, a clipped frame or a mask covered the content after it (a sign-in form went
  under its background art). Each child of a ZStack is now its own stacking context, painted in order; a `zIndex` still
  reorders them. A `z-index` inside a child no longer reaches past its ZStack sibling, as in SwiftUI.
- **A gradient mask fades the content by its alpha.** `.mask { LinearGradient(...) }` (or a `RadialGradient`) became a
  rectangle mask, so nothing faded. The gradient is now the CSS `mask-image`, as SwiftUI masks by the gradient's alpha.
- **A shape drawn without `fill` or `stroke` is filled with the foreground style.** `Circle()` or a custom triangle in a
  label drew nothing; SwiftUI fills it with the foreground style, and so does the page now.
- **A navigation bar is transparent at the scroll edge, as on iOS.** The bar always drew its material and hairline, as if
  content were scrolled under it. It is now transparent while the screen on top of the stack sits at its top, and takes the
  material and hairline once its vertical scroll view scrolls under it (the host marks the view with `data-scrolled`). A
  screen whose background fills the window (a reader's paper) shows through the bar; an app that made the bar transparent
  with its own CSS can drop it.
- **A view that ignores the safe area runs under the navigation bar, as on iOS.** A screen of a NavigationStack is laid
  out below the bar (its safe area) and the bar is drawn over it, but `.ignoresSafeArea()` only made a view fill its own
  box, so a reader's paper (`ZStack { paper.ignoresSafeArea(); … }`) stopped at the bar and the window's background
  showed behind the back button. Now a view that ignores the safe area, fills the height it is offered and reaches the
  top of the screen grows up to the top of the stack, under the bar; a background layer
  (`.background { color.ignoresSafeArea() }`) does too. The rest of the screen still starts below the bar, and a view of
  a fixed height, one that does not reach the top, one inside a scroll view and one under a hidden bar stay where they
  were. An application that pulled such a view up with its own CSS can drop it.
- **A VideoPlayer that takes no touches shows no controls.** Under `.allowsHitTesting(false)` (on the player or a
  container) the AVKit controls stayed on screen, inert, over a player screen that draws its own transport. On iOS they
  appear only in answer to a touch, so they never show there; the page now hides them too, and the app no longer needs CSS
  of its own for it.
- **A NavigationLink or a Link whose label fills its row fills it.** The page laid an `<a>` out as a closed box the size
  of its text, so a link whose label is `.frame(maxWidth: .infinity)` (the wide pill of a hero's primary action, beside a
  48-point button) hugged its text, and a pill with a fixed height clipped it. A NavigationLink or a Link without a
  bordered style now passes the proposal to its label, as a plain `Button` already did. Checked in a browser against the
  same screen on an iPad: the pill is 502 px wide in a 600 px column where it was 92. A link whose label does not fill
  keeps its width; nothing in an application needs to change.
- **A mouse drag over a view that a `DragGesture` moves selects no text.** Dragging a carousel with a mouse selected the
  titles it crossed, which iOS and Android never show. Text outside a drag gesture stays selectable.
- **A pushed screen that hides the tab bar is as wide as the page.** `toolbar(.hidden, for: .tabBar)` removed the sidebar
  of a `sidebarAdaptable` TabView but kept its inset, so a pushed detail sat beside a 248-pixel empty band. The band is
  gone, as on an iPad; the sidebar and its inset come back when the screen is popped.
- **A NavigationLink draws its label through an app-defined `ButtonStyle`.** SwiftUI treats a link as a button, so
  `.buttonStyle(PrimaryButtonStyle())` on a NavigationLink fills it as it fills a Button; the page drew the bare label.
  The style receives `isPressed` as it does for a Button. Built-in styles are unchanged.
- **A menu Picker with hidden labels is a menu button, as on iOS and iPadOS.** `Picker(…).pickerStyle(.menu).labelsHidden()`
  rendered a chrome-less select in the inherited color, which an application then decorated itself. It now shows the
  selected value in the tint with the up-and-down chevrons after it, still without a field border or background. An
  application that drew its own chevron next to one should drop it, or put a `Picker` in a `Menu` with its own label, as
  it would on iOS.
- **A Button inside a view with a `DragGesture` acts on a click or a tap.** The page captured the pointer for the gesture as
  soon as it went down, so the release and the click went to the gesture's view and the button never ran its action (the
  play button of a player whose controls sit in a swipe-to-dismiss view). The pointer now stays with the control until it
  moves farther than a tap, then the drag takes it, as in SwiftUI.
- **A `Picker` in a `Menu` lists its options as the menu's items**, a checkmark before the selected one, as in SwiftUI; it
  drew a select inside the menu.
- **The back button of a pushed screen has the native bar's leading inset**: 16 points from the edge, as on iOS and
  iPadOS. It was pulled 4 points toward the edge.
- **The floating tab bar of a phone is as wide as iOS draws it**: about 99 points a tab, centered, with a 16-point margin
  on a narrow screen. It hugged its titles. Each tab's symbol and title sit together in the middle of the tab, with the
  same space above and below; the title used to fill the rest of the tab and pushed the symbol to the top.
- **A switch knob is white in dark appearance too**, as SwiftUI draws it; it was the inverse of the primary color.
- **More SF Symbols have a glyph.** `paintbrush`, `paintbrush.pointed`, `shield`, `calendar.badge.clock`,
  `calendar.badge.exclamationmark` and `chevron.up.chevron.down` drew nothing.
- **One typeface for all text.** The base gave `<html>` the stack `Inter, ui-sans-serif, system-ui, -apple-system, …`, while
  the text styles (`.font(.title)`, `.headline` and the rest) use the system stack (`-apple-system, BlinkMacSystemFont,
  system-ui, …`). On a machine with Inter installed, text without a `.font` was drawn in Inter beside titles in San
  Francisco, in the same card. Every text now uses the system stack, as SwiftUI draws it. An application that wants Inter
  sets it through `--default-font-family`.

- **A `Link` with a custom label is not underlined under the pointer.** Every `Link` underlined its label on hover, so a
  link drawn as a pill, a button or a card grew a line under its text. Only a link whose label is plain text
  (`Link("Docs", destination:)`) is underlined now; one with a custom label keeps its look, as in SwiftUI.

- **A segmented `Picker`'s segments are as wide as the widest label.** The segments were a flex row that shared the track
  in equal parts of the sum of the labels, so with `.fixedSize()` (or anywhere the picker hugs its content) the longest label
  had less than its width and wrapped onto two lines: "4x slower" beside "Normal" was a segment 48 px tall. The track is now a
  grid of equal columns, each the widest label's width where the picker hugs its content and an equal share of the track
  where it fills, as `UISegmentedControl` sizes them; the control is 32 px tall again, one line per label (Apple: 24 pt).
  Checked on the site's Performance page and the lowering app's layout parity fixture before and after, in Chromium and
  WebKit; nothing in an application needs to change.

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

- **`matchedGeometryEffect` moves a view from where it was, not from the layout's own box.** A view that follows a source and
  moves to another one (a segmented control's thumb) started its move from the size the layout gave it when the commit rewrote
  its box (a background layer is as wide as what it sits behind), so it opened to the whole control and then shrank onto the
  new tab. The host now remembers where it put the view (and how far along its move was, if one was playing) and moves from
  that. Checked by sampling the thumb during the move (57 to 69 px wide on the way, where it was 208 before) in Chromium and
  WebKit; nothing in an application needs to change.
- **A `.fill` symbol is solid for the closed shapes.** `heart.fill`, `star.fill`, `bell.fill`, `bookmark.fill`, `bolt.fill`,
  `moon.fill`, `flame.fill`, `circle.fill` and `square.fill` were drawn as the same outline as their plain names; they are filled
  with the text color now. The other `.fill` names (a check in a circle, an arrow) are still outlines.

### Release bundles ship two WebAssembly modules

A release build splits `app.wasm` by what the first screen runs (`Architecture/WASM_SPLIT.md`): `app.<hash>.wasm` downloads
before the first screen and `app-rest.<hash>.wasm` right after it. Deploy and cache the second file like the first (the
same headers, content type `application/wasm`); a host that only copies `app.*.wasm` must copy `app-rest.*.wasm` too. The
build machine needs Binaryen's `wasm-split` and a headless Chromium; without them the build ships one `app.wasm` and says
so in a warning. `SWIFTUIWEB_WASM_SPLIT=0` keeps one module.

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
