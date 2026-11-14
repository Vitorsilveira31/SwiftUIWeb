---
name: skip-testing
description: Write or diagnose Skip platform tests, choosing the native Fuse runner or the transpiled Lite/JUnit harness.
---


# Skip Testing

Match the test runner to the target's `Skip/skip.yml`. A target that uses Fuse native mode runs with the native runner; Lite's generated Kotlin/JUnit harness does not establish Fuse parity.

| Target or need | Check |
| --- | --- |
| Focused Swift test | `swift test --filter <TestClass-or-method>` |
| Host Swift suite | `make test` (all product tests; omits only the generated Android runner) |
| Trio example for Android (build) | `skip android build` from `Examples/Trio` (see `Examples/Trio/README.md`) |
| Fuse tests requiring Android app APIs | `skip android test --apk` |
| Lite Kotlin/JUnit harness | `swift test --filter XCSkipTests` |

Current native Fuse Gradle/APK runners execute Swift Testing only; XCTest classes remain host tests. New shared tests should use Swift Testing. Do not count an APK runner as executing XCTest cases, and never disable product actor isolation to hide a harness crash. The standalone `skip android test` shell runner lacks JNI; use it only for packages without Android framework dependencies.

Follow existing test conventions and use deterministic fixtures appropriate to the behavior. For async state, exercise stale responses after selection/session changes and cancellation when those paths are affected. A source-only build does not prove device UI behavior.

Load [Lite harness details](references/lite-harness.md) only for transpiled test targets, Robolectric, Kotlin compilation failures, or a custom `XCGradleHarness`. In Lite, XCTest assertions may continue where a JUnit assertion throws, so failure counts can differ. Use generated `.kt` locations to locate the original Swift failure.

Run checks by impact as defined in `AGENTS.md`. Distinguish toolchain/cache failures from behavior failures, and report exactly which platforms ran. Once relevant checks pass, stop unless a new change or unresolved concern requires more coverage.
