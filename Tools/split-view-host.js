// Divider drag and keyboard resizing for HSplitView and VSplitView.
//
// Swift places each pane in a `split-item` (its box inline: left, top, width, height) and each divider in the layout box
// beside it. A divider carries its split's axis and index, and each pane carries its limits in px (`data-split-min`, and
// `data-split-max` when it has one). A pointer drag or an arrow key moves a divider here: the two panes it separates take
// their new boxes, one DOM write batch per pointer frame, with no Swift round trip per move. The CSS layout lays out the
// content of those panes again from their boxes (its observer sees the writes). When the move ends (pointer up, or one key
// press), the divider reports its positions to Swift as `split-positions`: "p0,p1,..." with one fraction of the split per
// pane, summing to 1. Swift keeps them (`_SplitViewStateStore`) and renders the split from them.

const DIVIDER = '[data-split-divider-index]';
// An arrow key moves a divider by this fraction of the split, a Shift+arrow by the larger one, as the browser runtime did.
const KEY_STEP = 0.02;
const KEY_STEP_LARGE = 0.1;

/** The pane sizes after the divider between `index` and `index + 1` moves by `delta` px. Only those two panes change, and a
 * move stops at the limit of either. `minimums` and `maximums` hold each pane's limit; a move the limits forbid changes nothing. */
export function movedSizes(sizes, index, delta, minimums, maximums) {
  const pair = sizes[index] + sizes[index + 1];
  const lower = Math.max(minimums[index], pair - maximums[index + 1]);
  const upper = Math.min(maximums[index], pair - minimums[index + 1]);
  if (!(upper >= lower)) return sizes;
  const leading = Math.min(upper, Math.max(lower, sizes[index] + delta));
  const next = sizes.slice();
  next[index] = leading;
  next[index + 1] = pair - leading;
  return next;
}

const sum = (values) => values.reduce((total, value) => total + value, 0);

// The extent a pane was placed with, as Swift wrote it (its inline box), not as the browser rounds a measurement.
const extentOf = (item, horizontal) => parseFloat(horizontal ? item.style.width : item.style.height);

export class SplitViewHost {
  constructor(root, { dispatchNamed, window: host = globalThis.window }) {
    this.root = root;
    this.window = host;
    this.dispatchNamed = dispatchNamed;
    // The drag in progress (a pointer holds the divider), and the animation frame that will place its next move.
    this.drag = null;
    this.frame = 0;
    // The fractions each split was last placed at, by its layout box.
    this.remembered = new WeakMap();
    this.abort = new host.AbortController();
    root.addEventListener('pointerdown', (event) => this.pointerDown(event), { capture: true, signal: this.abort.signal });
    root.addEventListener('pointermove', (event) => this.pointerMove(event), { capture: true, signal: this.abort.signal });
    root.addEventListener('pointerup', (event) => this.pointerEnd(event), { capture: true, signal: this.abort.signal });
    root.addEventListener('pointercancel', (event) => this.pointerEnd(event), { capture: true, signal: this.abort.signal });
    root.addEventListener('keydown', (event) => this.keyDown(event), { signal: this.abort.signal });
  }

  pointerDown(event) {
    const divider = this.dividerOf(event);
    if (!divider || event.button !== 0 || this.drag) return;
    const drag = this.begin(divider);
    if (!drag) return;
    drag.pointerId = event.pointerId;
    drag.coordinate = drag.horizontal ? event.clientX : event.clientY;
    drag.userSelect = this.body().style.userSelect;
    this.body().style.userSelect = 'none';
    this.drag = drag;
    event.preventDefault();
    divider.focus({ preventScroll: true });
    try { divider.setPointerCapture(event.pointerId); } catch {}
  }

  pointerMove(event) {
    const drag = this.drag;
    if (!drag || event.pointerId !== drag.pointerId) return;
    const coordinate = drag.horizontal ? event.clientX : event.clientY;
    drag.delta = (coordinate - drag.coordinate) / drag.scale;
    if (!this.frame) this.frame = this.window.requestAnimationFrame(() => this.placeFrame());
  }

  pointerEnd(event) {
    const drag = this.drag;
    if (!drag || event.pointerId !== drag.pointerId) return;
    this.drag = null;
    if (this.frame) this.window.cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.move(drag, this.sizesFor(drag));
    this.body().style.userSelect = drag.userSelect;
    try { drag.divider.releasePointerCapture(event.pointerId); } catch {}
    this.report(drag);
  }

