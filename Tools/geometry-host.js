/** Browser measurement host for GeometryReader and onGeometryChange.
 *
 * Host-only adapter: it measures DOM boxes and reports them through the named
 * value-event channel. Coordinate-space semantics (`.local`, `.global`,
 * `.named`, `.scrollView`, `bounds(of:)`) and change detection live in Swift
 * (Sources/SwiftUIWebCore/GeometryMeasurement.swift), which also documents
 * the wire format produced by `measurementPayload`.
 */
const RS = '\u001e', US = '\u001f';
const round = n => Math.round(n * 64) / 64;
const box = (x, y, width, height) => [x, y, width, height].map(round).join(',');

const TRANSFORM_PROPERTIES = ['transform', 'translate', 'rotate', 'scale'];

/** The frame of `element`. A `data-geometry-untransformed` element (the target of a visual effect) is measured without the
 * transform the effect writes inline on it: measured with it, the effect would move its own input each commit and never settle.
 * Its transition is held meanwhile, so neither style change starts one. */
function frameOf(element) {
  const marker = element.getAttribute('data-geometry-untransformed');
  const rect = untransformedFrame(element, marker);
  // A geometry effect is handed the size its content lays out at (`local`), not the viewport's size of it.
  return marker === 'local' ? withLayoutSize(element, rect) : rect;
}

/** Where the transforms of `element` and its ancestors take its own x and y axes in the window, as the matrix [a, b, c, d]
 * (one CSS pixel along x lands a across and b down, one along y lands c across and d down); the identity without a transform,
 * null where the browser has no `DOMMatrix`. */
function axisMap(element, window) {
  // One pass of measurements asks for the views of one page: the map of each ancestor is kept until the pass is over.
  if (!axisMap.cache) { axisMap.cache = new Map(); window.queueMicrotask(() => { axisMap.cache = null; }); }
  const cache = axisMap.cache;
  if (cache.has(element)) return cache.get(element);
  const above = element.parentElement ? axisMap(element.parentElement, window) : IDENTITY_AXES;
  let result = above;
  const style = window.getComputedStyle(element);
  if (above !== null && TRANSFORM_PROPERTIES.some((property) => style[property] && style[property] !== 'none')) {
    if (!window.DOMMatrix) result = null;
    else {
      const [a, b, c, d] = above;
      let matrix = new window.DOMMatrix();
      if (style.rotate && style.rotate !== 'none') {
        const [, number, unit] = /(-?[\d.e+-]+)(deg|rad|turn|grad)?\s*$/.exec(style.rotate) ?? [];
        const angle = parseFloat(number);
        if (Number.isFinite(angle)) matrix = matrix.rotate(unit === 'rad' ? angle * 180 / Math.PI : unit === 'turn' ? angle * 360 : unit === 'grad' ? angle * 0.9 : angle);
      }
      if (style.scale && style.scale !== 'none') {
        const [x, y = x] = style.scale.split(/\s+/).map(Number);
        if (Number.isFinite(x) && Number.isFinite(y)) matrix = matrix.scale(x, y);
      }
      if (style.transform && style.transform !== 'none') matrix = matrix.multiply(new window.DOMMatrix(style.transform));
      // The element's own transform applies before those above it.
      result = [a * matrix.a + c * matrix.b, b * matrix.a + d * matrix.b, a * matrix.c + c * matrix.d, b * matrix.c + d * matrix.d];
    }
  }
  cache.set(element, result);
  return result;
}
const IDENTITY_AXES = Object.freeze([1, 0, 0, 1]);
/** Whether a view's axes are turned or mirrored: something its box and layout size do not show (a square turned a quarter
 * has the box it had). */
const turnedAxes = map => map !== null && (Math.abs(map[1]) > 1e-6 || Math.abs(map[2]) > 1e-6 || map[0] < 0 || map[3] < 0);

/** How many window pixels one CSS pixel of `element` is along its own x and y axes: the lengths of its axes in the window,
 * whatever rotation is among its transforms. A bounding box against the layout size is not this under a rotation, which trades
 * the box's width for its height. */
function axisScales(element, window) {
  const map = axisMap(element, window);
  return map ? [Math.hypot(map[0], map[1]) || 1, Math.hypot(map[2], map[3]) || 1] : null;
}

/** The size `element` lays out at, in its own CSS pixels, or null when the browser reports none (an inline element). */
function layoutBox(element) {
  const computed = element.ownerDocument.defaultView.getComputedStyle(element);
  let width = parseFloat(computed.width), height = parseFloat(computed.height);
  if (!(width >= 0) || !(height >= 0)) return null;
  const px = value => parseFloat(value) || 0;
  if (computed.boxSizing !== 'border-box') {
    width += px(computed.paddingLeft) + px(computed.paddingRight) + px(computed.borderLeftWidth) + px(computed.borderRightWidth);
    height += px(computed.paddingTop) + px(computed.paddingBottom) + px(computed.borderTopWidth) + px(computed.borderBottomWidth);
  }
  return {width, height};
}

