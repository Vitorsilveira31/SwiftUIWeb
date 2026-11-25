# Embedded source lowering

The canonical browser build uses the Swift executable built from
`Tools/SwiftUIWebLowering`, a SwiftPM package of its own on SwiftSyntax (the
framework package never depends on swift-syntax). It runs before SwiftPM compiles the temporary
Embedded workspace and never rewrites the checked-in application sources.

`Tools/swiftuiweb-lowering.sh` builds the tool into
`.build/swiftuiweb-lowering-build` (under `SWIFTUIWEB_BUILD_ROOT` when it is set;
`SWIFTUIWEB_LOWERING_BUILD_DIR` names the folder itself) and reuses SwiftPM's
incremental artifacts on subsequent builds. The first build on a machine compiles
swift-syntax, which takes about two minutes; the wrapper prints one line saying so,
and CI restores the folder with `.github/actions/cache-lowering-tool`. The wrapper
accepts the same flags as the lowerer's command-line interface:

```sh
Tools/swiftuiweb-lowering.sh \
  --apply --root . --product ShowcaseApp --workspace .build/lowering-workspace
```

The wrapper builds the release configuration by default: the lowerer runs on every
browser build, and a release binary lowers an application several times
faster than a debug one. While editing the lowerer itself,
`SWIFTUIWEB_LOWERING_PROFILE=dev` (or `--lowering-profile dev` on
`Tools/swiftuiweb-run.swift` and the `swiftuiweb` command plugin) builds the debug
configuration instead. The profile never changes the lowered sources.
`SWIFTUIWEB_LOWERING_TOOL` runs another executable in place of the built one, and
`SWIFTUIWEB_SWIFT` names the Swift compiler that builds it (the browser build's
compiler, else the one on `PATH`).

The lowerer owns the source compatibility pass (observation storage,
SwiftUI-shaped key paths, Embedded Codable helpers, browser exports, and the
disposable workspace copy). It reports the rewritten files and rule counts as
JSON, including a generated-line-to-source-line map plus generated/source
line-and-column anchors for each rewritten file, and fails closed when it
cannot safely lower an `@Observable` declaration. Diagnostics are structured
(`code`, `severity`, `file`, `line`, `column`, and byte `offset`) and transform
errors are printed as `path:line:column: [code] message`, so build logs and
editors identify the original application location directly. Each rewritten
file also records stable source/generated content hashes and is checked by a
second lowering pass before it is written; a non-idempotent transform is a
hard error rather than silently producing a different workspace on the next
build.

