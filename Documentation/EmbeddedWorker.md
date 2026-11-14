# Running the Swift side in a Web Worker

The Embedded browser runtime can run the Swift WASM application in a Web
Worker, so rendering never blocks input on the page's main thread.

It is the default. Opt out with `?render-in-worker=0` in the page URL,
`window.__renderWorker = false` before loading, or
`instantiate(url, { worker: false })`. Browsers without `Worker` fall back to the
main thread.

## Split

| Main thread | Worker |
|---|---|
| DOM patching, events, focus, scroll, presentations | WASM instance (Swift), task pump |
| Layout measurement (the browser lays out with CSS) | BrowserIO: `fetch`, IndexedDB, mirrored `localStorage`/`sessionStorage` |

The worker posts a snapshot after every Swift publication: the publication bytes
(see `Architecture/BINARY_PATCHES.md`) plus the small pieces of Swift state the
host reads synchronously (lazy collection counts and extents, SecureField values,
diagnostics counters). The host applies only the newest snapshot; acknowledging
it lets Swift keep unchanged subtrees out of later publications.

## Files

- `Tools/embedded-runtime.js`: instantiates the module and chooses between the Worker and the main thread.
- `Tools/embedded-worker-client.js`: the page side of the Worker protocol, with the same `exports` surface the DOM host calls.
- `Tools/embedded-worker.js`: the worker side, which owns the WASM instance, its task pump and the BrowserIO host.
- `Tools/event-value.js`: moves event values and SecureField text across the boundary in one copy.

## Differences from the main-thread mode

- `onKeyPress` cannot veto the browser's default action: the answer is
  asynchronous, so the key is treated as ignored by the browser.
- Storage is mirrored at startup (keys with the `swui:` prefix) and written
  through; changes from other tabs are forwarded.
- WebMount and `DOMViewRepresentable` work in both modes, but a DOM read is
  answered from the mount snapshot the main thread reported before the last
  reconciliation, not from the live element. Writes are applied after the
  commit that produced them. Synchronous media reads (`BrowserMediaBridge`,
  used by AVFoundation wrappers) still need the main thread and report an error
  in the worker rather than returning a silent default.

## DOM bridge for WebMount and DOMView

The worker has no `document`, so the DOM operations that `BrowserIO` performs
for WebMount and `DOMViewRepresentable` are split across the two threads:

| Step | Where | Message |
|---|---|---|
| 1. Commit patches the DOM from the published publication | main | (none) |
| 2. Snapshot of the mounted elements (`token`, `key`, attributes, value, text) with a numeric handle per element node | main | `mounts` (`seq`, `table`) followed by the `webmount_reconcile` call |
| 3. `reconcileEmbedded` runs in the worker; reads come from the snapshot, writes are queued | worker | (none) |
| 4. The queued batch (attribute/value/text writes, `dom-view` mount/update/unmount, reports) | worker -> main | `dom` (`seq`, `ops`) |
| 5. Batch applied in order (`remote-dom-host.js`) | main | (none) |

The same `mounts`/`dom` pair is the only transport: it rides the worker channel
the patches and events already use. Mount handles are stable while an element
is the same node, so a re-created element is a new mount (dispose, then mount),
as in the main-thread mode. A removed element keeps its handle until the batch
that unmounts it has been applied, so its dismantle runs exactly once.

`DOMViewRepresentable` components still run on the main thread, against the open
ShadowRoot, through the same lifecycle code as the main-thread mode
(`Tools/BrowserIO/dom-view-host.mjs`). The worker queues `dom-view` ops that carry the component
name and the state string (`mount`: `component` and `state`; `update`: `state`; `unmount`: nothing); the
components themselves are registered in the page (`SwiftUIWebDOMComponents.define`), which the worker never sees. Their `emit` calls return
through the existing `dispatch_named` event path.

Failures are never silent. A mount that cannot happen (no registered
implementation for a key, no lifecycle descriptor, a failed snapshot, a write to
an unknown or retired handle, a throwing script) is logged with `console.error`
under `[SwiftUIWeb]` and recorded in a `data-dom-view-error`
attribute on the affected element, or on the app root when there is no element.
The browser gate asserts that attribute is absent.

