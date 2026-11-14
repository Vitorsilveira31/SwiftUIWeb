---
name: browser-validation
description: "Use when building, testing, or diagnosing SwiftUIWeb browser, WASI, Embedded DOM, focus, presentation, scrolling, or Playwright behavior. Do not use for native-only SwiftPM tests."
---

# Browser Validation

Use the repository's existing Make targets and fixture runners instead of
inventing a second browser harness. First inspect `Makefile` and the relevant
fixture/tool so the test matches the runtime mode being changed.

## Choose the gate

- Semantic/runtime contracts: `make integrated-check`, or
  the focused `make identity-test`, `make scrolling-test`, and
  `make presentation-test` targets.
- Browser contracts: `make browser-contract-test` for the integrated host. The
  browser suites are Node/bun Playwright scripts (`Tools/test-*.mjs`) built on
  `Tools/browser-test-support.mjs`; run `make browser-test-setup` once to
  install the browsers.
- Embedded browser behavior: `make embedded-ui-test`,
  `make embedded-showcase-test`, `make identity-browser-test`,
  `make scrolling-browser-test`, `make presentation-browser-test`, and
  `make focus-browser-test`.
- Final application gate: `make integration-release-test` after the matching
  Swift/WASI SDK, Bun, and browser test environment are available.

## Evidence rules

- Distinguish source/tooling contract tests from a real rebuilt WASM application.
- Record the exact command, runtime mode (`standard` or `embedded`), fixture,
  and artifact path used for a result.
- A DOM snapshot or host-only test is not evidence of a successful full Swift +
  WASM release.
- Prefer semantic assertions (identity, focus, presentation lifecycle, layout,
  scroll anchoring, accessibility) over pixel snapshots.
- Do not edit generated `.build` artifacts as a fix; change the source or the
  owning tool and rerun the narrowest gate.