A browser is a desktop host, and WASI matches no `os(...)` platform, so an
application's platform conditions would compile to nothing. In application sources
(never the framework's) the lowerer evaluates `os(macOS)` in `#if`/`#elseif`
conditions as `true`, which makes the macOS side of Apple's multiplatform code
(`HSplitView`, pointer-driven chrome, `Color(nsColor:)`) the one that runs; the
`os-macos-condition` count reports it. Code the browser cannot run on that side
(an AppKit-only service) is excluded or replaced in the application's package.

For an `@Observable` reference type, each stored mutable member becomes a
`@Published(memberID: n)` member. The member ID is a deterministic ordinal
within that lowered declaration and is retained by the wrapper as diagnostic
metadata. The wrapper allocates a compact property source token; reads and
writes go through the same registrar used by `@State`.
The Embedded runtime keeps a direct source-to-StateStore routing index, so a
write probes only stores that have actually read that source instead of
scanning every live store. The dependency graph (Swift, `_DependencyGraph`) remains the authority for the
source-to-render-owner edge during a pass and marks only that source dirty on
mutation. Fiber refreshes the unique retained owner subtree. If a source is
read by multiple owners, or has no proven owner, it deliberately falls back to
one root reconciliation so the optimization never changes observable behavior.

A `@State` property that holds an `@Observable` class keeps SwiftUI's
semantics: the view owns the reference for its lifetime and observes the
members each body reads. The lowerer first collects every `@Observable` class
declared in the lowered package, then stores such properties with the
retained `StateObject` model. The decision uses the declared type or the
initializer (`@State var store = Store()`, `@State var router: Router`,
`_router = State(wrappedValue: router)`); the property name plays no role, and
value state keeps `@State`.

This is registrar-style observation rather than a copy of the compiler's
`ObservationRegistrar` implementation: model values and Swift key paths never
cross the registrar, and the lowerer does not synthesize unstable compiler-private
symbols. Browser invalidations are coalesced by Fiber, so multiple property
writes in one event produce one commit.

There is no compatibility implementation in another language. Production
builds and tooling tests invoke this executable through the wrapper, so
the browser path and regression suite exercise the same lowering code. The
tool has unit tests for projection, observation, and Codable cases
(`swift test --package-path Tools/SwiftUIWebLowering`), while `make lowering-test`
validates the real Embedded browser bundle and observer mutation path.

## Codable parity

App models keep their Foundation spelling. The lowerer maps `Codable`,
`Decodable` and `Encodable` onto the `Embedded*` protocols and synthesizes the
JSON half of each type from its stored properties and `CodingKeys` (including
raw-string keys, nested types and `URL` fields, which decode from their
string). Hand-written decoders run on a small shim over the parsed
`EmbeddedJSONValue` in `Sources/SwiftUIWebTransferable/EmbeddedDecoder.swift`:

- `Decoder`, `CodingKey`, `KeyedDecodingContainer`,
  `SingleValueDecodingContainer` and `DecodingError` are renamed to
  `EmbeddedDecoder`, `EmbeddedCodingKey` and friends. Supported calls are
  `container(keyedBy:)`, `singleValueContainer()`, `decode`, `decodeIfPresent`,
  `contains`, `decodeNil`, `allKeys`, `nestedContainer(keyedBy:forKey:)` and
  `superDecoder(forKey:)`. `enum CodingKeys: CodingKey` without a raw type gets
  its `stringValue` generated.
- A type that declares `init(from decoder: Decoder)` uses it as its decode
  contract; every synthesized struct also gets `init(from:)`, so a flattened
  composite can call `try Child(from: decoder)` and then read its own container
  from the same decoder. Unused initializers are dead-stripped.
- Generated extensions sit at file scope, so nested type names (a sibling
  `enum Kind` inside the parent) are written fully qualified, and a trailing
  `T?` is spelled `Optional<T>`.
- `Task.checkCancellation()` becomes `_embeddedCheckCancellation()`, because
  Embedded marks the original unavailable.

Not covered: unkeyed containers, `superDecoder()` without a key, custom
`encode(to:)`, and `Int`-raw `CodingKey` enums. `Tests/Apps/EmbeddedLoweringConformanceApp/EmbeddedCodableFixture.swift`
exercises the supported shapes in a real Embedded build (`make lowering-test`).

## Key paths in function arguments and `Bindable` members

- `labeled-function-member`: a plain key path (`\.a`, `\.a.b`, no root type) passed under a label whose
  parameter is always a function becomes a closure: `split(whereSeparator: \.isNewline)` becomes
  `split(whereSeparator: { $0.isNewline })`. The labels are `whereSeparator`, `where`, `while` and `by`
  (`drop(while:)`, `firstIndex(where:)`, `Dictionary(grouping:by:)`). No standard-library or SwiftUI `by:` takes a
  key path. A call that also takes another key path is left alone, because it belongs to a key-path API. Every other
  label keeps its key path, since `id`, `value`, `using`, `sortUsing`, `keyPath` and `children` take `KeyPath`s.
  Unlabeled single arguments follow the member rules instead: `allSatisfy`, `mapValues`, `compactMapValues` and
  `forEach` are `allSatisfy-member`, `mapValues-member`, `compactMapValues-member` and `forEach-member`, lowered like
  `map-member`. Roots, optional chaining and subscripts stay key paths.
- `bindable-member`: `Bindable(model).a.b` makes the binding that `$model.a.b` makes and takes the same form,
  `_memberBinding(get: { model.a.b }, set: { model.a.b = $0 })`. The model is an identifier path (`model`,
  `self.model`, `store.session`), since the closures repeat it. `Bindable(model)` alone, a member followed by a call
  and a model that is any other expression stay as they are.

## Where lowering runs for an external package

`Tools/swiftuiweb-run.swift` (and the SwiftPM plugin) lower a **disposable copy** of the consumer package and of the
framework checkout, so the application's files are never rewritten. Nothing needs to be restored when the launcher is
interrupted or killed, and nothing modified can be committed by accident.

The lowered copy is then synced into a **build cache** that lives between runs, `.build/build-cache/<product>-<configuration>-<profile>`
in the consumer's build root, together with SwiftPM's scratch folder. Only files whose bytes changed are rewritten, so the
others keep their modification times, and the next build compiles only what changed. A build that changed nothing still
runs `swift build`, which finds nothing to do. One build at a time uses a cache: a second build of the same product and
configuration waits for the first and says which process it waits for (`Tools/build-cache-lock.mjs`, a `flock` the kernel
releases when the build ends, however it ends). The cache is
disabled on CI (`CI` set), where the machine is new for each run. `SWIFTUIWEB_STABLE_WORKSPACE=0` builds in a temporary
folder that is removed afterwards, as before; `=1` keeps a cache on CI too. A development loop (`SWIFTUIWEB_DEV_CACHE`)
uses its own cache whatever `SWIFTUIWEB_STABLE_WORKSPACE` says. The cache only changes where the build
runs: the compiler, flags and output are the same as a build in a temporary folder. The development loop's settings
stay with `SWIFTUIWEB_DEV_CACHE` ([`DEVELOPMENT_WORKFLOW.md`](DEVELOPMENT_WORKFLOW.md)). Deleting the folder costs one
full build.

Each copy holds the **whole package directory**: every folder and file a manifest can name (targets outside `Sources/`,
`Resources/`, environment files), leaving out only generated output and caches (`.build`, `.git`, `.swiftpm`,
`node_modules`, `DerivedData`). Lowering still rewrites only `Sources/`, `Web/` and `Examples/<product>/` or `Tests/Apps/<product>/`; Swift files
elsewhere are copied as they are.

The framework copy is placed where the consumer's manifest declares SwiftUIWeb (`.package(path: "../../swiftuiweb")`),
so `SWIFTUIWEB_ROOT` may name any checkout: a worktree or a copy whose directory has another name.

A manifest may instead name SwiftUIWeb by URL (`.package(url: "git@github.com:Vitorsilveira31/SwiftUIWeb.git", from: "0.1.0")`).
Native SwiftPM builds then fetch the tagged framework. The staged build cannot use that copy, because its sources are not
lowered, so `Tools/framework-url-dependency.mjs` rewrites the declaration in the staged manifests (the consumer's and its
local dependencies') to a path dependency on the lowered framework. With no declared path to mirror, the framework copy
is placed two levels above the consumer in a directory called `swiftuiweb`, whatever the checkout that provides it is
called (a worktree is fine); a local dependency that goes up more than two levels is refused as being outside the
staging area. The checkout that runs the launcher (`SWIFTUIWEB_ROOT`) is the one that gets lowered, so it should be at
the tag the manifest asks for. The staged manifests of the consumer, its local dependencies and its remote browser packages
(below) are all rewritten, so every package of the build uses the one lowered framework. In-place mode
(`SWIFTUIWEB_LOWER_IN_PLACE=1`) refuses a URL declaration.

The consumer's other **local** package dependencies (`.package(path: "../Modules")`) are staged and lowered the same way,
at the same relative place as in the checkout, so the staged manifest finds them, and so are their own local
dependencies, transitively. A path dependency named `swiftuiweb` is always the framework, never a library, whichever
checkout the manifest's path happens to reach. `Tools/local-package-dependencies.mjs`
lists them from the manifests; their sources join the application evidence of the release reachability
check. A path that goes up more levels than the SwiftUIWeb dependency does is refused with an explanation (it would leave
the staging area), and absolute paths are not staged. In-place mode does not handle local dependencies.

A **remote** (URL) dependency that depends on SwiftUIWeb, a library with a browser target such as a Skip package's web
build, is lowered too, so a consumer declares it by URL with a version or branch, as its native build does, instead of
keeping a checkout next to its own. When a staged manifest declares a URL other than SwiftUIWeb's, the launcher resolves
the staged package with the browser build's environment (`swift package show-dependencies`, its checkouts kept in the
build cache), and `Tools/remote-package-dependencies.mjs` lists each remote package of the graph that depends on SwiftUIWeb.
Its resolved checkout is lowered into `<staging>/remote/<repository name>`, so the package identity stays the URL's, and the
declarations of its URL in every staged manifest, in any spelling (https or ssh, with or without `.git`), become a path
dependency on that copy. Its `Web/Resources` reach the bundle like a local package's. A remote package that does not depend
on SwiftUIWeb stays a URL dependency: SwiftPM fetches it from the copied `Package.resolved`, and its sources are not
lowered.

The historical behaviour, rewriting the consumer's `Sources` in place and restoring them on exit, is opt-in with
`SWIFTUIWEB_LOWER_IN_PLACE=1`. It is needed only for a package whose SwiftUIWeb dependency is an absolute path (a copy
cannot preserve an absolute path). A checkout left lowered by an older interrupted in-place run is restored automatically
the next time the launcher starts, when its state file still exists.


## Where a lowered program behaves differently

Embedded Swift lacks a few runtime features, so some rewrites keep the source compiling with a meaning that is close to
the original but not identical. Each rule's count in the report says how often it applied.

- **`type(of: x) == T.self` becomes `x is T`** (`type-of-test`). The cast also accepts a subclass of `T`: with a class
  hierarchy, an instance of a subclass passes a test written for its superclass. Compare an identifying property instead
  when the exact class matters.
- **Weak references become strong** (`weak`, `weak-self`). `[weak self]` becomes `[self]` and `weak var` loses `weak`,
  so an object a closure or property held weakly lives as long as that closure or holder. A reference cycle written to
  be broken by `weak` is never collected; release the closure (cancel the task, remove the observer) to end it.
- **`os(macOS)` is true** in application conditions (above).
- **Protocol-extension members become requirements** (`protocol-extension-requirement`). A promoted method is
  dispatched dynamically: when a conforming type declares a member with the same signature, a call through the protocol
  now reaches the type's member, where Swift would call the extension's. Give such a member a different name if the two
  must stay apart.

### Files the lowering will not touch

- A symbolic link is never written or deleted through: a write first replaces a link at the destination, and a removal
  removes the link itself. In in-place mode a linked Swift file or folder stops the run with an error (lowering it
  would replace the link or rewrite what it points at, and building it unlowered would differ from a workspace run):
  use a workspace, as the launcher does.
- The in-place restore puts a file back only while it still holds the text the lowering wrote. A file edited since the
  lowering keeps the edit, its original stays in the backup next to the state file, and the restore reports it; the
  state file stays too, so the next lowering refuses to start until the file is settled by hand (compare it with the
  backup, then remove `.build/embedded-source-lowering`).

## The lowerer's sources, tests and golden output

`Tools/SwiftUIWebLowering` holds `LoweringCore` (the pipeline, one file per pass, and the workspace driver), the
`swiftuiweb-lowering` executable and `Tools/SwiftUIWebLowering/Tests/LoweringCoreTests` (Swift Testing; `make lowering-unit-test` runs them). Each
pass reads the syntax tree and computes text edits at offsets taken from it, never a reprint of the tree, so everything a pass
does not touch keeps its formatting. The passes run in a fixed order in `LoweringPipeline.standard`; `--rules` and
`--list-passes` list them for the tests. The Embedded Codable generation, the view input comparisons, the single-node text
rewrites (`@Model`, error messages and descriptions, `Task.checkCancellation()`, `os(macOS)`, `#Preview`, `@Query(sort:)`,
`UserDefaults` casts, `type(of:)`, `@Entry`, `as Data`), the key-path rewrites (table sorting, the simple rules, final
classes), weak references, the protocol-extension requirements, the observable family (`@Observable` classes, observable
`@State`, `@State` member identities; the workspace reads the package's `@Observable` classes before it lowers a file,
and an `@Observable` that is not a class it can rewrite stops the run with `SWUI-L001`, an initializer assignment it
cannot delimit with `SWUI-L002`) and the import and export rewrites (the published and Renderer SPI imports, the `@main`
entry points, the `Package.swift` linker exports and the Combine diagnostics) are all passes.

The driver around the passes: the workspace copy (or lowering in place), the idempotency check of every rewritten file, the
report (version 4: `sourceMap` with each file's `lineMap`, line and column `mappings` and content `hashes`, and the `SWUI-I001`
`diagnostics`, which `Tools/run-browser-embedded.sh` points a build error at), the state (version 3), the summary on standard
output, the exit status and the text of every failure. Lowering in place writes the original of every rewritten file to a
backup folder next to its state file, named after it (`app-state.json` keeps its originals in `app-state.backup`), so the
framework's and the application's states can share a folder, as they do in `Tools/run-browser-embedded.sh`, and restoring one
leaves the other's originals alone. The report and state files are pretty-printed JSON with keys in sorted order, the layout
the build's consumers read.

The lowerer is tested by its own package (`make lowering-unit-test`): one suite per rewrite, each lowering a small source
in a temporary package and asserting on the result. There are no stored copies of lowered output to compare with.
