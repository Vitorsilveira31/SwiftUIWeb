import { test } from "bun:test";

// The host fixture is intentionally kept as a standalone Node/Bun script so
// it can also be run by `make embedded-network-storage-test`. Importing it
// here puts the exact same HTTP, cancellation, storage and Intl contract under
// Bun's coverage collector without replacing its assertion-driven harness.
test("BrowserIO host contract exercises transport, storage, Intl and cleanup", async () => {
  await import("../../Tools/BrowserIO/test-host.mjs");
});
