// Live reload for the development server (`swiftuiweb-run --watch`). Used by Tools/bun-server.ts only when
// SWIFTUIWEB_LIVE_RELOAD_TOKEN is set; the production bundle never contains any of this.
//
//   GET  /__livereload.js            the page script (injected into HTML responses)
//   GET  /__livereload               a server-sent-events stream the page listens to
//   POST /__livereload/notify?token  the watcher tells every open page what happened:
//        {"type":"reload"}                       a build finished: reload the page
//        {"type":"swap"}                         a hot build changed only the application: load it into the running page
//        {"type":"css"}                          only stylesheets changed: swap them without losing the page's state
//        {"type":"build-start"}                  show "Building..."
//        {"type":"build-error","message":"..."}  show the compiler output over the page (the old bundle keeps running)
//        {"type":"build-ok"}                     hide the overlay
//
// The notify endpoint needs the token, which only the watcher and the server share, so another page open in the same
// browser cannot trigger reloads.

import { timingSafeEqual } from "node:crypto";
import { isLoopbackHost } from "./dev-server-policy.mjs";

export const CLIENT_SCRIPT = `(() => {
  const overlayId = "live-reload-overlay";
  const overlay = () => document.getElementById(overlayId);
  const show = (text, tone) => {
    let box = overlay();
    if (!box) {
      box = document.createElement("div");
      box.id = overlayId;
      box.style.cssText = "position:fixed;z-index:2147483647;left:12px;right:12px;bottom:12px;max-height:60vh;overflow:auto;" +
        "font:12px/1.4 ui-monospace,Menlo,monospace;padding:10px 12px;border-radius:8px;white-space:pre-wrap;box-shadow:0 4px 24px rgba(0,0,0,.35)";
      document.documentElement.append(box);
    }
    box.style.background = tone === "error" ? "#3b1218" : "#1f2937";
    box.style.color = tone === "error" ? "#ffd7d7" : "#e5e7eb";
    box.textContent = text;
  };
  const hide = () => overlay()?.remove();
  let missedLiterals = false;
  // Set by the module when a replacement could not be used (a literal of a type it cannot replace).
  const staleKey = "swui:14:swiftuiweb.dev:literals-stale";
  const takeStale = () => { try { const stale = sessionStorage.getItem(staleKey) !== null; sessionStorage.removeItem(staleKey); return stale; } catch { return false; } };
  takeStale();
  const source = new EventSource("/__livereload");
  // A reload after a build keeps the page's state: the module writes it to sessionStorage (a debug build's
  // embedded_browser_state_save) and the module that replaces it reads it when it starts. When the app runs in the worker
  // the write arrives a moment after the call, so the reload waits for the key, for at most 400 ms.
  const stateKey = "swui:14:swiftuiweb.dev:state";
  const reloadKeepingState = () => {
    let asked = false;
    try { sessionStorage.removeItem(stateKey); asked = globalThis.__swiftuiwebSaveState?.() === true; } catch { asked = false; }
    if (!asked) { location.reload(); return; }
    const started = performance.now();
    const wait = () => {
      let saved = false;
      try { saved = sessionStorage.getItem(stateKey) !== null; } catch { saved = true; }
      if (saved || performance.now() - started > 400) location.reload(); else setTimeout(wait, 10);
    };
    wait();
  };
  source.addEventListener("reload", reloadKeepingState);
  // Hot swap: the page loads the new application module into the module it is running (Tools/side-module.js) and starts
  // the application again in place. A page that cannot (it runs another build, or the swap failed) reloads.
  source.addEventListener("swap", async () => {
    let swapped = false;
    try { swapped = (await globalThis.__swiftuiwebSwap?.(new URL("app-side.wasm", document.baseURI).href)) === true; } catch (error) { console.error("[SwiftUIWeb] hot swap failed", error); }
    if (swapped) hide(); else reloadKeepingState();
  });
  source.addEventListener("css", () => {
    for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
      const url = new URL(link.href, location.href);
      if (url.origin !== location.origin) continue;
      url.searchParams.set("live-reload", String(Date.now()));
      link.href = url.href;
    }
    hide();
  });
  source.addEventListener("literals", (event) => {
    let taken = 0;
    try { taken = globalThis.__swiftuiwebLiveLiterals?.(JSON.parse(event.data).message ?? "") ?? 0; } catch { taken = 0; }
    missedLiterals = missedLiterals || !(taken > 0);
  });
  // When the app runs in the worker, the mark of an unusable replacement reaches this thread a moment after the worker
  // wrote it, which can be after the build ended (and a literal that is first run later is marked later still). So the
  // mark is looked for again for a while after each build, not only at its end.
  const settleLiterals = () => { if (takeStale() || missedLiterals) reloadKeepingState(); };
  let settleTimers = [];
  source.addEventListener("literals-built", () => {
    settleLiterals();
    for (const timer of settleTimers) clearTimeout(timer);
    settleTimers = [250, 1000, 3000, 10000].map((delay) => setTimeout(settleLiterals, delay));
  });
  source.addEventListener("build-start", () => show("Building\\u2026", "info"));
  source.addEventListener("build-ok", hide);
  source.addEventListener("build-error", (event) => show("Build failed. The page below is the last good build.\\n\\n" + (JSON.parse(event.data).message ?? ""), "error"));
})();
`;

