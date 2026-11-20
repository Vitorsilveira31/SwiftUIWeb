/** Insertion and removal transitions, and the motion of the siblings around them (Sources/SwiftUIWebCore/Transitions.swift).
 * Host-only module of the retained DOM host (embedded-dom.js).
 *
 * In SwiftUI a view inserted or removed in an animated transaction plays its transition (opacity unless it says
 * otherwise), and the views around it move to their new places with the same animation. Here:
 * - an inserted element plays its active state (`data-transition-insert`) into identity;
 * - a removed element stays where it was, out of the layout (absolutely positioned at its last box, inert), plays
 *   identity into its removal state (`data-transition-remove`) and is taken out when that ends;
 * - the siblings of a parent whose children changed are moved from their old boxes to their new ones (FLIP: their
 *   offset is measured before and after the patch and animated away with an additive `translate`).
 * - a text whose view has a `.contentTransition` replaces its characters as that transition says: `numericText` rolls the
 *   changed characters vertically (up when the number grows), `opacity` and `interpolate` cross-fade the text.
 * The animation is the element's own (`data-transition-timing`, `AnyTransition.animation`) or the commit's: the
 * `withAnimation` transaction, or an `.animation(_:value:)` on an ancestor whose value changed in this commit.
 */

const LEAVING = 'data-transition-leaving';
// The tables below that are built by a call are marked pure, so a release that leaves this module out
// (Tools/build-runtime-bundle.mjs) drops them too: a bundler keeps a top-level call it cannot prove free of effects.
// Elements the framework or another host owns the arrival of (presentations, navigation, lazy windows, tab panels), and
// nodes that are not views. They keep their own motion; only an explicit `.transition` overrides that.
const OWN_MOTION = '[data-lazy-cell],[data-lazy-spacer],[data-lazy-owner],.presentation-root,[data-presentation-id],.navigation-destination,[data-tab-panel],[data-tab-content],[popover],dialog,.context-menu-panel,[data-measurement-island],[data-hover-rules],[data-geometry-host],[data-timeline-view="true"]';
// Surfaces that leave as they arrived, backwards (`[data-exit-animation="true"]` in styles.css), whether or not the commit
// that dismisses them animates: SwiftUI dismisses a sheet, a cover, a popover, an alert or a dialog, and pops a navigation
// destination, with the same motion it presented them with.
const EXITING_SURFACES = '.presentation-root,.sheet-panel,.full-screen-cover,.popover-card,.alert-panel,.confirmation-dialog,.navigation-destination,.toast-banner,.tooltip-bubble';
// The presentations a removed subtree may hold (a destination or a toast inside it leaves with the subtree, at once).
const PRESENTATION_SURFACES = '.presentation-root,.sheet-panel,.full-screen-cover,.popover-card,.alert-panel,.confirmation-dialog';
// The longest exit styles.css plays; a surface whose animation never starts (hidden, unsupported) leaves after it.
const EXIT_LIMIT = 900;
// The screens of a navigation stack: its root and the destinations pushed on it.
const SCREENS = '.navigation-root,.navigation-destination';
// Marks the screen under a push or a pop while the screen on top slides (styles.css): "covered" under a push, "revealed"
// under a pop.
const NAVIGATION_MOTION = 'data-navigation-motion';
// The animation (styles.css) that plays each part of a push or a pop: the screen on top (no state), the one it covers, the
// one a pop reveals.
const NAVIGATION_ANIMATIONS = {top: 'swu-navigation-push', covered: 'swu-navigation-cover', revealed: 'swu-navigation-reveal'};
const MOTION_PROPERTIES = ['--motion-surface', '--motion-left', '--motion-top', '--motion-width', '--motion-height', '--motion-shift'];
// Surfaces whose arrival styles.css animates (`[data-enter-animation="true"]`): sheets, covers, popovers, alerts, dialogs,
// navigation destinations, toasts and tooltips. They animate as SwiftUI presents them, with or without `withAnimation`;
// the host marks one when it is inserted after the first commit, and unmarks it when its animation ends.
const ENTERING_SURFACES = '.presentation-root,.sheet-panel,.full-screen-cover,.popover-card,.alert-panel,.confirmation-dialog,.navigation-destination,.toast-banner,[role="status"],[aria-live="polite"],.tooltip-bubble,[data-tooltip]';
const VIEW_TRANSITION_NAMED = '[style*="view-transition-name"]';
const NOT_VIEWS = /* @__PURE__ */ new Set(['style', 'script', 'template', 'link', 'meta', 'source', 'track', 'option', 'optgroup']);
// The siblings of one parent that FLIP measures at most; a bigger list (a long eager stack) only plays its transitions.
const FLIP_LIMIT = 64;
const RUN = 'data-content-run';
// The `scopedTiming` of a `.transaction` that disables animation: distinct from "no transaction" (null), which lets the
// ancestor's `.animation` decide.
const DISABLED = /* @__PURE__ */ Object.freeze({disabled: true});
const numberIn = text => { const match = (text || '').replace(/[^\d.,-]/g, '').replace(/,/g, '').match(/-?\d+(?:\.\d+)?/); return match ? Number(match[0]) : NaN; };
// The discrete symbol effects (`symbolEffect(_:options:value:)`): keyframes of the glyph's individual transform properties,
// so they compose with the view's own transform, and how long one run lasts.
const swing = (axis, sign) => [0, 1, -0.7, 0.45, -0.2, 0].map(step => ({translate: axis === 'x' ? `${sign * step * 14}% 0` : `0 ${sign * step * 14}%`}));
const SYMBOL_EFFECTS = /* @__PURE__ */ (() => ({
  'bounce': [[{translate: '0 0', scale: '1'}, {translate: '0 -22%', scale: '1.04 0.96', offset: 0.3}, {translate: '0 4%', scale: '0.98 1.02', offset: 0.62}, {translate: '0 0', scale: '1'}], 600],
  'bounce-down': [[{translate: '0 0', scale: '1'}, {translate: '0 18%', scale: '1.04 0.96', offset: 0.3}, {translate: '0 -3%', scale: '0.98 1.02', offset: 0.62}, {translate: '0 0', scale: '1'}], 600],
  'pulse': [[{opacity: 1}, {opacity: 0.35}, {opacity: 1}], 700],
  'variable-color': [[{opacity: 1}, {opacity: 0.4}, {opacity: 1}], 900],
  'scale': [[{scale: '1'}, {scale: '1.2'}, {scale: '1'}], 500],
  'scale-down': [[{scale: '1'}, {scale: '0.8'}, {scale: '1'}], 500],
  'appear': [[{opacity: 0, scale: '0.5'}, {opacity: 1, scale: '1'}], 400],
  'appear-down': [[{opacity: 0, scale: '1.5'}, {opacity: 1, scale: '1'}], 400],
  'disappear': [[{opacity: 1, scale: '1'}, {opacity: 0, scale: '0.5', offset: 0.5}, {opacity: 1, scale: '1'}], 600],
  'disappear-down': [[{opacity: 1, scale: '1'}, {opacity: 0, scale: '1.5', offset: 0.5}, {opacity: 1, scale: '1'}], 600],
  'replace-down-up': [[{opacity: 1, scale: '1'}, {opacity: 0, scale: '0.6', offset: 0.45}, {opacity: 0, scale: '0.6', offset: 0.55}, {opacity: 1, scale: '1'}], 500],
  'replace-up-up': [[{opacity: 1, scale: '1'}, {opacity: 0, scale: '1.4', offset: 0.45}, {opacity: 0, scale: '0.6', offset: 0.55}, {opacity: 1, scale: '1'}], 500],
  'replace-off-up': [[{opacity: 1, scale: '1'}, {opacity: 0, scale: '1', offset: 0.45}, {opacity: 0, scale: '0.6', offset: 0.55}, {opacity: 1, scale: '1'}], 500],
  'wiggle-clockwise': [[0, 14, -10, 6, -3, 0].map(degrees => ({rotate: degrees + 'deg'})), 700],
  'wiggle-counter-clockwise': [[0, -14, 10, -6, 3, 0].map(degrees => ({rotate: degrees + 'deg'})), 700],
  'wiggle-left': [swing('x', -1), 700],
  'wiggle-right': [swing('x', 1), 700],
  'wiggle-up': [swing('y', -1), 700],
  'wiggle-down': [swing('y', 1), 700],
  'rotate': [[{rotate: '0deg'}, {rotate: '360deg'}], 900],
  'rotate-counter-clockwise': [[{rotate: '0deg'}, {rotate: '-360deg'}], 900],
  'breathe': [[{scale: '1'}, {scale: '1.15'}, {scale: '1'}], 1200],
  'breathe-pulse': [[{scale: '1', opacity: 1}, {scale: '1.15', opacity: 0.6}, {scale: '1', opacity: 1}], 1200],
}))();
// How a replace takes the old symbol out and brings the new one in, each half on its own glyph, and how long it lasts.
const REPLACE_HALVES = {
  'replace-down-up': [[{opacity: 1, scale: '1'}, {opacity: 0, scale: '0.6'}], [{opacity: 0, scale: '0.6'}, {opacity: 1, scale: '1'}], 500],
  'replace-up-up': [[{opacity: 1, scale: '1'}, {opacity: 0, scale: '1.4'}], [{opacity: 0, scale: '0.6'}, {opacity: 1, scale: '1'}], 500],
  'replace-off-up': [[{opacity: 1}, {opacity: 0}], [{opacity: 0, scale: '0.6'}, {opacity: 1, scale: '1'}], 500],
};
// What a copy of a replaced symbol must not carry: the identities the runtime and tests find elements by.
const GHOST_ATTRIBUTE = /^(id|data-embedded-.*|data-fiber-.*|data-view-id|data-view-key|data-testid|data-accessibility-identifier|data-symbol-effect.*)$/;

/** The keyframes and duration of a discrete symbol effect by name (`wiggle-angle-<milliradians>` swings along an angle). */
export function symbolEffectFrames(name) {
  const angle = /^wiggle-angle-(-?\d+)$/.exec(name || '');
  if (angle) {
    const radians = Number(angle[1]) / 1000, x = Math.cos(radians), y = -Math.sin(radians);
    return [[0, 1, -0.7, 0.45, -0.2, 0].map(step => ({translate: `${(x * step * 14).toFixed(2)}% ${(y * step * 14).toFixed(2)}%`})), 700];
  }
  return SYMBOL_EFFECTS[name] ?? SYMBOL_EFFECTS['bounce'];
}
const camel = name => name.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());

/** `opacity:0;translate:-100% 0` → {opacity: '0', translate: '-100% 0'}; '' and 'identity' are no change. */
export function transitionDeclarations(text) {
  const result = {};
  if (!text || text === 'identity') return result;
  let depth = 0, start = 0;
  const flush = end => {
    const piece = text.slice(start, end), colon = piece.indexOf(':');
    if (colon > 0) result[camel(piece.slice(0, colon).trim())] = piece.slice(colon + 1).trim();
  };
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (character === '(') depth++;
    else if (character === ')') depth--;
    else if (character === ';' && depth === 0) { flush(index); start = index + 1; }
  }
  flush(text.length);
  return result;
}

