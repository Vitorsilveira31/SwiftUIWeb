# Browser application shell and styling

This guide covers the browser-side customization points an application uses to
match a design system without platform branches in Swift: the document-head
hook, the `TabView` `.sidebarAdaptable` shell, custom fonts and rich text,
chrome-less form controls and icons. Application Swift stays ordinary
SwiftUI source that also compiles for Apple platforms; the few browser-only
APIs (`.documentHead`, for example) go under `#if canImport(SwiftUIWebWeb)` in
code shared with an Apple app ([sharing code](SHARING_CODE.md)).

## Document-head hook

A consumer package can ship browser-only static files in a `Web/Resources/`
directory next to its browser target (`Resources/` at the package root also
works, and `SWIFTUIWEB_RESOURCES` names any other). The Embedded browser build
copies it next to `index.html`, following symbolic links so a file shared with
another target (fonts) lives in one place, and two optional files form the head
hook (`Tools/inject-app-head.mjs`):

| File | Effect |
| --- | --- |
| `Resources/head.html` | HTML fragment inserted into `<head>` right after the framework `styles.css`. A `<title>` or `theme-color` `<meta>` in the fragment replaces the template default. |
| `Resources/app.css` | Linked after the fragment. Unlayered application CSS always wins over the framework's layered framework styles, so it can override `--color-swu-*` tokens and the custom properties below. |

### Content-Security-Policy

