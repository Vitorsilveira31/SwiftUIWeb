/** The page's scroll view as the document's scroll (Documentation/Architecture/CSS_LAYOUT.md, "The document scrolls").
 *
 * A browser on a phone shows the page in a viewport its own bars float over: Safari's bottom bar, Chrome's address bar. The
 * page runs under them and the bars shrink as it scrolls, but only when the document itself scrolls. A SwiftUI window keeps
 * its scrolling in a ScrollView whose box is the window's height (`100dvh`), so the page ended a bar's height above the
 * bottom of the screen and the bars never shrank. On a touch screen (`pointer: coarse`) the vertical ScrollView that reaches
 * the bottom of the window (the page's scroll view) hands its scrolling to the document:
 *
 * - it and the views around it up to the window (the chain) grow with what it holds, and are never shorter than the window
 *   leaves them, so a short page still fills the screen as before;
 * - what sits above it in the chain (a header, a Divider) sticks to the top of the screen where it is, and what sits below
 *   it (a bar, a safe-area inset) to the bottom, so the page looks as it did; a view stuck there that paints no background
 *   gets the window's, as SwiftUI shows the window behind it and not the page scrolled under it;
 * - the scroll view answers for the document: its `scrollTop`, `scrollTo`, `scrollHeight`, `clientHeight`, its box (the
 *   part of the screen between what sticks at the top and at the bottom) and its `scroll` events are the window's, so
 *   everything that reads or moves a scroll view (scroll positions, lazy stacks, `scrollTo`, a large title) works unchanged.
 *
 * Switching the page's scroll view (another tab shown) keeps each one's offset, as a tab keeps its own. A window this cannot
 * hand over keeps the scroll view's own scrolling: one inside a NavigationStack, a sidebar-adaptable TabView, a
 * GeometryReader or a user-defined Layout, or with a layer over the chain (an overlay) that is not as large as what it covers.
 */
const COARSE = '(pointer: coarse)';
// The views a chain does not cross: their layout keeps a box of the window's size (a navigation bar over a screen, a
// sidebar beside it, a container size the content reads, subviews Swift placed at a size).
const BARRIERS = '.navigation-stack,.navigation-view,.tab-view[data-tab-style="sidebar-adaptable"],[data-geometry-reader],.geometry-reader,.layout-box,.split-pane,.presentation-root,.presentation-content';
const proto = typeof Element === 'undefined' ? null : Element.prototype;
const realRect = element => proto.getBoundingClientRect.call(element);
const displayed = element => element.checkVisibility ? element.checkVisibility() : element.getClientRects().length > 0;
// The rules of the document scroll. They sit in a constructed stylesheet of their own, outside the stylesheet's layers, as
// the CSS layout's blocks do (css-layout.js). Those blocks (`[data-cl-n]`) are `!important` so that a component's rule
// cannot undo the layout; these are too, and outrank them by specificity:
// - the page's scroll view and its chain grow with the page, never shorter than the window leaves them; one that clipped
//   or scrolled (`="clip"`, a TabView's panel) clips across only, which keeps it from being a scroll container;
// - a view that sticks stays where it is at the top of the screen or at the bottom (not while the module measures the flow),
//   over the page, on the window's background when it paints none.
const RULES = [
  '[data-document-scroll-root] [data-document-scroll-chain][data-document-scroll-chain],[data-document-scroll-root] [data-document-scroller][data-document-scroller]{height:auto !important;max-height:none !important;min-height:var(--document-scroll-min,0px) !important}',
  '[data-document-scroll-root] [data-document-scroll-chain="clip"][data-document-scroll-chain],[data-document-scroll-root] [data-document-scroller][data-document-scroller]{overflow-x:clip !important;overflow-y:visible !important}',
  '[data-document-scroll-root]:not([data-document-scroll-measuring]) [data-document-sticky="top"][data-document-sticky]{position:sticky !important;top:var(--document-sticky-offset,0px) !important;bottom:auto !important;z-index:30 !important}',
  '[data-document-scroll-root]:not([data-document-scroll-measuring]) [data-document-sticky="bottom"][data-document-sticky]{position:sticky !important;bottom:var(--document-sticky-offset,0px) !important;top:auto !important;z-index:30 !important}',
  '[data-document-scroll-root]:not([data-document-scroll-measuring]) [data-document-sticky-fill][data-document-sticky-fill]{background-color:var(--color-swu-background) !important}',
].join('\n');
const transparent = color => color === 'transparent' || /rgba?\([^)]*,\s*0\)$/.test(color) || /\/\s*0\)$/.test(color);