export class TransitionHost {
  /** `armedTiming(element, within)`: the timing of the nearest `.animation(_:value:)` armed in this commit on `element` or
   * an ancestor; with `within`, only one strictly below that element. It carries the repetition as a commit's timing does.
   * `motionTiming` parses a CSS transition value; `supportedTransition` rewrites an easing the engine lacks. */
  constructor({window, root, reducedMotion, armedTiming, motionTiming, supportedTransition}) {
    this.motionTiming = motionTiming;
    this.supportedTransition = supportedTransition;
    this.window = window;
    this.root = root;
    this.reducedMotion = reducedMotion;
    this.armedTiming = armedTiming;
    this.leaving = new WeakSet();
    this.commitTiming = null;
    this.entering = [];
    this.holding = [];
    this.exiting = [];
    this.pushes = [];
    // The destinations this commit inserted: a push covers the screen that was on top before them.
    this.arrived = new Set();
    this.parents = new Map();
    this.texts = [];
    // The text runs playing a content transition: the wrapper that stands in for the text node, and that node.
    this.runs = new Set();
    this.numericValues = new WeakMap();
    // The runs a patch put the text nodes back for, to play again from where they were if the patch left their text alone.
    this.suspended = new Map();
    // The boxes of the children a patch removes, measured before the patch moves them (see noteChildren).
    this.removalBoxes = new Map();
    this.removalSizes = new Map();
  }

  /** Called before a patch with the commit's transaction timing (a CSS transition value) or null. `viewTransition`: the
   * patch runs inside a browser view transition, which animates the views it names. */
  begin(transactionTiming, viewTransition = false) {
    this.commitTiming = transactionTiming || null;
    this.viewTransition = viewTransition;
    this.entering = []; this.holding = []; this.pushes = []; this.arrived = new Set(); this.parents = new Map(); this.texts = []; this.removalBoxes = new Map(); this.removalSizes = new Map();
    // Exits a patch that did not finish left behind leave at once.
    for (const node of this.exiting) node.remove();
    this.exiting = [];
    // A patch writes text nodes: the ones a run stands in for go back first (the run ends where it is). A run whose text the
    // patch leaves alone plays again from there (finish).
    for (const run of [...this.runs]) {
      if (run.__play) this.suspended.set(run.__textNode, {node: run.__textNode, text: run.getAttribute(RUN), play: run.__play, startedAt: run.__startedAt});
      this.endRun(run);
    }
    // No patch may follow (a commit with nothing to write): the runs then play again at the next frame.
    if (this.suspended.size) this.window.requestAnimationFrame(() => this.resume([]));
  }

  isLeaving(node) { return node.nodeType === 1 && this.leaving.has(node); }

  animatedCommit() { return !this.reducedMotion.matches; }

  /** The timing of the transaction `element` changes in, as SwiftUI resolves it: the modifier closest to the view wins.
   * A `.transaction` modifier on it or above it (`parent`) writes its own (`data-transaction-timing`, "none" when
   * animations are off, which is DISABLED); an `.animation(_:value:)` armed in this commit below that modifier, or with
   * none above, replaces it and the commit's (`withAnimation`); the commit's is what is left (null when it has none). */
  scopedTiming(element, parent) {
    const scoped = element.closest?.('[data-transaction-timing]') || parent?.closest?.('[data-transaction-timing]');
    if (!scoped) return this.armedTiming(parent) || this.commitTiming;
    const nearer = this.armedTiming(parent, scoped);
    if (nearer) return nearer;
    const timing = scoped.getAttribute('data-transaction-timing');
    return timing === 'none' ? DISABLED : timing || this.armedTiming(parent) || null;
  }

  /** The parsed timing of a transaction value from `scopedTiming`. DISABLED is no timing at all: an explicit
   * `.transaction { $0.animation = nil }` keeps an ancestor's `.animation` from animating the subtree. */
  resolveTiming(source) {
    return source === DISABLED ? null : this.motionTiming(source);
  }