const encoder = new TextEncoder();

/** The longest replacement text a `literals` event carries; the watcher builds and reloads for a longer one. */
export const LITERALS_LIMIT = 200_000;

// Constant-time token check: a timing difference must not reveal the token byte by byte.
function sameToken(given, expected) {
  const a = Buffer.from(given ?? "");
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function createLiveReload(token) {
  const clients = new Set();
  // The replacements sent since the last build the pages loaded. A page that connects while that build is still running
  // loaded the bundle from before them, so it is sent them again.
  let pendingLiterals = [];
  const send = (controller, type, data) => {
    try {
      controller.enqueue(encoder.encode(`event: ${type}\ndata: ${JSON.stringify(data)}\n\n`));
      return true;
    } catch {
      return false;
    }
  };
  const broadcast = (type, data = {}) => {
    for (const client of [...clients]) if (!send(client, type, data)) clients.delete(client);
    return clients.size;
  };
  const heartbeat = setInterval(() => {
    for (const client of [...clients]) {
      try { client.enqueue(encoder.encode(": keep-alive\n\n")); } catch { clients.delete(client); }
    }
  }, 5000);
  heartbeat.unref?.();

  return {
    /** A Response for the live-reload routes, or null when the request is not one of them. */
    async handle(request, server) {
      const url = new URL(request.url);
      // A DNS-rebinding page can reach the stream, so the routes answer only to loopback names, as the dev server does.
      if (url.pathname.startsWith("/__livereload") && !isLoopbackHost(request.url)) return new Response(null, { status: 403 });
      if (url.pathname === "/__livereload.js") {
        return new Response(CLIENT_SCRIPT, { headers: { "Content-Type": "text/javascript; charset=utf-8", "Cache-Control": "no-store" } });
      }
      if (url.pathname === "/__livereload" && request.method === "GET") {
        server?.timeout?.(request, 0);
        let controller;
        const stream = new ReadableStream({
          start(c) {
            controller = c;
            clients.add(c);
            c.enqueue(encoder.encode(": connected\n\n"));
            for (const message of pendingLiterals) send(c, "literals", { message });
          },
          cancel() { clients.delete(controller); },
        });
        return new Response(stream, { headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-store", Connection: "keep-alive" } });
      }
      if (url.pathname === "/__livereload/notify" && request.method === "POST") {
        if (!sameToken(url.searchParams.get("token"), token)) return new Response(null, { status: 403 });
        let body = {};
        try { body = await request.json(); } catch { return new Response(null, { status: 400 }); }
        const type = String(body.type ?? "");
        if (!["reload", "swap", "css", "literals", "literals-built", "build-start", "build-ok", "build-error"].includes(type)) return new Response(null, { status: 400 });
        // A message is cut to a length an overlay can show, except replacements: part of them is not what was saved.
        let message = typeof body.message === "string" ? body.message : undefined;
        if (type === "literals") {
          if (message === undefined || message.length > LITERALS_LIMIT) return new Response(null, { status: 413 });
          pendingLiterals.push(message);
        } else {
          message = message?.slice(0, 20000);
          if (type === "literals-built" || type === "reload" || type === "swap") pendingLiterals = [];
        }
        const listeners = broadcast(type, { message });
        return Response.json({ listeners });
      }
      return null;
    },
    /** Adds the page script to an HTML document. */
    inject(html) {
      const tag = '<script src="/__livereload.js"></script>';
      return /<\/head>/i.test(html) ? html.replace(/<\/head>/i, `${tag}</head>`) : tag + html;
    },
    clients: () => clients.size,
  };
}
