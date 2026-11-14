# Contributing to SwiftUIWeb

Thanks for helping. SwiftUIWeb is a SwiftUI-shaped framework that runs as Embedded Swift/WebAssembly in the browser, with
thin JavaScript host adapters.

## License of contributions

The project is licensed under the [Mozilla Public License 2.0](LICENSE). By submitting a contribution you agree that it is
licensed under the same terms. There is no separate contributor agreement. Code you copy in from elsewhere must be under a
license compatible with MPL-2.0 and recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Where code goes

[AGENTS.md](AGENTS.md) has the full rules, for people and coding agents alike; the architecture behind them is in
[Documentation/ARCHITECTURE.md](Documentation/ARCHITECTURE.md). In short:

- **Swift** for the public SwiftUI-shaped API, the Fiber runtime, diffing, serialization and validation.
- **JavaScript** (run by `bun`) only for browser capabilities: DOM, `fetch`, storage, media. Keep it a thin adapter.
- Tests, audits and build scripts are JavaScript or Swift; the source lowerer is the Swift package
  `Tools/SwiftUIWebLowering`. No Python.
- A public API that exists in Apple's SwiftUI must match Apple's signature and behavior. Fix a divergence in the code; do
  not add it to a baseline. API that SwiftUI does not have goes in `SwiftUIWebWeb`.

## Building and testing

```sh
make setup           # checks Swift (Embedded SDK) and Bun
make test            # native Swift tests plus the tooling and documentation checks
make browser-test    # what a pull request must pass: the lowerer and every real-browser suite
make tools-test      # the JavaScript tooling
make docs-test       # links, paths and make targets in the docs
make run             # build and serve the project site (Embedded)
```

[Documentation/DEVELOPMENT_WORKFLOW.md](Documentation/DEVELOPMENT_WORKFLOW.md) lists the focused gates (layout, identity,
scrolling, presentation, accessibility, performance) and when each applies. Validate the Embedded browser path for a change
that touches runtime behavior; a native build alone is not enough evidence.

## Pull requests

- Keep a change to one concern and say what you ran and what you could not run.
- A behavior change comes with a test. Run `make api-diff` if you touched public API, and update
  [Documentation/MIGRATION.md](Documentation/MIGRATION.md) for a breaking change.
- Do not edit baselines or budgets to make a check pass.
- Write commit messages and descriptions in English.

## Reporting a security problem

Do not open a public issue for a vulnerability. Report it privately as described in [SECURITY.md](SECURITY.md).

## Code of conduct

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