  /** The parsed timing a transition of `element` (under `parent`) plays with, or null when it does not animate. */
  timingFor(element, parent, side = null) {
    if (!this.animatedCommit()) return null;
    const own = (side && element.getAttribute?.('data-transition-' + side + '-timing')) || element.getAttribute?.('data-transition-timing');
    // A transition's own animation may repeat: its timing carries ` repeat:<iterations> <direction>` after the CSS timing.
    const repeat = own ? /\s+repeat:(\S+)\s+(\S+)$/.exec(own) : null;
    const scoped = own ? null : this.scopedTiming(element, parent);
    const transaction = own || scoped === DISABLED ? null : scoped;
    const parsed = own ? this.motionTiming(repeat ? own.slice(0, repeat.index) : own) : this.resolveTiming(scoped);
    let timing = parsed && repeat ? {...parsed, iterations: repeat[1] === 'infinite' ? Infinity : Number(repeat[1]) || 1, direction: repeat[2]} : parsed;
    // The commit's (or subtree's) animation repeats too: its CSS timing carries `/* repeat N */` or `/* infinite */`, and
    // `/* alternate */` when it autoreverses. A view that enters or leaves plays them, as the Swift-driven data does.
    if (timing && side && typeof transaction === 'string') {
      const count = /\/\*\s*repeat\s+(\d+)\s*\*\//.exec(transaction);
      if (/\/\*\s*infinite\s*\*\//.test(transaction) || count && Number(count[1]) > 1) {
        timing = {...timing, iterations: count ? Number(count[1]) : Infinity, direction: /\/\*\s*alternate\s*\*\//.test(transaction) ? 'alternate' : 'normal'};
      }
    }
    // A symbol effect transition's options (`data-transition-speed`, `-repeat`) play whichever timing it has faster, or again.
    const speed = Number(element.getAttribute?.('data-transition-speed'));
    const times = Math.floor(Number(element.getAttribute?.('data-transition-repeat')));
    if (timing && (speed > 0 && speed !== 1 || times > 1)) {
      timing = {...timing, duration: timing.duration / (speed > 0 ? speed : 1), delay: timing.delay / (speed > 0 ? speed : 1)};
      if (times > 1) timing.iterations = times, timing.direction = timing.direction ?? 'normal';
    }
    return timing && timing.duration > 0 ? timing : null;
  }

  /** Whether `element` plays a transition at all: a view, not owned by another host, with a non-identity state. */
  transitions(element, parent, side) {
    if (element.nodeType !== 1 || NOT_VIEWS.has(element.localName)) return false;
    // A view the running view transition names (a matched geometry source, or what holds one) is animated by it: the old one
    // left in the page to fade would hold the name a second time, which makes the browser skip the transition, and the new
    // one would fade in under the morph.
    if (this.viewTransition && (element.matches(VIEW_TRANSITION_NAMED) || element.querySelector(VIEW_TRANSITION_NAMED))) return false;
    const explicit = element.getAttribute('data-transition-' + side);
    if (explicit !== null) return explicit !== 'identity';
    if (parent === this.root || element.namespaceURI !== 'http://www.w3.org/1999/xhtml') return false;
    return !element.matches(OWN_MOTION) && !parent.closest?.(OWN_MOTION);
  }

  /** Before a parent's children are reconciled: when the list changes in an animated commit, the boxes of the
   * children are measured relative to the parent so that the ones that stay can move from there. */
  noteChildren(parent, previous, nextChildren, elementKey) {
    if (parent.nodeType !== 1 || this.parents.has(parent) || !this.animatedCommit()) return;
    const scoped = this.scopedTiming(parent, parent);
    // Whether the parent's other children move to make room (a commit or an ancestor animates). A child with a transition
    // animation of its own still plays its removal without that, so its box is taken either way.
    const flips = scoped !== DISABLED && !!scoped;
    if (!flips && !previous.some(node => node.nodeType === 1 && (node.hasAttribute('data-transition-timing') || node.hasAttribute('data-transition-remove-timing')))) return;
    let changed = previous.length !== nextChildren.length;
    for (let index = 0; !changed && index < previous.length; index++) {
      const a = previous[index], b = nextChildren[index];
      changed = a.nodeType !== b.nodeType || (a.nodeType === 1 && (elementKey(a) !== elementKey(b) || a.localName !== b.localName));
    }
    if (!changed) return;
    // A child the new list drops is measured now: the patch inserts its replacement before it, which pushes it down, and
    // finish() starts its removal from this box, not from where the replacement left it.
    const kept = new Set(nextChildren);
    for (const node of previous) if (node.nodeType === 1 && !kept.has(node) && !this.leaving.has(node) && (flips || this.timingFor(node, parent, 'remove'))) { this.removalBoxes.set(node, node.getBoundingClientRect()); this.removalSizes.set(node, layoutSize(this.window, node)); }
    if (!flips) return;
    const children = previous.filter(node => node.nodeType === 1 && !this.leaving.has(node));
    if (!children.length || children.length > FLIP_LIMIT) return;
    // Relative to the parent's own corner: under a rotation its bounding box's corner is another one, and moves as the parent
    // grows without any child moving in it.
    const [originX, originY] = originCorner(this.window, parent);
    const boxes = new Map();
    for (const child of children) {
      const box = child.getBoundingClientRect();
      boxes.set(child, {x: box.left - originX, y: box.top - originY, width: box.width, height: box.height});
    }
    this.parents.set(parent, boxes);
  }

  noteInsertion(node, parent) {
    if (node.nodeType !== 1) return;
    this.markSurfaces(node);
    if (node.matches('[data-scroll-flash-on-appear]') || node.querySelector('[data-scroll-flash-on-appear]')) {
      this.window.requestAnimationFrame(() => { for (const element of [node, ...node.querySelectorAll('[data-scroll-flash-on-appear]')]) if (element.matches('[data-scroll-flash-on-appear]')) this.flashScrollIndicators(element); });
    }
    const timing = this.timingFor(node, parent, 'insert');
    if (timing && this.transitions(node, parent, 'insert')) this.entering.push({node, parent, timing});
  }

  /** Marks the presentation surfaces in an inserted subtree so that their entry animation (styles.css) runs once. */
  markSurfaces(node) {
    if (this.reducedMotion.matches || node.ownerDocument.documentElement.dataset.embeddedMounted !== 'true') return;
    const surfaces = node.matches(ENTERING_SURFACES) ? [node] : [];
    if (node.firstElementChild) surfaces.push(...node.querySelectorAll(ENTERING_SURFACES));
    for (const surface of surfaces) {
      if (surface.matches('.navigation-destination')) {
        this.arrived.add(surface);
        // A destination inserted with its stack (a tab, a sheet, a path set at once) arrives with it, as in SwiftUI: only a
        // push onto a stack already on screen slides in.
        if (surface !== node && node.contains(surface.parentElement)) continue;
        if (surface.getAttribute('data-navigation-inactive') !== 'true') this.pushes.push(surface);
      }
      surface.setAttribute('data-enter-animation', 'true');
      const done = event => { if (event.target === surface) { surface.removeAttribute('data-enter-animation'); surface.removeEventListener('animationend', done); surface.removeEventListener('animationcancel', done); } };
      surface.addEventListener('animationend', done);
      surface.addEventListener('animationcancel', done);
      // A surface the stylesheet gives no entry animation must not keep the mark.
      this.window.setTimeout(() => { if (!surface.getAnimations().length) surface.removeAttribute('data-enter-animation'); }, 50);
    }
  }

  /** `symbolEffect(_:options:value:)`: the effect plays when the value's hash changes, not when the view first appears. */
  noteSymbolTrigger(element, previous) {
    const next = element.getAttribute('data-symbol-effect-trigger');
    if (previous === null || next === null || previous === next || this.reducedMotion.matches) return;
    const [frames, duration] = symbolEffectFrames(element.getAttribute('data-symbol-effect'));
    const speed = Number(element.getAttribute('data-symbol-effect-speed')) || 1;
    // "0" is SymbolEffectOptions.repeating (repeat forever); an absent attribute is one run.
    const repeatText = element.getAttribute('data-symbol-effect-repeat');
    const repeats = repeatText === '0' ? Infinity : Number(repeatText) || 1;
    element.__symbolEffect?.cancel();
    element.__symbolEffect = element.animate(frames, {duration: duration / speed, iterations: repeats, easing: 'ease-in-out'});
  }

  /** `scrollIndicatorsFlash`: a scroll view shows its indicators when it scrolls; a step there and back shows them. The step
   * is along every axis the view can scroll (a horizontal one has no room for a vertical step), towards the room it has. */
  flashScrollIndicators(element) {
    const views = element.matches?.('.scroll-view') ? [element] : [...(element.querySelectorAll?.('.scroll-view') ?? [])];
    for (const view of views) {
      const x = view.scrollLeft, y = view.scrollTop;
      const [dx, dy] = scrollNudge(view);
      if (!dx && !dy) continue;
      view.scrollTo({left: x + dx, top: y + dy, behavior: 'instant'});
      view.scrollTo({left: x, top: y, behavior: 'instant'});
    }
  }

  /** The symbol of `element` changed: under `.contentTransition(.symbolEffect)`, in an animated commit, it plays the
   * replace effect. `ghost` is a copy of the element as it was: it stays over the element, inert and out of the layout,
   * while it plays the old symbol leaving, and the element plays the new one arriving as the old one goes. The copy sits
   * in the document's body, fixed where the element is, with the element's color and size: no patch of the page meets it. */
  noteSymbolReplace(element, ghost) {
    const host = element.closest('[data-content-transition="symbol-effect"]');
    if (!host || !this.timingFor(host, host)) return;
    const [outgoing, incoming, duration] = REPLACE_HALVES[host.getAttribute('data-content-transition-direction')] ?? REPLACE_HALVES['replace-down-up'];
    // The effect's options: how many times faster it plays, and how many times it repeats (endless would never let the old
    // symbol go, so it plays once).
    const speed = Number(host.getAttribute('data-content-transition-speed')) > 0 ? Number(host.getAttribute('data-content-transition-speed')) : 1;
    const iterations = Math.max(1, Math.floor(Number(host.getAttribute('data-content-transition-repeat'))) || 1);
    const scaled = duration / speed;
    element.__symbolEffect?.cancel();
    element.__symbolGhost?.remove();
    // The box the copy takes is the element's as it shows, read before the arriving half scales it down.
    const box = element.getBoundingClientRect();
    element.__symbolEffect = element.animate(incoming, {duration: scaled * 0.6, delay: scaled * 0.4, iterations, easing: 'ease-out', fill: 'backwards'});
    if (!ghost || !element.parentNode) return;
    for (const node of [ghost, ...ghost.querySelectorAll('*')]) {
      for (const name of [...node.getAttributeNames()]) if (GHOST_ATTRIBUTE.test(name)) node.removeAttribute(name);
    }
    ghost.setAttribute(LEAVING, '');
    ghost.setAttribute('aria-hidden', 'true');
    ghost.inert = true;
    const computed = this.window.getComputedStyle(element);
    // Under a scaled or rotated ancestor the box is the viewport's and the copy, in the body, has none of those transforms: it
    // takes the size the element lays out at and the ancestors' transform about its center, which is the box's.
    const basis = localBasis(this.window, element);
    const size = (basis && layoutSize(this.window, element)) || {width: box.width, height: box.height};
    const style = ghost.style;
    style.setProperty('position', 'fixed');
    style.setProperty('left', (box.left + (box.width - size.width) / 2) + 'px'); style.setProperty('top', (box.top + (box.height - size.height) / 2) + 'px');
    style.setProperty('width', size.width + 'px'); style.setProperty('height', size.height + 'px');
    if (basis) {
      const own = computed.transform && computed.transform !== 'none' ? ' ' + computed.transform : '';
      style.setProperty('transform', `matrix(${basis.a}, ${basis.b}, ${basis.c}, ${basis.d}, 0, 0)` + own);
    }
    style.setProperty('box-sizing', 'border-box');
    style.setProperty('margin', '0px');
    style.setProperty('pointer-events', 'none');
    style.setProperty('z-index', '2147483647');
    for (const name of ['color', 'font-size', 'font-weight', 'line-height', 'display']) style.setProperty(name, computed.getPropertyValue(name));
    this.leaving.add(ghost);
    (element.ownerDocument.body ?? this.root).appendChild(ghost);
    element.__symbolGhost = ghost;
    const leave = ghost.animate(outgoing, {duration: scaled * 0.6, iterations, easing: 'ease-in', fill: 'forwards'});
    leave.id = 'symbol-replace-out';
    const remove = () => { ghost.remove(); this.leaving.delete(ghost); if (element.__symbolGhost === ghost) element.__symbolGhost = null; };
    leave.finished.then(remove, remove);
  }

  /** A text node the patch just rewrote from `previous`: queued when its view has a content transition that animates. */
  noteText(node, previous) {
    const host = node.parentElement?.closest('[data-content-transition]');
    if (!host || !node.parentNode) return;
    const kind = host.getAttribute('data-content-transition');
    const direction = host.getAttribute('data-content-transition-direction');
    const value = Number(host.getAttribute('data-content-transition-value'));
    const was = this.numericValues.get(host);
    if (direction === 'value' && Number.isFinite(value)) this.numericValues.set(host, value);
    if (kind === 'identity') return;
    const timing = this.timingFor(host, host);
    if (!timing || previous === node.nodeValue) return;
    let up = direction !== 'down';
    if (direction === 'value') {
      const before = Number.isFinite(was) ? was : numberIn(previous), after = Number.isFinite(value) ? value : numberIn(node.nodeValue);
      up = !(after < before);
    }
    this.texts.push({node, previous, kind, up, timing});
  }

  /** At the end of a patch, for a node its parent no longer lists. Returns true when the node stays to play its removal. */
  holdRemoval(node, parent) {
    if (node.nodeType !== 1 || this.leaving.has(node) || !node.isConnected) return false;
    if (this.exits(node)) { this.exiting.push(node); return true; }
    const timing = this.timingFor(node, parent, 'remove');
    if (!timing || !this.transitions(node, parent, 'remove')) return false;
    this.holding.push({node, parent, timing});
    return true;
  }

  /** Whether a removed element is (or holds) a presentation surface that plays its exit. */
  exits(node) {
    if (this.reducedMotion.matches || !node.isConnected) return false;
    // A surface that holds a view-transition name (a zoom destination) is animated by the view transition, which gives the
    // name back to its source: a copy left in the page would hold the name twice.
    if (node.matches('[style*="view-transition-name"]') || node.querySelector?.('[style*="view-transition-name"]')) return false;
    return node.matches(EXITING_SURFACES) || !!node.querySelector?.(PRESENTATION_SURFACES);
  }

  /** Plays the exits of the surfaces in `node`, which stays in the page, inert, until they end. */
  playExit(node) {
    this.leaving.add(node);
    node.setAttribute(LEAVING, '');
    node.setAttribute('aria-hidden', 'true');
    node.inert = true;
    // An element in the flow (a navigation destination) keeps its box while it leaves, out of the flow.
    if (this.window.getComputedStyle(node).position === 'static') {
      const box = node.getBoundingClientRect(), parent = node.offsetParent?.getBoundingClientRect() ?? {left: 0, top: 0};
      // Under a scaled or rotated ancestor the box is the viewport's and the styles are the element's own: it takes the size it
      // lays out at and is put back where it was through the ancestors' transform, as a removed view is (finish).
      const basis = localBasis(this.window, node);
      const size = (basis && layoutSize(this.window, node)) || {width: box.width, height: box.height};
      const style = node.style;
      style.setProperty('position', 'absolute');
      style.setProperty('left', basis ? '0px' : (box.left - parent.left) + 'px'); style.setProperty('top', basis ? '0px' : (box.top - parent.top) + 'px');
      // The sizes are border boxes.
      style.setProperty('box-sizing', 'border-box');
      style.setProperty('width', size.width + 'px'); style.setProperty('height', size.height + 'px');
      style.setProperty('margin', '0px');
      if (basis) {
        const placed = node.getBoundingClientRect();
        const [left, top] = toLocal(basis, box.left - placed.left, box.top - placed.top);
        style.setProperty('left', left + 'px'); style.setProperty('top', top + 'px');
      }
    }
    const surfaces = node.matches(EXITING_SURFACES) ? [node] : [];
    surfaces.push(...node.querySelectorAll(PRESENTATION_SURFACES));
    for (const surface of surfaces) { surface.removeAttribute('data-enter-animation'); surface.setAttribute('data-exit-animation', 'true'); }
    if (node.matches('.navigation-destination')) this.playPop(node);
    let removed = false;
    const remove = () => { if (removed) return; removed = true; this.leaving.delete(node); node.remove(); };
    const running = surfaces.flatMap(surface => surface.getAnimations());
    if (!running.length) { remove(); return; }
    Promise.allSettled(running.map(animation => animation.finished)).then(remove);
    this.window.setTimeout(remove, EXIT_LIMIT);
  }

  /** A push, as UIKit plays it: the screen it covers stays in view under the new one (styles.css slides both) at the new
   * one's box, out of the layout, until the new one has arrived. */
  playPush(screen, arrived) {
    const parent = screen.parentElement;
    if (!parent || screen.getAttribute('data-enter-animation') !== 'true') return;
    // The screen that was on top: the last one before this that this commit did not insert. One still sliding in from an
    // earlier push is that screen.
    let covered = null;
    for (const sibling of parent.children) {
      if (sibling === screen) break;
      if (sibling.matches(SCREENS) && !this.leaving.has(sibling) && !arrived.has(sibling)) covered = sibling;
    }
    const surface = this.stackSurface(parent);
    this.markMotion(screen, null, surface);
    if (!covered) return;
    // Where the stack is not laid out by the layout host, the covered screen is put at the new one's box, out of the flow
    // (styles.css); the layout host keeps it in its own cell, where it was. Layout offsets, not boxes: the new screen is
    // already translated by its animation. A screen not laid out yet takes the rest of the stack.
    const top = screen.offsetTop;
    const height = screen.offsetHeight || Math.max(parent.clientHeight - top, 0);
    covered.style.setProperty('--motion-left', screen.offsetLeft + 'px');
    covered.style.setProperty('--motion-top', top + 'px');
    covered.style.setProperty('--motion-width', screen.offsetWidth + 'px');
    covered.style.setProperty('--motion-height', height + 'px');
    // A third of the screen's width, not of the covered view's own (a root sized to its content is narrower).
    covered.style.setProperty('--motion-shift', 0.3 * screen.offsetWidth + 'px');
    this.markMotion(covered, 'covered', surface);
  }

  /** A pop: the screen it uncovers comes back from under the one that leaves (styles.css). */
  playPop(node) {
    const parent = node.parentElement;
    if (!parent || this.reducedMotion.matches) return;
    let revealed = null;
    for (const sibling of parent.children) {
      // A screen this commit inserted (a path whose top was replaced) arrives as a push.
      if (sibling === node || this.leaving.has(sibling) || this.arrived.has(sibling) || !sibling.matches(SCREENS)) continue;
      const hidden = sibling.getAttribute('data-navigation-inactive') === 'true' || (sibling.matches('.navigation-root') && sibling.getAttribute('aria-hidden') === 'true');
      if (!hidden) revealed = sibling;
    }
    const surface = this.stackSurface(parent);
    node.style.setProperty('--motion-surface', surface);
    if (!revealed) return;
    revealed.style.setProperty('--motion-shift', 0.3 * node.offsetWidth + 'px');
    this.markMotion(revealed, 'revealed', surface);
  }

  /** Marks a screen for the motion of a push or a pop (`state` null: the screen on top, which only takes the surface),
   * and clears the mark and the properties written for it when that motion's animation ends. A later motion of the same
   * screen (a pop while the push still plays) replaces it: the end of the animation it cancels clears nothing. A covered
   * screen is inert while it shows, out of reach of the keyboard as it was when hidden, and gets its own state back after. */
  markMotion(screen, state, surface) {
    const token = {};
    screen.__navigationMotion = token;
    this.restoreInert(screen);
    if (state === 'covered') {
      screen.__motionInert = screen.inert;
      screen.inert = true;
      // The browser moves focus out of an inert subtree only at its next rendering update: it leaves now, as it did when
      // the screen was hidden.
      const focused = screen.ownerDocument.activeElement;
      if (focused && focused !== screen.ownerDocument.body && screen.contains(focused)) focused.blur();
    }
    // The screen on top carries no mark: one left by a motion this one replaces goes.
    if (state) screen.setAttribute(NAVIGATION_MOTION, state);
    else screen.removeAttribute(NAVIGATION_MOTION);
    screen.style.setProperty('--motion-surface', surface);
    const animation = NAVIGATION_ANIMATIONS[state ?? 'top'];
    let settled = false;
    const settle = event => {
      if (settled || (event && (event.target !== screen || event.animationName !== animation))) return;
      settled = true;
      screen.removeEventListener('animationend', settle); screen.removeEventListener('animationcancel', settle);
      if (screen.__navigationMotion !== token) return;
      screen.__navigationMotion = null;
      this.restoreInert(screen);
      if (state && screen.getAttribute(NAVIGATION_MOTION) === state) screen.removeAttribute(NAVIGATION_MOTION);
      for (const name of MOTION_PROPERTIES) screen.style.removeProperty(name);
    };
    screen.addEventListener('animationend', settle); screen.addEventListener('animationcancel', settle);
    this.window.setTimeout(() => settle(), EXIT_LIMIT);
  }

  /** Gives a screen back the inert state it had before a push covered it. */
  restoreInert(screen) {
    if (screen.__motionInert === undefined) return;
    screen.inert = screen.__motionInert;
    screen.__motionInert = undefined;
  }

  /** The color behind a stack: the first background up from it that is not transparent, so that the screens painted with it
   * look as the stack does at rest. */
  stackSurface(element) {
    for (let current = element; current && current.nodeType === 1; current = current.parentElement) {
      const color = this.window.getComputedStyle(current).backgroundColor;
      if (color && color !== 'transparent' && !/^rgba\([^)]*,\s*0\)$/.test(color) && !/\/\s*0\)$/.test(color)) return color;
    }
    return 'var(--color-swu-background)';
  }

  /** After the patch wrote everything: removed elements leave the layout and play out, the siblings that stayed move
   * from their old boxes, inserted elements play in. Reads and writes are batched so the browser lays out a few times
   * per commit, not once per element. */
  finish() {
    const {holding, entering, parents, exiting, removalBoxes, removalSizes} = this;
    this.holding = []; this.entering = []; this.parents = new Map(); this.exiting = []; this.removalBoxes = new Map(); this.removalSizes = new Map();
    const texts = this.texts; this.texts = [];
    // The exits read `this.arrived` too (playPop): a screen this commit inserted is pushed, not revealed.
    const pushes = this.pushes, arrived = this.arrived;
    for (const node of exiting) this.playExit(node);
    this.pushes = []; this.arrived = new Set();
    for (const screen of pushes) this.playPush(screen, arrived);
    if (!holding.length && !entering.length && !parents.size && !texts.length) return;
    const window = this.window;
    // Removed elements: their box before the patch (noteChildren), else their last box (read), then out of the layout at
    // that box (write, read, correct).
    const boxes = holding.map(({node}) => removalBoxes.get(node) ?? node.getBoundingClientRect());
    // Under a scaled or rotated ancestor the boxes are in the viewport's coordinates and the styles written in the view's own.
    const bases = holding.map(({node}) => localBasis(window, node));
    // The size is the one it lays out at, not its bounding box's: that has its transforms in it, and a rotation mixes the sides.
    const sizes = holding.map(({node}) => removalSizes.get(node) ?? layoutSize(window, node));
    for (let index = 0; index < holding.length; index++) {
      const {node} = holding[index], box = boxes[index], basis = bases[index];
      // Without a layout size (an inline or SVG element), the size whose box under the ancestors' transform is the one measured.
      const [width, height] = cssSizeFor(basis, box.width, box.height);
      const size = sizes[index] ?? {width, height};
      this.leaving.add(node);
      node.setAttribute(LEAVING, '');
      node.setAttribute('aria-hidden', 'true');
      node.inert = true;
      const style = node.style;
      style.setProperty('position', 'absolute');
      style.setProperty('left', '0px'); style.setProperty('top', '0px');
      style.setProperty('margin', '0px');
      style.setProperty('box-sizing', 'border-box');
      style.setProperty('width', size.width + 'px'); style.setProperty('height', size.height + 'px');
      style.setProperty('pointer-events', 'none');
      style.setProperty('transition', 'none');
    }
    const placed = holding.map(({node}) => node.getBoundingClientRect());
    for (let index = 0; index < holding.length; index++) {
      const {node} = holding[index];
      const [left, top] = toLocal(bases[index], boxes[index].left - placed[index].left, boxes[index].top - placed[index].top);
      node.style.setProperty('left', left + 'px');
      node.style.setProperty('top', top + 'px');
    }
    // The siblings that stayed: where they are now, relative to the parent.
    const moves = [];
    for (const [parent, before] of parents) {
      if (!parent.isConnected) continue;
      const [originX, originY] = originCorner(window, parent);
      const timing = this.resolveTiming(this.scopedTiming(parent, parent));
      if (!timing || timing.duration <= 0) continue;
      // The children share their ancestors: their displacement is measured in the viewport and played in their own coordinates.
      const probe = [...before.keys()].find(child => child.parentNode === parent && !this.leaving.has(child));
      const basis = probe ? localBasis(window, probe) : null;
      for (const [child, was] of before) {
        if (child.parentNode !== parent || this.leaving.has(child)) continue;
        const box = child.getBoundingClientRect();
        // A sibling that changed size the way a scale would (the hero of Food Truck's New Orders becoming a small tile) grows
        // or shrinks from its old size about its centre, as SwiftUI animates its frame; one whose proportions changed (a row
        // that only widened) moves without a scale, which would distort what it holds.
        const scaleX = box.width > 0 ? was.width / box.width : 1, scaleY = box.height > 0 ? was.height / box.height : 1;
        const scales = (Math.abs(was.width - box.width) > 0.5 || Math.abs(was.height - box.height) > 0.5) && scaleX > 0 && scaleY > 0 && Math.abs(scaleX / scaleY - 1) < 0.1;
        const dx = scales ? was.x + was.width / 2 - (box.left - originX + box.width / 2) : was.x - (box.left - originX);
        const dy = scales ? was.y + was.height / 2 - (box.top - originY + box.height / 2) : was.y - (box.top - originY);
        if (scales || Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) { const [x, y] = toLocal(basis, dx, dy); moves.push({child, dx: x, dy: y, scale: scales ? [scaleX, scaleY] : null, timing}); }
      }
    }
    // The identity values the inserted and removed elements animate from or to.
    const enteringFrames = entering.filter(({node}) => node.isConnected).map(entry => {
      const active = transitionDeclarations(entry.node.getAttribute('data-transition-insert') ?? 'opacity:0');
      return {...entry, active, identity: this.identityOf(entry.node, active)};
    });
    const leavingFrames = holding.map(entry => {
      const active = transitionDeclarations(entry.node.getAttribute('data-transition-remove') ?? 'opacity:0');
      return {...entry, active, identity: this.identityOf(entry.node, active)};
    });
    this.resume(texts);
    for (const text of texts) if (text.node.parentNode && text.node.isConnected) this.playText(text);
    for (const {child, dx, dy, scale, timing} of moves) {
      const from = {translate: `${dx}px ${dy}px`}, to = {translate: '0px 0px'};
      if (scale) { from.scale = `${scale[0]} ${scale[1]}`; to.scale = '1 1'; }
      child.animate([from, to], {...this.options(timing), composite: 'add'});
    }
    for (const {node, active, identity, timing} of enteringFrames) {
      node.animate([{...identity, ...this.composeActive(identity, active, node)}, identity], {...this.options(timing), fill: 'backwards'});
    }
    for (const {node, active, identity, timing} of leavingFrames) {
      // A removal that repeated forever would never let the view go: it plays its repeats, and at most once when they are endless.
      const options = {...this.options(timing), fill: 'forwards'};
      if (options.iterations === Infinity) options.iterations = 1;
      const animation = node.animate([identity, {...identity, ...this.composeActive(identity, active, node)}], options);
      const done = () => { this.leaving.delete(node); node.remove(); };
      animation.addEventListener('finish', done, {once: true});
      animation.addEventListener('cancel', done, {once: true});
    }
  }

  /** The transition's active state over what the view already has (`identity`): the active opacity multiplies the view's, and a
   * transform or filter comes after the view's own. A translate, scale or rotate the view has is replaced by the transition's. */
  composeActive(identity, active, node) {
    const composed = {};
    // What a custom transition's identity phase put on the view (`data-transition-rest`) is part of how it rests, not of what it
    // has of its own: the active look goes over the view's own.
    const resting = transitionDeclarations(node.getAttribute?.('data-transition-rest') ?? '');
    for (const [key, value] of Object.entries(active)) {
      const base = identity[key];
      if (key === 'transformOrigin' || !base || base === 'none') composed[key] = value;
      else if (key === 'opacity') composed.opacity = resting.opacity !== undefined && Number(resting.opacity) === 0 ? value : String(Number(value) * Number(base));
      else if (key === 'transform' || key === 'filter') {
        let own = base;
        if (resting[key]) {
          // The browser writes a value its own way (`rotate(10.0deg)` is `rotate(10deg)` in the style): compared as it writes it.
          const probe = node.ownerDocument.createElement('div');
          probe.style[key] = resting[key];
          const rest = probe.style[key] || resting[key], inline = node.style?.[key] ?? '';
          own = inline.endsWith(rest) ? inline.slice(0, inline.length - rest.length).trim() : base;
        }
        composed[key] = own && own !== 'none' ? own + ' ' + value : value;
      }
      else composed[key] = value;
    }
    // A view with a transform of its own keeps the point that transform is about (identityOf): the transition's scale about its
    // own anchor is then the same scale about the view's point and a move, (1 - scale) times the way from that point to the anchor.
    if (active.transformOrigin !== undefined && identity.transformOrigin !== active.transformOrigin && active.scale !== undefined) {
      composed.transformOrigin = identity.transformOrigin;
      const size = layoutSize(this.window, node) ?? {width: node.offsetWidth || 0, height: node.offsetHeight || 0};
      const length = (token, extent) => token === undefined ? extent / 2 : token.endsWith('%') ? parseFloat(token) * extent / 100 : parseFloat(token) || 0;
      const [anchorX, anchorY] = active.transformOrigin.trim().split(/\s+/), [ownX, ownY] = identity.transformOrigin.trim().split(/\s+/);
      const [scaleX, scaleY = scaleX] = active.scale.trim().split(/\s+/).map(Number);
      const dx = (1 - scaleX) * (length(anchorX, size.width) - length(ownX, size.width)), dy = (1 - scaleY) * (length(anchorY, size.height) - length(ownY, size.height));
      const [moveX = '0px', moveY = '0px'] = active.translate !== undefined ? splitTopLevel(active.translate) : [];
      composed.translate = `calc(${moveX} + ${dx}px) calc(${moveY} + ${dy}px)`;
    }
    return composed;
  }

  /** Plays again the runs a patch put the text nodes back for, from where they were, when the patch left their text alone
   * (`texts` are the changes it made). */
  resume(texts) {
    const suspended = [...this.suspended.values()];
    this.suspended.clear();
    for (const {node, text, play, startedAt} of suspended) {
      // From where real time has taken it, however many commits came in between.
      const elapsed = this.window.performance.now() - startedAt;
      if (elapsed < play.timing.delay + play.timing.duration && node.parentNode && node.isConnected && node.nodeValue === text && !texts.some(entry => entry.node === node)) this.playText({node, ...play, elapsed});
    }
  }

  /** Stands a run of spans in for the text node: the characters that stay, and a slot per changed character that holds
   * the old character leaving and the new one arriving. The slots' widths ease from the old character's to the new's,
   * so the text around them moves smoothly. The text node comes back when the run ends. */
  playText({node, previous, kind, up, timing, elapsed = 0}) {
    // A number that changes more characters than this is updated in plain text: a slot per character of a long text is
    // not worth its DOM (the app's text is not bounded).
    if (kind === 'numeric-text' && Math.max(previous.length, node.nodeValue.length) > 64) return;
    const document = node.ownerDocument, next = node.nodeValue;
    // A whole text that wraps (a cross-fade of a paragraph) keeps wrapping: the character slots do not break lines, so it only
    // fades in, in place, instead of becoming one overflowing line while it plays.
    const wraps = kind !== 'numeric-text' && textWraps(node);
    const run = document.createElement('span');
    run.setAttribute(RUN, next);
    run.setAttribute('role', 'text');
    run.setAttribute('aria-label', next);
    if (!wraps) run.style.setProperty('white-space', 'pre');
    const slots = [];
    let wrapped = null;
    const addStatic = text => { if (text) run.append(document.createTextNode(text)); };
    const addSlot = (from, to) => {
      const slot = document.createElement('span');
      slot.style.cssText = 'display:inline-block;position:relative;white-space:pre;vertical-align:bottom';
      const arriving = document.createElement('span');
      arriving.textContent = to;
      arriving.style.cssText = 'display:inline-block;white-space:pre';
      slot.append(arriving);
      let leaving = null;
      if (from) {
        leaving = document.createElement('span');
        leaving.textContent = from;
        leaving.setAttribute('aria-hidden', 'true');
        leaving.style.cssText = 'position:absolute;left:0;top:0;white-space:pre';
        slot.append(leaving);
      }
      run.append(slot);
      slots.push({slot, arriving: to ? arriving : null, leaving});
    };
    if (kind === 'numeric-text') {
      // Characters the two texts share at either end stay; the middle is aligned from the right, as digits are.
      let start = 0;
      while (start < previous.length && start < next.length && previous[start] === next[start]) start++;
      let end = 0;
      while (end < previous.length - start && end < next.length - start && previous[previous.length - 1 - end] === next[next.length - 1 - end]) end++;
      const from = previous.slice(start, previous.length - end), to = next.slice(start, next.length - end);
      addStatic(next.slice(0, start));
      const width = Math.max(from.length, to.length);
      for (let index = 0; index < width; index++) {
        const a = from[from.length - width + index] ?? '', b = to[to.length - width + index] ?? '';
        if (a === b) addStatic(b); else addSlot(a, b);
      }
      addStatic(next.slice(next.length - end));
    } else if (wraps) {
      wrapped = document.createElement('span');
      wrapped.textContent = next;
      run.append(wrapped);
    } else {
      addSlot(previous, next);
    }
    node.replaceWith(run);
    this.runs.add(run);
    run.__textNode = node;
    run.__play = {previous, kind, up, timing};
    run.__startedAt = this.window.performance.now() - elapsed;
    const options = {...this.options(timing), fill: 'backwards'};
    const animations = [];
    // Widths are read once the run is in the page; a slot without an arriving character closes to nothing.
    // The slots' widths are in their own pixels: the widths the characters lay out at, not their boxes in the viewport, which have
    // every scale above the text in them (the browser would apply it a second time) and, under a rotation, their height.
    const laidWidth = element => element ? layoutSize(this.window, element)?.width ?? element.offsetWidth : 0;
    const widths = slots.map(({arriving, leaving}) => [laidWidth(leaving), laidWidth(arriving)]);
    const rise = kind === 'numeric-text' ? (up ? 1 : -1) : 0;
    if (wrapped) animations.push(wrapped.animate([{opacity: 0}, {opacity: 1}], options));
    slots.forEach(({slot, arriving, leaving}, index) => {
      const [from, to] = widths[index];
      if (Math.abs(from - to) > 0.5) animations.push(slot.animate([{width: from + 'px'}, {width: to + 'px'}], options));
      if (!arriving) slot.firstChild.textContent = '';
      if (arriving) animations.push(arriving.animate(rise
        ? [{transform: `translateY(${rise * 0.6}em) scale(0.85)`, opacity: 0, filter: 'blur(3px)'}, {transform: 'none', opacity: 1, filter: 'blur(0px)'}]
        : [{opacity: 0}, {opacity: 1}], options));
      if (leaving) animations.push(leaving.animate(rise
        ? [{transform: 'none', opacity: 1, filter: 'blur(0px)'}, {transform: `translateY(${-rise * 0.6}em) scale(0.85)`, opacity: 0, filter: 'blur(3px)'}]
        : [{opacity: 1}, {opacity: 0}], {...options, fill: 'forwards'}));
    });
    if (!animations.length) { this.endRun(run); return; }
    if (elapsed > 0) for (const animation of animations) animation.currentTime = elapsed;
    Promise.all(animations.map(animation => animation.finished.catch(() => {}))).then(() => this.endRun(run));
  }

  endRun(run) {
    if (!this.runs.delete(run)) return;
    const node = run.__textNode;
    for (const animation of run.getAnimations({subtree: true})) animation.cancel();
    if (run.parentNode) run.replaceWith(node);
  }

  options(timing) {
    const options = {duration: timing.duration, delay: timing.delay, easing: this.supportedTransition(timing.easing)};
    if (timing.iterations) { options.iterations = timing.iterations; options.direction = timing.direction; }
    return options;
  }

  /** The element's current values of the properties a transition state names. `transform-origin` stays as stated, unless the
   * view has a transform of its own: that one is about the view's own point, which both frames keep, and the transition's scale
   * about its anchor is played as a scale and a move (composeActive). */
  identityOf(node, active) {
    const computed = this.window.getComputedStyle(node), identity = {};
    const ownOrigin = active.transformOrigin !== undefined && active.scale !== undefined && active.transform === undefined && computed.transform && computed.transform !== 'none';
    if (ownOrigin) identity.translate = computed.translate || 'none';
    for (const key of Object.keys(active)) {
      if (key === 'transformOrigin') { identity[key] = ownOrigin ? computed.transformOrigin : active[key]; continue; }
      const value = computed[key];
      identity[key] = value === undefined || value === '' ? (key === 'opacity' ? '1' : 'none') : value;
    }
    return identity;
  }

  /** Leaving elements are not part of what Swift published: the DOM comparison of tests leaves them out. */
  static isLeavingElement(node) { return node.nodeType === 1 && node.hasAttribute(LEAVING); }
}