## Verification

`Tools/test-embedded-worker-client.mjs` checks the protocol with a fake Worker,
including the WebMount snapshot and the batched DOM writes. `Tools/BrowserIO/test-host.mjs`
covers the worker side of the DOM bridge (`remoteDOM`). The Showcase gate
`Tools/test-embedded-showcase.mjs` runs the `DOMComponentFixture` (`/domComponent`) twice:
in the default worker runtime and with `?render-in-worker=0`. Each run checks mount, an
update that keeps the component instance and host node, a message from the
component back to Swift, one dismantle, and a remount, and asserts the runtime it
actually got from `window.__embeddedSession.worker`.
An application's end-to-end run uses the worker by default, and `?render-in-worker=0` selects the main thread.

## Starting on the main thread

Unless a Worker is forced (`instantiate(url, {worker: true})`, `window.__renderWorker = true` or `?render-in-worker=1`),
`instantiate` runs a stack probe while the app module downloads. `workerStackSufficient` in `Tools/embedded-runtime.js`
starts a Worker from a blob: URL that calls a recursive WebAssembly function `STACK_PROBE_DEPTH` (546) frames deep, and
reports whether the call returned or ran out of stack. A Worker that cannot take that depth runs the app on the main
thread; a probe that cannot run (no Worker, a blocked blob: URL) or that does not answer within three seconds keeps the
Worker. The result is cached in `sessionStorage` under a key that holds the probe version and depth
(`swui:worker-stack:v2:546`), so later loads in the tab skip the probe. A tab in which the Worker has overflowed before
(`swui:worker-overflow`) goes straight to the main thread. An overflow after the start is handled by `restartOnMainThread`,
which records it under the same key and restarts the app on the main thread (see "When the Worker's call stack runs out").

## Event values and SecureField text cross the boundary in one copy

Event payloads (a TextField's text, `dispatchNamed` names and values, scroll and
history keys) cross the boundary through bulk exports. The host (`Tools/event-value.js`)
uses them when present and falls back to the per-byte exports (`event_value_push`,
`secure_value_byte`) for builds that lack them. The SecureField ids of the newest
publication are exported as a list (`secure_ids_pointer`).

| Export | Contract |
|---|---|
| `event_value_alloc(len) -> ptr` | Reserves `len` bytes in a reused staging buffer (amortized doubling, 64 MiB cap) and returns its address; `0` means refused, so the host falls back to the byte path. |
| `event_value_commit(len)` | Makes the first `len` bytes the pending event value, then wipes the staging buffer (it can hold a password). |
| `secure_value_pointer() -> ptr` | Address of the value `secure_value` just resolved (its length is that call's result). Valid until `secure_value_reset` or the next `secure_value`; the host copies and resets. |
| `secure_ids_length()` / `secure_ids_pointer()` | Newline-separated ids of the SecureFields in the newest publication, so the worker no longer decodes the HTML. |

Ownership: Swift allocates and frees every buffer; the host only borrows an
address, copies right away and re-reads `memory.buffer` after each call because
growth may move it. Pointers are validated against `memory.buffer.byteLength`
before use. The worker client (no WASM memory) offers `event_value_write` and
`secure_value_bytes` shims with the same effect. All of these are
feature-detected, so no ABI version bump is needed; `Tools/test-event-value.mjs`
covers the bulk and per-byte paths.

## When the Worker's call stack runs out

The Worker's host (`Tools/embedded-host-core.js`) also runs on the main thread. It keeps a snapshot of the
instance's linear memory taken after every pass. If a pass overflows the Worker's stack (application code that recurses
deeper than the engine's Worker allows), the Worker hands the snapshot, the calls since it, the call that failed and the host
state to the page; the same module is instantiated on the main thread, the memory copied in and those calls run again. The
DOM session, layout and event wiring stay as they are, so `@State`, navigation, scroll, focus and text input survive.
In-flight timers, observers and read-only fetches restart; writes and transactions report cancellation. Without a snapshot
(overflow while starting, more than 192 MiB of memory) the app restarts on the main thread with its state reset.