  keyDown(event) {
    const divider = this.dividerOf(event);
    if (!divider || this.drag || event.altKey || event.ctrlKey || event.metaKey) return;
    const drag = this.begin(divider);
    if (!drag) return;
    const horizontal = drag.horizontal;
    const step = (event.shiftKey ? KEY_STEP_LARGE : KEY_STEP) * sum(drag.start);
    let delta;
    if (event.key === (horizontal ? 'ArrowRight' : 'ArrowDown')) delta = step;
    else if (event.key === (horizontal ? 'ArrowLeft' : 'ArrowUp')) delta = -step;
    else if (event.key === 'Home') delta = -Infinity;
    else if (event.key === 'End') delta = Infinity;
    else return;
    event.preventDefault();
    event.stopPropagation();
    drag.delta = delta;
    this.move(drag, this.sizesFor(drag));
    this.report(drag);
  }

  placeFrame() {
    this.frame = 0;
    if (this.drag) this.move(this.drag, this.sizesFor(this.drag));
  }

  sizesFor(drag) {
    return movedSizes(drag.start, drag.index, drag.delta, drag.minimums, drag.maximums);
  }

  // Writes the panes and dividers at `sizes` when they differ from the ones on the page.
  move(drag, sizes) {
    if (sizes.every((size, index) => size === drag.current[index])) return;
    drag.current = sizes;
    drag.moved = true;
    const total = sum(sizes);
    this.remembered.set(drag.wrapper, sizes.map((size) => size / total));
    place(drag, sizes);
  }

  report(drag) {
    if (!drag.moved || !drag.divider.isConnected) return;
    const total = sum(drag.current);
    if (!(total > 0)) return;
    this.dispatchNamed(drag.divider, 'split-positions', drag.current.map((size) => String(size / total)).join(','));
  }

  // The state a move starts from: the panes as they are on the page, and the limits Swift gave them.
  begin(divider) {
    const wrapper = divider.parentElement;
    const horizontal = divider.getAttribute('data-split-axis') === 'horizontal';
    const index = Number(divider.getAttribute('data-split-divider-index'));
    const items = [...wrapper.children].filter((child) => child.hasAttribute('data-split-item-index'));
    const dividers = [...wrapper.children].filter((child) => child.hasAttribute('data-split-divider-index'));
    if (!(index >= 0) || index + 1 >= items.length) return null;
    const thickness = Number(wrapper.getAttribute('data-split-divider-size')) || 6;
    // The panes start from the fractions this host last placed and reported, not from the page: a commit of an earlier report
    // can land between two moves and put the panes back where that report had them. The split's own extent is what Swift wrote.
    const available = parseFloat(horizontal ? wrapper.style.width : wrapper.style.height) - dividers.length * thickness;
    const remembered = this.remembered.get(wrapper);
    const start = remembered && remembered.length === items.length && available > 0
      ? remembered.map((fraction) => fraction * available)
      : items.map((item) => extentOf(item, horizontal));
    if (!start.every(Number.isFinite) || !(sum(start) > 0)) return null;
    const box = wrapper.getBoundingClientRect();
    const measured = horizontal ? wrapper.offsetWidth : wrapper.offsetHeight;
    const scale = measured > 0 ? (horizontal ? box.width : box.height) / measured : 1;
    return {
      divider, wrapper, horizontal, index, items, dividers, start, current: start,
      minimums: items.map((item) => Number(item.getAttribute('data-split-min')) || 0),
      maximums: items.map((item) => (item.hasAttribute('data-split-max') ? Number(item.getAttribute('data-split-max')) : Infinity)),
      thickness,
      scale, delta: 0, moved: false, coordinate: 0, pointerId: null, userSelect: '',
    };
  }

  dividerOf(event) {
    const divider = event.target?.closest?.(DIVIDER);
    return divider && this.root.contains(divider) ? divider : null;
  }

  body() {
    return this.root.ownerDocument.body;
  }

  dispose() {
    this.abort.abort();
    if (this.frame) this.window.cancelAnimationFrame(this.frame);
    this.frame = 0;
    if (this.drag) this.body().style.userSelect = this.drag.userSelect;
    this.drag = null;
  }
}

// Places every pane and divider of a split at `sizes` (px along the axis), and records the same positions as fractions on
// the layout box and its children, where Swift keeps them.
function place(drag, sizes) {
  const total = sum(sizes);
  const encoded = sizes.map((size) => String(size / total)).join(',');
  const [offset, extent] = drag.horizontal ? ['left', 'width'] : ['top', 'height'];
  let position = 0;
  let boundary = 0;
  drag.items.forEach((item, index) => {
    item.style[offset] = `${position}px`;
    item.style[extent] = `${sizes[index]}px`;
    item.setAttribute('data-split-positions', encoded);
    position += sizes[index];
    boundary += sizes[index] / total;
    const divider = drag.dividers[index];
    if (!divider) return;
    divider.style[offset] = `${position}px`;
    divider.setAttribute('aria-valuenow', String(boundary * 100));
    divider.setAttribute('data-split-positions', encoded);
    position += drag.thickness;
  });
  drag.wrapper.setAttribute('data-split-positions', encoded);
}
