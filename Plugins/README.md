# Plugins

SwiftUIWeb ships two SwiftPM plugins.

| Plugin | Kind | What it is for |
|---|---|---|
| [`SwiftUIWebWebPlugin`](SwiftUIWebWebPlugin/README.md) | command plugin (`swift package web init`) | Writes `./swiftweb`, the script that runs the development loop, builds and the toolchain report for your package. Start here. |
| [`SwiftUIWebPlugin`](SwiftUIWebPlugin/README.md) | command plugin (`swift package plugin swiftuiweb`) | Builds your app for the browser: it runs the same launcher the framework uses, so a consumer package needs no scripts of its own. |

```mermaid
flowchart LR
    A["Your package<br/>depends on SwiftUIWeb"] --> B["swift package plugin swiftuiweb"]
    B --> C["Browser bundle<br/>(app.wasm + page files)"]
```

Read [`SwiftUIWebPlugin/README.md`](SwiftUIWebPlugin/README.md) for how it works and what it deliberately does not do.
