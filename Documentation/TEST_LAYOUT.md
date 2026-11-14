# Test, fixture, and example layout

The repository keeps three kinds of source separate:

* `Sources/` contains the library and runtime implementation.
* `Examples/` contains executable products and user-facing reference apps.
* `Tests/Apps/` contains the executable test apps that the browser tests build and drive.
* `Tests/` contains Swift Testing and JavaScript tests (the source lowerer's own tests live in its package, `Tools/SwiftUIWebLowering/Tests`) plus their input fixtures,
  snapshots, and browser harnesses.

Fixtures are data consumed by a test (`Tests/**/fixtures`, snapshots, JSON,
HTML, or small compiler inputs); they are not SwiftPM products and must not be
imported by library targets. An executable used to validate the real Embedded
bundle belongs in `Tests/Apps/` with a clearly named product (`Examples/` is for apps people learn from), while a focused
compiler or DOM probe that is only an input to a test stays beside that test.

The public API baseline scans only library targets. Release reachability scans
the application sources under `Examples/<product>` and `Tests/Apps/<product>`
(see `Tools/release-reachability.js`), not the rest of `Tests/`. This prevents
snapshots and fixture strings from becoming accidental API or browser-feature
evidence. The canonical test
commands are:

```sh
make tools-test       # deterministic parser/fixture tooling
make docs-test        # local Markdown links and documentation paths
make api-diff         # public declarations and availability contract
make plugin-test      # consumer-facing SwiftPM build plugin
make test             # native Swift tests plus the tooling and documentation checks
```

Native Swift test targets use the toolchain's built-in Swift Testing module;
there is no package dependency to add. The Makefile runs them with
`--enable-swift-testing --disable-xctest --no-parallel`, so the test contract is
explicit and the legacy XCTest runner is not part of the gate. A focused local
run can use the same flags, for example:

```sh
swift test --enable-swift-testing --disable-xctest --filter GeometryCompatibilityTests
```

Do not add a second copy of a fixture under `.build`, a separate browser-fixtures folder,
or a package dependency's source tree. Generated browser bundles remain
under `.build` and are never checked in.
