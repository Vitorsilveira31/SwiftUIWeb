# SwiftUIWebWebPlugin

A SwiftPM **command plugin** with one job: it writes `swiftweb`, a small script at the root of your package that runs
SwiftUIWeb for it. Add SwiftUIWeb to your `Package.swift`, run this once, and nothing else is installed by hand.

```sh
swift package --allow-writing-to-package-directory web init
./swiftweb dev
```

| Command | What it does |
|---|---|
| `./swiftweb dev [product]` | Builds, serves, and when a source file is saved rebuilds what changed and reloads the page (debug) |
| `./swiftweb build [product]` | Release bundle |
| `./swiftweb run [product]` | Release bundle, served |
| `./swiftweb doctor` | What the toolchain is missing (Swift, the WebAssembly SDKs, Bun), with the command that installs each |

A package with one executable needs no product name. Options after the command go to the launcher
([`Tools/swiftuiweb-run.swift`](../../Tools/swiftuiweb-run.swift)): `--product NAME`, `--port N`, `--dev-profile embedded`.

## Why a script and not `swift package web dev`

- **A SwiftPM command cannot serve.** Command plugins run in a sandbox without a local server.
- **A SwiftPM command holds the package's build lock.** While `swift package …` runs, a `swift build` or `swift test` in
  another terminal waits for it. A development loop stays open for hours.
- **Starting through SwiftPM costs a few seconds every time.** The script calls the tools directly.

So the plugin is used for the step that is short and needs SwiftPM (it knows where the SwiftUIWeb checkout is), and the
loop runs outside it.

## How the script finds SwiftUIWeb

In order: `SWIFTUIWEB_ROOT` when set; the place the dependency was when the script was written, relative to your package
(a path dependency such as `../swiftuiweb`); a checkout below `.build/checkouts` (a dependency by URL). When none is
there it says to run `swift package resolve`.

The script is plain text and safe to commit. `web init` writes over a `swiftweb` it wrote before and refuses to replace a
file that is not its own (`--force` replaces it).

## Why it is not called `web`

Packages keep their browser target in a `Web` folder. On a file system that ignores case (the macOS default) a file named
`web` cannot sit next to it.
