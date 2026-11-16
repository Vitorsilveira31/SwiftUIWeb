# Release reachability

`Tools/release-reachability.js` decides which optional browser features a
release bundle carries. SwiftPM and LLVM still own Swift symbol reachability;
this planner covers what Swift cannot see: the `SWIFTUIWEB_RELEASE_HAS_*`
compile gates, runtime helper scripts, the icon catalog and optional CSS.

## Evidence rule

- **Application evidence** (`--source`) is the consumer's own code: for an
  external package its `Sources` and `Web`; for the framework's examples and test apps
  only `Examples/<product>` or `Tests/Apps/<product>`. Only this text switches a feature on (`MeshGradient`,
  `Canvas`, `onDrop`, `onHover`, `PhotosPicker`, `URLSession`, `@AppStorage`, ...).
- **Framework roots** (`--framework-source`, plus `SwiftUIWebCore` and
  `SwiftUIWebBrowser`) supply vocabulary only: CSS class names, the icon
  catalog and asset discovery. The framework mentioning a feature is never
  evidence that the application uses it.
- The rule stays conservative. An application reference it cannot resolve
  (`Image(systemName: someString)`, `className`, a runtime `Bundle` lookup)
  falls back to the complete set: the whole icon catalog (`icons.dynamic`), no
  CSS pruning (`css.dynamic`), all discovered assets (`assets.dynamic`). A
  computed `String` property made only of literal `switch` arms
  (`case .home: "house"` or `return "house"`) counts as finite; if two types
  declare the same property name and either is not finite, the name is dynamic.

## The manifest

`Tools/release-reachability.js` writes the manifest to `$BUILD_ROOT/release-manifest-<product>.json`
(`BUILD_ROOT` defaults to `.build`), as `Tools/run-browser-embedded.sh` calls it. No checked-in or built copy exists to
quote, so the keys below are those the script writes:

```json
{
  "version": 1,
  "product": "<product>",
  "configuration": "release",
  "sourceRoots": ["Examples/<product>"],
  "features": { "<feature>": true },
  "icons": { "symbols": ["house"], "dynamic": false, "asset": "icon-adapter.js" },
  "css": { "dynamic": false, "proof": { "safeToPruneOptionalRules": true } },
  "assets": { "retain": [], "dynamic": false, "proof": { "complete": true } },
  "proof": { "sourceFiles": [], "featureEvidence": {}, "safeToPruneUnlistedAssets": true }
}
```

The `features` map is the reachability decision per optional feature, `icons`, `css` and `assets` carry what the
pipeline may prune, and `proof` records the evidence behind each decision. Other keys (`frameworkRoots`,
`browserBindings`, `swiftDefines`, `runtime`, `notes`) are written beside them.

## What the pipeline does with the manifest

`Tools/run-browser-embedded.sh` (release):

- compiles with the `SWIFTUIWEB_RELEASE_HAS_*` defines the manifest lists;
- copies only the helpers in `runtime.initial` and `runtime.lazy`, and
  `rewrite-release-index.js` drops the unreachable `<script>` tags;
- generates `icon-adapter.js` from `icons.symbols` unless `icons.dynamic`;
- runs `prune-release-css.js` on `styles.css`, which removes optional
  rules for absent features and is a no-op when `css.dynamic`;
- builds the JavaScript runtime with `Tools/build-runtime-bundle.mjs`, which leaves out the browser hosts of
  unreachable features through `bun build --define` constants and dead-code elimination (nothing is loaded
  later): `motion` (transition-host.js: transitions, `.animation`, matched geometry, symbol and content effects,
  and the motion of presentations and navigation), `media` (media-host.js), `splitViews` (split-view-host.js),
  `predicates` (the NSPredicate engine, in the page and the worker), `navigation` (the adaptive TabView shell)
  and `dragDrop` (the native drag coordinator). Their rules are deliberately wider than the API they serve: a
  false positive only keeps a host.
  Like every feature here, the evidence is the application's own sources and its local packages: a feature used
  only inside a remote Swift package dependency is not seen. Such an application names it in a JSON file passed as
  `SWIFTUIWEB_RELEASE_ASSETS` (`{"features": {"motion": true}}`), which turns the feature on.

The compile gates, and the application evidence that keeps each one:

| Define | Kept by | What a release without it drops |
| --- | --- | --- |
| `SWIFTUIWEB_RELEASE_HAS_CANVAS` | `Canvas`, `GraphicsContext` (a `TextRenderer`), `ResolvedText` | the browser canvas binding |
| `SWIFTUIWEB_RELEASE_HAS_MESH_GRADIENT` | `MeshGradient` | the mesh gradient binding |
| `SWIFTUIWEB_RELEASE_HAS_DRAGDROP` | `onDrag`, `onDrop`, `dropDestination`, `.draggable`, `Transferable` | drag and drop |
| `SWIFTUIWEB_RELEASE_HAS_PHOTOS` | `PhotosPicker`, `.photosPicker` | the photo picker |
| `SWIFTUIWEB_RELEASE_HAS_IMAGES` | `Image("name")`, `AsyncImage`, `Label(_, image:)` | the asset-catalog table install |
| `SWIFTUIWEB_RELEASE_HAS_STORAGE` | `@AppStorage`, `@SceneStorage`, `UserDefaults` | the Web Storage adapters and their change observer |
| `SWIFTUIWEB_RELEASE_HAS_NETWORKING` | `URLSession`, `URLRequest`, `HTTPCookie`, `URLCache`, `WebSocket`, ... | the fetch, streaming, connectivity and cookie-jar hosts |
| `SWIFTUIWEB_RELEASE_HAS_NAVIGATION` | any `Navigation…` type, `navigationDestination`, `TabView`, `Tab`, `toolbar`, `sheet` | the browser history adapter |
| `SWIFTUIWEB_RELEASE_HAS_WEBMOUNT` | `WebMount`, `DOMViewRepresentable`, web content, maps, video | the WebMount registry and DOM view mounts |

The entry points the page calls by name (`embedded_browser_history_*`, `embedded_browser_webmount_reconcile`,
`embedded_browser_cookies_changed`) stay in every release; without the feature they do nothing.

Some framework code is not gated at all but referenced only from the API that needs it, so the linker drops it when
the application never calls that API: the measured text and the canvas a `TextRenderer` draws on are installed by
`textRenderer(_:)` and by a reader of `Text.LayoutKey` (`Text._installMeasuredRendering`), and the split of a string into
inline image runs by `appendInterpolation(_: Image)` (`Text._installInlineImageSplitting`).

Debug builds compile every feature in and skip the defines, so a feature can
work in debug yet be absent from release. Check release with a release build of the consuming app (`make browser-release
EXAMPLE=<product>` in this repository).

`make reachability-test` covers the rule, including an external consumer that
mentions a feature only inside the framework.
