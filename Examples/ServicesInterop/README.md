# ServicesInterop

Swift calling a page service, a JavaScript object without a view of its own (an SDK, say), through
`BrowserService` ("Page services" in [Documentation/BROWSER_APP_SHELL.md](../../Documentation/BROWSER_APP_SHELL.md)).
`Resources/echo-service.js` defines the `echo` service; `Sources/ServicesInteropApp.swift` calls it, shows its failure and
observes its events. `make services-browser-test` builds it for Embedded WebAssembly and checks it in a browser with Swift
in a worker and on the main thread.