/** `scrollTransition(_:axis:transition:)`: each element's phase follows where it sits in its scroll view.
 * Swift publishes the effect at each phase (`data-scroll-transition-leading|identity|trailing`, `opacity=0.5;transform=…`),
 * the configuration (`interactive`, `animated` or `identity`), the timing curve or animation and the threshold. Interactive
 * transitions hold a paused animation through the three phases and set its time from the scroll position on every frame
 * the position changes; animated ones play to a phase when the element crosses the threshold. */
/** A one pixel step along each axis `view` can scroll, towards the side it has room on; zero along an axis that cannot. The
 * horizontal position is negative in a right-to-left view. */
export function scrollNudge(view) {
  const step = (position, room) => room < 1 ? 0 : Math.abs(position) >= 1 ? -Math.sign(position) : 1;
  const dx = step(view.scrollLeft, view.scrollWidth - view.clientWidth), dy = step(view.scrollTop, view.scrollHeight - view.clientHeight);
  // Away from the start: in a right-to-left view that is towards negative positions.
  const rtl = dx > 0 && view.ownerDocument?.defaultView?.getComputedStyle(view).direction === 'rtl';
  return [rtl ? -1 : dx, dy];
}

/** What configures a scroll transition, after `data-scroll-transition-`: a change of any of them builds its animations again
 * (`sync`), so the commit phase that calls `sync` watches them all. */
