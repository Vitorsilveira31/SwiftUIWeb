---
name: wasm-release-audit
description: "Use when auditing SwiftUIWeb WASM release size, link maps, Brotli budgets, reachability, code splitting, ICU linkage, or release provenance."
---

# WASM Release Audit

Use the repository's audit scripts against a freshly built artifact. Size and
reachability conclusions are only valid for the exact product, configuration,
runtime mode, and toolchain that produced the artifact.

## Standard workflow

- Build with `make browser-release EXAMPLE=showcase` (the Embedded
  release build).
- Use `make wasm-audit BUNDLE=...` for the size report; pass `LINK_MAP=...`
  when a link map and source attribution are needed.
- Use `make wasm-budget BUNDLE=...` for the Brotli budget, and
  `make wasm-size` / `make wasm-size-check` for the section report and its
  check.
- Use `bun Tools/analyze-wasm-data.js` (it reads the linker map) when data
  sections or archive attribution are part of the question.
- Use `make reachability-test` for conservative release-pruning checks. Lazy
  chunks show up in `make bundle-sizes`.

## Reporting

Record the bundle path, product, configuration, runtime mode, Brotli quality,
budget, link-map/provenance files, and the exact command. Separate a failed or
unexecuted build from a failed audit. Never hand-edit generated reports or
declare the tracked baseline updated without an explicit user request.