/** `rect` with the size the element lays out at when a scale or rotation above it makes the two differ. */
function withLayoutSize(element, rect) {
  const local = layoutBox(element);
  if (!local || (Math.abs(local.width - rect.width) <= 0.5 && Math.abs(local.height - rect.height) <= 0.5)) return rect;
  return {left: rect.left, top: rect.top, width: local.width, height: local.height};
}

function untransformedFrame(element, marker) {
  const style = element.style;
  if (marker === null || !TRANSFORM_PROPERTIES.some((property) => style[property])) {
    return element.getBoundingClientRect();
  }
  const saved = TRANSFORM_PROPERTIES.map((property) => style[property]), transition = style.transition;
  style.transition = 'none';
  for (const property of TRANSFORM_PROPERTIES) style[property] = 'none';
  const rect = element.getBoundingClientRect();
  TRANSFORM_PROPERTIES.forEach((property, index) => { style[property] = saved[index]; });
  element.getBoundingClientRect();
  style.transition = transition;
  return rect;
}

/** The payload for `element`: its window frame followed by the ancestor
 * coordinate spaces (nearest first) that Swift may resolve against. */

export function measurementPayload(element, root) {
  const rect = frameOf(element);
  let payload = withLocal(box(rect.left, rect.top, rect.width, rect.height), rect, layoutBox(element), element);
  for (let node = element; node; node = node.parentElement) {
    const name = node.getAttribute('data-coordinate-space');
    if (name !== null && !name.includes(RS) && !name.includes(US)) {
      const r = node === element ? rect : node.getBoundingClientRect();
      payload += RS + 'n' + US + name + US + withLocal(box(r.left, r.top, r.width, r.height), r, layoutBox(node), node);
    }
    // A view is never inside its own scroll view's coordinate space.
    if (node !== element && node.classList?.contains('scroll-view')) {
      const r = node.getBoundingClientRect();
      const axes = node.classList.contains('scroll-both') ? 'both'
        : node.classList.contains('scroll-horizontal') ? 'horizontal' : 'vertical';
      // The scroll view's space is its visible (padding-box) area. Under a scale above it the area is the window's pixels
      // (its axes' scale) and the client size is in its own points.
      const [kx, ky] = axisScales(node, node.ownerDocument.defaultView) ?? [node.offsetWidth > 0 ? r.width / node.offsetWidth : 1, node.offsetHeight > 0 ? r.height / node.offsetHeight : 1];
      const scaled = Math.abs(kx - 1) > 0.005 || Math.abs(ky - 1) > 0.005;
      const map = axisMap(node, node.ownerDocument.defaultView), local = layoutBox(node);
      if (turnedAxes(map) && local) {
        // Turned or mirrored: the visible area is the box its padding box has in the window, through the scroll view's map
        // from its own corner, and the record says where its axes go, as a view's does.
        const [a, b, c, d] = map;
        const cornerX = r.left - Math.min(0, a * local.width) - Math.min(0, c * local.height), cornerY = r.top - Math.min(0, b * local.width) - Math.min(0, d * local.height);
        const xs = [], ys = [];
        for (const [x, y] of [[node.clientLeft, node.clientTop], [node.clientLeft + node.clientWidth, node.clientTop], [node.clientLeft, node.clientTop + node.clientHeight], [node.clientLeft + node.clientWidth, node.clientTop + node.clientHeight]]) {
          xs.push(cornerX + a * x + c * y); ys.push(cornerY + b * x + d * y);
        }
        const left = Math.min(...xs), top = Math.min(...ys);
        payload += RS + 's' + US + axes + US + box(left, top, Math.max(...xs) - left, Math.max(...ys) - top) + ',' + round(node.clientWidth) + ',' + round(node.clientHeight)
          + ',' + map.map(value => Math.round(value * 1e6) / 1e6).join(',');
        if (node === root) break;
        continue;
      }
      const visible = box(r.left + node.clientLeft * kx, r.top + node.clientTop * ky, node.clientWidth * kx, node.clientHeight * ky);
      payload += RS + 's' + US + axes + US + (scaled ? visible + ',' + round(node.clientWidth) + ',' + round(node.clientHeight) : visible);
    }
    if (node === root) break;
  }
  return payload;
}

/** `frame` (the box in the window) with the size the element lays out at, when a scale or rotation above it makes the two
 * differ, and then where its axes go in the window (`axisMap`) when they are turned or mirrored: the two sizes give a plain
 * scale, not a rotation, which trades the box's width for its height. */