const SCROLL_TRANSITION_PARTS = ['leading', 'identity', 'trailing', 'mode', 'curve', 'timing', 'threshold', 'inset', 'axis', 'trailing-mode', 'trailing-curve', 'trailing-timing', 'trailing-threshold', 'trailing-inset'];
export const SCROLL_TRANSITION_ATTRIBUTES = /* @__PURE__ */ (() => ['data-scroll-transition', ...SCROLL_TRANSITION_PARTS.map(name => 'data-scroll-transition-' + name)])();

export class ScrollTransitionHost {
  constructor({window, root, reducedMotion, motionTiming, supportedTransition}) {
    this.window = window;
    this.root = root;
    this.reducedMotion = reducedMotion;
    this.motionTiming = motionTiming;
    this.supportedTransition = supportedTransition;
    this.states = new Map();
    this.frame = 0;
    this.update = () => { this.frame = 0; this.measure(); };
    this.schedule = () => { if (!this.frame && this.states.size) this.frame = window.requestAnimationFrame(this.update); };
    // Capture: a scroll event does not bubble, and any scroll view of the page may hold transitioning views.
    window.addEventListener('scroll', this.schedule, {capture: true, passive: true});
    window.addEventListener('resize', this.schedule, {passive: true});
  }

  dispose() {
    this.window.removeEventListener('scroll', this.schedule, {capture: true});
    this.window.removeEventListener('resize', this.schedule);
    for (const state of this.states.values()) { state.animation?.cancel(); for (const animation of state.animations) animation.cancel(); }
    this.states.clear();
  }

