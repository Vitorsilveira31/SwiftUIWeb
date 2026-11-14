# Concurrency in SwiftUIWeb

SwiftUIWeb is main-actor isolated the way SwiftUI is: `View`, `body`, modifiers, `Layout`, the styles, the
state runtime, the render pipeline and every closure a view hands to the framework (`Button` actions, `onTapGesture`,
`onAppear`, `onChange`, `task`, gesture callbacks, `onSubmit`, `onFocus`, `onHover`, `Stepper` increments, ...) are
`@MainActor`. A function type isolated to a global actor is implicitly `@Sendable`, so a plain `() -> Void` cannot
be passed where one is expected: store such closures as `@MainActor () -> Void`. `Shape` and the built-in shapes
stay `nonisolated`, as in SwiftUI.

`MainActor.assumeIsolated` is never used (it traps in Embedded, where there is no executor tracking outside a job, and
in native tests that call a `Binding` from a nonisolated context). The few places where SwiftUI's nonisolated API reaches
the main-actor runtime use `_assumeMainActor` (`MainActorBridge.swift`), which runs a `@MainActor` closure without the
dynamic check, and a handful of `nonisolated(unsafe)` locals that hand a closure or view the nonisolated entry point
received to main-actor storage. Each is the entry point of an API SwiftUI declares nonisolated: `Binding`, `State`,
`FocusState`, `GestureState`, `Environment`, `AnyView` and the modifiers. Process-wide state that nonisolated code can reach sits behind `_Locked` or a
`_RuntimeLock`-guarded object from `SwiftUIWebLocking`, a target of its own so a module that only needs a guarded
global (CoreLocation, BrowserIO) does not depend on Transferable.

## Every remaining `@unchecked Sendable`

Removing a conformance and building (native, and the Embedded Showcase, where a few more
are needed) showed which ones nothing required: 21, among them `_RenderOwnerRegistry`, `_EnvironmentResolution`, `_UnsafeStateTaskBox`
and the Browser prefetch types. `_StateSubscription` and `_GestureActionBox`-style
vestiges were examined too: `_StateSubscription` is `@MainActor` (with an `isolated deinit`) now and
`_UnsafeStateTaskBox` is gone (`StateStore` is main-actor, so its `Task` uses the closure directly). `_GestureActionBox`
was kept at first and went once `Gesture` became `@MainActor`, as it is in SwiftUI. Public types that lost `@unchecked Sendable` and could keep a checked `Sendable`
(`BrowserIOOperation`, `TimeObserverToken`, `HoverEffect.ID`, `WebSocketConnection`) now
declare plain `Sendable`, so the compiler verifies them; the other public types kept their conformance so as not to
narrow the API. `DismissAction`, `OpenURLAction`, `RefreshAction` and the button and label style renderers store `@MainActor` closures (implicitly Sendable) and are plain `Sendable`; the gesture types, their callback box and the paste and drop operation boxes are main-actor. Each `@unchecked Sendable` in the runtime's core types should have a row here.

