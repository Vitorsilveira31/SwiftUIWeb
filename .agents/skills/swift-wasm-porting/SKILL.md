---
name: swift-wasm-porting
description: "Use when checking or changing SwiftUIWeb code for WebAssembly, WASI, or Embedded Swift compatibility. Triggers: wasm, WebAssembly, WASI, Embedded Swift, wasm32, SWIFTUIWEB_EMBEDDED, Foundation fallback, SDK compatibility."
---

# Swift WebAssembly and Embedded Porting

Apply this skill when a change affects the Swift/WASI/Embedded boundary. SwiftUIWeb
supports native SwiftPM builds, standard WASI/browser builds, and a stricter
Embedded Swift browser profile; these are related but not interchangeable.

## Project constraints

- Read `Package.swift` and the relevant target before changing conditional imports.
- Preserve native implementations while keeping `#if os(WASI)` and
  `#if hasFeature(Embedded)` fallbacks deterministic and Foundation-free where
  the target requires it.
- `SwiftUIWebCore` must remain browser-host neutral. Browser and PackageToJS
  details belong at the host boundary, not in Core/Fiber/HTML.
- PackageToJS may be the packager/bootstrap layer; that does not mean the
  Embedded runtime should import or depend on the JavaScriptKit Swift runtime.
- Do not claim an Embedded or WASM build passed unless the matching SDK/toolchain
  actually compiled the target.

## Validation

Use the narrowest relevant gate first:

- `make embedded-preflight` for compiler/SDK capability checks.
- `make embedded-core-check` for the actual Core compatibility gate.
- `make browser-release EXAMPLE=showcase` for the Embedded browser build
  (the canonical profile; there is no separate standard WASI browser build).
- `make embedded-fallback-audit` after changing fallback or conditional code.

When a toolchain is unavailable, report the source-level checks separately from
the unexecuted final link and identify the missing SDK, Bun, or browser.