  /** After a commit: (re)builds the animation of every element whose effects or configuration changed. */
  sync() {
    const retained = new Set();
    for (const element of this.root.querySelectorAll('[data-scroll-transition]')) {
      retained.add(element);
      const get = name => element.getAttribute('data-scroll-transition-' + name) || '';
      const signature = SCROLL_TRANSITION_PARTS.map(get).join('\n');
      const old = this.states.get(element);
      // The same configuration keeps its animations, unless the elements they play on (a snap target's children) changed.
      if (old?.signature === signature && !(old.split && !sameEffectTargets(old, element, this.window)) && old.underlying === underlyingKey(old.targets)) continue;
      old?.animation?.cancel();
      for (const animation of [...(old?.animations ?? []), ...(old?.discrete ?? [])]) animation.cancel();
      const edge = prefix => ({mode: get(prefix + 'mode') || 'interactive', curve: get(prefix + 'curve') || 'ease-in-out', timing: this.motionTiming(get(prefix + 'timing')),
        threshold: get(prefix + 'threshold') || '1', inset: Number(get(prefix + 'inset')) || 0});
      const frames = ['leading', 'identity', 'trailing'].map(name => effectFrame(get(name)));
      const keys = new Set(frames.flatMap(Object.keys));
      for (const frame of frames) for (const key of keys) if (!(key in frame)) frame[key] = key === 'opacity' ? '1' : 'none';
      // `scrollTransition(topLeading:bottomTrailing:)`: each edge has its own mode, curve, animation, threshold and inset.
      const leading = edge(''), trailing = get('trailing-mode') ? edge('trailing-') : leading;
      const mode = leading.mode === 'identity' && trailing.mode === 'identity' ? 'identity' : 'scroll';
      const state = {signature, frames, mode, axis: get('axis'), leading, trailing, phase: null, animation: null, animations: [], discrete: [], targets: [], split: false};
      // The elements the effect plays on (a snap target's children, or the element itself), whichever edges animate it.
      const placements = effectTargets(element, frames, this.window).map(([target, targetFrames]) => [target, this.composeFrames(target, targetFrames, keys)]);
      state.placements = placements;
      state.split = placements.length !== 1 || placements[0][0] !== element;
      state.targets = placements.map(([target]) => target);
      state.underlying = underlyingKey(state.targets);
      if ((leading.mode === 'interactive' || trailing.mode === 'interactive') && keys.size) {
        // The curve of a keyframe eases the segment after it: the leading edge's into identity, the trailing edge's out of it.
        for (const [target, targetFrames] of placements) {
          const animation = target.animate([{...targetFrames[0], easing: leading.curve}, {...targetFrames[1], easing: trailing.curve}, targetFrames[2]], {duration: 1000, fill: 'both'});
          animation.id = 'scroll-transition';
          animation.pause();
          state.animations.push(animation);
        }
        state.animation = state.animations[0] ?? null;
      }
      this.states.set(element, state);
    }
    for (const [element, state] of this.states) if (!retained.has(element)) { state.animation?.cancel(); for (const animation of [...state.animations, ...state.discrete]) animation.cancel(); this.states.delete(element); }
    this.measure();
  }

  /** The effect's frames over what `target` already has. An effect is a change made to the view, not its absolute value: at
   * identity the view keeps its own opacity, filter and transform, and the effect's opacity multiplies the view's. */
  composeFrames(target, frames, keys) {
    if (!keys.size) return frames;
    const own = this.window.getComputedStyle(target);
    return frames.map(frame => {
      const composed = {...frame};
      for (const key of keys) {
        const base = own[key];
        if (!base || base === 'none' || (key === 'opacity' && base === '1')) continue;
        if (key === 'opacity') composed.opacity = String(Number(frame.opacity) * Number(base));
        else if (key === 'transform' || key === 'filter') composed[key] = frame[key] === 'none' ? base : base + ' ' + frame[key];
        else if (frame[key] === 'none') composed[key] = base;
      }
      return composed;
    });
  }

  /** The phase value of each element: -1 past the leading edge, 0 at identity, 1 past the trailing edge. */
  measure() {
    const containers = new Map(), bases = new Map();
    const boxes = [];
    for (const [element, state] of this.states) {
      if (state.mode === 'identity' || !element.isConnected) continue;
      let container = containers.get(element.parentElement);
      if (container === undefined) { container = scrollContainer(element, this.window); containers.set(element.parentElement, container); }
      boxes.push([element, state, layoutRect(element, this.window, bases), container ? container.getBoundingClientRect() : {top: 0, left: 0, bottom: this.window.innerHeight, right: this.window.innerWidth}, container]);
    }
    for (const [element, state, box, view, container] of boxes) {
      const horizontal = state.axis ? state.axis === 'horizontal' : container ? container.scrollWidth > container.clientWidth && container.scrollHeight <= container.clientHeight : false;
      const phaseValue = ({threshold: thresholdText, inset}) => {
        const [start, end, viewStart, viewEnd] = horizontal ? [box.left, box.right, view.left + inset, view.right - inset] : [box.top, box.bottom, view.top + inset, view.bottom - inset];
        const size = Math.max(end - start, 1);
        if (thresholdText === 'centered') {
          const offset = (start + end) / 2 - (viewStart + viewEnd) / 2;
          return Math.max(-1, Math.min(1, offset / ((viewEnd - viewStart) / 2 + size / 2)));
        }
        const threshold = Number(thresholdText);
        const visible = Math.max(0, Math.min(end, viewEnd) - Math.max(start, viewStart)) / size;
        // `.hidden` publishes a threshold of 0: any visible part is in view, so only a view fully outside is in a phase.
        let magnitude;
        if (threshold === 0) magnitude = visible > 0 ? 0 : 1;
        else magnitude = visible >= threshold ? 0 : threshold > 0 ? Math.min(1, 1 - visible / threshold) : 1;
        return magnitude === 0 ? 0 : (start + end) / 2 < (viewStart + viewEnd) / 2 ? -magnitude : magnitude;
      };
      // The edge the element is past decides: its threshold measures the phase, and its mode plays it.
      let value = Math.min(0, phaseValue(state.leading));
      if (value === 0) value = Math.max(0, phaseValue(state.trailing));
      const side = value < 0 ? state.leading : state.trailing;
      if (side.mode === 'identity') value = 0;
      const first = !state.measured;
      state.measured = true;
      if (side.mode === 'interactive' || (value === 0 && state.animations.length && !state.animation)) {
        state.animation?.cancel();
        for (const animation of state.discrete) animation.cancel();
        state.animation = null;
        state.discrete = [];
        state.phase = null;
        for (const animation of state.animations) animation.currentTime = interactiveTime(value, this.reducedMotion.matches);
      } else {
        const phase = discretePhase(value, side);
        if (phase === state.phase) continue;
        state.phase = phase;
        // Out of an interactive edge, from where its scrubbing left the element. The effect plays on the same targets as
        // the interactive one: a snap target keeps its box, and its children move.
        const scrubbed = state.animation || state.animations.length;
        const targets = state.placements.map(([target, frames]) => [target, scrubbed ? currentFrame(target, frames[1], this.window) : frames[phase], frames[phase]]);
        for (const animation of state.animations) animation.currentTime = 500;
        state.animation?.cancel();
        for (const animation of state.discrete) animation.cancel();
        const timing = side.timing ?? {duration: 350, easing: 'ease-in-out', delay: 0};
        state.discrete = targets.map(([target, from, to]) => {
          const animation = target.animate([from, to], {
            duration: first || this.reducedMotion.matches ? 0 : timing.duration, delay: first || this.reducedMotion.matches ? 0 : timing.delay,
            easing: this.supportedTransition(timing.easing), fill: 'forwards'});
          animation.id = 'scroll-transition';
          return animation;
        });
        state.animation = state.discrete[0] ?? null;
      }
    }
  }
}

/** The phase an animated scroll transition plays for a measured `value` (-1 past the leading edge, 1 past the trailing one):
 * 0 leading, 1 identity, 2 trailing. A threshold above zero, and `centered`, put the view in a phase as soon as it is partly
 * past; `hidden` (zero) only when it is fully out. */
export function discretePhase(value, side) {
  const partial = side.threshold === 'centered' || Number(side.threshold) > 0;
  return value <= -1 + 1e-6 || (value < 0 && partial) ? 0 : value >= 1 - 1e-6 || (value > 0 && partial) ? 2 : 1;
}

/** Whether the text of a text node is laid out on more than one line: its boxes are at more than one height, in the text's own
 * axes (under a rotation the boxes of one line are at several heights in the viewport). */
function textWraps(node) {
  const range = node.ownerDocument.createRange();
  range.selectNodeContents(node);
  const rects = [...range.getClientRects()];
  if (rects.length < 2) return false;
  const window = node.ownerDocument.defaultView, parent = node.parentElement;
  const map = parent ? cssToViewport(ancestorLinear(window, parent), ownLinear(window, parent)) : null;
  return new Set(rects.map(rect => Math.round(toLocal(map, rect.left + rect.width / 2, rect.top + rect.height / 2)[1]))).size > 1;
}

/** The parts of a CSS value separated by spaces outside parentheses: `calc(-100% + 3px) 0px` is two. */
function splitTopLevel(text) {
  const parts = [];
  let depth = 0, current = '';
  for (const character of text.trim()) {
    if (character === '(') depth++; else if (character === ')') depth--;
    if (/\s/.test(character) && depth === 0) { if (current) parts.push(current); current = ''; } else current += character;
  }
  if (current) parts.push(current);
  return parts;
}

/** The time an interactive scroll transition's animation is set to for a measured phase `value` (-1 to 1): 500 is the identity.
 * With reduced motion the scroll does not move the view: it stays at identity. */
export function interactiveTime(value, reducedMotion) {
  return reducedMotion ? 500 : (value + 1) * 500;
}

/** `opacity=0.5;transform=scale(0.8,0.8)` → {opacity: '0.5', transform: 'scale(0.8,0.8)'}. */
function effectFrame(text) {
  const frame = {};
  for (const pair of (text || '').split(';')) {
    const at = pair.indexOf('=');
    if (at > 0) frame[camel(pair.slice(0, at))] = pair.slice(at + 1);
  }
  return frame;
}

const TRANSFORMS = /* @__PURE__ */ new Set(['transform', 'translate', 'scale', 'rotate']);
/** Where each part of a scroll-transition effect goes. A snap target (`scrollTargetBehavior(.viewAligned)`) keeps its box:
 * the browser computes snap positions from transformed boxes and would snap back as the effect changes them, while in
 * SwiftUI the effect is visual only. Its transforms go to its children; opacity and filters stay on it. */
function effectTargets(element, frames, window) {
  const snapping = (window.getComputedStyle(element).scrollSnapAlign || 'none').split(' ').some(part => part !== 'none');
  if (!snapping || !element.firstElementChild || !frames.some(frame => Object.keys(frame).some(key => TRANSFORMS.has(key)))) return [[element, frames]];
  const split = keep => frames.map(frame => Object.fromEntries(Object.entries(frame).filter(([key]) => TRANSFORMS.has(key) === keep)));
  const own = split(false), moved = split(true);
  const targets = [...element.children].map(child => [child, moved]);
  if (Object.keys(own[0]).length) targets.unshift([element, own]);
  return targets;
}

/** The rectangle `element` has without its own translate, scale and (non-rotating) transform. A scroll transition
 * measures where its view is laid out: the box its own effect gives it would feed the effect back into its phase, so a
 * view half out of the scroll view alternates between two phases. A rotation has no single unrotated box and is kept. */
