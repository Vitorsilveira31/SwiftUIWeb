# Test coverage contract

SwiftUIWeb treats coverage as a behavior contract for the core/runtime and
infrastructure layers. The long-term goal for controlled stable code is 100%
line coverage and 100% semantic branch coverage. Tests must exercise an
observable success, failure, fallback, cancellation, cleanup, lifecycle, or
edge-case behavior; adding an unreachable test-only branch is not acceptable.

The UI showcase, component catalogue, CSS and examples use interaction,
responsive and accessibility tests instead of a 100%
line target.

## Run the audit

```sh
bun Tools/coverage.mjs --gate
```

This runs Swift Testing with LLVM instrumentation, and writes `.build/coverage/report.json` plus
`.build/coverage/report.md`. To include the real BrowserIO host (Bun must be
installed and the process must be allowed to bind loopback for its local HTTP
fixture), run:

```sh
bun Tools/coverage.mjs --browserio --gate
```

`make coverage` is the CI-friendly alias. `COVERAGE_BROWSER=1 make coverage`
adds the Bun host contract. Use `--strict-target` only when evaluating the
100% milestone; the normal gate prevents regressions below the floors in
`Tools/coverage-policy.json` while the remaining gaps are being closed.

## Floors

`Tools/coverage-policy.json` is the source of the floors. It holds:

- `minimumLine` and `minimumFunction`: the floor of each measured module, in percent. A module below its floor fails the gate.
- `targetLine` and `targetBranch`: the 100% targets that `--strict-target` checks.
- `semanticBranchSuites`: the named suites that stand in for branch coverage (see below).

The floors are the checked-in numbers; the generated report is authoritative for the exact counts of a given run.

## What is measured

- Swift test products are exported one executable at a time and aggregated by
  source module. Only `Sources/` files are included; test sources and package
  dependencies cannot inflate the result.
- The arena, dependency graph and child matching are Swift and are measured as `SwiftUIWebFiber` and `SwiftUIWebCore`.
- The source lowerer (`Tools/SwiftUIWebLowering`) is a package of its own with its own tests
  (`make lowering-unit-test`). It is outside the gate: the policy has no floor for it, and it is not part of this report.
- BrowserIO uses Bun's LCOV output from the real HTTP, cancellation, streaming,
  storage transaction, Intl and cleanup host contract. The BrowserIO module
  metric is intentionally scoped to the two shipped files
  (`protocol.generated.mjs` and `browser-io.mjs`); the local Bun
  fixture (`test-host.mjs`) is a test harness and is not distributed. Bun
  function metrics are retained when LCOV publishes them; branch records remain
  `unsupported` when the Bun runtime does not emit `BRDA` entries.
- The report records line, function and branch counts for every instrumented
  module and leaves missing instrumentation visible as `n/a`/`unsupported`.

The native run exercises the Foundation-free BrowserIO façade, the C callback
bridge, the native connectivity-monitor lifecycle, the App façade entrypoints,
storage adapters, Observation lifecycle and cancellation paths. The C bridge
is held at 100% line and branch coverage. The Swift BrowserIO lines that call
Embedded/WASI DOM exports are validated by the Embedded compile and browser
gates and the Bun host contract rather than being hidden with an exclusion.
Native-only Foundation adapters are measured in their native products, while
browser counterparts use the host contract.

## Branch coverage limitation

The LLVM maps generated for Swift source currently contain no branch records.
That is a toolchain limitation, not an exclusion: the source remains in the
line report and the report explicitly marks the branch metric as
`unsupported`. C maps and Bun/V8 host coverage are kept separate. Until
compiler branch maps are available, the semantic branch suites are the gate:
structural-arena stale-handle paths, dependency ownership and fallback rules,
Observation coalescing/teardown, lowerer diagnostics and idempotence, layout
properties, and BrowserIO failure/cancellation/cleanup.

This limitation is documented rather than silently reporting a false 100%.
When the toolchain emits branch records, `--strict-target` will enforce the
100% target for those records as well.

## Exclusions

No source exclusion is used to raise a percentage. A line that cannot run on
the native host (an Embedded-only compile-time branch, a host-version fallback)
stays in the source and in the report, and is covered by the corresponding
Embedded, browser-host or property/fuzz gate. Guards that protect teardown or
stale callbacks are not removed to make a line reachable, and no hidden test
switch is added for the same purpose.