function withLocal(frame, rect, local, element) {
  if (!local) return frame;
  // A square turned a quarter, or a mirrored view, has the box it would have anyway: its axes say what its sizes do not.
  const map = local.width > 0 && local.height > 0 ? axisMap(element, element.ownerDocument.defaultView) : null;
  const turned = turnedAxes(map);
  if (!turned && Math.abs(local.width - rect.width) <= 0.5 && Math.abs(local.height - rect.height) <= 0.5) return frame;
  const sized = frame + ',' + round(local.width) + ',' + round(local.height);
  if (!turned) return sized;
  // Finer than a box's 1/64 pixel: the axes multiply offsets of hundreds of pixels.
  return sized + ',' + map.map(value => Math.round(value * 1e6) / 1e6).join(',');
}

/** The size a payload reports: the one the view lays out at when it carries one, else its box's. */
const payloadSize = payload => { const head = payload.split(RS, 1)[0].split(','); return (head.length >= 6 ? head.slice(4, 6) : head.slice(-2)).join(','); };
const pixels = value => { const n = parseFloat(value); return Number.isFinite(n) ? n : 0; };

/** The axis functions the text layout measurement (text-layout-host.js) takes as its `axes`. */
export const GEOMETRY_AXES = Object.freeze({axisMap, axisScales, turnedAxes});

/** The measurement of a `TextRenderer`'s text arrives after the first screen (text-layout-host.js, which `useTextLayout` hands
 * to the host). A text found before is measured when it arrives. */