export function layoutRect(element, window, bases = null) {
  const rect = element.getBoundingClientRect();
  const style = window.getComputedStyle(element);
  const has = value => value && value !== 'none';
  if (!window.DOMMatrix || has(style.rotate) || !(has(style.translate) || has(style.scale) || has(style.transform))) return rect;
  // The offsets and sizes below are in the element's own CSS pixels and the rectangle is in the viewport's: the ancestors'
  // linear transform (their scales and rotations composed, which mixes the axes under a rotation) brings the first to the
  // second. `bases` keeps it per parent for the callers that measure many siblings.
  const parent = element.parentElement;
  let basis = bases?.get(parent);
  if (basis === undefined) { basis = ancestorLinear(window, element); bases?.set(parent, basis); }
  const width = element.offsetWidth, height = element.offsetHeight;
  const length = (token, size) => token.endsWith('%') ? parseFloat(token) * size / 100 : parseFloat(token) || 0;
  const [tx = '0px', ty = '0px'] = has(style.translate) ? style.translate.split(/\s+/) : [];
  const [sx = '1', sy = sx] = has(style.scale) ? style.scale.split(/\s+/) : [];
  const transform = has(style.transform) ? new window.DOMMatrix(style.transform) : new window.DOMMatrix();
  if (Math.abs(transform.b) > 1e-9 || Math.abs(transform.c) > 1e-9) return rect;
  const [ox, oy] = style.transformOrigin.split(/\s+/).map(parseFloat);
  // CSS applies translate, rotate, scale, then transform, about the transform origin.
  const total = new window.DOMMatrix().translateSelf(ox, oy).translateSelf(length(tx, width), length(ty, height))
    .scaleSelf(Number(sx), Number(sy)).multiplySelf(transform).translateSelf(-ox, -oy);
  // The bounding box of the element's box in the viewport, from the ancestors' origin: as drawn (`own` is its effect) and
  // as laid out. The drawn one is `rect`, which places the other.
  const bounds = own => {
    const xs = [], ys = [];
    for (const [px, py] of [[0, 0], [width, 0], [0, height], [width, height]]) {
      const x = own ? own.a * px + own.c * py + own.e : px, y = own ? own.b * px + own.d * py + own.f : py;
      xs.push(basis ? basis.a * x + basis.c * y : x); ys.push(basis ? basis.b * x + basis.d * y : y);
    }
    return {left: Math.min(...xs), top: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys)};
  };
  const drawn = bounds(total), laid = bounds(null);
  const left = rect.left - drawn.left + laid.left, top = rect.top - drawn.top + laid.top;
  return {left, top, right: left + laid.width, bottom: top + laid.height, width: laid.width, height: laid.height};
}

/** Where the top-left corner of a box of `cssWidth` by `cssHeight` CSS pixels is in the viewport, from its bounding box there
 * (`box`) and the map from its CSS pixels to the viewport: the bounding box's own corner unless the map turns or mirrors it. */
function cornerOf(box, map, cssWidth, cssHeight) {
  if (!map) return [box.left, box.top];
  return [box.left - Math.min(0, map.a * cssWidth) - Math.min(0, map.c * cssHeight), box.top - Math.min(0, map.b * cssWidth) - Math.min(0, map.d * cssHeight)];
}

/** Where the top-left corner of the box `element` lays out at is in the viewport, under whatever turns or scales it. */
function originCorner(window, element) {
  const box = element.getBoundingClientRect();
  const map = cssToViewport(ancestorLinear(window, element), ownLinear(window, element));
  const size = map ? layoutSize(window, element) : null;
  return size ? cornerOf(box, map, size.width, size.height) : [box.left, box.top];
}

/** The linear part of the transforms of the ancestors of `element`, outermost first (their scales and rotations; a translation
 * moves the origin only), or null when none scales or rotates it. Computed, not measured: it runs on every scroll frame. */
function ancestorLinear(window, element) {
  let basis = null;
  for (let current = element.parentElement; current; current = current.parentElement) {
    const own = ownLinear(window, current);
    if (own) basis = cssToViewport(own, basis);
  }
  return basis;
}

/** What decides the opacity, transform and filter a view has of its own, before a scroll effect: its inline values and its classes.
 * An effect is composed over them (`composeFrames`), so a change of them composes it again. */
function underlyingKey(targets) {
  return targets.map(target => ['opacity', 'transform', 'translate', 'scale', 'rotate', 'filter'].map(property => target.style[property]).join('|') + '|' + target.getAttribute('class')).join('||');
}

/** Whether the elements the scroll effect of `element` plays on are still the ones `state` made its animations for. */
function sameEffectTargets(state, element, window) {
  const current = effectTargets(element, state.frames, window).map(([target]) => target);
  return current.length === state.targets.length && current.every((target, index) => target === state.targets[index]);
}

/** The nearest ancestor that scrolls, or null for the page. */
function scrollContainer(element, window) {
  for (let current = element.parentElement; current && current !== element.ownerDocument.body; current = current.parentElement) {
    const style = window.getComputedStyle(current);
    if (/(auto|scroll|overlay)/.test(style.overflowY + ' ' + style.overflowX) && (current.scrollHeight > current.clientHeight || current.scrollWidth > current.clientWidth)) return current;
  }
  return null;
}

/** The current values of the animated properties (`keys` of `frame`) of `element`. */
function currentFrame(element, frame, window) {
  const computed = window.getComputedStyle(element), current = {};
  for (const key of Object.keys(frame)) current[key] = computed[key];
  return current;
}

/** Whether an ancestor of `element` scales or rotates it (a translation alone keeps the viewport's axes). */
function transformedAncestor(window, element) {
  for (let current = element.parentElement; current; current = current.parentElement) {
    const style = window.getComputedStyle(current);
    if (style.rotate && style.rotate !== 'none' || style.scale && style.scale !== 'none') return true;
    if (style.transform && style.transform !== 'none') {
      const matrix = new window.DOMMatrix(style.transform);
      if (Math.abs(matrix.a - 1) > 1e-6 || Math.abs(matrix.b) > 1e-6 || Math.abs(matrix.c) > 1e-6 || Math.abs(matrix.d - 1) > 1e-6) return true;
    }
  }
  return false;
}

/** Where one unit of the element's own x and y lands in the viewport (the ancestors' transform), measured by moving it; null
 * when no ancestor scales or rotates it. Rects are in the viewport's coordinates and an element's CSS in its own. */
export function localBasis(window, element) {
  if (!transformedAncestor(window, element)) return null;
  const style = element.style, priority = style.getPropertyPriority('translate'), value = style.getPropertyValue('translate');
  // From a translation of zero: one the element has already (a move still playing) is not the ancestors' mapping, and the
  // probes below replace it.
  style.setProperty('translate', '0px 0px', 'important');
  const base = element.getBoundingClientRect();
  style.setProperty('translate', '100px 0', 'important');
  const x = element.getBoundingClientRect();
  style.setProperty('translate', '0 100px', 'important');
  const y = element.getBoundingClientRect();
  if (value) style.setProperty('translate', value, priority); else style.removeProperty('translate');
  return {a: (x.left - base.left) / 100, b: (x.top - base.top) / 100, c: (y.left - base.left) / 100, d: (y.top - base.top) / 100};
}

/** The size `element` lays out at, in its own CSS pixels: no transform of its own or of an ancestor is in it (a bounding box
 * has them all, and a rotation mixes width and height). Null when the browser reports none (an inline or SVG element). */
function layoutSize(window, element) {
  const computed = window.getComputedStyle(element);
  const px = value => parseFloat(value) || 0;
  let width = parseFloat(computed.width), height = parseFloat(computed.height);
  if (!(width >= 0) || !(height >= 0)) {
    width = element.offsetWidth; height = element.offsetHeight;
    return Number.isFinite(width) && Number.isFinite(height) && (width || height) ? {width, height} : null;
  }
  if (computed.boxSizing !== 'border-box') {
    width += px(computed.paddingLeft) + px(computed.paddingRight) + px(computed.borderLeftWidth) + px(computed.borderRightWidth);
    height += px(computed.paddingTop) + px(computed.paddingBottom) + px(computed.borderTopWidth) + px(computed.borderBottomWidth);
  }
  return {width, height};
}

/** The linear part of the transform, rotate and scale of the element's own (not the translation), or null when it has none. */
function ownLinear(window, element) {
  const computed = window.getComputedStyle(element);
  const has = value => value && value !== 'none';
  let matrix = new window.DOMMatrix();
  if (has(computed.rotate)) {
    const [, number, unit] = /(-?[\d.e+-]+)(deg|rad|turn|grad)?\s*$/.exec(computed.rotate) ?? [];
    const angle = parseFloat(number);
    if (Number.isFinite(angle)) matrix = matrix.rotate(unit === 'rad' ? angle * 180 / Math.PI : unit === 'turn' ? angle * 360 : unit === 'grad' ? angle * 0.9 : angle);
  }
  if (has(computed.scale)) {
    const [x, y = x] = computed.scale.split(/\s+/).map(Number);
    if (Number.isFinite(x) && Number.isFinite(y)) matrix = matrix.scale(x, y);
  }
  if (has(computed.transform)) matrix = matrix.multiply(new window.DOMMatrix(computed.transform));
  const identity = Math.abs(matrix.a - 1) < 1e-6 && Math.abs(matrix.b) < 1e-6 && Math.abs(matrix.c) < 1e-6 && Math.abs(matrix.d - 1) < 1e-6;
  return identity ? null : {a: matrix.a, b: matrix.b, c: matrix.c, d: matrix.d};
}

/** The map from an element's CSS pixels to the viewport: the ancestors' basis after the element's own linear transform. */
function cssToViewport(basis, own) {
  if (!basis && !own) return null;
  const b = basis ?? {a: 1, b: 0, c: 0, d: 1}, o = own ?? {a: 1, b: 0, c: 0, d: 1};
  return {a: b.a * o.a + b.c * o.b, b: b.b * o.a + b.d * o.b, c: b.a * o.c + b.c * o.d, d: b.b * o.c + b.d * o.d};
}

/** The CSS width and height that make a box show `width` by `height` in the viewport under `map`: its bounding box is
 * |a| w + |c| h wide and |b| w + |d| h high, which a rotation mixes. */
function cssSizeFor(map, width, height) {
  if (!map) return [width, height];
  const a = Math.abs(map.a), b = Math.abs(map.b), c = Math.abs(map.c), d = Math.abs(map.d), det = a * d - c * b;
  if (Math.abs(det) < 1e-9) return [width / (Math.hypot(map.a, map.b) || 1), height / (Math.hypot(map.c, map.d) || 1)];
  return [Math.max(0, (width * d - height * c) / det), Math.max(0, (height * a - width * b) / det)];
}

/** A displacement in the viewport as the element's own: through the inverse of its basis. */
function toLocal(basis, dx, dy) {
  const det = basis ? basis.a * basis.d - basis.b * basis.c : 0;
  return basis && Math.abs(det) > 1e-9 ? [(basis.d * dx - basis.c * dy) / det, (basis.a * dy - basis.b * dx) / det] : [dx, dy];
}

/** `matchedGeometryEffect(id:in:properties:anchor:isSource: false)`: a view takes the frame of the source with its name
 * (`data-matched-target`, `data-matched-source`), the parts `data-matched-properties` names, with its anchor point
 * (`data-matched-anchor`, the center by default) on the source's. Its size is written inline as important, over the
 * layout's own rules for the box (the layout engine writes its sizes as important inline values, which only an important
 * one beats), and given back to what the layout wrote when the view stops following a source; its place is a filling `translate` animation; in an animated commit it moves from
 * where it showed with the commit's animation (a FLIP: the new box at once, scaled and moved from the old one). Without
 * a source the view keeps its own frame. */
