// Worker entry for the download-progress check: the same probe, run where the worker-mode runtime runs the host.
import { runDownloadProgressProbe } from './download-progress-probe.mjs';

self.onmessage = async (event) => {
  try {
    postMessage({ ok: true, results: await runDownloadProgressProbe(event.data.origin) });
  } catch (error) {
    postMessage({ ok: false, error: String(error?.stack ?? error) });
  }
};
