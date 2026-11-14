// Runs the Embedded Swift application off the main thread.
//
// The main thread keeps the DOM, layout measurement and every browser interaction; this worker owns the WASM
// instance, its task pump and the BrowserIO host (fetch, IndexedDB, mirrored storage). The host itself is
// embedded-host-core.js, which the page also runs on the main thread when this worker's call stack runs
// out; this file only connects it to `postMessage`.
import { createHostCore } from './embedded-host-core.js';

const core = createHostCore({ post: (message, transfer) => self.postMessage(message, transfer || []), scope: self, canMigrate: true });

self.onmessage = async ({ data }) => {
  if (await core.handle(data) === 'dispose') self.close();
};
