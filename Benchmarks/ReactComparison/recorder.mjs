// Installed in every page the comparison opens (Playwright's addInitScript), before the app runs. It is the same code on both
// sides and knows nothing about either framework: it reads the page the way a user's eye and hands do.
//
// A measured interaction starts at the input event (`event.timeStamp`, the time the browser received it) and is read twice:
//   - work: when the page's DOM shows what the interaction should have made appear (a condition on the DOM) and the browser has
//     recomputed style and layout for it. It is read the moment the DOM changes (a MutationObserver), so it is not rounded to
//     a frame. It is the framework's work plus the browser's layout, and nothing else.
//   - on screen: when the frame that presents that change starts to reach the screen. A write made inside an animation frame
//     (SwiftUIWeb commits there) is presented by that very frame, which ends at the start of the next one; a write made
//     in an event task (React's) is presented by the next frame, which ends one frame later. This is what the eye sees, and at
//     60 Hz it moves in steps of 16.7 ms.
// Conditions are plain data (`{ text: [testid, expected] }`, `{ shaded: testid }` for the row that holds the element ...) because the app's content security policy forbids eval.

export function installRecorder(readyCondition) {
  const state = { armed: false, beganAt: 0, t0: null, long: [], readyAt: null, readyFrameAt: null, readyBytes: 0, readyNodes: 0, frames: null, inFrame: false };
  window.__bench = state;

  // Which writes the page makes inside an animation frame: its callbacks are wrapped, and the flag stays up until the
  // microtasks the callback queued (the MutationObserver's among them) have run.
  const nativeFrame = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (callback) => nativeFrame((timestamp) => {
    state.inFrame = true;
    try { callback(timestamp); } finally { queueMicrotask(() => { state.inFrame = false; }); }
  });
  /** The time the frame that presents a change starts to reach the screen, given whether the change was made inside a frame. */
  const presented = (inFrame, done) => {
    let remaining = inFrame ? 1 : 2;
    const tick = (timestamp) => { remaining -= 1; if (remaining > 0) nativeFrame(tick); else done(timestamp); };
    nativeFrame(tick);
  };

  const holds = (conditions) => conditions.every((condition) => {
    if (condition.text) {
      const element = document.querySelector(`[data-testid="${condition.text[0]}"]`);
      return !!element && element.textContent.trim() === condition.text[1];
    }
    if (condition.shaded) {
      // The row of the work (the element with that test id sits in it) is painted: its background is not transparent. A selected row.
      const row = document.querySelector(`[data-testid="${condition.shaded}"]`)?.closest('[data-testid="row"]');
      if (!row) return false;
      const color = getComputedStyle(row).backgroundColor;
      return color !== "rgba(0, 0, 0, 0)" && color !== "transparent";
    }
    if (condition.count) return document.querySelectorAll(condition.count[0]).length === condition.count[1];
    if (condition.exists) return document.querySelector(condition.exists) !== null;
    if (condition.absent) return document.querySelector(condition.absent) === null;
    return false;
  });

  for (const type of ["keydown", "pointerdown", "mousedown", "click", "wheel"]) {
    addEventListener(type, (event) => { if (state.armed && state.t0 === null) state.t0 = event.timeStamp; }, { capture: true, passive: true });
  }
  // Long tasks are an entry type some engines do not have (WebKit has no Long Tasks API: its observer runs and never reports).
  // Where it is missing, the blocking time is not read: it is null, not zero.
  state.longTasks = (PerformanceObserver.supportedEntryTypes ?? []).includes("longtask");
  if (state.longTasks) {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) state.long.push({ start: entry.startTime, duration: entry.duration });
    }).observe({ type: "longtask", buffered: true });
  }

  // Core Web Vitals, where the engine reports them (Chromium): the largest contentful paint, the layout shift of the page, and
  // Event Timing of each input, whose duration runs from the input to the next paint (what INP is made of). Each is null where
  // the engine has no such entries.
  const supports = (type) => (PerformanceObserver.supportedEntryTypes ?? []).includes(type);
  state.vitals = {
    lcp: null, cls: 0, inputs: [],
    supported: { lcp: supports("largest-contentful-paint"), layoutShift: supports("layout-shift"), event: supports("event") },
  };
  if (state.vitals.supported.lcp) {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) state.vitals.lcp = entry.startTime;
    }).observe({ type: "largest-contentful-paint", buffered: true });
  }
  if (state.vitals.supported.layoutShift) {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) if (!entry.hadRecentInput) state.vitals.cls += entry.value;
    }).observe({ type: "layout-shift", buffered: true });
  }
  if (state.vitals.supported.event) {
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) if (entry.interactionId) state.vitals.inputs.push(entry.duration);
    }).observe({ type: "event", buffered: true, durationThreshold: 16 });
  }

  // The moment the DOM and its layout first show the screen the app was opened for. The clock is `performance.now()`, which
  // starts at the navigation, so this is the time to the board on screen.
  const settle = () => {
    void document.documentElement.getBoundingClientRect();
    return performance.now();
  };
  const readyObserver = new MutationObserver(() => {
    if (state.readyAt === null && holds(readyCondition)) {
      state.readyAt = settle();
      presented(state.inFrame, (timestamp) => { state.readyFrameAt = timestamp; });
      state.readyNodes = document.getElementsByTagName("*").length;
      // Each file counts once: a module the page and its worker both import (a shared chunk) has two resource entries,
      // the second answered from the memory cache, but crossed the network once.
      const bytesByURL = new Map();
      for (const entry of [performance.getEntriesByType("navigation"), performance.getEntriesByType("resource")].flat()) {
        bytesByURL.set(entry.name, Math.max(bytesByURL.get(entry.name) || 0, entry.encodedBodySize || 0));
      }
      state.readyBytes = [...bytesByURL.values()].reduce((sum, bytes) => sum + bytes, 0);
      readyObserver.disconnect();
    }
  });
  readyObserver.observe(document, { subtree: true, childList: true, characterData: true, attributes: true });

  /** Resolves with the latency of the interaction the caller starts after this call, and the blocking time it caused. */
  state.until = (conditions, timeoutMs) => new Promise((resolve, reject) => {
    state.armed = true;
    state.t0 = null;
    state.beganAt = performance.now();
    const observer = new MutationObserver(() => {
      if (!holds(conditions)) return;
      const end = settle();
      observer.disconnect();
      clearTimeout(giveUp);
      state.armed = false;
      // The input's time stamp is on the page's clock in Chromium. In WebKit a synthetic click's time stamp is not (it is far off
      // the page's clock), so an input outside the second before the action began starts the interaction when the action began.
      const start = state.t0 !== null && state.t0 >= state.beganAt - 1000 && state.t0 <= end ? state.t0 : state.beganAt;
      const blocking = state.longTasks ? state.long.filter((task) => task.start + task.duration >= start && task.start <= end)
        .reduce((sum, task) => sum + Math.max(0, task.duration - 50), 0) : null;
      const inFrame = state.inFrame;
      presented(inFrame, (frameAt) => resolve({ latency: frameAt - start, work: end - start, blocking }));
    });
    const giveUp = setTimeout(() => {
      observer.disconnect();
      state.armed = false;
      reject(new Error(`condition never held: ${JSON.stringify(conditions)}`));
    }, timeoutMs);
    observer.observe(document, { subtree: true, childList: true, characterData: true, attributes: true });
  });

  /** Arms `until` and returns at once, so the caller knows the observer is in place before it acts; `finish()` gives the result. */
  state.begin = (conditions, timeoutMs) => {
    state.pending = state.until(conditions, timeoutMs);
    state.pending.catch(() => {});
  };
  state.finish = () => state.pending;

  /** Frame intervals while the caller scrolls, until `windowMs` after this call. */
  state.frames = (windowMs) => new Promise((resolve) => {
    const stamps = [];
    const began = performance.now();
    const frame = (timestamp) => {
      stamps.push(timestamp);
      if (timestamp - began < windowMs) { requestAnimationFrame(frame); return; }
      const gaps = stamps.slice(1).map((stamp, index) => stamp - stamps[index]);
      const blocking = state.longTasks ? state.long.filter((task) => task.start >= began).reduce((sum, task) => sum + Math.max(0, task.duration - 50), 0) : null;
      resolve({ frames: gaps.length, maxFrame: Math.max(0, ...gaps), slowFrames: gaps.filter((gap) => gap > 25).length, blocking });
    };
    requestAnimationFrame(frame);
  });
}
