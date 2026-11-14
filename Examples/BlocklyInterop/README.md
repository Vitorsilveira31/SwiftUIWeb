# Blockly DOM interop

This isolated browser example uses the official `blockly` npm package and
SwiftUIWeb's `DOMViewRepresentable` lifecycle. Blockly mounts in the current
page's ShadowRoot. It does not navigate or create an iframe, and the ShadowRoot
keeps the component's CSS away from the rest of the application.

From this directory, run:

```sh
./run.sh
```

The script installs the pinned Bun dependency, bundles Blockly and its official
media assets for browsers, builds `BlocklyInteropApp` with the repository's
Embedded Swift tools, then serves the generated application at
`http://127.0.0.1:8080` (or `$PORT`). Open that address in a browser.

Use **Atualizar para estado B** (update to state B) to send a Swift value change to the existing
Blockly instance. Add or move a block and the workspace is serialized back to
Swift as JSON. **Remover componente** (remove component) runs the DOM view teardown, removes its
listeners, calls `workspace.dispose()`, and clears the ShadowRoot; mounting it
again creates a fresh workspace.

## Using the adapter

Conform a leaf `View` to `DOMViewRepresentable`, which lives in the web-only
`SwiftUIWebWeb` product. Swift names a component the page registered and sends
it a state string; no script text crosses, so the page's Content-Security-Policy
needs no `'unsafe-eval'`.

The page registers the component from a script served by its own origin. Here
that is `Resources/head.html` (a module that loads `blockly-global.js`):

```js
(globalThis.SwiftUIWebDOMComponents ??= { queue: [], define(name, factory) { this.queue.push([name, factory]); } })
  .define("map-canvas", () => ({
    mount(host, root, emit, state) {
      const canvas = document.createElement("canvas");
      root.append(canvas);
      const map = createMap(canvas, JSON.parse(state));
      map.on("move", () => emit(JSON.stringify(map.center())));
      return { map };
    },
    update(instance, state) { instance.map.setZoom(JSON.parse(state).zoom); },
    dispose(instance) { instance.map.remove(); },
  }));
```

`mount` receives `host`, `root` (a `ShadowRoot`), `emit` and the state, and
returns the instance that `update` and `dispose` receive. Messages passed to
`emit` arrive in `DOMView.onMessage`, which `makeDOMView(context:)` assigns.
The factory may return a Promise (for instance after `await import("./map.js")`),
so the component's code is fetched only when a view first mounts it.

```swift
import SwiftUIWebWeb

struct MapCanvas: DOMViewRepresentable {
  let zoom: Int

  func makeDOMView(context: Context) -> DOMView {
    DOMView(component: "map-canvas", state: "{\"zoom\":\(zoom)}")
  }

  func updateDOMView(_ domView: DOMView, context: Context) {
    domView.state = "{\"zoom\":\(zoom)}"
  }
}
```

`DOMView` is unrelated to `WebView`'s iframe-backed URL/HTML API. The component
runs with the page's privileges: register only code you wrote or trust.