export class DocumentScroll {
  constructor(root) {
    this.root = root; this.document = root.ownerDocument; this.window = this.document.defaultView;
    this.media = this.window.matchMedia?.(COARSE) ?? null;
    this.active = null; this.offsets = new WeakMap();
    this.sheet = null;
    // Each scroll is the page's offset, kept as it happens: by the time a pass sees another tab shown, the browser has already
    // brought the shorter document back to its top.
    this.onScroll = () => {
      const s = this.active?.scroller;
      if (!s) return;
      this.offsets.set(s, this.window.scrollY);
      s.dispatchEvent(new this.window.Event('scroll'));
    };
  }
  get enabled() { return !!this.media?.matches; }
  /** Before a layout pass: the document's offset. A pass can lay the page out shorter for a moment (a ViewThatFits measured
   * with no candidate shown), and the browser then brings the document back towards its top; `sync` puts it back. */
  begin() { this.begun = this.active ? { scroller: this.active.scroller, top: this.window.scrollY } : null; }
  /** After a layout pass: hand the page's scroll view to the document, or give it back, and keep what sticks in place. */
  sync() {
    const windowRoot = this.enabled ? this.windowRoot() : null;
    const scroller = windowRoot ? this.find(windowRoot) : null;
    if (this.active && (this.active.scroller !== scroller || this.active.windowRoot !== windowRoot)) this.leave();
    if (scroller && !this.active) this.enter(scroller, windowRoot);
    if (this.active) {
      this.refresh();
      const begun = this.begun;
      if (begun?.scroller === this.active.scroller && this.window.scrollY !== begun.top) this.window.scrollTo({ top: begun.top, left: this.window.scrollX, behavior: 'instant' });
    }
    this.begun = null;
  }
  windowRoot() {
    for (const child of this.root.children) if (!child.classList.contains('presentation-root') && !child.classList.contains('presentation-backdrop') && displayed(child)) return child;
    return null;
  }
  /** The page's scroll view: a vertical ScrollView as wide as the window that reaches its bottom, with nothing between it and
   * the window that keeps a box of its own (`BARRIERS`, another scroll view, a layer narrower than what it covers). */
  find(windowRoot) {
    const box = realRect(windowRoot);
    if (box.height === 0) return null;
    let best = null, area = 0;
    for (const scroller of windowRoot.querySelectorAll('.scroll-view.scroll-vertical')) {
      if (scroller.parentElement?.closest('.scroll-view') && windowRoot.contains(scroller.parentElement.closest('.scroll-view'))) continue;
      if (!displayed(scroller)) continue;
      const r = realRect(scroller);
      if (r.width < box.width - 1 || r.bottom < box.bottom - 1 || r.height === 0) continue;
      if (!this.crossable(scroller, windowRoot)) continue;
      if (r.width * r.height > area) { best = scroller; area = r.width * r.height; }
    }
    return best;
  }
  crossable(scroller, windowRoot) {
    for (let e = scroller.parentElement; e; e = e.parentElement) {
      if (e.matches(BARRIERS)) return false;
      // A layer the chain's view carries (an overlay) is placed against it: as tall as the page, it would leave the screen.
      for (const sibling of e.children) {
        if (!displayed(sibling) || sibling.contains(scroller)) continue;
        const position = this.window.getComputedStyle(sibling).position;
        if (position !== 'absolute' && position !== 'fixed') continue;
        const s = realRect(sibling), p = realRect(e);
        if (s.width < p.width - 1 || s.height < p.height - 1) return false;
      }
      if (e === windowRoot) return true;
      const overflow = this.window.getComputedStyle(e).overflowY;
      if ((overflow === 'auto' || overflow === 'scroll') && !e.classList.contains('tab-panel') && !e.hasAttribute('data-document-scroll-chain')) return false;
    }
    return false;
  }
  enter(scroller, windowRoot) {
    const top = this.offsets.get(scroller) ?? Object.getOwnPropertyDescriptor(proto, 'scrollTop').get.call(scroller);
    const chain = [];
    for (let e = scroller.parentElement; e; e = e.parentElement) { chain.push(e); if (e === windowRoot) break; }
    this.active = { scroller, windowRoot, chain, stuck: [], insetTop: 0, insetBottom: 0 };
    this.setPadding(0);
    this.root.setAttribute('data-document-scroll-root', '');
    scroller.setAttribute('data-document-scroller', '');
    // Read before anything changes: a view that clipped or scrolled keeps clipping across.
    const clips = chain.map(e => { const style = this.window.getComputedStyle(e); return style.overflowX !== 'visible' || style.overflowY !== 'visible'; });
    chain.forEach((e, i) => e.setAttribute('data-document-scroll-chain', clips[i] ? 'clip' : ''));
    this.install(scroller);
    this.window.addEventListener('scroll', this.onScroll, { passive: true });
    this.refresh();
    // The document takes this scroll view's offset, its top included: the page left behind may have been scrolled.
    this.offsets.set(scroller, top || 0);
    this.window.scrollTo({ top: top || 0, left: 0, behavior: 'instant' });
  }
  leave() {
    const { scroller, chain, stuck } = this.active;
    const top = this.offsets.get(scroller) ?? 0;
    this.window.removeEventListener('scroll', this.onScroll);
    this.uninstall(scroller);
    for (const e of stuck) { e.removeAttribute('data-document-sticky'); e.removeAttribute('data-document-sticky-fill'); e.style.removeProperty('--document-sticky-offset'); }
    for (const e of [scroller, ...chain]) { e.removeAttribute('data-document-scroll-chain'); e.style.removeProperty('--document-scroll-min'); }
    scroller.removeAttribute('data-document-scroller');
    this.root.removeAttribute('data-document-scroll-root');
    this.active = null;
    this.setPadding(null);
    // A scroll view that stays on screen keeps its place (the window went from a phone's to a desktop's pointer).
    if (top && displayed(scroller)) scroller.scrollTop = top;
  }
  /** What sticks, where, and how tall the chain must stay: measured with nothing stuck, at the document's coordinates. */
  refresh() {
    const a = this.active, { scroller, windowRoot, chain } = a;
    const sy = this.window.scrollY, doc = r => ({ top: r.top + sy, bottom: r.bottom + sy, height: r.height });
    const stuck = new Map();
    for (let child = scroller; child !== windowRoot; child = child.parentElement) {
      const parent = child.parentElement;
      for (const sibling of parent.children) {
        if (sibling === child || !displayed(sibling)) continue;
        const position = this.window.getComputedStyle(sibling).position;
        if (position === 'absolute' || position === 'fixed') continue;
        stuck.set(sibling, child);
      }
    }
    // What the measure below follows, read as the page is: what sticks and how tall each is, where the scroll view starts and
    // how much of the window follows it. A pass that changed none of it (a commit inside the page, a key in a field) measures
    // nothing again: the measure lays the page out twice.
    const sr = realRect(scroller), rr = realRect(windowRoot);
    const key = [...stuck.keys()].map(e => Math.round(realRect(e).height)).join(',') + `|${Math.round(sr.top + sy)}|${Math.round(rr.bottom - sr.bottom)}|${Math.round(rr.top + sy)}`;
    if (key === a.key && a.stuck.length === stuck.size && a.stuck.every(e => stuck.has(e))) return;
    a.key = key;
    // Measured with nothing stuck and nothing filled: where each view is in the flow, and whether it paints a background.
    this.root.setAttribute('data-document-scroll-measuring', '');
    const natural = new Map(), fills = new Map(), rootBox = doc(realRect(windowRoot));
    for (const e of [scroller, ...chain, ...stuck.keys()]) natural.set(e, doc(realRect(e)));
    for (const e of stuck.keys()) fills.set(e, transparent(this.window.getComputedStyle(e).backgroundColor));
    this.root.removeAttribute('data-document-scroll-measuring');
    const edges = new Map();
    for (const [sibling, child] of stuck) {
      const s = natural.get(sibling), c = natural.get(child);
      edges.set(sibling, s.top + s.height / 2 <= c.top + Math.min(c.height, this.viewport()) / 2 ? 'top' : 'bottom');
    }
    for (const e of a.stuck) if (!stuck.has(e)) { e.removeAttribute('data-document-sticky'); e.removeAttribute('data-document-sticky-fill'); e.style.removeProperty('--document-sticky-offset'); }
    a.stuck = [...stuck.keys()];
    for (const [e, edge] of edges) {
      // Stuck where it is at the top of the document, or at its end.
      const n = natural.get(e), offset = edge === 'top' ? n.top : rootBox.bottom - n.bottom;
      if (e.getAttribute('data-document-sticky') !== edge) e.setAttribute('data-document-sticky', edge);
      write(e, '--document-sticky-offset', Math.round(offset) + 'px');
      const fill = fills.get(e);
      if (fill !== e.hasAttribute('data-document-sticky-fill')) e.toggleAttribute('data-document-sticky-fill', fill);
    }
    const s = natural.get(scroller);
    a.insetTop = Math.max(0, s.top);
    // What follows the scroll view in the flow ends the document after it; a bar laid over its end does not.
    a.insetBottom = Math.max(0, rootBox.bottom - s.bottom);
    // Each view of the chain is at least as tall as the window leaves it: the screen less what is above and below it.
    for (const e of [scroller, ...chain]) {
      const n = natural.get(e);
      write(e, '--document-scroll-min', `calc(100dvh - ${Math.round(Math.max(0, n.top - rootBox.top) + Math.max(0, rootBox.bottom - n.bottom))}px)`);
    }
    this.setPadding(a.insetTop);
  }
  viewport() { return this.document.documentElement.clientHeight || this.window.innerHeight; }
  /** The rules, adopted the first time a page's scroll view is handed over, and while it is (`top` not null) the document's:
   * `scroll-padding-top`, so that `scrollIntoView` and a fragment stop below what sticks at the top, as they stop at a scroll
   * view's top edge; and no scroll anchoring, which moves the document when a header above the page grows (a scroll view
   * below a header that grows keeps its offset and gets shorter). */
  setPadding(top) {
    if (!this.sheet) { this.sheet = new this.window.CSSStyleSheet(); this.document.adoptedStyleSheets = [...this.document.adoptedStyleSheets, this.sheet]; }
    const text = RULES + (top == null ? '' : `\n:root{overflow-anchor:none;scroll-padding-top:${Math.round(top)}px}`);
    if (this.sheet.__text !== text) { this.sheet.replaceSync(text); this.sheet.__text = text; }
  }
  /** The scroll view answers for the document. */
  install(scroller) {
    const self = this, w = this.window;
    const top = () => w.scrollY;
    const height = () => Math.max(0, self.viewport() - self.active.insetTop - self.active.insetBottom);
    const define = (name, descriptor) => Object.defineProperty(scroller, name, { configurable: true, ...descriptor });
    define('scrollTop', { get: top, set: v => w.scrollTo({ top: Number(v) || 0, left: w.scrollX, behavior: 'instant' }) });
    define('scrollHeight', { get: () => Math.max(Math.round(realRect(scroller).height), height()) });
    define('clientHeight', { get: () => Math.round(height()) });
    const move = (base, args) => {
      const [first, second] = args;
      const options = typeof first === 'object' && first !== null ? first : { left: first, top: second };
      const t = options.top == null ? undefined : base + Number(options.top);
      if (t === undefined) return;
      w.scrollTo({ top: t, left: w.scrollX, behavior: options.behavior ?? 'auto' });
    };
    define('scrollTo', { value: (...args) => move(0, args) });
    define('scroll', { value: (...args) => move(0, args) });
    define('scrollBy', { value: (...args) => move(top(), args) });
    define('getBoundingClientRect', { value: () => {
      const r = realRect(scroller), t = self.active.insetTop, b = Math.max(t, self.viewport() - self.active.insetBottom);
      return new w.DOMRect(r.left, t, r.width, b - t);
    } });
  }
  uninstall(scroller) {
    for (const name of ['scrollTop', 'scrollHeight', 'clientHeight', 'scrollTo', 'scroll', 'scrollBy', 'getBoundingClientRect']) delete scroller[name];
  }
  dispose() { if (this.active) this.leave(); }
}

function write(element, name, value) { if (element.style.getPropertyValue(name) !== value) element.style.setProperty(name, value); }
