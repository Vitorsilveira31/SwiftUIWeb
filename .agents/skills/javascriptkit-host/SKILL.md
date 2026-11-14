---
name: javascriptkit-host
description: "Use explicitly when changing SwiftUIWebBrowser, JavaScriptKit interop, PackageToJS bootstrap, browser imports, DOM host adapters, or WASI-to-JavaScript lifecycle wiring. Do not use for SwiftUIWebCore, Fiber, HTML, or Embedded code that must remain JavaScriptKit-free."
---

# JavaScriptKit and PackageToJS Host Boundary

Keep JavaScriptKit and PackageToJS work at the browser executable/host boundary.
The framework's Core, Fiber, HTML, and Embedded runtime must remain neutral and
must not acquire browser globals or JavaScriptKit imports merely to simplify a
host implementation.

## Review constraints

- Inspect `Package.swift`, `Tools/run-browser.sh`, the active PackageToJS
  bootstrap, and `SwiftUIWebBrowser` before changing interop code.
- Distinguish the PackageToJS packager/bootstrap from the JavaScriptKit Swift
  runtime. Embedded builds may use PackageToJS while intentionally omitting the
  JavaScriptKit Swift runtime.
- Preserve WASI initialization order, reactor entrypoints, memory setup,
  exported symbols, and browser import namespaces.
- Keep DOM and JavaScript values behind the host adapter; expose neutral Swift
  values to Core and application views.
- Validate with the narrowest host contract first, then the matching standard or
  Embedded browser release and its real-browser test.

## Useful gates

- `make embedded-network-storage-test`
- `make single-browser-runtime-audit`
- `make browser-release EXAMPLE=showcase` (the Embedded build)