export class MatchedGeometryHost {
  constructor({window, root, timingFor, supportedTransition}) {
    this.window = window;
    this.root = root;
    this.timingFor = timingFor;
    this.supportedTransition = supportedTransition;
    this.placed = new Map();
    this.plays = new Map();
    this.saved = new Map();
    // Where each placed view was put by the last sync (and where its move started, while it runs): a commit rewrites the
    // view's box before the next sync reads it, so the box it shows by then is the layout's own, not where the view was.
    this.last = new Map();
    this.frame = 0;
    this.update = () => { this.frame = 0; this.sync(false); };
    this.schedule = () => { if (!this.frame && this.placed.size) this.frame = window.requestAnimationFrame(this.update); };
    window.addEventListener('resize', this.schedule, {passive: true});
    // A source and its target can have different scrolling ancestors; scrolling moves one of them without a commit. Scroll
    // events do not bubble, so the capture phase sees every container's.
    window.addEventListener('scroll', this.schedule, {passive: true, capture: true});
  }

  dispose() {
    this.window.removeEventListener('resize', this.schedule);
    this.window.removeEventListener('scroll', this.schedule, {capture: true});
    if (this.frame) this.window.cancelAnimationFrame(this.frame);
    for (const element of [...this.placed.keys()]) this.release(element);
    this.last.clear();
  }

  /** Gives `element` its own frame back. */
  release(element) {
    this.placed.get(element)?.cancel();
    this.placed.delete(element);
    this.plays.delete(element);
    for (const [property, value, priority, wrote] of this.saved.get(element) ?? []) {
      // Only what the match still owns goes back: a size the layout wrote since is the layout's.
      if (element.style.getPropertyValue(property) !== wrote) continue;
      if (value) element.style.setProperty(property, value, priority); else element.style.removeProperty(property);
    }
    this.saved.delete(element);
  }

  /** Where `target` showed before this commit rewrote its box: where the last sync put it, or, while its move is still playing,
   * how far along the move it was. Null for a view that was not placed. */
  shownBefore(target) {
    const last = this.last.get(target);
    if (!last || !this.placed.has(target)) return null;
    const rect = (left, top, width, height) => ({left, top, width, height, right: left + width, bottom: top + height, x: left, y: top});
    const play = this.plays.get(target);
    if (last.from && play && play.animation.playState === 'running') {
      const progress = play.animation.effect?.getComputedTiming?.().progress;
      const at = Number.isFinite(progress) ? progress : 1;
      const mix = (a, b) => a + (b - a) * at;
      return rect(mix(last.from.left, last.left), mix(last.from.top, last.top), mix(last.from.width, last.width), mix(last.from.height, last.height));
    }
    return rect(last.left, last.top, last.width, last.height);
  }

  /** Places every view that takes a source's frame. `animated`: after a commit, which may animate the move. */
  sync(animated) {
    const targets = [...this.root.querySelectorAll('[data-matched-target]')].filter(element => !element.closest(`[${LEAVING}]`));
    const kept = new Set(targets);
    for (const element of [...this.placed.keys()]) if (!kept.has(element)) this.release(element);
    for (const element of [...this.last.keys()]) if (!kept.has(element)) this.last.delete(element);
    if (!targets.length) return;
    const sources = [...this.root.querySelectorAll('[data-matched-source]')].filter(element => !element.closest(`[${LEAVING}]`));
    // All the reads, then all the writes: where each view shows now, its own box, then its box at its new size.
    const work = targets.map(target => {
      const name = target.getAttribute('data-matched-target');
      // A move that is still playing is remembered with how far it got: if the commit does not change where it goes, it goes on.
      const play = this.plays.get(target);
      const running = play && play.animation.playState === 'running' ? {...play, time: play.animation.currentTime} : null;
      return {target, running, source: sources.find(element => element.getAttribute('data-matched-source') === name), shown: this.shownBefore(target)};
    });
    for (const {target} of work) if (this.placed.has(target)) this.release(target);
    for (const item of work) { item.own = item.target.getBoundingClientRect(); item.to = item.source?.getBoundingClientRect() ?? null; }
    // Rects are in the viewport's coordinates and the view's CSS in its own: under a scaled or rotated ancestor they differ.
    for (const item of work) item.basis = item.to ? localBasis(this.window, item.target) : null;
    // And the view's own scale or rotation is in its box too: with the ancestors', the whole map from its CSS pixels to the viewport.
    for (const item of work) item.map = item.to ? cssToViewport(item.basis, ownLinear(this.window, item.target)) : null;
    for (const item of work) {
      if (!item.to) continue;
      const properties = item.target.getAttribute('data-matched-properties') || 'frame';
      const size = properties === 'frame' || properties === 'size';
      // The size the view shows at (its box in the viewport), and the CSS size that gives it: a rotation mixes the two sides.
      item.visibleWidth = size ? item.to.width : item.own.width;
      item.visibleHeight = size ? item.to.height : item.own.height;
      [item.width, item.height] = cssSizeFor(item.map, item.visibleWidth, item.visibleHeight);
      // Only a matched size is written: a position-only match leaves the view's layout size alone.
      if (!size) continue;
      // A new size can move the view in its parent (a centered layer): it is laid out at that size first.
      const style = item.target.style;
      const before = ['box-sizing', 'width', 'height'].map(property => [property, style.getPropertyValue(property), style.getPropertyPriority(property)]);
      // Important, with a reason (AGENTS.md): the layout engine (css-layout.js) writes the box's own width and height as
      // important inline values, and a view that matches a frame is sized by the source, not by its layout.
      style.setProperty('box-sizing', 'border-box', 'important');
      style.setProperty('width', item.width + 'px', 'important');
      style.setProperty('height', item.height + 'px', 'important');
      this.saved.set(item.target, before.map(([property, value, priority]) => [property, value, priority, style.getPropertyValue(property)]));
    }
    // The placement keyframes put the transform origin at the corner (below), so the box is measured with it there too: a view
    // with a scale or rotation of its own would otherwise move when the origin does.
    const origins = work.map(item => item.to ? [item.target.style.getPropertyValue('transform-origin'), item.target.style.getPropertyPriority('transform-origin')] : null);
    for (const item of work) if (item.to) item.target.style.setProperty('transform-origin', '0 0');
    for (const item of work) if (item.to) item.laid = item.target.getBoundingClientRect();
    work.forEach((item, index) => {
      if (!origins[index]) return;
      const [value, priority] = origins[index];
      if (value) item.target.style.setProperty('transform-origin', value, priority); else item.target.style.removeProperty('transform-origin');
    });
    for (const item of work) {
      if (!item.to) continue;
      const {target, own, to, laid, shown, basis} = item;
      // The size the view shows at, in the viewport.
      const width = item.visibleWidth, height = item.visibleHeight;
      // A displacement in the viewport, as the view's own translate.
      const translation = (dx, dy) => { const [x, y] = toLocal(basis, dx, dy); return `${x}px ${y}px`; };
      const properties = target.getAttribute('data-matched-properties') || 'frame';
      const [ax, ay] = (target.getAttribute('data-matched-anchor') || '0.5 0.5').split(' ').map(Number);
      const position = properties === 'frame' || properties === 'position';
      // The view's anchor point goes on the source's, or stays where its own is when only the size is matched.
      const left = (position ? to.left + ax * to.width : own.left + ax * own.width) - ax * width;
      const top = (position ? to.top + ay * to.height : own.top + ay * own.height) - ay * height;
      const end = {translate: translation(left - laid.left, top - laid.top), scale: '1', transformOrigin: '0 0'};
      const timing = animated && shown ? this.timingFor(target, target.parentElement) : null;
      const moves = timing && (Math.abs(shown.left - left) > 0.5 || Math.abs(shown.top - top) > 0.5 || Math.abs(shown.width - width) > 0.5 || Math.abs(shown.height - height) > 0.5);
      // Where it showed, as a scale and a move of the new box about its own corner (the transform origin). Both are in the view's
      // own axes: the size it showed at as a CSS size (under a rotation the viewport's width is not the view's), and its
      // corner, which is the box's top-left in the viewport only when nothing turns or mirrors it.
      const corner = (box, cssWidth, cssHeight) => cornerOf(box, item.map, cssWidth, cssHeight);
      let from = null;
      if (moves) {
        const [shownWidth, shownHeight] = cssSizeFor(item.map, shown.width, shown.height);
        const [fromX, fromY] = corner(shown, shownWidth, shownHeight), [laidX, laidY] = corner(laid, item.width, item.height);
        from = {translate: translation(fromX - laidX, fromY - laidY), scale: `${item.width > 0 ? shownWidth / item.width : 1} ${item.height > 0 ? shownHeight / item.height : 1}`, transformOrigin: '0 0'};
      }
      this.last.set(target, {left, top, width, height, from: moves ? {left: shown.left, top: shown.top, width: shown.width, height: shown.height} : null});
      const key = [end.translate, item.width, item.height].join('|');
      const goesOn = item.running?.key === key;
      const frames = goesOn ? item.running.frames : moves ? [from, end] : [end, end];
      const options = goesOn ? item.running.options : moves
        ? {duration: timing.duration, delay: timing.delay, easing: this.supportedTransition(timing.easing), fill: 'both'}
        : {duration: 0, fill: 'forwards'};
      const animation = target.animate(frames, options);
      if (goesOn) animation.currentTime = item.running.time;
      animation.id = 'matched-geometry';
      this.placed.set(target, animation);
      this.plays.set(target, {key, frames, options, animation});
    }
  }
}

/** A view transition between two sources of a matched geometry morphs the whole frame. With `properties` naming only
 * the position, the group takes the new size at once and moves the old anchor point to the new one; with only the size,
 * the new anchor point stays where it is while the size changes; with neither, nothing morphs. Called when the
 * transition is ready, for the groups of the sources in the page now. */
export function matchViewTransitionGeometry(document, root) {
  const matrix = text => { const match = /matrix\(([^)]*)\)/.exec(text || ''); return match ? match[1].split(',').map(Number) : null; };
  for (const element of root.querySelectorAll('[data-matched-source][data-matched-properties]')) {
    const name = element.style.getPropertyValue('view-transition-name');
    const properties = element.getAttribute('data-matched-properties');
    if (!name || properties === 'frame') continue;
    const [ax, ay] = (element.getAttribute('data-matched-anchor') || '0.5 0.5').split(' ').map(Number);
    for (const animation of document.getAnimations()) {
      if (animation.effect?.pseudoElement !== `::view-transition-group(${name})`) continue;
      const frames = animation.effect.getKeyframes().map(({computedOffset, ...frame}) => frame);
      if (frames.length < 2) continue;
      const first = frames[0], last = frames[frames.length - 1];
      const from = matrix(first.transform), to = matrix(last.transform);
      if (!from || !to) continue;
      const [ow, oh, nw, nh] = [first.width, first.height, last.width, last.height].map(parseFloat);
      let start;
      if (properties === 'position') {
        // The old anchor point, with the new size around it.
        const x = from[4] + ax * ow - ax * nw, y = from[5] + ay * oh - ay * nh;
        start = {...first, width: last.width, height: last.height, transform: `matrix(${from.slice(0, 4).join(', ')}, ${x}, ${y})`};
      } else if (properties === 'size') {
        // The new anchor point, with the old size around it.
        const x = to[4] + ax * nw - ax * ow, y = to[5] + ay * nh - ay * oh;
        start = {...first, transform: `matrix(${to.slice(0, 4).join(', ')}, ${x}, ${y})`};
      } else {
        start = {...last, offset: first.offset};
      }
      animation.effect.setKeyframes([start, ...frames.slice(1)]);
    }
  }
}