export class GeometryHost {
  constructor(root, {dispatch, eventIdAttribute, eventsAttribute, batch = run => run()}) {
    this.root = root; this.document = root.ownerDocument; this.window = this.document.defaultView;
    this.dispatch = dispatch; this.eventId = eventIdAttribute; this.events = eventsAttribute; this.batch = batch;
    this.observed = new Set(); this.sent = new WeakMap();
    this.scrolled = new Set(); this.frame = 0; this.fullFrame = false;
    this.trace = {measurements: 0, dispatches: 0, scrollFrames: 0};
    this.window.__geometryTrace = this.trace;
    this.abort = new this.window.AbortController();
    const options = {passive: true, capture: true, signal: this.abort.signal};
    // Scroll does not bubble; one capturing listener sees every scroller.
    this.document.addEventListener('scroll', event => this.schedule(event.target), options);
    this.window.addEventListener('resize', () => this.schedule(null), {passive: true, signal: this.abort.signal});
    // A web font that finishes loading changes the glyphs of the texts a TextRenderer draws, not always their boxes.
    this.document.fonts?.addEventListener?.('loadingdone', () => this.batch(() => { this.textLayout?.clearFontMetrics(); this.textKeys = new WeakMap(); for (const element of this.observed) if (element.hasAttribute('data-text-layout')) this.measure(element); }), {signal: this.abort.signal});
    // text-layout-host.js once it is here, and the texts that waited for it.
    this.textLayout = null; this.textWaiting = new Set();
  }
  /** Takes the text layout measurement (text-layout-host.js) and measures the texts found before it arrived. */
  useTextLayout(textLayout) {
    this.textLayout = textLayout;
    const waiting = [...this.textWaiting]; this.textWaiting.clear();
    if (waiting.length) this.batch(() => { for (const element of waiting) this.measure(element); });
  }
  selector() { return `[data-geometry-reader][${this.eventId}],[data-geometry-change][${this.eventId}],[data-text-layout][${this.eventId}]`; }
  schedule(target) {
    if (target === null || target === this.document || target === this.document.documentElement) this.fullFrame = true;
    else if (target?.nodeType === 1) this.scrolled.add(target);
    if (!this.frame) this.frame = this.window.requestAnimationFrame(() => this.flushPositions());
  }
  /** Re-measures position readers under the scrolled ancestors. */
  flushPositions() {
    this.frame = 0; this.trace.scrollFrames++;
    const full = this.fullFrame, scrolled = [...this.scrolled];
    this.fullFrame = false; this.scrolled.clear();
    for (const element of this.observed) {
      if (!element.isConnected || !this.tracksPosition(element)) continue;
      if (full || scrolled.some(host => host.contains(element) && host !== element)) this.measure(element);
    }
  }
  tracksPosition(element) {
    return element.getAttribute('data-geometry-position') === 'true' || element.getAttribute('data-geometry-change-position') === 'true';
  }
  /** Sends each geometry event whose observable value changed. Size-only
   * consumers are deduplicated by size so moving them costs nothing. */
  measure(element) {
    if (!element?.isConnected) return;
    // A view without a layout box (an inactive tab panel, a collapsed
    // disclosure) has no geometry to report: keep the last measurement so
    // hiding and re-showing it does not re-render its whole subtree twice.
    if (element.getClientRects().length === 0) return;
    const id = element.getAttribute(this.eventId); if (!id) return;
    const names = (element.getAttribute(this.events) || '').split(',');
    const payload = measurementPayload(element, this.root);
    this.trace.measurements++;
    let sent = this.sent.get(element); if (!sent) { sent = {}; this.sent.set(element, sent); }
    const send = (name, position) => {
      if (!names.includes(name)) return;
      const key = id + '|' + (position ? payload : payloadSize(payload));
      if (sent[name] === key) return;
      sent[name] = key; this.trace.dispatches++;
      this.trace.log?.push([name, payload.split(RS, 1)[0], element.tagName + '.' + String(element.className).slice(0, 60), element.closest('[role=tabpanel]')?.id || '']);
      this.dispatch(element, name, payload);
    };
    if (element.hasAttribute('data-geometry-reader')) send('geometry', element.getAttribute('data-geometry-position') === 'true');
    if (element.hasAttribute('data-geometry-change')) send('geometryChange', element.getAttribute('data-geometry-change-position') === 'true');
    if (element.hasAttribute('data-text-layout') && names.includes('textLayout')) {
      const textLayout = this.textLayout;
      if (!textLayout) { this.textWaiting.add(element); return; }
      // Measuring every grapheme is the costly part: it runs again only when the text, its size or its style changed.
      const rect = element.getBoundingClientRect();
      let styles = element.getAttribute('style') || '';
      for (const run of element.querySelectorAll('[style]:not(canvas)')) styles += '|' + run.getAttribute('style');
      const key = id + '|' + rect.width + ',' + rect.height + '|' + element.textContent + '|' + styles + '|' + textLayout.paintKey(element);
      this.textKeys ||= new WeakMap();
      if (this.textKeys.get(element) !== key) {
        this.textKeys.set(element, key);
        const layout = textLayout.textLayoutPayload(element, GEOMETRY_AXES);
        if (sent.textLayout !== layout) { sent.textLayout = layout; this.trace.dispatches++; this.dispatch(element, 'textLayout', layout); }
      }
    }
  }
  /** Whether `sync` can change anything after a commit with these changes. With no view observed, it observes what the patch
   * adds or changes to match the selector (a stopped match, an attribute removed from a view that was observed, is covered by
   * the changed attributes: the view no longer matches). With a view observed, every commit syncs: `sync` re-measures every view
   * after the next layout (`measureAfterLayout`), since a patch can move a view without changing its size or any attribute
   * of its own, and no observer reports a move. */
  needsSync(changes) {
    if (changes.everything || this.observed.size) return true;
    return changes.touches(this.selector()) || changes.changedAttribute(['data-geometry-reader', 'data-geometry-change', 'data-text-layout', this.eventId]);
  }
  /** After a commit or settled layout: observe new views, forget removed
   * ones and re-measure everything (positions may have moved) once the
   * browser has laid the page out.
   *
   * Measuring here, in the middle of the commit, made the browser recalculate
   * style and lay out right away for what the patch and the layout pass had
   * just written (the largest forced recalculation of a commit: 774 elements
   * on a navigation in a large app), and the frame's own rendering did it again
   * for what came after. A ResizeObserver notification arrives after the
   * frame's layout and before its paint, so the same reads cost nothing and
   * the values reach Swift in the same frame as before. */
  sync() {
    this.resizeObserver ||= new this.window.ResizeObserver(entries => this.batch(() => { for (const entry of entries) this.measure(entry.target); }));
    const added = [];
    for (const element of this.root.querySelectorAll(this.selector())) {
      if (!this.observed.has(element)) { this.observed.add(element); this.resizeObserver.observe(element); added.push(element); }
    }
    for (const element of this.observed) {
      if (!this.root.contains(element) || !element.matches(this.selector())) { this.resizeObserver.unobserve(element); this.observed.delete(element); }
    }
    if (this.observed.size) this.measureAfterLayout();
    // The views measured for the first time, whose layout may change once Swift has their size (`data-measuring`).
    return added;
  }
  /** Re-measures every observed view in the next ResizeObserver delivery: observing an element (again) always reports
   * it once, after the next layout. The reports of one delivery reach Swift as one batch. */
  measureAfterLayout() {
    if (this.measurePending) return;
    this.measurePending = true;
    this.probe ||= new this.window.ResizeObserver(() => {
      if (!this.measurePending) return;
      this.measurePending = false; this.probe.unobserve(this.root);
      this.batch(() => { for (const element of this.observed) this.measure(element); });
    });
    this.probe.observe(this.root);
  }
  /** Measures `elements` now, in one batch (the commit that inserted them, which this lays out right away). */
  measureNow(elements) { this.batch(() => { for (const element of elements) this.measure(element); }); }
  dispose() {
    this.abort.abort(); this.resizeObserver?.disconnect(); this.probe?.disconnect(); this.measurePending = false; this.observed.clear(); this.textWaiting.clear();
    if (this.frame) this.window.cancelAnimationFrame(this.frame);
  }
}
