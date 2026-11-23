// Diagnostics redaction shared by the BrowserIO host (browser-io.mjs) and the page service host (service-host.mjs).
// Host diagnostics must never echo credentials, cookies, request bodies or
// query strings into the RenderNode/DOM error channel or console. Keep the
// stable error class/name because callers use the code, not an opaque message.
export function safeErrorMessage(error) {
  return redactDiagnostics(String(error?.message || error || 'Browser host error')).slice(0, 512);
}
/** An error's stack, redacted like its message and capped, for the `runtime-error` event's `detail.stack` (an error
 * monitor on the page reports it); empty when there is none. A WASM trap's stack names the Swift frames it ran through. */
export function safeErrorStack(stack) {
  return typeof stack === 'string' ? redactDiagnostics(stack).slice(0, 4096) : '';
}
export function redactDiagnostics(raw) {
  return raw
    .replace(/([?&](?:token|access_token|refresh_token|code|key|secret|password|authorization))=[^&#\s]*/gi, '$1=[redacted]')
    .replace(/(authorization\s*:\s*)(?:bearer\s+)?[^,;\s]+/gi, '$1[redacted]')
    .replace(/(cookie\s*:\s*)([^,;\s]+)/gi, '$1[redacted]')
    .replace(/(bearer\s+)[^\s]+/gi, '$1[redacted]')
    .replace(/https?:\/\/[^\s]+/gi, value => {
      try { const url = new URL(value); url.username = ''; url.password = ''; url.search = ''; url.hash = ''; return url.href; }
      catch { return '[redacted-url]'; }
    });
}
