// Reports each change of the page's cookie jar (`document.cookie`) once. The Embedded app reads cookies from
// a mirror in the worker, or from the page itself when it runs on the main thread; both use this module so the
// triggers and the change check are the same. A change comes from another tab, a server response handled on the
// main thread, or this page's own writes (which the caller announces with `wrote()`).

const CHANNEL = 'cookie-changes';

/**
 * @param {{window?: Window, onChange: (cookies: string) => void}} options
 * @returns {{current(): string, wrote(): void, dispose(): void}}
 */
export function watchCookies({ window: hostWindow, onChange }) {
  let last = read();
  let disposed = false;
  function read() { try { return hostWindow?.document?.cookie ?? ''; } catch { return ''; } }
  function sync() {
    if (disposed) return;
    const cookies = read();
    if (cookies === last) return;
    last = cookies;
    onChange(cookies);
  }
  // Chromium reports every change through cookieStore; elsewhere the page re-reads when it is shown or focused.
  const cookieStore = hostWindow?.cookieStore;
  const onVisibility = () => { if (hostWindow.document.visibilityState === 'visible') sync(); };
  if (cookieStore?.addEventListener) cookieStore.addEventListener('change', sync);
  else {
    hostWindow?.document?.addEventListener?.('visibilitychange', onVisibility);
    hostWindow?.addEventListener?.('focus', sync);
  }
  // Other tabs of this origin hear about a write made here and re-read the jar.
  const channel = typeof hostWindow?.BroadcastChannel === 'function' ? new hostWindow.BroadcastChannel(CHANNEL) : null;
  if (channel) channel.onmessage = sync;
  return {
    current: () => last,
    wrote() { last = read(); channel?.postMessage('changed'); },
    dispose() {
      if (disposed) return;
      disposed = true;
      if (cookieStore?.removeEventListener) cookieStore.removeEventListener('change', sync);
      else {
        hostWindow?.document?.removeEventListener?.('visibilitychange', onVisibility);
        hostWindow?.removeEventListener?.('focus', sync);
      }
      channel?.close();
    }
  };
}