The page ships with a policy, written into `index.html` as the last build step (`Tools/seal-csp.mjs`, which hashes the
page's inline bootstrap scripts):

```
default-src 'self'; script-src 'self' 'wasm-unsafe-eval' <inline-script hashes>; style-src 'self' 'unsafe-inline' https:;
img-src * data: blob:; font-src * data:; media-src * data: blob:; connect-src * data: blob:; frame-src * data: blob:;
worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'
```

The page runs its own files and WebAssembly and nothing else: no script from another origin, no inline handler, no
`javascript:` address, no `eval` or `new Function`, no plugin. That keeps injected markup from running code even if a value ever reaches the
page unescaped. Requests, images, media, fonts and frames may go to any origin, because an application talks to its own
APIs and embeds what it needs; tighten those in your own policy.

What this means for an application:

- A `<script>` in `head.html` must be a file on your own origin. An inline script or one from a CDN (an analytics tag, for
  example) is blocked until you declare a policy that allows it.
- No bundle gets `'unsafe-eval'`. `DOMViewRepresentable` does not run script text: Swift names a component and sends it
  a state string, and the component is a function the application registered from one of its own files (next section).
  Tools/seal-csp.mjs has no flag to loosen the policy, and Tools/test-csp-bundles.mjs fails a bundle that evaluates a string.
- **To replace the policy,** put your own `<meta http-equiv="Content-Security-Policy" content="...">` in `head.html`. It
  replaces the default as a whole (two policies would both have to allow a script, so the default cannot be loosened by
  adding another).
- The page is checked by the Showcase browser test, which fails on any blocked script, eval or frame.

### DOM components

A `DOMViewRepresentable` mounts a JavaScript component (a map, a chart, a three.js stage, Blockly) in a ShadowRoot of its
own. The application registers the component in the page; Swift only names it and sends a `String` state:

```swift
DOMView(component: "stage", state: sceneJSON)     // makeDOMView(context:)
domView.state = sceneJSON                          // updateDOMView(_:context:)
```

```js
SwiftUIWebDOMComponents.define("stage", () => ({
  mount(host, root, emit, state) { /* build into root; emit(text) sends a message to DOMView.onMessage */ return instance; },
  update(instance, state) { /* apply the new state to the same instance */ },
  dispose(instance) { /* optional: release listeners, GPU resources, workers */ },
}));
```

- **Where the code lives.** A file on your origin (`script-src 'self'`). The state is data the component parses itself
  (JSON, say); it is never evaluated.
- **When to define.** `SwiftUIWebDOMComponents` exists once the framework has started. A script that runs earlier (a module
  in `head.html`) pre-creates it as a queue, and the framework adopts it:
  `(globalThis.SwiftUIWebDOMComponents ??= { queue: [], define(name, factory) { this.queue.push([name, factory]); } }).define(name, factory)`.
  A script injected later calls `define` on the live registry.
- **Lazy code.** The factory runs on the first mount of the name, and may return a Promise: load the component's code there
  (`() => import("./stage.js").then((module) => module.default)`) and a large bundle is fetched only when a view first
  shows it. A factory that fails is retried by the next mount.
- **Timing.** The Swift lifecycle is synchronous. If the component is not defined (or still loading) when the view
  mounts, the mount waits, keeps the latest `state`, and runs when the component is ready; removing the view first cancels
  it. `mount` itself must return the instance synchronously.
- **Failures** are lifecycle errors, never an `EvalError`: a console error under `[SwiftUIWeb]` and a `data-dom-view-error`
  attribute on the host element. A name still undefined ten seconds after the view mounted is reported once (it still
  mounts when defined later).

### What an application may customize

The component rules of `styles.css` are the framework's own and are not an extension point: views add to them through
modifiers (inline values and attributes on the node), and an application restyles through tokens. Supported:

- the design tokens in `@layer theme` (`--color-swu-*`, `--radius-swu`, `--spacing`, the type and easing scales);
- `--tint-color`, the tab shell's `--tab-*` properties, the switch's `--switch-*` and the shared `--layout-*` tokens.

Class names and `data-*` attributes are internal and may change between releases. `Tools/lint-styles.mjs` keeps each
component's base rule in one place by failing when a later rule with the same selectors makes a declaration dead.

Example `Resources/head.html`:

```html
<title>My Studio</title>
<meta name="title-template" content="%s · My Studio">
<meta name="tab-breakpoints" content="720,1100">
<meta name="tab-labels" content='{"expand":"Expand menu","collapse":"Collapse menu","open":"Open menu","close":"Close menu","openWithBadge":"Open menu, {count} waiting","activity":"working","navigation":"Main navigation"}'>
<meta name="theme-color" content="#F3F2F7" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#121118" media="(prefers-color-scheme: dark)">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700&family=Newsreader:opsz,wght@6..72,400;6..72,500;6..72,600&display=swap">
```

Dark-mode values belong under `[data-color-scheme="dark"]`; the framework sets
that attribute from the system preference or `.preferredColorScheme(_:)`.

The browser lays out the application with CSS flexbox and grid (see `Documentation/Architecture/CSS_LAYOUT.md`).

### Document title

`.navigationTitle(...)` updates `document.title`: the innermost visible title
(inactive tabs, covered navigation roots and presentations are ignored) is
formatted with the optional `title-template` meta (`%s` is the
title). Without a visible title the document keeps the `<title>` from the
head.

### Document head per screen

`head.html` is static: it applies to the whole app and is fixed at build time. A screen that needs its own
`<meta>` or `<link>` (a different tab icon, a `description`, `robots`, a `theme-color`) declares it with
`.documentHead`, which lives in `SwiftUIWebWeb` because SwiftUI has no equivalent:

```swift
import SwiftUIWeb
#if canImport(SwiftUIWebWeb)
import SwiftUIWebWeb
#endif

OrdersScreen()
#if canImport(SwiftUIWebWeb)
  .documentHead {
    HeadElement.favicon("/icons/alert.png")
    HeadElement.meta(name: "robots", content: "noindex")
    HeadElement.themeColor("#121118", media: "(prefers-color-scheme: dark)")
  }
#endif
```

`HeadElement` has `favicon(_:type:sizes:media:)`, `meta(name:content:)`, `meta(property:content:)` (Open Graph),
`themeColor(_:media:)` and `canonical(_:)`. The block accepts `if`, `else` and `for`.

- **Same rule as the title.** Only visible screens count: inactive tabs, covered navigation roots, hidden subtrees and
  presentations are ignored. When two visible screens declare the same element, the inner one wins. An element is
  identified by its tag, its `rel` (link) or `name`/`property` (meta), and its `media` and `sizes`, so a light and a dark
  `theme-color` coexist.
- **The static head comes back.** An element from `head.html` is replaced while a screen overrides it and is put back where
  it was when the screen leaves.
- **Only `<meta>` and `<link>`.** The host ignores any other tag and any attribute outside `rel`, `href`, `type`, `sizes`,
  `media`, `name`, `property` and `content`, so a screen cannot inject a script or a `refresh`.
- **Guard it like any web-only API.** The module is not imported on Apple platforms, so the call goes inside
  `#if canImport(SwiftUIWebWeb)` (an app can equally use its own `WEB` flag, as `Examples/UniversalApp` does).

### Readable addresses per screen

A `TabView` puts its selection in the address as `?tab-selection=<hash>`: it reloads and goes Back correctly, but it cannot be
shared or read. A screen that wants a real address declares it with `.path`, which lives in `SwiftUIWebWeb` next to
`.documentHead` because SwiftUI has no equivalent:

```swift
ComponentsScreen()
  .tabItem { Text("Components") }
  .tag(Page.components)
#if canImport(SwiftUIWebWeb)
  .path("en", "components", selectedComponent)   // /en/components/slider
  .navigationTitle("Slider · Components")
#endif
```

- **Same rule as the title.** The innermost visible screen's path is the page's address: the selected tab, or the
  destination a `NavigationStack` shows. The segments are joined with `/`, percent-escaped, and empty ones are dropped, so
  they can be built from state; `.path(_: [String])` takes an array.
- **The address follows the screen.** Selecting another tab pushes a history entry whose address is that tab's path, and
  Back and Forward return to it. A path that changes while the screen stays (another catalog entry, another language)
  replaces the address of the current entry and adds nothing to the history. The `?tab-selection` the framework wrote
  goes away when a path covers it.
- **Opening an address reaches the app through `onOpenURL`.** A link, a reload and Back or Forward to an older entry deliver
  the address to the `onOpenURL` handler, which puts the app's state where the path says. That handler is what makes the two
  directions agree; `Examples/ShowcaseSite` reads `/pt/components/slider` into a language, a page and a catalog entry
  (`SiteRoute`). On a first visit the address of the default screen replaces `/`.
- **The server must answer every address with `index.html`.** `Tools/bun-server.ts` does. A static host needs a rewrite
  rule (a fallback to `/index.html`) for the paths the app declares. The page's `<base href="/">` keeps the bundle's files
  found from nested addresses.
- **Titles and the head come with it.** `.navigationTitle` sets `document.title` and `.documentHead` the `<meta>` tags of
  the screen, as above, so a shared link has the right title and description once the page runs. The page is still drawn
  in the browser: a crawler that does not run scripts sees the static head only.

## First paint

A release build can put the first screen into `index.html`, so the page paints it as soon as the HTML and the stylesheet are
there, before the wasm is requested, and the runtime takes it over when it mounts. Design, limits and measurements:
[Architecture/FIRST_PAINT.md](Architecture/FIRST_PAINT.md).

```sh
SWIFTUIWEB_FIRST_PAINT=1 CONFIGURATION=release make run site        # or Tools/run-browser.sh <example>, or the SwiftPM plugin
```

| Variable | Meaning |
|---|---|
| `SWIFTUIWEB_FIRST_PAINT=1` | Turns it on (release only). Absent or `0`: the page is the page it was. |
| `SWIFTUIWEB_FIRST_PAINT_ROUTE` | The route that is captured (default `/`). |
| `SWIFTUIWEB_FIRST_PAINT_VIEWPORT` | The viewport of the capture, `WIDTHxHEIGHT` (default `1280x1200`); the page is prerendered for viewports no taller than it, over the widths the build verified. |
| `SWIFTUIWEB_FIRST_PAINT_VERIFY=0` | Skips the verification (never for shipping). |

The step needs headless Chromium (`bunx --bun playwright install chromium`) and fails the build, naming the pixels that
differ, when what the runtime shows first is not what was captured: a screen that shows data from a request, a clock or a random
value cannot be prerendered. It adds one inline script to the page (about 1 KB), allowed by hash in the policy: no `unsafe-eval`,
no new origin. An application with its own policy needs a `script-src` in it.

## Split module

A release build splits `app.wasm` by what the first screen runs: `app.wasm` keeps those functions and downloads before the
screen, `app-rest.wasm` holds the rest and downloads right after it. A call that needs a function of the rest before it
arrived waits for it; nothing fails. Design, measurements and limits: [Architecture/WASM_SPLIT.md](Architecture/WASM_SPLIT.md).

```sh
CONFIGURATION=release make run site                                  # split; SWIFTUIWEB_WASM_SPLIT=0 for one app.wasm
```

| Variable | Meaning |
|---|---|
| `SWIFTUIWEB_WASM_SPLIT` | Absent: a release splits, or ships one `app.wasm` with a warning when it cannot. `0`: one `app.wasm`. `1`: a split that cannot be made fails the build. Debug never splits. |
| `SWIFTUIWEB_WASM_SPLIT_CACHE` | `0` makes every build profile again instead of reusing the split of unchanged inputs (`.build/wasm-split-cache`). |
| `SWIFTUIWEB_WASM_SPLIT_ROUTE` | The route whose first screen is profiled (default `/`). |
| `SWIFTUIWEB_WASM_SPLIT_VIEWPORTS` | The viewports profiled, `WIDTHxHEIGHT,...` (default `1280x800,390x844`: the regular and the compact layout). |

The step needs Binaryen (`wasm-split`, `wasm-opt`) and headless Chromium (`bunx --bun playwright install chromium`);
`bun Tools/wasm-split-release.mjs --check` says whether this machine has them.

## TabView `.sidebarAdaptable` shell

```swift
TabView(selection: $route) {
  Tab("Home", systemImage: "house", value: .home) { HomeScreen() }
  Tab("Reviews", systemImage: "eye", value: .reviews) { ReviewsScreen() }.badge(3)
  Tab("Production", systemImage: "waveform.path.ecg", value: .production) { JobsScreen() }.badge("•")
  TabSection("Studio") {
    Tab("Settings", systemImage: "gearshape", value: .settings) { SettingsScreen() }
  }
}
.tabViewStyle(.sidebarAdaptable)
.tabViewSidebarHeader { BrandHeader() }       // logo + wordmark
.tabViewSidebarFooter { MobileActions() }     // mobile panel only
.tabViewSidebarBottomBar { AccountRow() }     // avatar + name
```

The browser host (`Tools/tab-shell.js`) chooses the presentation
from the viewport width and sets `data-tab-layout` on the tab view:

| Width | `data-tab-layout` | Behavior |
| --- | --- | --- |
| `≤ first breakpoint` | `mobile` | No sidebar. A 60px floating menu button (bottom-right, safe-area aware) opens a navigation panel over a blurred backdrop. The panel lists the tabs and then the sidebar footer; Escape, the backdrop and a tab selection close it; focus is trapped while open and returns to the button. The button shows the sum of numeric tab badges. |
| `≤ second breakpoint` | `rail` | Collapsed 72px icon rail by default. The toggle expands it for the session (not persisted). |
| wider | `sidebar` | Expanded 248px sidebar by default. The toggle choice is persisted in `localStorage`. |

The defaults are `767,1199`; `<meta name="tab-breakpoints"
content="720,1100">` overrides them. `tab-labels` localizes the
toggle/button labels (`expand`, `collapse`, `open`, `close`,
`openWithBadge` with a `{count}` placeholder, `activity`, `navigation`).

Placements:

- **Header** (`tabViewSidebarHeader`): the 64px top row, before the collapse
  toggle (36px, `sidebar.left` icon). When the sidebar collapses the header
  content hides and the toggle grows to 44px and shows a copy of the first
  `Image` in the header (the app logo); hovering or focusing it swaps back to
  the sidebar icon.
- **Footer** (`tabViewSidebarFooter`): shown only in the mobile panel, after
  the tabs (for actions that the desktop top bar already exposes). Set
  `--tab-sidebar-footer-display: block` to show it in the sidebar too.
- **Bottom bar** (`tabViewSidebarBottomBar`): pinned below the tabs with a top
  border and 12px padding. The collapsed rail keeps only the first element of
  its stacks (for example an avatar) centered. Hidden in the mobile panel.

Header, footer and bottom-bar content are laid out by CSS layout
as independent roots sized by their slot, so frames, padding, shapes and
stacks behave as in the rest of the app.

Collapsed rail: section titles become 1px separators, tabs are 44px icon
buttons, badges move to the icon's top-right corner, and a tooltip with the
tab title (plus a numeric badge) appears on hover/focus.

### Badges

- `Tab(...).badge(3)` renders a 20px pill.
- `Tab(...).badge("•")` is the **activity convention**: a pulsing 8px dot
  painted with `--tab-ribbon` instead of a count. It is hidden from
  assistive technology; the tab's accessible name gets the localized
  `activity` label ("Production, in progress"). Activity dots do not count
  toward the mobile button badge.

### Style variables

Every color and size is a custom property with a framework-token fallback.
Set them on `:root` (and `[data-color-scheme="dark"]`) in `app.css`:

| Property | Meaning |
| --- | --- |
| `--tab-background` | Page background behind the shell, mobile button icon, button badge ring |
| `--tab-panel` | Sidebar and mobile panel surface |
| `--tab-line` | Borders and separators |
| `--tab-ink` | Primary text, hover text, mobile button and tooltip fill |
| `--tab-ink-secondary` | Tab labels |
| `--tab-muted` | Collapse toggle icon |
| `--tab-soft` | Section titles |
| `--tab-sunk` | Hover background |
| `--tab-accent` | Selected tab text and focus ring |
| `--tab-accent-soft` | Selected tab background |
| `--tab-warn` / `--tab-warn-background` | Badge text / fill |
| `--tab-ribbon` | Activity dot paint (default `linear-gradient(90deg,#63CDF2 0%,#A688F2 38%,#F08BC2 70%,#F7C18A 100%)`) |
| `--tab-overlay` | Mobile backdrop color |
| `--tab-shadow` / `--tab-shadow-lg` / `--tab-fab-shadow` | Tooltip / mobile panel / mobile button shadows |
| `--tab-sidebar-expanded-width` / `--tab-sidebar-rail-width` | 248px / 72px |
| `--tab-content-clearance` | Space kept after the last content on mobile so the floating button never covers it (default 96px + safe area) |
| `--tab-sidebar-footer-display` | Footer display in sidebar/rail (default `none`) |

The content column stays a plain scroll container: applications render their
own top bar inside each tab. On mobile, the outer vertical `ScrollView` of the shown tab ends with
`--tab-content-clearance` of room (the layout adds `--scroll-end-clearance` to
the bottom padding of its last content), so it scrolls clear of the floating bar.

## Custom fonts and rich text

- `Font.custom(_:size:)`, `Font.custom(_:size:relativeTo:)` and
  `Font.custom(_:fixedSize:)` emit
  `font-family: var(--asset-font-<slug>, "<Name>", system-ui, …, sans-serif)`.
  The slug is the lowercase ASCII name with separators as `-`, so
  `--asset-font-newsreader: "Newsreader", Georgia, serif;` supplies a serif
  fallback stack. `.weight`, `.bold()`, `.italic()`, `.monospacedDigit()`
  chain as usual. Browsers have no Dynamic Type; `relativeTo:` keeps the
  requested size. Text is re-measured when `document.fonts` finishes loading.
- `Text` has the SwiftUI Text-returning modifiers (`bold()`, `fontWeight(_:)`,
  `italic()`, `font(_:)`, `foregroundColor(_:)`, `foregroundStyle(_:)`,
  `underline()`, `strikethrough()`, `monospacedDigit()`, `kerning(_:)`,
  `tracking(_:)`, `baselineOffset(_:)`, `fontDesign(_:)`) and `Text + Text`.
  A concatenation renders as one text leaf with inline styled runs, so it
  wraps as a paragraph, honors `lineLimit`/`multilineTextAlignment`, and keeps
  the concatenated string for accessibility. Modifiers on the concatenation
  style the paragraph; a run's own modifiers take precedence.

```swift
(Text("8 tasks need you").fontWeight(.semibold).foregroundColor(ink)
  + Text(" and ")
  + Text("1 job is").bold()
  + Text(" running."))
  .font(.custom("Figtree", size: 14.5))
  .foregroundColor(muted)
```

## Chrome-less controls

These SwiftUI spellings emit `data-field-chrome="plain"`: the native control has
no framework border, background, padding, radius or max width, inherits font
and color, and fills the box assigned by layout, so the application draws the
field with ordinary modifiers (`.padding`, `.frame`, `.background(_:in:)`,
`.overlay`). Default looks are unchanged.

| SwiftUI | Web control |
| --- | --- |
| `TextField` / `SecureField` + `.textFieldStyle(.plain)` | plain `<input>`; horizontally greedy in stacks like SwiftUI's `TextField`, as a field with the default look is too |
| `TextEditor` + `.scrollContentBackground(.hidden)` | plain `<textarea>` |
| `Picker` + `.pickerStyle(.menu)` + `.labelsHidden()` | native `<select>` without the title, border or background: the selected value in the tint followed by up-and-down chevrons, as iOS draws a menu button |
| `DatePicker` + `.labelsHidden()` + `.datePickerStyle(.compact)` | plain native `<input type="date">` (`.date`), `type="time"` (`.hourAndMinute`) or `datetime-local` |

The style modifiers are inherited through the environment, as in SwiftUI, so
they can be applied to a container. `.labelsHidden()` alone also hides the
Picker/DatePicker title.

`Toggle` switch geometry is overridable: `--switch-width` (2.75rem),
`--switch-height` (1.5rem), `--switch-knob-size` (1.25rem),
`--switch-knob-inset` (2px), `--switch-knob-travel` (1.25rem),
`--switch-border-width` (1px), `--switch-track`,
`--switch-track-on` and `--switch-knob`. `.tint(_:)` still colors the
on state. A 42×24 switch with an 18px knob uses width 42px, knob 18px, inset
3px, travel 18px and border 0px.

## Redacted placeholders

`.redacted(reason:)` marks a subtree and the stylesheet draws it (`Tools/styles.css`). With `.placeholder`, which is SwiftUI's
skeleton, each text run becomes transparent over a rounded bar in `--color-swu-muted` (so it follows light and dark), and each
shape, picture and symbol becomes a flat neutral block. The blocks pulse by opacity alone, so the compositor runs them and
layout does not move; controls under the skeleton take no pointer events. The text stays in the DOM and the subtree keeps
`aria-busy="true"`, so assistive technology hears that content is loading without reading the placeholder text.

`.redacted(reason: .privacy)` blurs the subtree. `.unredacted()` ends the redaction rules at its node (its `unredacted` class
is the scope limit of an `@scope` rule), so the subtree paints as it would without the modifier. A privacy blur is a filter
on the redacted node itself, so an `.unredacted()` child of a privacy-redacted node stays blurred; placeholders have no such
limit. `@scope` is supported by current Chromium and WebKit; elsewhere the skeleton rules are ignored, so the text is not
hidden. With `prefers-reduced-motion: reduce` the skeleton is still drawn and only the pulse stops.

## Matched views

`matchedGeometryEffect` (for the source, `isSource: true`) and `matchedTransitionSource` name their element with a
`view-transition-name` style, unique per namespace and id. When a commit applies a change that names such an element, the page
runs that commit inside `document.startViewTransition`, one frame later, and the browser animates the change. The final DOM is
the same as without the transition. No transition starts while the user types, in the 150 ms after a scroll, while the page is
hidden, with `prefers-reduced-motion: reduce`, or where the API is missing. Two rendered sources with one name skip the
transition (the browser would abort it) and the DOM is still applied. `navigationTransition(.zoom(sourceID:in:))` on a pushed destination zooms from a source in the same `NavigationStack`
that was rendered before it (the root, or an earlier destination). While that destination is on the stack the source gives its name
up, so the name is on one element at a time: the zoom grows from the source's frame to the destination. Popping gives the name back
to the source. A zoom with no matching source, and `.automatic`, are plain pushes. A source inside a nested stack is zoomed from
only by a destination of that same inner stack.

## Icons

`Image(systemName:)` is realized with Lucide icons. The stroke width follows
`--icon-stroke-width` (default 2; for example 1.7 for a lighter set).
The SF Symbol → Lucide catalog lives in
`Sources/SwiftUIWebBrowser/LucideIcons.swift`; only reachable symbols are
emitted into the bundle.

## What the generated `index.html` loads

The bootstrap `index.html` carries only the scripts the reachability manifest
lists as initial (`feature-loader.js` when a provider/image/media
feature is reachable, `icon-adapter.js` for the icon adapter,
`mesh-gradient.js` when `MeshGradient` is used), then the module
entry `index.js`. The page applies the binary updates Swift sends to the DOM
(`Tools/embedded-dom.js`; the format is in
[`Architecture/BINARY_PATCHES.md`](Architecture/BINARY_PATCHES.md)).