| Types | Module | Why it is safe |
|---|---|---|
| _RuntimeLock, _Locked<Value> | SwiftUIWebLocking | The lock primitives. Every other row marked 'lock' keeps its state in one of these. |
| SwiftUIWebTransferRuntimeLock, Transferable State | SwiftUIWebTransferable | Transfer registry; every access happens under `stateLock`. |
| `_AnyTransferRepresentation`, `DataRepresentation`, `CodableRepresentation`, `FileRepresentation`, `ProxyRepresentation`, `TupleTransferRepresentation`, `SwiftUIWebAnyTransferRepresentation` | SwiftUIWebTransferable | Public generic representation values holding closures that are not Sendable; applications and tests send them across tasks, as with Apple's `TransferRepresentation`s, so they keep the conformance. |
| SwiftUIWebTransferLease | SwiftUIWebTransferable | Immutable handle whose deinit releases a registry entry under that lock; may be dropped on any thread. |
| Storage.State, Storage Values (`_ProcessStorage`) | SwiftUIWebFeatures | AppStorage/SceneStorage process registries; guarded by `_RuntimeLock`. |
| Localization.State | SwiftUIWebCore | Translation tables; registered at startup, read from any thread, guarded by `_RuntimeLock`. |
| ObservableObjectRuntime.Registry | SwiftUIWebCore (native only) | Per-object publishers; guarded by `_RuntimeLock`. |
| NavigationHistoryAdapterValue | SwiftUIWebCore | Environment value holding an existential of the (nonisolated) `NavigationHistoryAdapter` protocol; `EnvironmentKey.defaultValue` must be Sendable. |
| HorizontalAlignment, VerticalAlignment | SwiftUIWebCore | Immutable alignment identifiers holding a pure `(ViewDimensions) -> CGFloat`; SwiftUI's are Sendable. |
| _EnvironmentSnapshot | SwiftUIWebCore | Immutable environment snapshot carried by a task-local value. |
| _GeometryProxyAccess | SwiftUIWebCore | One flag set during a main-actor render and read by the host; no cross-thread writer. |
| _EmbeddedBrowserExecutor, _EmbeddedBrowserIOOperationBox, _EmbeddedBrowserTaskBox | SwiftUIWebBrowser (Embedded) | The browser job queue and its boxes: executors must be Sendable, and the single-threaded browser is their only user. |
| _RenderThreadState | SwiftUIWebCore (Embedded) | The per-thread render state is a shared static in the single-threaded browser. |
| ScrollPosition, _PreferenceStore, AVAsset and AVURLAsset, NotificationSubscription, SwiftUIWebAnyTransferRepresentation, PhotosPickerTransferProgress | public API | Public types whose stored properties are not Sendable (type-erased identity, mutable callbacks) but which SwiftUI/Foundation declare Sendable; kept so the API does not narrow. |
| _BrowserLayoutPhaseCoordinator | SwiftUIWebBrowser | Development-time ordering check; single-threaded browser host, shared static. |
| _BrowserIOOperationBox | SwiftUIWebBrowserIO | Cancellation flag shared between the caller and the host callback. |
| Counter (UUID string) | SwiftUIWebAVFoundation | Counter guarded by `_RuntimeLock`. |
| CLLocation, CLLocationManager | SwiftUIWebCoreLocation | Foundation-shaped classes handed across Task boundaries by the API; the manager's mutable state is behind `_Locked`. |
| UserNotificationCenter | SwiftUIWebUserNotifications | Foundation-shaped shared singleton; observers are registered under the provider. |
| PhotosUI Storage | SwiftUIWebPhotosUI | Holds an immutable `SwiftUIWebTransferLease`. |
| URLResponse, HTTPURLResponse | SwiftUIWebNetworking | Immutable, but `open`/subclassable like Foundation's: a non-final class cannot declare plain Sendable, and its subclasses must restate the conformance (the Embedded build warns otherwise). `WebSocketConnection` is plain Sendable. |
| URLSession, URLSessionTask and its four subclasses, NetworkConnectivityMonitor | SwiftUIWebNetworking | Foundation-shaped reference types whose state is behind `_Locked`/`_RuntimeLock` and which are captured by @Sendable network closures. |
| _NetworkRequestRace, _NetworkSleepRace, _NetworkStreamRace | SwiftUIWebNetworking | First-result-wins boxes guarded by `_RuntimeLock`. |

Removing one: delete the conformance, run `make build` and `make test CONFIGURATION=release`, and let the compiler
say whether anything still needs it.

## Embedded

The runtime's main executor is the browser executor (`swift_task_getMainExecutor_hook`, installed in
`_EmbeddedBrowserExecutor`); without it a drained main-actor job is never "on" the main actor. The pipeline builds
with `-disable-dynamic-actor-isolation` and `-disable-actor-data-race-checks`: the browser is single-threaded, so
those runtime checks could only misfire, which makes a static warning the only safety net. That is why
`run-browser-embedded.sh` fails the build on a concurrency warning for this repository's examples
(`SWIFTUIWEB_CONCURRENCY_WARNINGS=error`).
`EmbeddedEncodable`/`EmbeddedDecodable` do not refine `Sendable`, otherwise default-isolated app types that conform
to them would be inferred nonisolated.

## `Binding`

`Binding` is nonisolated and takes `@isolated(any) @Sendable` closures, as in SwiftUI.
