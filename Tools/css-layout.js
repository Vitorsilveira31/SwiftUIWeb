/** CSS layout: lays out the subtrees whose SwiftUI semantics CSS can express with the browser's own flexbox and grid
 * (it replaced an earlier layout engine and the JS placement pass that drove it, both removed). See
 * Documentation/Architecture/CSS_LAYOUT.md.
 * Comments below that say "the JS host" mean the JavaScript layout that stays outside CSS; the rest describe SwiftUI behaviour this ports.
 *
 * An island is a subtree handed to CSS (the scroll views of a screen). `CssLayout.claim(root)` analyses it: it reads the
 * `data-*` layout attributes the Swift side already emits, works out for every node whether it is rigid (its size does
 * not depend on the proposal), hugs its content, or fills what it is offered, and derives one declaration block per
 * node from that and the node's parent. The blocks are interned as rules of one constructed stylesheet. An element
 * carries `data-cl-<n>`, which its rule matches, and `data-cl="<n>"`, which names it for diagnostics and the two global
 * rules: the browser files attribute selectors by attribute name, so a rule per name is found like a class, where
 * `[data-cl="<n>"]` had every styled element tested against every rule (a full style recalculation of a large app's
 * Production screen took 4.2 ms with them, 3.1 ms this way, 2.9 ms without the rules).
 */
// flex-grow of a child by layout priority: a higher priority is offered the space first, so it takes (nearly) all of it
// up to its ideal size before a lower one gets any. An unprioritised Spacer is last in line (priority -1).
const weight = priority => Math.pow(1000000, Math.max(-1, Math.min(3, priority)) + 1);
const STYLE_ATTRIBUTES = new Set(['class', 'hidden', 'data-layout-kind', 'data-layout-gap', 'data-layout-alignment', 'data-align-x', 'data-align-y',
  'data-spacer-min', 'data-fixed-x', 'data-fixed-y', 'data-aspect-ratio', 'data-aspect-fill', 'data-grid-tracks', 'data-row-spacing',
  'data-size-w', 'data-size-h', 'data-layout-leaf', 'data-resizable', 'data-layout-hidden', 'data-tab-hidden', 'data-tab-prepared', 'data-navigation-inactive',
  'data-ideal-w', 'data-ideal-h', 'data-layout-priority', 'data-layout-wrap', 'data-relative-w', 'data-relative-h', 'data-layout-child-proposal', 'data-layout-content-width', 'data-layout-content-height',
  'data-grid-cell-columns', 'data-grid-cell-anchor', 'data-grid-unsized-axes', 'data-grid-column-alignment']);
for (const k of ['w', 'h', 'min-w', 'min-h', 'ideal-w', 'ideal-h', 'max-w', 'max-h']) STYLE_ATTRIBUTES.add('data-frame-' + k);
for (const k of ['top', 'leading', 'bottom', 'trailing']) STYLE_ATTRIBUTES.add('data-padding-' + k);
export const ownsCssLayoutAttribute = name => name === 'data-cl' || name.startsWith('data-cl-');
export const affectsCssLayout = name => STYLE_ATTRIBUTES.has(name);
/** The layers an element holds besides its own (`data-layout-wrap`, outermost first): `kind;name=value;...` separated by `|`.
 * A layer's field names are the attribute names it would have on an element of its own, without `data-`. */
const parseLayers = text => text.split('|').map(part => {
  const [kind, ...pairs] = part.split(';'); const map = new Map();
  for (const pair of pairs) { const i = pair.indexOf('='); if (i > 0) map.set(pair.slice(0, i), pair.slice(i + 1)); }
  return { kind, map };
});
const LAYER_KINDS = new Set(['frame', 'padding', 'fixed']);

const num = (v, d = null) => v == null || v === '' ? d : v === 'inf' ? Infinity : Number.isFinite(Number(v)) ? Number(v) : d;
// A length: a number of pixels, or a CSS expression (a `containerRelativeFrame`'s, see `relativeLength`).
const px = v => typeof v === 'string' ? v : (Math.round(v * 64) / 64) + 'px';
/** A length that can change with every step of a resize, a scroll or an animation (a frame's size, a position, a lazy extent), marked
 * for `lengthVariables`: the rule of a block carries `var(--len<i>)` where it stands and the element the values, so a new value
 * rewrites one inline declaration and adds no rule (a rule inserted in a stylesheet invalidates the style of the whole document). */
const vpx = v => '\u0001' + px(v) + '\u0002';
/** The rule text of a block that `vpx` marked, and its lengths in order: `<prefix><i>` is the i-th (Swift's blocks use `--len`, the
 * mapper's own `--cl-len`, which a DOM patch leaves alone, see `ownsLayoutStyle`). With `variables` false (a collapsed
 * rail's block, whose element already carries the lengths of its expanded one) the lengths stay in the text and the list is empty. */
export function lengthVariables(block, variables = true, prefix = '--len') {
  const lengths = [];
  const text = block.replace(/\u0001([^\u0002]*)\u0002/g, (_, length) => variables ? (lengths.push(length), `var(${prefix}${lengths.length - 1})`) : length);
  return [text, lengths];
}
/** Whether `element` carries `lengths` as `<prefix><i>`, and nothing more. */
const holdsLengths = (element, lengths, prefix = '--len') => lengths.every((length, i) => element.style.getPropertyValue(prefix + i) === length) && element.style.getPropertyValue(prefix + lengths.length) === '';
const writeLengths = (element, lengths, prefix = '--len') => {
  lengths.forEach((length, i) => element.style.setProperty(prefix + i, length));
  for (let i = lengths.length; element.style.getPropertyValue(prefix + i) !== ''; i++) element.style.removeProperty(prefix + i);
};
/** The proposal a user-defined Layout placed a subview with (`data-layout-child-proposal`, `width,height`): null on an axis it left unspecified. */
const childProposal = e => (e.getAttribute('data-layout-child-proposal') || ',').split(',').map(v => v === '' ? null : Math.max(0, Number(v)));
/** What a user-defined Layout's wrapper and subviews are laid out from, as an analysis read it. */
const layoutRead = e => (e.getAttribute('data-layout-child-proposal') ?? '') + '|' + (e.getAttribute('data-layout-content-width') ?? '') + ',' + (e.getAttribute('data-layout-content-height') ?? '');
const FLEX = ['flex-start', 'center', 'flex-end'];
const side = a => a <= 0.25 ? 0 : a >= 0.75 ? 2 : 1;
const align = value => /start|leading|top/.test(value || '') ? 0 : /end|trailing|bottom/.test(value || '') ? 1 : .5;
/** A canvas that carries its own frame (`frame(...)` keeps the element): the drawing it holds is a flexible leaf with no element. */
const framedCanvas = n => n.kind === 'frame' && !n.virtual && n.element.localName === 'canvas' && !n.element.children.length;
const LEAVES = new Set(['intrinsic', 'opaque', 'field', 'flexible', 'spacer', 'size']);
// The kinds the host wraps in a vstack of their own when they hold more than one view.
const GROUPING = new Set(['frame', 'padding', 'fixed', 'aspect']);
// The kinds a Divider inside them still runs along the stack around them (`Divider().frame(height: 20)` is a vertical rule in an
// HStack, as is one with a padding, a fixedSize or an overlay); a ZStack, a VStack, a ScrollView and the rest start over.
const RUNS_THROUGH = new Set(['frame', 'padding', 'fixed', 'overlay', 'background']);
// The height of a linear ProgressView's track: the 8 px its view authors (and the host measures), which the published DOM no longer
// carries when Swift emitted the block that overrides it.
const PROGRESS_TRACK = 8;
/** Whether a Divider directly in a node of `kind` held by `parent` runs vertically: its stack is an HStack. */
const runsVertical = (kind, parent) => kind === 'hstack' || (RUNS_THROUGH.has(kind) && !!parent?.runsVertical);
// What a container-size query takes the size of: a ScrollView and a navigation container (a NavigationStack, a pushed
// screen, a tab's panel). A semantic root is one too, of the size it is proposed.
const CONTAINERS = new Set(['scroll', 'navstack', 'panel']);
// The drawing of a framed canvas, which takes what its frame proposes (see `analyse`).
const CANVAS_DRAWING = { kind: 'flexible', axis: { x: { fill: true, soft: false, rigid: false }, y: { fill: true, soft: false, rigid: false } } };
/** A `containerRelativeFrame`'s length on one axis (`data-relative-w`/`-h`, Swift's samples `container:length;…`) as a CSS
 * expression of the nearest container's length (`--sl-cw`/`--sl-ch`, which `updateContainers` writes):
 * `relative_length`, the piecewise-linear function through the samples (sorted by container length, so they may arrive in
 * any order and decrease), extended along the first and last segments and at least 0, as a sum of ramps. Two samples at one
 * container length are a step there, held at the value below it (as the segments do). `undefined` on an axis the frame
 * does not select. */
const relativeLength = (samples, variable) => {
  if (samples == null) return undefined;
  const sorted = samples.split(';').map(p => p.split(':').map(Number)).filter(p => p.length === 2 && p.every(Number.isFinite)).sort((a, b) => a[0] - b[0]);
  if (!sorted.length) return undefined;
  // One point per container length: samples that share one are a step (`first` below it, `last` from it on).
  const points = [];
  for (const [at, value] of sorted) { const p = points[points.length - 1]; if (p?.at === at) { p.last = value; p.step = true; } else points.push({ at, first: value, last: value }); }
  const n = points.length, r = v => Number(v.toFixed(6)), length = `var(${variable},100%)`;
  if (n === 1) return px(Math.max(0, points[0].last));
  const slope = i => (points[i + 1].first - points[i].last) / (points[i + 1].at - points[i].at);
  // From the first container length on, the value runs along the segments (a ramp where one bends, a step where a length
  // has two samples); before it, along the first segment, or flat when the first length has two samples.
  const head = points[0].step;
  let expr = `${r(points[0].last)}px + ${r(slope(0))} * ${head ? 'max(0px, ' : '('}${length} - ${r(points[0].at)}px)`;
  for (let i = 1; i < n; i++) {
    const bend = r(i < n - 1 ? slope(i) - slope(i - 1) : points[i].step ? -slope(i - 1) : 0), jump = r(points[i].last - points[i].first);
    if (jump) expr += ` + ${jump} * clamp(0px, (${length} - ${r(points[i].at)}px) * 1000000, 1px)`;
    if (bend) expr += ` + ${bend} * max(0px, ${length} - ${r(points[i].at)}px)`;
  }
  return `max(0px, calc(${expr}))`;
};

/** The rule of a block Swift sent: `.sl<n>`, or, for a collapsed rail (`r<n>`), `.sr<n>` scoped to the rail. */
const swiftRule = (key, block) => key[0] === 'r' ? `.tab-view[data-tab-sidebar-expanded="false"] .sr${key.slice(1)}{${block}}` : `.sl${key}{${block}}`;

/** The layout kind of an element: its `data-layout-kind`, else what the host's `describeFresh` would infer. */
export function kindOf(element) {
  const c0 = element.classList;
  // The shell of `.tabViewStyle(.sidebarAdaptable)`: the stylesheet lays out its sidebar, and the screen beside it is
  // inset by the sidebar's width (see `tabview` in `declarations`).
  if (c0.contains('tab-view') && element.getAttribute('data-tab-style') === 'sidebar-adaptable') return 'tabview';
  const explicit = element.getAttribute('data-layout-kind');
  if (explicit) return explicit;
  const c = element.classList;
  if (element.hasAttribute('data-geometry-reader')) return 'geometry';
  if (element.hasAttribute('data-view-that-fits')) return 'fit';
  if (c.contains('scroll-view')) return 'scroll';
  // A NavigationStack (or the legacy NavigationView, whatever its tag): its bar (the stylesheet's `::before` title and the toolbar
  // items) is a row above the screen, which is the pushed destination when there is one (see `pushedStack`).
  if (c.contains('navigation-stack') || c.contains('navigation-view')) return 'navstack';
  // What holds the selected tab's or a pushed screen: it takes the proposal and layers what it holds (a navigation without chrome).
  if (c.contains('tab-body') || c.contains('tab-panel') || c.contains('navigation-destination')) return 'panel';
  if (element.localName === 'button' && (c.contains('button-plain') || c.contains('button-borderless') || c.contains('button-custom'))) return 'zstack';
  if (element.localName === 'input' && element.getAttribute('data-field-chrome') === 'plain') return 'field';
  // A linear Gauge takes the width it is offered (the host's flexible-width frame around its track) and is as tall as its
  // track, which the stylesheet stretches across it.
  if (c.contains('gauge-meter')) return 'field';
  // A linear ProgressView and a Slider take the width they are offered too (their view authors `width: 100%`) and are as tall
  // as their track: the browser gives a slider a width of its own (129 px) and a progress bar none.
  if (element.localName === 'progress' || (element.localName === 'input' && element.getAttribute('type') === 'range')) return 'field';
  // A user-defined Layout, and an HSplitView or VSplitView (the split layout places its panes): Swift sized the wrapper for the
  // proposal the page reported (`reportLayouts`), so it is a box of that size.
  if (c.contains('layout-box') && element.hasAttribute('data-layout-proposal')) return 'size';
  if (c.contains('layout-box') || c.contains('regular-grid') || c.contains('table-view') || ['button', 'input', 'textarea', 'select', 'details', 'table', 'ul', 'ol', 'label'].includes(element.localName)) return 'opaque';
  if (c.contains('avkit-video-player') || c.contains('data-chart') || c.contains('shape-layer') || c.contains('mesh-gradient') || ['canvas', 'iframe', 'video'].includes(element.localName) || element.getAttribute('data-resizable') === 'true') return 'flexible';
  if (c.contains('backdrop-layer')) return 'background';
  if (c.contains('overlay-layer')) return 'overlay';
  if (c.contains('vstack') || c.contains('searchable')) return 'vstack';
  if (c.contains('hstack')) return 'hstack';
  if (c.contains('zstack')) return 'zstack';
  if (c.contains('swipe-row') || c.contains('swipe-content')) return 'zstack';
  if (c.contains('grid-layout')) return 'grid';
  if (c.contains('scroll-view-reader') || c.contains('lazy-cell') || c.contains('navigation-root') || c.contains('timeline-view') || c.contains('layout-item')) return 'zstack';
  return element.children.length ? 'opaque' : 'intrinsic';
}
/** What the stylesheet hides with `display: none` among what takes no part. Such an element keeps the blocks it had while
 * it was shown (a global rule gives it its `display: none` back), so showing a tab again writes nothing. */
const HIDDEN = '[hidden],.tab-panel[data-tab-hidden="true"],[data-layout-hidden],.navigation-destination[data-navigation-inactive="true"],' +
  '.view-that-fits-candidate:not([data-fit-selected="true"]),' +
  '.navigation-root[aria-hidden="true"]';
/** Whether a NavigationStack shows a pushed destination: its depth (`data-navigation-depth`) is authoritative, as for the host,
 * not the root's `aria-hidden`, which a presentation's focus isolation may restore. The root then takes no part. */
const pushedStack = element => Number(element.getAttribute('data-navigation-depth')) > 0;
/** The shown items of a NavigationStack's bar on one side (`start`, `center`, `end`), in the order they were declared. */
const shownOn = (n, side) => n.bar.filter(item => item.shown && item.side === side);
/** The tracks of a NavigationStack's bar grid: `lead` and `trail`, one per item on a side that holds several, as wide as it
 * is, and `centre`, one per principal item when there are several. Null when no side needs one (the bar is one cell). */
const barTracks = n => {
  const start = shownOn(n, 'start').length, centre = shownOn(n, 'center').length, end = shownOn(n, 'end').length;
  if (centre > 1) return { lead: start > 1 ? start : 0, centre, trail: end > 1 ? end : 0 };
  return start < 2 && end < 2 ? null : { lead: start, centre: 0, trail: end };
};
/** The columns of that grid: the leading items' tracks, the rest of the bar and the trailing items' tracks (the host sets the
 * items of a side 8 px apart, in the order they were declared). Several principal items sit side by side, with no gap, as a
 * group centred on the bar (the host's): a track each between two equal flexible ones. The leading items are in the first,
 * whose minimum is their width and 8 px, so the group starts after them at the earliest; the trailing items keep to the end,
 * where the second gives way to them. */
const barColumns = n => {
  const t = barTracks(n), autos = count => Array(count).fill('auto');
  return t && [...autos(t.lead), ...t.centre ? ['1fr', ...autos(t.centre), 'minmax(0,1fr)'] : ['minmax(0,1fr)'], ...autos(t.trail)].join(' ');
};
/** The grid area of a shown bar item: its track when a side holds several items, else the bar row's one cell. */
const barArea = (n, item) => {
  const t = barTracks(n);
  if (!t) return '1 / 1';
  const index = shownOn(n, item.side).indexOf(item);
  if (item.side === 'center') return t.centre ? `1 / ${t.lead + 2 + index}` : '1 / 1 / 2 / -1';
  if (item.side === 'start') return `1 / ${index + 1}`;
  return t.trail ? `1 / ${t.lead + 2 + (t.centre ? t.centre + 1 : 0) + index}` : '1 / 1 / 2 / -1';
};
/** A safeAreaInset (or a TabView's bottom tab bar): the edge its inset sits on (`data-inset-edge`), whether that edge is
 * vertical (top or bottom: the inset is a row), and whether it is the start (top or leading). */
const insetEdge = n => { const edge = (n.attr ? n.attr('data-inset-edge') : n.element.getAttribute('data-inset-edge')) || 'bottom'; return { edge, vertical: edge === 'top' || edge === 'bottom', start: edge === 'top' || edge === 'leading' }; };
/** The grid area of an inset's child: the content's track and the inset's (its edge's end of the grid). */
const insetArea = (parent, n) => {
  const { vertical, start } = insetEdge(parent), first = (parent.kids[1] === n) === start;
  return vertical ? `${first ? 1 : 2} / 1` : `1 / ${first ? 1 : 2}`;
};
/** A ScrollView holding several views: its children are rows of its grid, in order (see `declarations`). */
const stackedScroll = n => n.kind === 'scroll' && n.kids.length > 1;
// The bar `NavigationStack` builds from `ToolbarItemPlacement.bottomBar` items: a row of its own below the screen.
const isBottomBar = element => element.classList.contains('navigation-bottom-bar');
const isToolbarChrome = element => element.classList.contains('toolbar-item') || element.classList.contains('toolbar-group');
// Bar items lead, are centred or trail, by placement (`data-toolbar-placement`).
const barSide = item => { const p = item.getAttribute('data-toolbar-placement') || ''; return p === 'principal' ? 'center' : /leading/.test(p) ? 'start' : 'end'; };
// A tab panel built hidden before it was ever shown (`data-tab-prepared`) is laid out while hidden (`HIDDEN` keeps it so).
const takesPart = child => !child.hidden && !child.classList.contains('swipe-actions') && child.getAttribute('data-navigation-inactive') !== 'true' &&
  (child.getAttribute('data-tab-hidden') !== 'true' || child.getAttribute('data-tab-prepared') === 'true') && !child.classList.contains('presentation-root') && !child.classList.contains('swiftuiweb-navigation-bar') &&
  !child.classList.contains('context-menu-panel') && !child.classList.contains('toolbar-item') && !child.classList.contains('toolbar-group') &&
  !child.hasAttribute('data-layout-hidden');

/** The offsets of the scroll views inside `roots`. Laying a ViewThatFits out to measure it (no candidate shown, or a candidate
 * out of the flow with no height to scroll in) makes the browser drop those offsets: a lazy list that grew was measured again
 * and went back to its top. */
function scrollOffsets(roots) {
  const offsets = [];
  for (const root of roots) for (const e of root.querySelectorAll('[data-scroll-node],.scroll-view')) if (e.scrollTop || e.scrollLeft) offsets.push([e, e.scrollLeft, e.scrollTop]);
  return offsets;
}
function restoreScrollOffsets(offsets) {
  for (const [e, left, top] of offsets) { if (e.scrollTop !== top) e.scrollTop = top; if (e.scrollLeft !== left) e.scrollLeft = left; }
}

export class CssLayout {
  constructor(document, options = {}) {
    this.document = document;
    this.options = options; // baseline: true aligns `.firstTextBaseline` stacks on the text baseline (the JS host centres them)
    this.rules = new Map(); // declaration block -> id
    this.blocks = []; // id -> declaration block
    this.cache = new WeakMap(); // element -> analysed node
    this.dirty = new Set();
    this.islands = new Set();
    this.swiftRoot = null; // the root of a `verifySwift` analysis, whose block Swift sent
    this.roots = new WeakMap(); // root island -> what its container proposes ({ def: {x, y}, ax, height })
    this.foreign = new WeakSet(); // semantic roots inside an island that the JS host lays out
    this.pending = new Set(); // islands with analysed-but-unassigned changes
    this.fits = new Set(); // the ViewThatFits elements of the islands, whose candidate the page selects (`chooseFits`)
    this.ideals = new WeakMap(); // ViewThatFits candidate -> its ideal size ({ width it was measured at, w, h })
    this.layouts = new Set(); // the wrappers of user-defined Layouts whose proposal and subview sizes the page reports (`reportLayouts`)
    this.containers = new Set(); // the containers whose length a containerRelativeFrame below reads (`updateContainers`)
    this.assigned = new WeakSet();
    this.stats = { analysed: 0, assigned: 0, rules: 0, unsupported: {}, nodes: 0, selectsMeasured: 0 };
    // `detached`: an analysis that writes nothing (the equivalence check of `flush`).
    if (options.detached) { this.sheet = null; return; }
    this.sheet = new document.defaultView.CSSStyleSheet();
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, this.sheet];
    // The rules of new blocks go into a stylesheet of their own per `assign`, adopted after the others: Chromium takes a
    // rule inserted into an adopted stylesheet as a change of the whole sheet and restyles every element any of its
    // rules matches (every element the mapper styles), where an appended sheet restyles only what its rules match (none
    // yet). The sheets are merged into one when the page is idle.
    this.ruleSheets = [];
    this.fresh = [];
    // A menu Picker is as wide as its selected label in SwiftUI; a <select> is as wide as its widest option. The page
    // measures the selected label as the host does (`sizeSelects`, `--sl-select-w`); until then, Chromium sizes it to the
    // selection with field-sizing (a pixel off the host's measure), WebKit and Firefox to its widest option.
    // The global rules hold for the elements Swift styles too (`data-sl`, see `_CSSLayoutEmitter`).
    this.selectWidths = new WeakMap(); // select -> what its width was measured for
    this.fontEpoch = 0; // a font that loads changes every label's width
    document.fonts?.addEventListener?.('loadingdone', () => { this.fontEpoch++; });
    this.sheet.insertRule(':is([data-cl],[data-sl-root]) select{field-sizing:content !important;width:var(--sl-select-w,auto) !important}', 0);
    // SwiftUI's Text is as wide as the lines it draws, not as what it is offered: a wrapped text is as wide as its longest
    // line, a truncated one as what it shows and the ellipsis. CSS keeps the box it offered, so the page measures the
    // lines (`fitTexts`) and caps the box there (`--sl-text-w`); what is left goes to the views beside it. The attribute
    // twice outranks a block (`[data-cl-<n>]`, `.sl<n>`).
    this.textWidths = new Map(); // text leaf -> the cap it carries
    this.fontSizes = new WeakMap(); // text leaf -> the font size a minimumScaleFactor shrink set, and the size Swift set
    this.sheet.insertRule('[data-text-fit][data-text-fit]{max-width:var(--sl-text-w) !important}', 0);
    // The stylesheet skips the rendering of lazy stacks and grids (`content-visibility: auto`, with a 160 px placeholder),
    // which is only harmless while the host gives them their size: with CSS layout their size is their content's, and
    // SwiftUIWeb's lazy windows already keep only the visible rows in the DOM.
    this.sheet.insertRule(':is([data-cl],[data-sl-root] *):is(.grid-layout,.lazy-vstack,.lazy-hstack){content-visibility:visible !important}', 0);
    // The container of a root proposed its cell (a presentation's content): a one-cell grid the root fills or is aligned in.
    // A presentation's content made a one-cell grid for its root, by the mapper (`data-cl-host`) or by Swift (`data-sl-host`).
    this.sheet.insertRule(':is([data-cl-host],[data-sl-host]){display:grid !important;grid-template-columns:minmax(0,1fr) !important;grid-template-rows:minmax(0,1fr) !important}', 0);
    // `.position(x:y:)` measures its point from the trailing edge in a right-to-left document (as SwiftUI's position does).
    this.sheet.insertRule(':is([data-cl],[data-sl-root] *)[data-layout-kind="position"]:dir(rtl) > *{left:auto !important;right:var(--sl-px) !important;translate:50% -50% !important}', 0);
    // A NavigationStack's title (the stylesheet's `::before`) is in the bar row with the items. A pushed destination replaces the
    // root whatever its `aria-hidden` says (the stylesheet hides it by that alone, and it takes no part in the layout).
    // The stack may itself be the styled root (an app whose window content is a NavigationStack), not only below one.
    this.sheet.insertRule('.navigation-stack:is([data-cl],[data-sl-root],[data-sl-root] *)::before{grid-area:1 / 1 / 2 / -1 !important}', 0);
    this.sheet.insertRule(':is(.navigation-stack,.navigation-view)[data-navigation-depth]:not([data-navigation-depth="0"]):is([data-cl],[data-sl-root],[data-sl-root] *) > .navigation-root:not([data-navigation-motion="covered"]){display:none !important}', 0);
    // A ViewThatFits being probed (`probeFits`) shows no candidate.
    this.sheet.insertRule('.view-that-fits[data-fit-probe] > *{display:none !important}', 0);
    // A hidden tab or screen keeps its blocks, whose `display` would override the stylesheet's `display: none`.
    // The screen under a push stays drawn while the push plays (`data-navigation-motion`, transition-host.js), still taking
    // no part in the layout.
    this.sheet.insertRule(`:is([data-cl],[data-sl-root] *):is(${HIDDEN}):not([data-navigation-motion="covered"]){display:none !important}`, 0);
    this.swiftBlocks = new Map(); // id -> block of the rules Swift sent
  }
  /** Records a mutation inside an island: the element and its ancestors are analysed again. */
  mark(element, root) {
    for (let e = element; e; e = e.parentElement) {
      if (this.dirty.has(e)) break;
      this.dirty.add(e);
      // A change inside a ViewThatFits candidate can change its ideal width.
      if (e.classList.contains('view-that-fits-candidate')) this.ideals.delete(e);
      if (e === root) break;
    }
  }
  /** Whether `element` (a ScrollView) can be an island. Only one that scrolls vertically: an island is a `flexible` leaf for
   * SwiftUI, which takes the proposal on both axes, while a horizontal ScrollView is as tall as its content. A horizontal one
   * inside an island is laid out by CSS with the rest of it. */
  static islandCandidate(element) {
    const c = element.classList;
    return !c.contains('scroll-horizontal') && !c.contains('scroll-both');
  }
  /** Analyses the subtree under `root`; true when CSS can lay all of it out. Mutations reach the mapper only inside the
   * islands it holds, so a root it refused before is analysed from scratch: its cached nodes may be stale. */
  claim(root) {
    if (!this.islands.has(root)) for (const e of [root, ...root.querySelectorAll('*')]) { this.cache.delete(e); this.ideals.delete(e); }
    this.rail = this.roots.get(root)?.key === 'rail';
    let node;
    try { node = this.analyse(root, null); } finally { this.rail = false; }
    if (node.supported) { this.islands.add(root); if (!this.assigned.has(root)) this.pending.add(root); }
    return node.supported;
  }
  /** Analyses a semantic root of the page (the application's root view, a sidebar slot's content); true when CSS can lay
   * all of it out. `proposal`: whether its container proposes a size on each axis (`def`), its horizontal alignment
   * there (`ax`) and the height a finite vertical proposal is (`height`, a CSS length). */
  claimRoot(root, proposal) {
    const previous = this.roots.get(root);
    if (!previous || previous.key !== proposal.key) {
      this.roots.set(root, proposal);
      // What takes part can depend on the container (a collapsed rail hides parts of a slot's content): from scratch.
      if (previous) for (const e of [root, ...root.querySelectorAll('*')]) this.cache.delete(e);
    }
    if (this.claim(root)) {
      if (previous?.key !== proposal.key) this.pending.add(root);
      if (proposal.item) this.layouts.add(root.parentElement);
      if (proposal.height === 'cell' && !root.parentElement.hasAttribute('data-cl-host')) root.parentElement.setAttribute('data-cl-host', '');
      // The ScrollViews it holds were islands of their own while the JS host laid out the root: they are its nodes now.
      // (Not the roots inside it: the subviews of a user-defined Layout it holds are roots of their own.)
      for (const island of this.islands) if (island !== root && root.contains(island) && !this.roots.has(island)) { this.islands.delete(island); this.pending.delete(island); this.assigned.delete(island); this.pending.add(root); }
      return true;
    }
    this.release(root);
    return false;
  }
  /** Whether `element` is a node of an island the mapper holds: analysed with it, though its block may not be written yet
   * (the islands claimed in a pass are styled at its end). */
  holds(element) {
    if (!this.cache.has(element)) return false;
    for (let p = element; p; p = p.parentElement) if (this.islands.has(p)) return true;
    return false;
  }
  /** Stops styling an island CSS can no longer lay out (something it cannot express appeared in it): its elements lose
   * their blocks (the host then reports the root as laid out by nothing). */
  release(island) {
    if (this.roots.get(island)?.height === 'cell') island.parentElement?.removeAttribute('data-cl-host');
    this.roots.delete(island);
    if (!this.islands.has(island)) return;
    this.islands.delete(island); this.pending.delete(island); this.assigned.delete(island);
    this.strip(island);
  }
  /** Removes the blocks of a subtree that stopped taking part other than by being hidden (`HIDDEN`), and of an island
   * that is released: a block would override what the stylesheet or the host gives it now. */
  strip(element) {
    // What a root of its own holds (the subviews of a user-defined Layout) keeps its blocks.
    const inRoot = e => { for (let p = e; p && p !== element; p = p.parentElement) if (this.roots.has(p)) return true; return false; };
    for (const e of [element, ...element.querySelectorAll('[data-cl]')]) {
      if (this.layouts.size && inRoot(e)) continue;
      const held = e.getAttribute('data-cl');
      if (held) { e.removeAttribute('data-cl-' + held); e.removeAttribute('data-cl'); }
      if (this.containers.has(e)) { this.containers.delete(e); e.style.removeProperty('--sl-cw'); e.style.removeProperty('--sl-ch'); }
      this.cache.delete(e);
    }
  }
  /** The semantic roots inside islands that the JS host lays out: a mutation inside one is the host's, not the
   * mapper's. */
  setForeign(elements) { this.foreign = new WeakSet(elements); }
  /** The claimed island that contains `element` (or is it), unless a semantic root the mapper does not hold is nearer. */
  islandOf(element) {
    if (this.islands.size === 0) return null;
    for (let e = element; e; e = e.parentElement) { if (this.islands.has(e)) return e; if (this.foreign.has(e)) return null; }
    return null;
  }
  /** A mutation record inside an island: only what can change CSS layout marks anything. */
  note(record, target, island) {
    // What a <select> shows sizes it (`sizeSelects`): the text of its options and which one is selected.
    const labelsSelect = target.localName === 'option' && (record.type === 'characterData' || record.attributeName === 'selected');
    if (labelsSelect) { if (record.type === 'attributes' && record.oldValue === target.getAttribute('selected')) return; }
    else if (record.type === 'attributes') {
      if (!affectsCssLayout(record.attributeName) || record.oldValue === target.getAttribute(record.attributeName)) return;
    } else if (record.type !== 'childList') return;
    this.mark(target, island);
    this.pending.add(island);
  }
  /** Analyses and styles every island with pending changes. */
  flush() {
    for (const island of this.islands) if (!island.isConnected) { this.islands.delete(island); this.pending.delete(island); }
    this.released = [];
    this.style();
    // Each pass (a patch, a resize of the window) selects the candidate of every ViewThatFits for what it is offered now.
    if (this.fits.size) this.chooseFits();
    if (this.containers.size) this.updateContainers();
    if (this.layouts.size) this.reportLayouts();
    this.sizeSelects();
  }
  /** Gives each <select> the CSS lays out the width of a copy that holds only its selected option (`--sl-select-w`), as
   * the host measures it. The copies are measured together outside the application's tree, with
   * the select's font and chrome, so the layout observes no mutation. */
  sizeSelects() {
    const view = this.document.defaultView, measured = [];
    let box = null;
    for (const select of this.document.getElementsByTagName('select')) {
      if (!select.parentElement?.closest('[data-cl],[data-sl-root]')) continue;
      const option = select.options[select.selectedIndex];
      // Read without a style recalculation (the computed style is read only to measure): the selection, its label, the
      // classes and the fonts loaded so far.
      const key = `${select.selectedIndex}:${option?.textContent ?? ''}:${select.className}:${this.fontEpoch}`;
      const known = this.selectWidths.get(select);
      // A DOM patch keeps `--sl-` properties (`ownsLayoutStyle`), so a select measured for this key still has its width.
      if (known === key) continue;
      const cs = view.getComputedStyle(select);
      const copy = this.document.createElement('select');
      if (option) copy.append(option.cloneNode(true));
      for (const name of ['font-family', 'font-size', 'font-weight', 'font-style', 'font-stretch', 'letter-spacing', 'text-transform', 'padding-left', 'padding-right', 'border-left-width', 'border-left-style', 'border-right-width', 'border-right-style', 'box-sizing', 'appearance', '-webkit-appearance'])
        copy.style.setProperty(name, cs.getPropertyValue(name));
      copy.style.setProperty('width', 'auto'); copy.style.setProperty('min-width', '0'); copy.style.setProperty('max-width', 'none');
      box ??= this.document.createElement('div');
      box.append(copy);
      measured.push([select, key, copy, cs.boxSizing === 'border-box' ? 0 : parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight) + parseFloat(cs.borderLeftWidth) + parseFloat(cs.borderRightWidth)]);
    }
    if (!box) return;
    this.stats.selectsMeasured += measured.length;
    box.style.cssText = 'position:absolute;visibility:hidden;left:0;top:0;width:0;height:0;overflow:hidden;contain:strict;pointer-events:none';
    this.document.body.append(box);
    const widths = measured.map(([, , copy, chrome]) => px(Math.max(0, copy.getBoundingClientRect().width - chrome)));
    box.remove();
    measured.forEach(([select, key], i) => {
      this.selectWidths.set(select, key);
      if (select.style.getPropertyValue('--sl-select-w') !== widths[i]) select.style.setProperty('--sl-select-w', widths[i]);
    });
  }
  /** Caps every text leaf CSS lays out at the width of the lines it draws, as SwiftUI's Text sizes itself (see the
   * `data-text-fit` rule). The caps are lifted first, so each text is measured in the box CSS offers it now (a window that
   * grew offers more), then set again where the lines are narrower than that box. A cap gives the views beside the text
   * what it does not use; a text that took that space is measured again, a few rounds at most. */
  fitTexts() {
    if (!this.sheet) return;
    for (const [text] of this.textWidths) text.removeAttribute('data-text-fit');
    const capped = new Map();
    let candidates = [...this.document.querySelectorAll('[data-layout-leaf="text"]')].filter(text =>
      text.isConnected && !text.hasAttribute('data-layout-wrap') && (text.hasAttribute('data-cl') || text.closest('[data-sl-root]')));
    // A font shrink comes before the lines are measured: a text that now fits is measured as the text it is.
    for (const text of candidates) this.shrinkToFit(text);
    for (let round = 0; round < 3 && candidates.length; round++) {
      // Read every width first (one layout), then write.
      const found = [];
      for (const text of candidates) { const width = this.linesWidth(text); if (width != null) found.push([text, width]); }
      for (const [text, width] of found) {
        const value = px(width);
        if (text.style.getPropertyValue('--sl-text-w') !== value) text.style.setProperty('--sl-text-w', value);
        text.setAttribute('data-text-fit', '');
        capped.set(text, width);
      }
      // A cap frees space for the texts beside it: those not capped yet are measured again in what they are offered now.
      candidates = found.length ? candidates.filter(text => !capped.has(text)) : [];
    }
    for (const [text] of this.textWidths) if (!capped.has(text)) text.style.removeProperty('--sl-text-w');
    this.textWidths = capped;
  }
  /** SwiftUI's minimumScaleFactor: a one-line text wider than its box is drawn at the font size that fits it, but not below
   * the factor's share of its size. The size Swift set is the base; a size this host set last is replaced by it, so the
   * text grows back when its box does. */
  shrinkToFit(text) {
    const factor = Number(text.getAttribute('data-minimum-scale-factor'));
    // A text that no longer shrinks (the factor went to 1, or the text is no longer one line) gets back the size Swift set.
    if (!(factor > 0 && factor < 1) || text.style.whiteSpace !== 'nowrap' || !text.firstChild) {
      const stale = this.fontSizes.get(text);
      if (stale !== undefined) {
        if (stale.size === text.style.fontSize) text.style.fontSize = stale.swift;
        this.fontSizes.delete(text);
      }
      return;
    }
    const applied = this.fontSizes.get(text);
    const ours = applied !== undefined && applied.size === text.style.fontSize;
    const swift = ours ? applied.swift : text.style.fontSize;
    const base = ours ? applied.base : parseFloat(this.document.defaultView.getComputedStyle(text).fontSize);
    if (!(base > 0)) return;
    text.style.fontSize = `${base}px`;
    const box = text.clientWidth;
    const range = this.document.createRange();
    range.selectNodeContents(text);
    const full = range.getBoundingClientRect().width;
    if (!box || full <= box + 0.5) {
      text.style.fontSize = swift;
      this.fontSizes.delete(text);
      return;
    }
    text.style.fontSize = `${Math.max(base * factor, base * box / full)}px`;
    this.fontSizes.set(text, { swift, base, size: text.style.fontSize });
  }
  /** The width of the lines `text` draws in its box, when they are narrower than the box (else null): its longest line when
   * it wraps; when it is one line cut with an ellipsis, the part it shows and the ellipsis. */
  linesWidth(text) {
    const box = text.clientWidth;
    if (!box || !text.firstChild) return null;
    const range = this.document.createRange();
    range.selectNodeContents(text);
    const full = range.getBoundingClientRect().width;
    let width;
    if (text.style.whiteSpace === 'nowrap' && text.style.textOverflow === 'ellipsis') {
      if (full <= box + 0.5) return null;
      width = this.truncatedWidth(text, range, box);
    } else {
      // Fragments on one line share their top: a line is as wide as from its first fragment's start to its last one's end.
      const lines = new Map();
      for (const rect of range.getClientRects()) {
        if (!rect.width) continue;
        const top = Math.round(rect.top), line = lines.get(top);
        lines.set(top, line ? [Math.min(line[0], rect.left), Math.max(line[1], rect.right)] : [rect.left, rect.right]);
      }
      if (lines.size < 2) return null;
      width = Math.max(...[...lines.values()].map(([left, right]) => right - left));
    }
    const padding = text.offsetWidth - box;
    // A hundredth over what the lines need keeps the browser breaking (or cutting) them where it did.
    return width != null && width < box - 0.25 ? width + padding + 0.01 : null;
  }
  /** A one-line text cut to `box`: as wide as the longest start of it that leaves room for the ellipsis, and the ellipsis. */
  truncatedWidth(text, range, box) {
    const view = this.document.defaultView, style = view.getComputedStyle(text);
    const context = (this.measureContext ??= this.document.createElement('canvas').getContext('2d'));
    if (!context) return null;
    context.font = style.font;
    const ellipsis = context.measureText('…').width;
    // SwiftUI's Text offered less than an ellipsis takes what it is offered.
    if (ellipsis >= box) return null;
    const nodes = [], walker = this.document.createTreeWalker(text, view.NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) nodes.push(node);
    const total = nodes.reduce((sum, node) => sum + node.length, 0);
    const prefixWidth = count => {
      let left = count, index = 0;
      while (index < nodes.length - 1 && left > nodes[index].length) { left -= nodes[index].length; index++; }
      range.setStart(nodes[0], 0); range.setEnd(nodes[index], Math.min(left, nodes[index].length));
      return range.getBoundingClientRect().width;
    };
    let low = 0, high = total;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      if (prefixWidth(middle) + ellipsis <= box) low = middle; else high = middle - 1;
    }
    return prefixWidth(low) + ellipsis;
  }
  /** Analyses and styles the islands with pending changes. */
  style() {
    if (this.pending.size === 0) return;
    for (const island of this.pending) {
      // Something CSS cannot express appeared in it: the host reports it (`released`).
      if (!this.claim(island)) { this.release(island); this.released.push(island); continue; }
      this.assign(island);
      this.assigned.add(island);
    }
    if (this.document.defaultView.__layoutVerify) for (const island of this.pending) this.verify(island);
    this.pending.clear();
    this.dirty.clear();
  }
  /** Selects the candidate of each ViewThatFits the mapper lays out, as SwiftUI's ViewThatFits does: the first whose ideal
   * size fits what the ViewThatFits is offered on the axes it chooses along, else the last.
   * - What it is offered: nothing on an axis with no proposal (every candidate fits there). Where the candidate shown
   *   takes what it is offered, the ViewThatFits's box. Elsewhere a probe (`probeFits`) lays the ViewThatFits out once as
   *   a view that takes all it is given (all a stack shares to it along the stack's axis, its whole proposal across),
   *   with no candidate shown, and reads its box.
   * - A candidate's ideal size: its size proposed nothing on those axes (`measureIdeals`), measured once and again after
   *   a change inside it.
   * A new selection styles the island again (the ViewThatFits is then as large as the candidate it shows). */
  chooseFits() {
    // A ViewThatFits in a candidate of another changes the ideal size of that candidate: chosen again, until none changes.
    for (let pass = 0; pass < 4 && this.selectFits(); pass++);
  }
  selectFits() {
    const live = [];
    for (const fit of this.fits) {
      if (!fit.isConnected) { this.fits.delete(fit); continue; }
      const node = this.cache.get(fit), island = this.islandOf(fit);
      if (!island || !node?.fit || !node.def || !node.kids[0]) continue;
      const candidates = [...fit.children].filter(child => child.classList.contains('view-that-fits-candidate'));
      // What the host left when it laid the ViewThatFits out: the mapper shows and hides the candidates now.
      for (const c of candidates) if (c.hasAttribute('data-layout-hidden')) { c.removeAttribute('data-layout-hidden'); c.style.removeProperty('display'); }
      if (!candidates.length) continue;
      const along = { x: node.fit !== 'vertical', y: node.fit !== 'horizontal' };
      const shown = node.kids[0].axis, offered = { x: Infinity, y: Infinity }, probe = [];
      const box = fit.getBoundingClientRect();
      for (const a of ['x', 'y']) {
        if (!along[a] || !node.def[a]) continue;
        if (shown[a].fill && !shown[a].soft) offered[a] = a === 'x' ? box.width : box.height;
        else probe.push(a);
      }
      live.push({ fit, node, island, candidates, along, offered, probe });
    }
    this.probeFits(live.filter(entry => entry.probe.length));
    for (const entry of live) this.measureIdeals(entry);
    // All are chosen before any is shown: showing one marks the candidates around it (their ideal sizes change).
    const picks = live.map(({ candidates, along, offered }) => {
      const chosen = candidates.findIndex(c => { const ideal = this.ideals.get(c); return (!along.x || ideal.w <= offered.x + 1e-3) && (!along.y || ideal.h <= offered.y + 1e-3); });
      return chosen < 0 ? candidates.length - 1 : chosen;
    });
    let changed = false;
    live.forEach(({ fit, node, island, candidates }, n) => {
      const chosen = picks[n];
      if (node.selected === candidates[chosen] && candidates.every((c, i) => (c.getAttribute('data-fit-selected') === 'true') === (i === chosen))) return;
      candidates.forEach((c, i) => { if (i === chosen) c.setAttribute('data-fit-selected', 'true'); else c.removeAttribute('data-fit-selected'); });
      this.mark(fit, island); this.pending.add(island); changed = true;
    });
    if (changed) this.style();
    return changed;
  }
  /** Reads what each ViewThatFits in `entries` is offered on its `probe` axes: all of them laid out at once as views that
   * take all they are given, with no candidate shown (`[data-fit-probe]`), then put back. Along a stack's axis it takes the
   * share a flexible view of its priority gets (a Spacer still keeps its minimum); across, or in a one-cell container, its
   * whole proposal (`max-width: 100%` of what holds it, which content-sized ancestors give up to their own proposal). */
  probeFits(entries) {
    if (!entries.length) return;
    // A probe shows no candidate, so a ViewThatFits in a candidate of another is probed after it.
    const top = entries.filter(entry => !entries.some(other => other !== entry && other.fit.contains(entry.fit)));
    if (top.length < entries.length) { this.probeFits(top); this.probeFits(entries.filter(entry => !top.includes(entry))); return; }
    // The stack a fit shares along is proposed as much as it is offered, so it takes all that: a stack that hugs its content
    // would give the fit nothing to share.
    const saved = entries.flatMap(({ fit }) => [[fit, fit.getAttribute('style')], [fit.parentElement, fit.parentElement.getAttribute('style')]]);
    const offsets = scrollOffsets(entries.map(({ fit }) => fit));
    for (const { fit, node, probe } of entries) {
      fit.setAttribute('data-fit-probe', '');
      let style = '', stack = '';
      for (const a of probe) {
        const [W, MIN, MAX] = a === 'x' ? ['width', 'min-width', 'max-width'] : ['height', 'min-height', 'max-height'];
        const main = (node.parentKind === 'hstack' && a === 'x') || (node.parentKind === 'vstack' && a === 'y');
        const take = `;${W}:100000px !important;${MIN}:0 !important;${MAX}:100% !important`;
        style += main ? `;flex:${weight(node.priority)} 1 0% !important;${W}:auto !important;${MIN}:0 !important;${MAX}:none !important` : take;
        if (main) stack += take;
      }
      fit.style.cssText += style;
      if (stack) fit.parentElement.style.cssText += stack;
    }
    for (const entry of entries) {
      const r = entry.fit.getBoundingClientRect();
      for (const a of entry.probe) entry.offered[a] = a === 'x' ? r.width : r.height;
    }
    for (const [element, style] of saved.reverse()) {
      element.removeAttribute('data-fit-probe');
      if (style == null) element.removeAttribute('style'); else element.setAttribute('style', style);
    }
    restoreScrollOffsets(offsets);
  }
  /** Tells Swift what it needs to place the subviews of each user-defined Layout, which only the page's layout knows (`layoutproposal`,
   * `layoutsizes`): the proposal the Layout is offered, read as `probeFits` reads a ViewThatFits's (the wrapper laid out once as a view
   * that takes all it is given, on the axes that have a proposal: `prop`, so none on an axis a view above asks for an ideal size along,
   * as a hugging Grid row does, where the Layout answers with the size it wants), and the size each subview took at the proposal it was placed
   * with (a subview is a root proposed that, see `rootPlacement`; the Layout is told once all of them are). Swift places the
   * subviews again and the sizes follow the new proposals; nothing here reads what Swift wrote for the Layout's own size. */
  reportLayouts() {
    const { onProposal, onLayoutSizes } = this.options, round = v => Math.round(v * 64) / 64, live = [];
    // A subtree that was detached while Swift changed what it reads (the sizes, the proposals) was not noted: analyse it again.
    let stale = false;
    for (const box of this.layouts) {
      if (!box.isConnected) { this.layouts.delete(box); continue; }
      for (const e of [box, ...box.children]) {
        const held = this.cache.get(e), island = held?.read !== undefined && this.islandOf(e);
        if (island && held.read !== layoutRead(e)) { this.mark(e, island); this.pending.add(island); stale = true; }
      }
    }
    if (stale) this.style();
    for (const box of this.layouts) {
      const node = this.cache.get(box);
      if (!node?.layout || !node.prop || !this.islandOf(box) || !box.getClientRects().length) continue;
      live.push({ fit: box, node, probe: ['x', 'y'].filter(a => node.prop[a]), offered: { x: Infinity, y: Infinity } });
    }
    const probing = live.filter(entry => entry.probe.length);
    // A view that is offered a size and takes less (a stack, a padding, the root) passes it on to its child, which the browser
    // gives no percentage of unless the view's own size is definite: while a Layout is probed, such a view takes its offer.
    const raised = new Map();
    for (const { fit, probe } of probing) {
      for (let e = fit.parentElement, node; e && (node = this.cache.get(e)); e = this.islands.has(e) ? null : e.parentElement) {
        const root = this.roots.get(e), proposed = root?.item ? childProposal(e) : null;
        for (const a of probe) {
          // (A size that follows from a rigid Layout below is not an offer; an aspect ratio gives its height from its width.)
          const s = node.axis?.[a], framed = node.kind === 'frame' && node.attr(a === 'x' ? 'data-frame-w' : 'data-frame-h') != null;
          if (framed || node.kind === 'aspect' || (s?.fill && node.def?.[a])) continue;
          if (!raised.has(e)) raised.set(e, e.getAttribute('style'));
          // The root takes its container's length (the window: `100dvh`), a subview of a Layout the proposal it was placed with.
          e.style.setProperty(a === 'x' ? 'width' : 'height', proposed ? px(proposed[a === 'x' ? 0 : 1] ?? 0) : a === 'y' && root && root.height !== 'cell' ? root.height : '100%', 'important');
        }
      }
    }
    // The wrapper holds nothing in the flow, so as a view that takes what it is given it contributes nothing to what holds it: its
    // share of the stack along the stack's axis, the whole cell or track elsewhere.
    const saved = probing.map(({ fit }) => [fit, fit.getAttribute('style')]);
    for (const { fit, node, probe } of probing) {
      for (const a of probe) {
        const [W, MIN, MAX] = a === 'x' ? ['width', 'min-width', 'max-width'] : ['height', 'min-height', 'max-height'];
        const main = (node.parentKind === 'hstack' && a === 'x') || (node.parentKind === 'vstack' && a === 'y');
        fit.style.cssText += `;${main ? `flex:${weight(node.priority)} 1 0% !important` : 'align-self:stretch !important;justify-self:stretch !important'};${W}:auto !important;${MIN}:0 !important;${MAX}:none !important`;
      }
    }
    for (const entry of probing) { const r = entry.fit.getBoundingClientRect(); for (const a of entry.probe) entry.offered[a] = a === 'x' ? r.width : r.height; }
    for (const [fit, style] of saved) { if (style == null) fit.removeAttribute('style'); else fit.setAttribute('style', style); }
    for (const [e, style] of raised) { if (style == null) e.removeAttribute('style'); else e.setAttribute('style', style); }
    for (const { fit, offered } of live) onProposal?.(fit, offered.x === Infinity ? null : round(offered.x), offered.y === Infinity ? null : round(offered.y));
    for (const box of this.layouts) {
      const items = [...box.children].filter(child => child.hasAttribute('data-layout-child-proposal'));
      if (!items.length || !onLayoutSizes || !items.every(child => this.roots.has(child)) || !box.getClientRects().length) continue;
      onLayoutSizes(box, [...box.children].map(child => {
        if (!items.includes(child)) return '';
        const r = child.getBoundingClientRect();
        return child.getAttribute('data-layout-child-proposal') + ':' + round(r.width) + ',' + round(r.height);
      }).join(';'));
    }
  }
  /** Writes the length of each container a `containerRelativeFrame` below reads (`--sl-cw`, `--sl-ch`) as a container-size query takes it: a container's proposal on an axis where it has one (it fills it, so its box says it),
   * else the outer container's (the variable is inherited from there). A semantic root's is what it is proposed: the
   * window (its container's width and `100dvh`), a slot's width, a presentation's content box. Read all, then written,
   * at each pass. */
  updateContainers() {
    const writes = [];
    for (const e of this.containers) {
      const node = this.cache.get(e);
      if (!e.isConnected || !node?.relativeBelow || !this.islandOf(e)) { this.containers.delete(e); e.style.removeProperty('--sl-cw'); e.style.removeProperty('--sl-ch'); continue; }
      if (!node.def) continue;
      const root = CONTAINERS.has(node.kind) ? null : this.roots.get(e);
      let w = null, h = null;
      if (root?.item) {
        const [pw, ph] = childProposal(e);
        if (pw != null) w = px(pw);
        if (ph != null) h = px(ph);
      } else if (root) {
        const box = e.parentElement, cs = this.document.defaultView.getComputedStyle(box);
        const inner = (size, a, b) => size - (parseFloat(cs[a]) || 0) - (parseFloat(cs[b]) || 0);
        if (root.def.x) w = px(inner(box.clientWidth, 'paddingLeft', 'paddingRight'));
        if (root.def.y) h = root.height === 'cell' ? px(inner(box.clientHeight, 'paddingTop', 'paddingBottom')) : root.height;
      } else {
        const r = e.getBoundingClientRect();
        if (node.def.x) w = px(r.width);
        if (node.def.y) h = px(r.height);
      }
      writes.push([e, w, h]);
    }
    for (const [e, w, h] of writes) for (const [name, value] of [['--sl-cw', w], ['--sl-ch', h]]) {
      if (value == null) { if (e.style.getPropertyValue(name)) e.style.removeProperty(name); }
      else if (e.style.getPropertyValue(name) !== value) e.style.setProperty(name, value);
    }
  }
  /** The ideal size of each candidate of `entry` (SwiftUI's: proposed nothing on the axes the ViewThatFits chooses along, its
   * proposal on the other): each shown out of the flow, all in one layout, then put back. Kept per candidate with the
   * width it was measured at. */
  measureIdeals({ candidates, along, offered }) {
    const width = along.x || offered.x === Infinity ? 'max-content' : px(offered.x);
    const unmeasured = candidates.filter(c => this.ideals.get(c)?.width !== width);
    if (!unmeasured.length) return;
    // A ViewThatFits inside a candidate is proposed nothing on the axes it chooses along too: it shows its first candidate.
    const inner = [];
    for (const f of this.fits) {
      const axes = this.cache.get(f)?.fit;
      if (!unmeasured.some(c => c !== f && c.contains(f)) || (axes !== 'vertical' && !along.x) || (axes !== 'horizontal' && !along.y)) continue;
      [...f.children].filter(child => child.classList.contains('view-that-fits-candidate')).forEach((child, i) => {
        inner.push([child, child.getAttribute('data-fit-selected')]);
        if (i) child.removeAttribute('data-fit-selected'); else child.setAttribute('data-fit-selected', 'true');
      });
    }
    const saved = unmeasured.map(c => [c, c.getAttribute('data-fit-selected'), c.getAttribute('style')]);
    const offsets = scrollOffsets(unmeasured);
    for (const c of unmeasured) {
      c.setAttribute('data-fit-selected', 'true');
      c.style.cssText += ';position:absolute !important;visibility:hidden !important;inset:0 auto auto 0 !important;' +
        `width:${width} !important;min-width:0 !important;max-width:none !important;height:auto !important;min-height:0 !important;` +
        'max-height:none !important;flex:none !important;margin:0 !important';
    }
    for (const c of unmeasured) { const r = c.getBoundingClientRect(); this.ideals.set(c, { width, w: r.width, h: r.height }); }
    for (const [c, selected] of inner) if (selected == null) c.removeAttribute('data-fit-selected'); else c.setAttribute('data-fit-selected', selected);
    for (const [c, selected, style] of saved) {
      if (selected == null) c.removeAttribute('data-fit-selected'); else c.setAttribute('data-fit-selected', selected);
      if (style == null) c.removeAttribute('style'); else c.setAttribute('style', style);
    }
    restoreScrollOffsets(offsets);
  }
  /** Equivalence check (`window.__layoutVerify`): every element of `island` must carry the block an analysis from scratch
   * gives it. */
  verify(island) {
    if (!island.isConnected || !this.islands.has(island)) return;
    const fresh = new CssLayout(this.document, { ...this.options, detached: true });
    fresh.islands.add(island);
    if (this.roots.has(island)) fresh.roots.set(island, this.roots.get(island));
    if (!fresh.claim(island)) { this.mismatch({ what: 'css island', note: 'refused from scratch' }); return; }
    fresh.assign(island, (element, block, lengths) => {
      const id = Number(element.getAttribute('data-cl'));
      if (this.blocks[id] !== block) this.mismatch({ what: 'css block', element: element.localName + '.' + String(element.className).split(' ')[0], incremental: this.blocks[id] ?? null, fresh: block });
      else if (!holdsLengths(element, lengths, '--cl-len')) this.mismatch({ what: 'css lengths', element: element.localName + '.' + String(element.className).split(' ')[0], fresh: lengths });
    });
  }
  mismatch(entry) {
    const window = this.document.defaultView;
    (window.__layoutMismatch ||= []).push(entry);
    console.error('[SwiftUIWeb] incremental layout css diverged', JSON.stringify(entry).slice(0, 400));
  }
  /** Analyses the subtree under `root` and returns its node. A node's children are analysed before it (as a recursion
   * would), with an explicit stack instead: the DOM can be deeper than the JS call stack. */
  analyse(root, rootParent) {
    const stack = [];
    let finished = this.open(root, rootParent, stack);
    while (stack.length) {
      const f = stack[stack.length - 1], { element, node, kind } = f;
      // A child that is done (cached, or just closed) joins its parent, in the order its siblings come.
      if (finished) {
        // The candidates a ViewThatFits does not show keep their blocks, ready to be shown.
        if (f.spare) node.spare.push(finished); else node.kids.push(finished);
        if (!finished.supported) node.supported = false;
        finished = null;
      }
      let opened = false;
      while (f.container && f.i < element.children.length) {
        const child = element.children[f.i++];
        // A collapsed rail hides parts of a slot's content with the stylesheet (`.hstack > :not(:first-child)`, which an
        // element's own inline `display` overrides): there, as the host does, what the browser does not display takes no
        // part. A child that took part carries a block, whose `display` keeps it displayed, as the host's description does.
        const railHidden = this.rail && !child.hasAttribute('data-cl') && this.document.defaultView.getComputedStyle(child).display === 'none';
        // The host hides the candidates of a ViewThatFits it lays out (`data-layout-hidden`); the mapper shows and hides them.
        const candidate = node.fit && child.classList.contains('view-that-fits-candidate');
        if ((candidate || takesPart(child)) && !railHidden && (kind !== 'tabview' || child.classList.contains('tab-body')) && !(kind === 'navstack' && child.classList.contains('navigation-root') && pushedStack(element))) {
          f.spare = !!candidate && child !== node.selected;
          finished = this.open(child, node, stack);
          opened = true;
          break;
        } else if (child.hasAttribute('data-cl') && !child.matches(HIDDEN) && !(kind === 'navstack' && isToolbarChrome(child))) this.strip(child);
      }
      if (!opened) { stack.pop(); finished = this.close(f); }
    }
    return finished;
  }
  /** The first half of `analyse` for `element` under `parent`: its cached node when nothing changed (returned), else a frame
   * for its children pushed on `stack` (null). */
  open(element, parent, stack) {
    const cached = this.cache.get(element);
    // A Divider runs along the stack around it (see `RUNS_THROUGH`), which can change without the Divider changing.
    if (cached && !this.dirty.has(element) && cached.runsVertical === runsVertical(cached.kind, parent) && (!cached.divider || cached.vertical === !!parent?.runsVertical)) return cached;
    this.stats.analysed++;
    const found = kindOf(element);
    // A ViewThatFits lays out the candidate it selected as a ZStack of one view does (SwiftUI's ViewThatFits: as large as
    // it, at its origin); the page selects it (`chooseFits`). One with no candidate is a ZStack of nothing, as large as nothing.
    // A `containerRelativeFrame` is a frame whose size on the axes it selects is a function of its container's length.
    const kind = found === 'fit' ? 'zstack' : found === 'container-relative' ? 'frame' : found;
    const a = name => element.getAttribute(name);
    const node = { element, kind, kids: [], attr: a, supported: true };
    // A Divider (an `hr`) is a line across the stack it is in: SwiftUI runs it vertically in an HStack and horizontally anywhere
    // else, and a frame, a padding, a fixedSize or an overlay or background around it leave the stack's say to it.
    node.runsVertical = runsVertical(kind, parent);
    if (kind === 'intrinsic' && element.localName === 'hr') { node.divider = true; node.vertical = !!parent?.runsVertical; }
    if (found === 'container-relative') {
      node.relative = { x: relativeLength(a('data-relative-w'), '--sl-cw'), y: relativeLength(a('data-relative-h'), '--sl-ch') };
    }
    if (element.hasAttribute('data-layout-child-proposal')) node.read = layoutRead(element);
    if (found === 'fit') { node.fit = a('data-view-that-fits') || 'both'; node.spare = []; }
    // A user-defined Layout is a box of the size Swift gave it (a 'size' leaf) whose subviews are roots of their own (`rootPlacement`),
    // as are the panes of a split view (the content of each `split-item`).
    if (found === 'size' && element.classList.contains('layout-box')) { node.layout = true; node.read = layoutRead(element); this.layouts.add(element); }
    else if (element.classList.contains('layout-box') && element.hasAttribute('data-layout-proposal')) { node.supported = false; this.stats.unsupported.layout = (this.stats.unsupported.layout || 0) + 1; }
    if (!node.supported) this.stats.unsupported[kind] = (this.stats.unsupported[kind] || 0) + 1;
    const container = !['intrinsic', 'opaque', 'field', 'flexible', 'spacer', 'size'].includes(kind);
    // The bar's items: the ones with something to show share the bar row, the others are not shown (as the host does).
    if (kind === 'navstack') node.bar = [...element.children].filter(isToolbarChrome).map(item => ({ element: item, shown: item.textContent.trim() !== '' || !!item.querySelector('button,input,select,a,img,svg'), side: barSide(item) }));
    // A ViewThatFits shows the candidate marked selected, else its first (the host's marks may be left from a pass of its own).
    if (node.fit) node.selected = [...element.children].find(child => child.classList.contains('view-that-fits-candidate') && child.getAttribute('data-fit-selected') === 'true') ||
      [...element.children].find(child => child.classList.contains('view-that-fits-candidate'));
    stack.push({ element, parent, node, kind, container, i: 0, spare: false });
    return null;
  }
  /** The second half of `analyse`: the node of `f` once its children are attached. */
  close(f) {
    const { element, parent, node, kind } = f, a = node.attr;
    // Where it sits decides how `chooseFits` reads its proposal (along a stack's axis, a share of the stack).
    if (node.fit || node.layout) node.parentKind = parent?.kind ?? null;
    if (node.fit && node.supported) this.fits.add(element);
    // A container with a `containerRelativeFrame` below it (through other containers too: where one has no proposal on an
    // axis, the outer one's length is read).
    node.relativeBelow = !!node.relative || node.kids.some(kid => kid.relativeBelow) || !!node.spare?.some(kid => kid.relativeBelow);
    if (node.relativeBelow && (CONTAINERS.has(kind) || this.roots.has(element))) this.containers.add(element);
    // A single-child modifier that holds several views stacks them, as the host does in a vstack of its own (`@group`),
    // which its one grid cell does not express. A ScrollView that does (a List's rows) is a grid of one column whose
    // rows are its children (see `declarations`).
    if (GROUPING.has(kind) && node.kids.length > 1) { node.supported = false; this.stats.unsupported.group = (this.stats.unsupported.group || 0) + 1; }
    // A run of frame, padding and fixedSize modifiers shares one element: the layers inside its own are nodes without an
    // element, the innermost holding the element's children (see "A run of layout modifiers is one element" in
    // Documentation/Performance/PERFORMANCE_CONTRACTS.md). CSS has one box for them, so `chainPlan` folds the chain into it.
    const wrap = LAYER_KINDS.has(kind) ? a('data-layout-wrap') : null;
    node.layers = null;
    if (wrap) {
      node.layers = parseLayers(wrap).map(({ kind: layerKind, map }) => ({ element, kind: layerKind, virtual: true, kids: [], supported: true,
        attr: name => map.has(name.slice(5)) ? map.get(name.slice(5)) : null }));
      for (const layer of node.layers) { layer.ax = num(layer.attr('data-align-x'), .5); layer.ay = num(layer.attr('data-align-y'), .5); }
    }
    if (kind === 'grid') {
      node.tracks = (a('data-grid-tracks') || 'flexible:10').split('|').map(t => { const [type, min, max, spacing, tx, ty] = t.split(':'); return { type, min: num(min, 0), max: num(max, Infinity), spacing: num(spacing), ax: num(tx), ay: num(ty) }; });
      let cell = 0; for (const kid of node.kids) kid.cell = kid.element.hasAttribute('data-lazy-spacer') ? -1 : cell++;
    }
    if (kind === 'table') {
      const rows = node.kids.filter(kid => kid.kind === 'gridrow');
      // A cell covers `data-grid-cell-columns` columns (gridCellColumns); a column is aligned as the first cell that starts in
      // it and names an alignment says (gridColumnAlignment).
      node.colAlign = [];
      for (const row of rows) {
        let col = 0;
        for (const cell of row.kids) {
          cell.col = col; cell.span = Math.min(1000, Math.max(1, Math.floor(num(cell.element.getAttribute('data-grid-cell-columns'), 1)) || 1));
          const alignment = cell.element.getAttribute('data-grid-column-alignment');
          if (alignment && node.colAlign[col] == null) node.colAlign[col] = alignment;
          col += cell.span;
        }
        row.width = col;
      }
      node.cols = Math.max(0, ...rows.map(r => r.width));
      node.colFill = Array.from({ length: node.cols }, (_, i) => rows.some(r => r.kids.some(cell => cell.col === i && cell.span === 1 && cell.axis?.x?.fill && !cell.axis.x.soft)));
    }
    if (kind === 'gridrow') node.rowAy = num(a('data-row-align-y'));
    if (kind === 'table') node.tableAlign = [num(a('data-align-x'), .5), num(a('data-align-y'), .5)];
    node.ax = num(a('data-align-x'), .5); node.ay = num(a('data-align-y'), .5);
    if (kind === 'vstack') node.ax = num(a('data-align-x'), align(a('data-layout-alignment')));
    if (kind === 'hstack') node.ay = num(a('data-align-y'), align(a('data-layout-alignment')));
    node.baseline = kind === 'hstack' && this.options.baseline === true && a('data-align-y') == null && a('data-layout-alignment') === 'baseline';
    node.explicitPriority = element.hasAttribute('data-layout-priority'); node.priority = num(a('data-layout-priority'), 0);
    node.spacing = element.classList.contains('searchable') ? 0 : num(a('data-layout-gap'), 8);
    node.ctxKey = kind + '|' + node.kids.length + '|' + node.ax + '|' + node.ay + '|' + node.spacing + (node.baseline ? '|bl' : '') + (wrap ? '|L' + wrap : '') + (kind === 'grid' ? '|' + (a('data-grid-tracks') || '') : '') + (kind === 'table' ? '|' + node.cols + node.colFill.join('') : '') + (kind === 'gridrow' ? '|' + node.rowAy : '') + (kind === 'inset' ? '|' + (a('data-inset-edge') || 'bottom') : '') + (kind === 'navstack' ? '|' + node.bar.map(item => (item.shown ? item.side : '-')).join(',') + '|' + (element.getAttribute('data-navigation-title-display-mode') || '') : '');
    node.ctxKeyBase = node.ctxKey;
    if (kind === 'table') for (const row of node.kids) if (row.kind === 'gridrow') { row.tableAlign = node.tableAlign; row.colAlign = node.colAlign; row.ctxKey = row.ctxKeyBase + '|T' + node.tableAlign.join(',') + '|C' + row.kids.map(cell => cell.span + ':' + (cell.element.getAttribute('data-grid-cell-anchor') ?? '') + ':' + (cell.element.getAttribute('data-grid-unsized-axes') ?? '')).join(',') + '/' + node.colAlign.join(','); }
    // A canvas is its own frame boundary (the drawing surface is never wrapped), so its frame has no child element: as
    // the host's `@content`, what the frame holds is the drawing, a flexible leaf (the size only, it has no element).
    const held = kind === 'frame' && element.localName === 'canvas' && node.kids.length === 0 ? [CANVAS_DRAWING] : node.kids;
    if (node.layers) {
      // Sizes from the innermost layer out: each layer holds the next, the innermost the element's children.
      for (let i = node.layers.length - 1; i >= 0; i--) this.size(node.layers[i], i === node.layers.length - 1 ? held : [node.layers[i + 1]]);
      this.size(node, [node.layers[0]]);
      node.plan = this.chainPlan(node);
      if (!node.plan) { node.supported = false; this.stats.unsupported.chain = (this.stats.unsupported.chain || 0) + 1; }
    } else this.size(node, held);
    this.cache.set(element, node);
    this.dirty.delete(element);
    return node;
  }
  /** Per axis: how the node's size relates to the proposal. fixed (a number), min/max, fill (takes what it is offered),
   * rigid (does not give way below its ideal size). */
  size(n, kids = n.kids) {
    const e = n.element, a = n.attr || (name => e.getAttribute(name)), k = n.kind;
    // A canvas is its own frame boundary: the drawing surface is never wrapped, so a framed canvas has no child element.
    // The host (`describeFresh` in `layout-host.js`) gives it a flexible leaf, which takes the frame's proposal.
    if (k === 'frame' && framedCanvas(n)) kids = [{ kind: 'flexible', axis: { x: { fill: true }, y: { fill: true } } }];
    // `soft`: a fill that an HStack does not grow along its axis (the JS host finds such a view's width the same at a
    // zero and at an unlimited proposal, so it is not flexible there), as a List row's link that takes the row's width.
    const axis = { x: { fixed: null, min: null, max: null, fill: false, rigid: false, soft: false }, y: { fixed: null, min: null, max: null, fill: false, rigid: false, soft: false } };
    const any = (ax, f) => kids.some(kid => kid.axis[ax][f]);
    const all = (ax, f) => kids.every(kid => kid.axis[ax][f]);
    const primary = k === 'overlay' ? kids[0] : k === 'background' ? kids[kids.length - 1] : null;
    const through = ax => {
      const s = axis[ax];
      if (k === 'overlay' || k === 'background') { const p = primary?.axis[ax]; if (p) { s.fill = p.fill; s.rigid = p.rigid; s.fixed = p.fixed; s.soft = p.soft; } return; }
      if (k === 'hstack' || k === 'vstack') {
        // A Spacer is flexible along its stack's axis only.
        const main = (k === 'hstack') === (ax === 'x');
        // An aspect box among siblings is offered at most its ideal size, so it does not make the stack flexible.
        // A soft fill does not grow the stack along its axis.
        const filling = kids.filter(kid => kid.axis[ax].fill && (main || kid.kind !== 'spacer') && !(main && (kid.axis[ax].capIdeal != null || kid.axis[ax].capContent) && kids.length > 1) && !(main && kid.axis[ax].soft));
        s.fill = filling.length > 0; s.soft = s.fill && filling.every(kid => kid.axis[ax].soft); s.rigid = kids.length > 0 && all(ax, 'rigid') && !s.fill; return;
      }
      s.fill = any(ax, 'fill'); s.soft = s.fill && kids.every(kid => !kid.axis[ax].fill || kid.axis[ax].soft); s.rigid = kids.length > 0 && all(ax, 'rigid');
    };
    switch (k) {
      case 'intrinsic': {
        const text = a('data-layout-leaf') === 'text' || e.classList.contains('rich-text-run');
        axis.x.rigid = !text; axis.y.rigid = true;
        // A Divider is a point thick (the stylesheet's border) and as long as the stack it is in: it takes the whole length across it.
        if (n.divider) { const [along, across] = n.vertical ? ['y', 'x'] : ['x', 'y']; Object.assign(axis[along], { fill: true, rigid: false }); Object.assign(axis[across], { fixed: 1, rigid: true }); }
        break;
      }
      case 'opaque': {
        const t = e.localName === 'textarea' || (e.localName === 'input' && ['text', 'search', 'email', 'password', 'url', 'tel', 'number', ''].includes(e.type || ''));
        // The JS host measures a composite leaf (a List row's link, a list, a table, a segmented picker) at the
        // finite width it is offered, so it takes that width; a native control and a span (measured as text) keep their
        // ideal width.
        // A `Link` (`a.anchor-link`, inline) is measured as its text: as wide as its label, which wraps where it must.
        const link = e.classList.contains('anchor-link');
        const composite = (!['button', 'input', 'textarea', 'select', 'label', 'details', 'span'].includes(e.localName) && !link) || e.classList.contains('picker-control') || e.classList.contains('disclosure-group');
        // The JS host measures a native leaf at the width it is offered: a button whose label is text gets narrower
        // (the label truncates) instead of holding its ideal width.
        const label = (e.localName === 'button' || link) && (e.textContent || '').trim() !== '';
        // A menu Picker shrinks to its arrows in a row too narrow for it (Apple's x-picker-row-tight), as the host measures it.
        const menu = e.localName === 'select';
        // It is a soft fill: along an HStack it keeps its ideal width, as it does offered no width at all.
        axis.x.fill = t || composite; axis.x.soft = composite && !t; axis.x.rigid = !t && !label && !menu; axis.y.rigid = true;
        // A TextEditor is flexible both ways: it takes the height of its frame, where it holds its text when the frame is smaller.
        if (e.localName === 'textarea') { axis.y.fill = true; axis.y.rigid = false; }
        break;
      }
      case 'field': {
        axis.x.fill = true; axis.y.rigid = true;
        // The browser gives a progress bar no height of its own: it is as tall as its track.
        if (e.localName === 'progress') axis.y.fixed = PROGRESS_TRACK;
        break;
      }
      case 'flexible': axis.x.fill = axis.y.fill = true; break;
      case 'spacer': axis.x.fill = axis.y.fill = true; axis.x.min = axis.y.min = num(a('data-spacer-min'), 8); break;
      case 'size': axis.x.fixed = num(a('data-size-w') ?? a('data-layout-content-width'), 0); axis.y.fixed = num(a('data-size-h') ?? a('data-layout-content-height'), 0); axis.x.rigid = axis.y.rigid = true; break;
      case 'geometry': case 'panel': case 'navstack': axis.x.fill = axis.y.fill = true; break;
      // A ScrollView: along an axis it scrolls it takes its proposal; across, it is as large as its content (which it
      // holds at its origin), and its parent places it.
      case 'scroll': {
        const c = e.classList, h = c.contains('scroll-horizontal') || c.contains('scroll-both'), v = c.contains('scroll-vertical') || c.contains('scroll-both') || !h;
        through('x'); through('y');
        for (const [on, s] of [[h, axis.x], [v, axis.y]]) if (on) Object.assign(s, { fill: true, soft: false, rigid: false });
        break;
      }
      // A LabeledContent row (a labeled row) is as wide as it is offered, its ideal width offered nothing; as tall as
      // its taller cell. Among a stack's views the stack offers it at most its ideal width, its answer to an unlimited
      // proposal (`capContent`).
      case 'labeledrow': axis.x.fill = true; axis.x.capContent = true; axis.y.rigid = true; break;
      // `.position(x:y:)` takes its proposal (10 pt where there is none). Among a stack's views, the stack offers it at most
      // what it answers an unlimited proposal: those 10 pt.
      case 'position': axis.x.fill = axis.y.fill = true; axis.x.capIdeal = axis.y.capIdeal = 10; break;
      // A grid: the tracks take what is proposed across them (a LazyVGrid's columns share its width, a LazyHGrid's rows
      // its height), and the grid is as long as its cells along the other axis.
      case 'grid': axis[e.classList.contains('hgrid') ? 'y' : 'x'].fill = true; break;
      case 'table': {
        axis.x.fill = (n.colFill || []).some(Boolean) || kids.some(kid => kid.kind !== 'gridrow' && kid.axis.x.fill && !kid.axis.x.soft);
        break;
      }
      case 'gridrow': through('x'); through('y'); break;
      case 'inset': {
        if (kids.length < 2) { through('x'); through('y'); break; }
        // A safe-area inset: the content takes what the inset leaves along its edge; across it, the larger of the two.
        const main = insetEdge(n).vertical ? 'y' : 'x', cross = main === 'y' ? 'x' : 'y', [body, inset] = kids;
        axis[main].fill = body.axis[main].fill; axis[main].soft = body.axis[main].fill && body.axis[main].soft;
        axis[main].rigid = body.axis[main].rigid && inset.axis[main].rigid;
        axis[cross].fill = body.axis[cross].fill || inset.axis[cross].fill;
        axis[cross].soft = axis[cross].fill && kids.every(kid => !kid.axis[cross].fill || kid.axis[cross].soft);
        axis[cross].rigid = body.axis[cross].rigid && inset.axis[cross].rigid;
        break;
      }
      case 'aspect': {
        // The aspect box takes the offered width (and the height its ratio gives); an unspecified width is the content's ideal.
        // In a stack's main axis the stack caps the offer at the response to an unbounded proposal, which is that ideal.
        axis.x.fill = true; axis.y.fill = false; axis.y.rigid = false;
        const only = kids[0]; if (only && only.axis.x.fixed != null) axis.x.capIdeal = only.axis.x.fixed;
        break;
      }
      case 'padding': through('x'); through('y'); break;
      case 'fixed': {
        through('x'); through('y');
        if (a('data-fixed-x') !== 'false') { axis.x.fill = axis.x.soft = false; axis.x.rigid = true; axis.x.ideal = true; }
        if (a('data-fixed-y') !== 'false') { axis.y.fill = axis.y.soft = false; axis.y.rigid = true; axis.y.ideal = true; }
        break;
      }
      case 'frame': {
        through('x'); through('y');
        for (const [ax, w, mn, mx] of [['x', 'w', 'min-w', 'max-w'], ['y', 'h', 'min-h', 'max-h']]) {
          const s = axis[ax], fixed = num(a('data-frame-' + w)), min = num(a('data-frame-' + mn)), max = num(a('data-frame-' + mx));
          if (fixed != null) { s.fixed = fixed; s.fill = s.soft = false; s.rigid = true; }
          else {
            s.min = min; s.max = max;
            // maxWidth: .infinity takes whatever it is offered; a finite maximum takes min(offered, max) whatever its content is.
            if (max === Infinity) { s.fill = true; s.soft = false; s.rigid = false; }
            else if (max != null) { s.fill = s.soft = false; s.rigid = false; s.cap = max; }
            else if (min != null) s.rigid = false;
          }
        }
        break;
      }
      default: through('x'); through('y'); // vstack hstack zstack overlay background
    }
    // A `containerRelativeFrame` is as large as its function of the container on the axes it selects.
    if (n.relative) for (const ax of ['x', 'y']) if (n.relative[ax] != null) Object.assign(axis[ax], { fixed: n.relative[ax], min: null, max: null, cap: null, fill: false, soft: false, rigid: true });
    n.axis = axis;
  }
  /** How the layers of an element fit its one CSS box, per axis: the padding between the box and a one-cell grid track, the
   * track's size, its alignment in the box (`content`), the alignment of the children in the track (`item`) and a padding
   * inside the innermost frame, which is the margin of the one child (`margin`). The element's own frame is the box;
   * paddings right inside it are its padding; the frames inside those make the track:
   * - a frame with no size on an axis takes its child's size there, so with one child it does nothing on that axis; with
   *   several (the innermost layer holds the element's children) it is the group they are arranged in: the track hugs them
   *   and its alignment arranges them;
   * - a `maxWidth: .infinity` frame fills what holds it, so the box inside it is aligned by it, and so is a child inside it;
   * - a fixed, a min/max or a fixedSize box is the track.
   * `null` when one box cannot do it: two boxes inside the paddings, a frame inside an inner padding, an inner padding
   * around several children, or a min/max frame nothing fills. */
  chainPlan(n) {
    const pad = { top: 0, leading: 0, bottom: 0, trailing: 0 }, margin = { top: 0, leading: 0, bottom: 0, trailing: 0 };
    const add = (into, node) => { for (const edge of Object.keys(into)) into[edge] += num(node.attr('data-padding-' + edge), 0); };
    const sized = (node, ax) => ['w', 'min-w', 'max-w'].map(k => k.replace('w', ax === 'x' ? 'w' : 'h')).some(k => node.attr('data-frame-' + k) != null);
    const several = n.kids.length > 1, layers = n.layers, boxes = [];
    let innerPadding = false;
    if (n.kind === 'padding') add(pad, n);
    for (let j = 0; j < layers.length; j++) {
      const node = layers[j], last = j === layers.length - 1;
      if (node.kind === 'padding') { if (boxes.length) { add(margin, node); innerPadding = true; } else add(pad, node); continue; }
      if (innerPadding) return null;
      if (node.kind === 'frame' && !sized(node, 'x') && !sized(node, 'y') && !(last && several)) continue;
      boxes.push(node);
    }
    if (innerPadding && several) return null;
    const innermost = layers[layers.length - 1];
    // A negative padding makes what it holds larger than its box: CSS has no negative padding, so it is a negative margin
    // of the children (each fills the one cell, so a group grows the same way).
    for (const edge of Object.keys(pad)) if (pad[edge] < 0) { margin[edge] += pad[edge]; pad[edge] = 0; }
    const plan = { pad, margin };
    for (const [ax, W, MIN, MAX, al] of [['x', 'w', 'min-w', 'max-w', 'ax'], ['y', 'h', 'min-h', 'max-h', 'ay']]) {
      const outer = n.kind === 'frame' ? n[al] : .5, entries = [];
      for (const node of boxes) {
        if (node.kind === 'fixed') { if (node.attr('data-fixed-' + ax) !== 'false') entries.push({ type: 'fit', align: .5 }); continue; }
        const fixed = num(node.attr('data-frame-' + W)), min = num(node.attr('data-frame-' + MIN)), max = num(node.attr('data-frame-' + MAX));
        if (fixed != null) entries.push({ type: 'fixed', size: fixed, align: node[al] });
        else if (max === Infinity) entries.push({ type: 'fill', min, align: node[al] });
        else if (min != null || max != null) entries.push({ type: 'range', min, max, align: node[al] });
        else if (node === innermost && several) entries.push({ type: 'group', align: node[al] });
      }
      // Several children inside an innermost padding are a group too, arranged at the centre.
      if (several && innermost.kind === 'padding' && !entries.some(entry => entry.type !== 'fill')) entries.push({ type: 'group', align: .5 });
      // A frame with a minimum and no maximum around a box is as large as the box and at least its minimum (the frame's response): like a filling frame with a minimum, it keeps the element at least that large and aligns the box.
      const floor = (entry, j) => entry.type === 'range' && entry.max == null && entries.slice(j + 1).some(inner => inner.type !== 'fill');
      const boxed = entries.flatMap((entry, j) => entry.type === 'fill' || floor(entry, j) ? [] : [j]);
      if (boxed.length > 1) return null;
      let track = 'minmax(0,1fr)', content = outer, item = outer, least = 0, range = null, fit = entries.some(entry => entry.type === 'fit');
      if (boxed.length === 0) {
        if (entries.length) {
          item = entries[entries.length - 1].align;
          const min = Math.max(0, ...entries.map(entry => entry.min ?? 0));
          // A flexible track is not aligned when its minimum overflows the box, where SwiftUI centres the frame.
          const fixed = n.axis[ax].fixed, inset = ax === 'x' ? pad.leading + pad.trailing : pad.top + pad.bottom;
          if (min && fixed != null && min + inset > fixed) return null;
          if (min) track = `minmax(${vpx(min)},1fr)`;
        }
      } else {
        const k = boxed[0], box = entries[k], after = entries.slice(k + 1);
        if (k > 0) content = entries[k - 1].align;
        // A filling frame or a floor with a minimum around the box keeps the element at least that large (plus its padding).
        least = Math.max(0, ...entries.slice(0, k).map(entry => entry.min ?? 0));
        item = after.length ? after[after.length - 1].align : box.align;
        if (box.type === 'fixed') track = vpx(box.size);
        else if (box.type === 'fit') track = 'max-content';
        else if (box.type === 'group') track = n.kids.some(kid => kid.axis[ax].fill) ? 'minmax(0,1fr)' : 'fit-content(100%)';
        // A min/max frame offered a size takes it, clamped to its range, whatever it holds; offered none it takes what it
        // holds, clamped (`declarations` picks one by the proposal).
        else range = { min: box.min ?? 0, max: box.max != null && box.max !== Infinity ? box.max : null, filled: after.length > 0 };
      }
      plan[ax] = { track, content, item, range, fit, least: least ? least + (ax === 'x' ? pad.leading + pad.trailing : pad.top + pad.bottom) : 0 };
    }
    return plan;
  }
  /** The declaration block of `n` as a child of `parent` ('cell' context: a one-cell grid; 'row'/'column': a stack). */
  declarations(n, parent) {
    const e = n.element, k = n.kind, d = [];
    const push = (p, v) => d.push(p + ':' + v);
    const ctx = !parent ? 'root' : parent.kind === 'hstack' ? 'row' : parent.kind === 'vstack' ? 'column' : 'cell';
    // Own display.
    // A root Swift styled (`verifySwift`) is not one: it is sized like any root (`rootPlacement`), not placed by the host.
    if (ctx === 'root' && k === 'scroll' && this.islands.has(e) && e !== this.swiftRoot) {
      // The island root: the host places it (it is a flexible leaf); CSS lays out what is inside.
      push('display', 'grid'); push('grid-template-columns', 'minmax(0,1fr)'); push('grid-template-rows', 'auto'); push('align-content', 'start'); push('padding', '0');
      return d;
    }
    const stack = k === 'hstack' || k === 'vstack';
    if (stack) { push('display', 'flex'); push('flex-direction', k === 'hstack' ? 'row' : 'column'); push('gap', px(n.spacing)); push('align-items', 'flex-start'); push('justify-content', 'flex-start'); }
    else if (n.plan) {
      // `unsafe`: a track larger than the box overflows it on both sides, as SwiftUI centres a child larger than its frame.
      const GRID = ['start', 'unsafe center', 'unsafe end'];
      const track = ax => {
        const { range, fit } = n.plan[ax];
        if (!range) return n.plan[ax].track;
        const offered = n.def[ax] && !fit && !(k === 'fixed' && n.axis[ax].ideal);
        if (offered) return `minmax(${vpx(range.min)},${range.max != null ? vpx(range.max) : '1fr'})`;
        // Offered nothing, a frame with a minimum is as large as what it holds and at least its minimum, which it offers
        // what it holds: one track that a filling child stretches over.
        return range.max != null ? `fit-content(${vpx(range.max)})` : range.min > 0 ? `minmax(${vpx(range.min)},auto)` : 'auto';
      };
      push('display', 'grid'); push('grid-template-columns', track('x')); push('grid-template-rows', track('y'));
      push('justify-content', GRID[side(n.plan.x.content)]); push('align-content', GRID[side(n.plan.y.content)]);
    }
    else if (k === 'navstack') {
      // Row 1: the bar (the stylesheet's `::before` title, a grid item of its own, and the items); row 2: the screen; row 3,
      // when the stack has a bottom bar: that bar, which then reserves its own space instead of overlapping the screen.
      push('display', 'grid'); push('grid-template-columns', barColumns(n) ?? 'minmax(0,1fr)'); push('grid-template-rows', (n.def.y ? 'auto minmax(0,1fr)' : 'auto auto') + (n.kids.some(kid => isBottomBar(kid.element)) ? ' auto' : ''));
      // Items on one side are 8 px apart; principal items touch, as on the host.
      if (barColumns(n) && shownOn(n, 'center').length < 2) push('column-gap', '8px');
    }
    else if (k === 'labeledrow') {
      // SwiftUI's labeled row, an HStack of the label and the value: when the row is too narrow for both, each column is
      // offered an equal share up to its natural width, so a short label keeps its width and a long value wraps in the
      // rest (two `auto` tracks grow that way). With room to spare the label sits at the leading edge and the value at the
      // trailing one. The row's spacing and padding.
      push('display', 'grid'); push('grid-template-columns', 'auto auto'); push('justify-content', 'space-between'); push('grid-template-rows', 'auto');
      push('column-gap', px(n.spacing)); push('align-items', 'center');
    }
    else if (k === 'inset' && n.kids.length > 1) {
      // A track for the inset, as large as it is, and one for the content, which takes what is left when there is a
      // proposal along the edge; `spacing` between them.
      const { vertical, start } = insetEdge(n), body = (vertical ? n.def.y : n.def.x) ? 'minmax(0,1fr)' : 'auto';
      const tracks = start ? `auto ${body}` : `${body} auto`;
      push('display', 'grid');
      if (vertical) { push('grid-template-columns', 'minmax(0,1fr)'); push('grid-template-rows', tracks); push('row-gap', px(n.spacing)); }
      else { push('grid-template-columns', tracks); push('grid-template-rows', 'minmax(0,1fr)'); push('column-gap', px(n.spacing)); }
    }
    else if (['zstack', 'frame', 'padding', 'fixed', 'aspect', 'geometry', 'overlay', 'background', 'scroll', 'panel', 'tabview', 'inset'].includes(k)) {
      push('display', 'grid'); push('grid-template-columns', 'minmax(0,1fr)');
      // A ScrollView holding several views stacks them from the top, leading, with no spacing (the host's `@group`):
      // a row each, as tall as its view.
      if (k === 'scroll' && n.kids.length > 1) { push('grid-template-rows', 'none'); push('grid-auto-rows', 'max-content'); push('align-content', 'start'); }
      else push('grid-template-rows', 'minmax(0,1fr)');
      // A GeometryReader is as large as it is proposed (10 pt where it is proposed nothing), never as its content.
      if (k === 'zstack' || k === 'geometry') { if (k === 'geometry') { push('place-items', 'start'); push('contain', 'size'); } }
    } else if (k === 'grid') this.grid(n, push);
    else if (k === 'table') {
      // Without GridRows there are no columns: the children are stacked, each as wide as it wants.
      push('display', 'grid');
      push('grid-template-columns', n.cols ? Array.from({ length: n.cols }, (_, i) => n.colFill[i] ? 'minmax(max-content,1fr)' : 'minmax(0,max-content)').join(' ') : 'minmax(0,max-content)');
      push('column-gap', px(n.spacing)); push('row-gap', px(num(e.getAttribute('data-row-spacing'), 8))); push('align-content', 'start');
    } else if (k === 'gridrow') { push('display', 'contents'); return d; }
    // A text leaf keeps the display its Swift view gave it (`-webkit-box` clamps the lines of a `lineLimit`).
    else if (k === 'intrinsic') {
      if (!e.style.display && !this.roots.get(e)?.ideal) push('display', 'block');
      if (e.localName === 'select' || e.querySelector?.('select')) push('field-sizing', 'content');
      // A vertical Divider draws its line along its leading edge, the stylesheet's rule along the top of a horizontal one.
      if (n.divider && n.vertical) { push('border-top-width', '0'); push('border-left-width', '1px'); }
    }
    else if (k === 'spacer' || k === 'size') push('display', 'block');
    // A flexible leaf that holds elements keeps the stylesheet's display, which lays them out (NavigationSplitView's grid of
    // columns, whose content is laid out as semantic roots of their own).
    else if (k === 'flexible') { if (!e.children.length) push('display', 'block'); }
    else if (k === 'opaque' && (e.localName === 'select' || e.querySelector('select'))) push('field-sizing', 'content');
    // A Gauge's label is as wide as its text (the stylesheet's column would stretch it over the track); the track still takes the width.
    else if (k === 'field' && e.classList.contains('gauge-meter')) push('align-items', 'flex-start');
    if (k === 'tabview') {
      // The sidebar's width and the mobile bottom bar's height, as the stylesheet sets them for the layout and state.
      push('padding', '0 0 var(--tab-bottom-inset) 0'); push('padding-inline-start', 'var(--tab-sidebar-width)');
    } else if (n.plan) {
      const p = n.plan.pad;
      push('padding', `${px(p.top)} ${px(p.trailing)} ${px(p.bottom)} ${px(p.leading)}`);
    } else if (k === 'padding' || k === 'labeledrow') {
      const p = side => Math.max(0, num(e.getAttribute('data-padding-' + side), 0));
      push('padding', `${px(p('top'))} ${px(p('trailing'))} ${px(p('bottom'))} ${px(p('leading'))}`);
    // A leaf keeps the padding the stylesheet gives it (a native button's): it is part of the size the JS host measures.
    } else if (!LEAVES.has(k) && (k !== 'grid' || !n.extent[0] && !n.extent[1])) push('padding', '0');
    push('box-sizing', 'border-box');
    const m = parent?.margin;
    if (ctx !== 'root') { push('position', 'relative'); push('inset', 'auto'); push('margin', m ? `${px(m.top)} ${px(m.trailing)} ${px(m.bottom)} ${px(m.leading)}` : '0'); push('grid-area', parent?.kind === 'inset' && parent.kids.length > 1 ? insetArea(parent, n) : parent?.kind === 'navstack' ? (isBottomBar(n.element) ? '3 / 1 / 4 / -1' : barColumns(parent) ? '2 / 1 / 3 / -1' : '2 / 1') : ctx === 'cell' && !['grid', 'table', 'gridrow'].includes(parent.kind) && !stackedScroll(parent) ? '1 / 1' : 'auto'); }
    // Grid cell content of a one-cell grid container.
    if (ctx !== 'root') this.placement(n, parent, ctx, push, d);
    else if (this.roots.has(e)) this.rootPlacement(n, push);
    else for (const a of ['x', 'y']) if (n.axis[a].fixed != null) push(a === 'x' ? 'width' : 'height', vpx(n.axis[a].fixed));
    // SwiftUI's Text proposed exactly `.zero` is `.zero` (proposed any other size, it shows at least one line): the subview of a
    // user-defined Layout that proposes it nothing on both axes.
    if (parent && e.getAttribute('data-layout-leaf') === 'text' && this.roots.get(parent.element)?.item && childProposal(parent.element).every(v => v === 0)) {
      push('max-width', '0'); push('max-height', '0'); push('overflow', 'hidden');
    }
    if (n.plan) for (const [a, MIN] of [['x', 'min-width'], ['y', 'min-height']]) if (n.plan[a].least) push(MIN, vpx(n.plan[a].least));
    if (k === 'fixed') {
      if (n.axis.x.ideal) push('width', 'max-content');
      if (n.axis.y.ideal) push('height', 'max-content');
    }
    if (k === 'aspect' && n.def.x) {
      const r = num(e.getAttribute('data-aspect-ratio'));
      if (r) { push('aspect-ratio', String(r)); push('width', '100%'); push('height', 'auto'); if (n.cap != null) push('max-width', vpx(n.cap * r)); }
    }
    // A custom SF Symbol is an empty span whose size its Swift view authored (in em), as the host measures it.
    if (k === 'intrinsic' && e.classList.contains('custom-symbol')) for (const p of ['width', 'height']) { const v = e.style?.getPropertyValue?.(p); if (v) push(p, v); }
    return d;
  }
  grid(n, push) {
    const e = n.element, horizontal = e.classList.contains('hgrid'), tracks = n.tracks;
    const cols = tracks.map(t => t.type === 'fixed' ? px(t.min) : t.type === 'adaptive' ? null : `minmax(${px(t.min)},${t.max === Infinity ? '1fr' : px(t.max)})`);
    push('display', 'grid');
    // Along the grid (a LazyVGrid's rows, a LazyHGrid's columns) the cells are `data-row-spacing` apart.
    const rowGap = num(e.getAttribute('data-row-spacing'), n.spacing);
    const adaptive = tracks.find(t => t.type === 'adaptive');
    if (adaptive) push(horizontal ? 'grid-template-rows' : 'grid-template-columns', `repeat(auto-fill,minmax(${px(adaptive.min)},${adaptive.max === Infinity ? '1fr' : px(adaptive.max)}))`);
    else push(horizontal ? 'grid-template-rows' : 'grid-template-columns', cols.join(' '));
    push(horizontal ? 'grid-template-columns' : 'grid-template-rows', 'none');
    push('grid-auto-flow', horizontal ? 'column' : 'row');
    // The spacing after the first track is the gap between tracks (a per-track spacing is not expressible).
    push(horizontal ? 'row-gap' : 'column-gap', px(tracks[0]?.spacing ?? n.spacing)); push(horizontal ? 'column-gap' : 'row-gap', px(rowGap));
    push('justify-items', 'start'); push('align-items', 'start'); push('align-content', 'start');
    const extent = which => { const el = [...e.children].find(c => c.getAttribute('data-lazy-spacer') === which); return el ? num(el.getAttribute(horizontal ? 'data-size-w' : 'data-size-h'), 0) : 0; };
    n.extent = [extent('__lazy_before'), extent('__lazy_after')];
    if (n.extent[0] || n.extent[1]) push(horizontal ? 'padding' : 'padding', horizontal ? `0 ${vpx(n.extent[1])} 0 ${vpx(n.extent[0])}` : `${vpx(n.extent[0])} 0 ${vpx(n.extent[1])} 0`);
  }
  /** The height the frames and paddings around an aspect box propose to it, when they propose one (a frame with a fixed height, or a
   * finite maximum, which SwiftUI proposes to what it holds, so an `.aspectRatio(.fit)` in `.frame(maxHeight: 250)` is at most 250 tall
   * whatever width it is offered); null otherwise. The box is then at most that height times its ratio wide (`declarations`).
   * Only the modifiers that share the element with the box are read (`passHeight` of each, from the outermost in): a stack in
   * between would share the height among its views. */
  aspectCap(n, parent) {
    if (!parent || n.attr('data-aspect-fill') === 'true' || !num(n.attr('data-aspect-ratio'))) return null;
    const height = parent.heightOut;
    return height != null && height < Infinity ? Math.max(0, height) : null;
  }
  /** What the modifier `m` proposes to its child as a height, when `height` is proposed to it (null: it is not a modifier). */
  passHeight(m, height) {
    const at = name => num(m.attr(name));
    if (m.kind === 'frame') {
      const fixed = at('data-frame-h'), min = at('data-frame-min-h'), max = at('data-frame-max-h');
      if (fixed != null) return fixed;
      if (max != null) height = Math.min(height, max);
      return min != null ? Math.max(height, min) : height;
    }
    if (m.kind === 'padding') return height - (at('data-padding-top') ?? 0) - (at('data-padding-bottom') ?? 0);
    return m.kind === 'fixed' ? (m.attr('data-fixed-y') !== 'false' ? Infinity : height) : null;
  }
  /** Whether the proposal `n` is given is finite on each axis (SwiftUI proposes `nil` to a child along the scrolling axis
   * of a ScrollView, to the fixed axes of fixedSize, and to anything an unspecified proposal reached).
   * `strict`: the proposal a size is asked for (`sizeThatFits`), which `reportLayouts` hands to a user-defined Layout, where
   * the views `n.def` counts as proposed a size are laid out at a size they already have: a frame with a minimum passes
   * a missing proposal on (a GeometryReader in it is placed at the minimum, a Layout in it is asked with nothing), and a
   * Grid asks its cells with the proposal it has itself (a hugging Grid asks for their ideal size, then places them in the
   * row it found). */
  definite(n, parent, flag, strict = false) {
    if (!parent) { const root = this.roots.get(n.element); return root ? root.def : n.kind === 'scroll' ? { x: true, y: true } : { x: false, y: false }; }
    const p = strict ? parent.prop : parent.def, k = parent.kind;
    if (k === 'scroll') { const c = parent.element.classList; return { x: p.x && !(c.contains('scroll-horizontal') || c.contains('scroll-both')), y: p.y && !(c.contains('scroll-vertical') || c.contains('scroll-both')) }; }
    // A frame with a minimum proposes at least that minimum where it is proposed nothing (SwiftUI clamps the proposal
    // into its range): a GeometryReader in `.frame(minHeight: 300)` below a ScrollView is 300 tall.
    if (k === 'frame') return { x: parent.axis.x.fixed != null || (!strict && parent.axis.x.min > 0) || p.x, y: parent.axis.y.fixed != null || (!strict && parent.axis.y.min > 0) || p.y };
    // A Grid sizes its rows and columns from its cells, then proposes each cell its column's width and its row's height
    // (a cell that fills, as a card holding a chart, is as tall as its row).
    if (k === 'table' || k === 'gridrow') return strict ? { x: p.x, y: p.y } : { x: true, y: true };
    if (k === 'fixed') return { x: parent.axis.x.ideal ? false : p.x, y: parent.axis.y.ideal ? false : p.y };
    if (k === 'geometry' || k === 'size') return { x: true, y: true };
    if (k === 'labeledrow') return { x: true, y: false };
    // An inset is offered its ideal size along its edge; the content, what is left of the proposal.
    if (k === 'inset' && parent.kids.length > 1 && parent.kids[1] === n) return insetEdge(parent).vertical ? { x: p.x, y: false } : { x: false, y: p.y };
    if (k === 'aspect') return { x: p.x || p.y, y: p.x || p.y };
    if (k === 'grid') return { x: true, y: true };
    if ((k === 'overlay' && parent.kids[0] !== n) || (k === 'background' && parent.kids[parent.kids.length - 1] !== n)) return { x: true, y: true };
    return { x: p.x, y: p.y };
  }
  /** Sizing and alignment of `n` inside its parent. */
  placement(n, parent, ctx, push, d) {
    const k = n.kind, ax = n.axis, e = n.element;
    const ps = parent.kind;
    const stackMain = ctx === 'row' ? 'x' : ctx === 'column' ? 'y' : null;
    const W = { x: 'width', y: 'height' }, MIN = { x: 'min-width', y: 'min-height' }, MAX = { x: 'max-width', y: 'max-height' };
    const alignOf = a => a === 'baseline' ? 'baseline' : FLEX[side(a)];
    if (ps === 'table' && n.kind === 'gridrow') { push('display', 'contents'); return; }
    if (ps === 'position') { this.positioned(n, parent, push); return; }
    if (ps === 'labeledrow') {
      // A cell is as wide as its column and centred in the row.
      push('grid-area', `1 / ${parent.kids.indexOf(n) + 1}`); push('justify-self', 'stretch'); push('width', 'auto'); push('min-width', '0'); push('max-width', 'none');
      push('align-self', 'center'); push('height', 'auto'); push('min-height', '0'); push('max-height', 'none');
      return;
    }
    if (ps === 'table' || ps === 'gridrow') {
      const [tax, tay] = parent.tableAlign || [.5, .5];
      const ay = ps === 'gridrow' && parent.rowAy != null ? parent.rowAy : tay;
      const spanning = ps === 'table', rows = parent.cols > 0;
      // A GridRow's cell, with what the grid cell modifiers say: the columns it covers (gridCellColumns), where it sits in its
      // slot (gridCellAnchor, as the nearest of the three sides), the axes on which it takes the slot instead of sizing it
      // (gridCellUnsizedAxes) and its column's alignment (gridColumnAlignment; a cell that covers several columns has no one column).
      const cell = ps === 'gridrow';
      const anchor = cell ? (e.getAttribute('data-grid-cell-anchor') || '').split(',').map(Number) : [];
      const anchored = anchor.length === 2 && anchor.every(Number.isFinite);
      const unsized = cell ? num(e.getAttribute('data-grid-unsized-axes'), 0) : 0;
      const columnAlign = cell && n.span === 1 ? { 'flex-start': 0, center: .5, 'flex-end': 1 }[parent.colAlign?.[n.col]] : undefined;
      push('grid-column', spanning ? '1 / -1' : cell && n.span > 1 ? 'span ' + n.span : 'auto');
      // A view that spans the columns does not size them: it is as wide as the table (when there are columns).
      if (spanning && rows || unsized & 1) push('contain', 'inline-size');
      for (const [a, al, selfProp] of [['x', anchored ? anchor[0] : columnAlign ?? tax, 'justify-self'], ['y', anchored ? anchor[1] : ay, 'align-self']]) {
        const sp = { ...n.axis[a] };
        if (k === 'flexible' && !n.def[a]) sp.fixed = num(e.getAttribute('data-ideal-' + (a === 'x' ? 'w' : 'h')), 10);
        push(W[a], 'auto'); push(MAX[a], 'none'); push(MIN[a], '0');
        if (unsized & (a === 'x' ? 1 : 2)) { push(selfProp, 'stretch'); if (a === 'x') { if (k === 'flexible') push(W[a], '100%'); } else { push(W[a], '0'); push(MIN[a], '100%'); } }
        else if (sp.fixed != null) { push(W[a], vpx(sp.fixed)); push(selfProp, alignOf(al)); }
        else if (spanning && rows && a === 'x') { push(selfProp, 'stretch'); if (k === 'flexible') push(W[a], '100%'); }
        else if (sp.fill && (a === 'x' ? true : n.def.y)) { push(selfProp, 'stretch'); if (k === 'flexible') push(W[a], '100%'); }
        // An aligned view keeps to its column (`max-width: 100%`), except a table: its columns already shrink to what the cell
        // gives it, and a percentage of a column sized by its content made the browser lay a table nested in a table out again
        // at every level (Chromium took seconds at ten levels and never finished a hundred).
        else { push(selfProp, alignOf(al)); if (a === 'x' && k !== 'table') push(MAX[a], '100%'); }
      }
      return;
    }
    if (ps === 'grid') {
      if (n.cell < 0) {
        // Virtualisation extents sit around the grid's rows, not between them (no row gap): they are the grid's padding.
        // The spacer after the rows sits at their end, where the JS host puts it (the lazy collection reads it).
        const after = e.getAttribute('data-lazy-spacer') === '__lazy_after';
        push('position', 'absolute'); push('width', '0'); push('height', '0'); push('inset', after ? 'auto auto 0 0' : '0 auto auto 0');
        push('grid-column', '1 / -1'); push('width', n.axis.x.fixed != null ? vpx(n.axis.x.fixed) : 'auto'); push('height', n.axis.y.fixed != null ? vpx(n.axis.y.fixed) : 'auto'); return; }
      const t = parent.tracks[n.cell % parent.tracks.length];
      const ax = t.ax ?? parent.ax, ay = t.ay ?? parent.ay;
      for (const [a, al, selfProp] of [['x', ax, 'justify-self'], ['y', ay, 'align-self']]) {
        const sp = { ...n.axis[a] };
        push(W[a], 'auto'); push(MAX[a], 'none'); push(MIN[a], '0');
        if (sp.fixed != null) { push(W[a], vpx(sp.fixed)); push(selfProp, alignOf(al)); }
        else if (sp.fill) { push(selfProp, 'stretch'); if (sp.max != null && sp.max !== Infinity) { push(MAX[a], vpx(sp.max)); } }
        else push(selfProp, alignOf(al));
      }
      return;
    }
    const primaryOfParent = (ps === 'overlay' && parent.kids[0] !== n) || (ps === 'background' && parent.kids[parent.kids.length - 1] !== n);
    if (primaryOfParent) { this.layer(n, parent, push, d); return; }
    // A screen larger than its NavigationStack or tab starts at its top leading corner (`safe`), as on the host.
    const safe = ps === 'navstack' || ps === 'panel';
    const alignIn = a => safe && side(a) !== 0 ? 'safe ' + alignOf(a) : alignOf(a);
    for (const a of ['x', 'y']) {
      const s = { ...ax[a] }, w = W[a];
      if ((k === 'geometry' || k === 'position') && !n.def[a]) s.fixed = 10; // a GeometryReader offered nothing takes 10pt
      if ((k === 'flexible' || framedCanvas(n)) && !n.def[a] && s.fixed == null) s.fixed = num(e.getAttribute('data-ideal-' + (a === 'x' ? 'w' : 'h')), 10); // a shape offered nothing takes its ideal size
      // A node only fills the proposal it is given: where the proposal along the axis is unspecified (below a scroll
      // view's scrolling axis, below fixedSize) it is as large as its content.
      // (A Divider across a stack takes the stack's length there, which the stack decides from its other views.)
      if (s.fill && !n.def[a] && !(n.divider && stackMain && a !== stackMain)) { s.fill = false; s.max = null; }
      // A Spacer is flexible, and has its minimum length, along its stack's axis only: across it, it is as thin as its
      // content (none).
      if (k === 'spacer' && stackMain && a !== stackMain) { s.fill = false; s.min = null; }
      // Offered nothing, a frame with a finite maximum is as large as what it holds, up to that maximum (SwiftUI's
      // `frame(maxHeight: 250)` around a taller view is 250 tall).
      if (s.cap != null && !n.def[a]) { s.cap = null; s.hugMax = s.max; }
      // Alignment of this node on the axis, from the parent.
      let place;
      if (ctx === 'row' && a === 'y' && parent.baseline) place = 'baseline';
      else if (ctx === 'cell') place = a === 'x' ? parent.ax : parent.ay;
      else if (ctx === 'row') place = a === 'y' ? parent.ay : 0;
      else place = a === 'x' ? parent.ax : 0;
      // A LabeledContent cell is widened to its column, its content left where it was (a stretched cell): at the start.
      if (ps === 'zstack' && parent.attr?.('data-cell-kind') === 'labeled') place = 0;
      if (ps === 'geometry') place = 0;
      // The content starts at the inset's edge's opposite corner; the inset is aligned across its edge.
      if (ps === 'inset' && parent.kids.length > 1) place = parent.kids[1] === n && a === (insetEdge(parent).vertical ? 'x' : 'y') ? (a === 'x' ? parent.ax : parent.ay) : 0;
      if (ps === 'scroll') place = 0;
      const selfProp = ctx === 'cell' ? (a === 'x' ? 'justify-self' : 'align-self') : 'align-self';
      const main = a === stackMain;
      // The stylesheet has width/height/max rules of its own (`.vstack:has(...)`, `.frame-box`): reset what is not set below.
      push(w, 'auto'); push(MAX[a], 'none');
      // The size of the node itself.
      if (s.fixed != null) {
        push(w, vpx(s.fixed));
        if (main) push('flex', `0 0 ${vpx(s.fixed)}`); else push(selfProp, alignIn(place));
        continue;
      }
      // A text in a LabeledContent cell keeps its words whole, as the host measures it there (`cellWrap`).
      const keepsWords = k === 'intrinsic' && a === 'x' && !!e.closest?.('[data-cell-kind="labeled"]');
      if (s.min != null) push(MIN[a], vpx(s.min)); else push(MIN[a], keepsWords ? 'min-content' : '0');
      if (main) {
        if (k === 'spacer') { push('flex', `${weight(n.explicitPriority ? n.priority : -1)} 1 0%`); continue; }
        if (s.fill && !s.soft) {
          push('flex', `${weight(n.priority)} 1 0%`);
          if (s.max != null && s.max !== Infinity) push(MAX[a], vpx(s.max));
          else if (s.capIdeal != null && parent.kids.length > 1) push(MAX[a], vpx(s.capIdeal)); // a lone child is offered everything
          else if (s.capContent && parent.kids.length > 1) push(MAX[a], 'max-content');
        // A finite maximum grows from nothing to that maximum, sharing what is left with its siblings as SwiftUI's stack
        // offers it (its content is what it contributes where the stack's length is not known yet, as a Grid's row).
        } else if (s.cap != null) { push('flex', `${weight(n.priority)} 1 0%`); push(MAX[a], vpx(s.cap)); }
        else if (s.rigid) { push('flex', '0 0 auto'); }
        // A <select> grows up to its selected label's width (`sizeSelects`), not to its widest option.
        // Firefox ignores an intrinsic maximum height (`max-height: max-content`), so in a column the share is written with
        // --sl-hug-grow and --sl-hug-basis, which styles.css sets for Firefox only: there the view keeps its content's
        // height and does not grow (`0 1 auto`).
        else if (a === 'y' && s.hugMax == null && e.localName !== 'select') { push('flex', `var(--sl-hug-grow,${weight(n.priority)}) 1 var(--sl-hug-basis,0%)`); push(MAX[a], 'max-content'); }
        else { push('flex', `${weight(n.priority)} 1 0%`); push(MAX[a], s.hugMax != null ? vpx(s.hugMax) : e.localName === 'select' ? 'var(--sl-select-w,max-content)' : 'max-content'); }
      } else if (s.cap != null) {
        push(w, vpx(s.cap)); push(MAX[a], '100%'); push(selfProp, alignIn(place));
      } else if (s.fill) {
        // A child that fills its cell with a margin (an inner or a negative padding of its parent) is that much smaller or larger.
        const m = parent.margin, inset = !m ? 0 : a === 'x' ? m.leading + m.trailing : m.top + m.bottom;
        if (k === 'flexible' || k === 'opaque') { push(w, inset ? `calc(100% - ${px(inset)})` : '100%'); push(selfProp, 'stretch'); }
        // An aspect box capped by the height it is proposed is narrower than its cell: aligned in it, as the frame aligns it.
        else push(selfProp, n.cap != null && a === 'x' ? alignIn(place) : 'stretch');
      } else {
        push(selfProp, alignIn(place));
        if (s.hugMax != null) push(MAX[a], vpx(s.hugMax));
        // An aligned view keeps to its cell (`max-width: 100%`), except a ZStack: its own children keep to it already, and
        // the percentage of a cell sized by its content made Chromium lay a ZStack nested in a ZStack out again at every
        // level (the renderer of Chromium 136 and 140 crashed at a thousand, `sheet-1000` in test-stack-depth-browser.mjs).
        else if (!s.ideal && n.def[a] && a === 'x' && k !== 'zstack') push(MAX[a], '100%');
        // Along the axis a ScrollView scrolls, its content is offered nothing and is as wide as it wants, not squeezed into
        // the viewport (a grid item's `auto` width is clamped to its track).
        else if (ps === 'scroll' && !n.def[a] && a === 'x') push(w, 'max-content');
      }
    }
  }
  /** Size and alignment of a root island in the container that hosts it (a block or a flex row the stylesheet lays out):
   * it takes the proposal where it fills and there is one, else it is as large as its content, aligned in the
   * proposed width by margins and at the top. */
  rootPlacement(n, push) {
    const root = this.roots.get(n.element), ax = n.axis;
    if (root.item) {
      // A subview of a user-defined Layout, proposed what the Layout placed it with: it takes that where it fills (wraps at it
      // otherwise, never narrower than its content can be), and is as large as its content on an axis left unspecified. Swift
      // pins its placed point (left, top); its anchor is a share of the size this decides. (Not `fit-content(<width>)`: a grid
      // container takes the whole length for its `fr` track.)
      push('position', 'absolute'); push('translate', 'var(--layout-anchor-x,0%) var(--layout-anchor-y,0%)'); push('margin', '0'); push('min-height', '0'); push('max-height', 'none');
      const [w, h] = childProposal(n.element), wraps = w != null && ax.x.fixed == null && !ax.x.fill;
      push('width', ax.x.fixed != null ? px(ax.x.fixed) : w != null && ax.x.fill ? px(w) : 'max-content');
      push('min-width', wraps ? 'min-content' : '0'); push('max-width', wraps ? px(w) : 'none');
      push('height', ax.y.fixed != null ? px(ax.y.fixed) : h != null && ax.y.fill ? px(h) : 'auto');
      return;
    }
    if (root.height === 'cell') {
      // The container is a one-cell grid (`data-cl-host`): the root fills it or is aligned in it, at the top.
      push('position', 'relative'); push('inset', 'auto'); push('margin', '0'); push('min-width', '0'); push('min-height', '0'); push('max-width', 'none'); push('max-height', 'none');
      for (const [a, W, self, al] of [['x', 'width', 'justify-self', root.ax], ['y', 'height', 'align-self', 0]]) {
        if (ax[a].fixed != null) { push(W, vpx(ax[a].fixed)); push(self, FLEX[side(al)]); }
        else if (ax[a].fill) { push(W, 'auto'); push(self, 'stretch'); }
        // A finite maximum takes min(offered, maximum) whatever the content is, the cell being what is offered.
        else if (ax[a].cap != null && root.def[a]) { push(W, vpx(ax[a].cap)); push('max-' + W, '100%'); push(self, FLEX[side(al)]); }
        else { push(W, a === 'x' ? 'fit-content' : 'auto'); push(self, FLEX[side(al)]); }
        if (ax[a].fixed == null && ax[a].min != null) push('min-' + W, vpx(ax[a].min));
      }
      return;
    }
    if (root.ideal) {
      // Proposed nothing (the layout tree of a table cell): as large as its ideal size, which the browser sizes the table's
      // columns from, and never narrower (the host gave it that size and the column could not shrink it).
      push('position', 'relative'); push('inset', 'auto'); push('margin', '0'); push('min-width', '0'); push('min-height', '0'); push('max-width', 'none'); push('max-height', 'none');
      push('width', ax.x.fixed != null ? px(ax.x.fixed) : 'max-content'); push('height', ax.y.fixed != null ? px(ax.y.fixed) : 'auto');
      return;
    }
    if (root.aligned) {
      // Placed by the flex box that holds it (a chart's foreignObject: Swift gave the box the justification and alignment the
      // view sits at), as large as its content unless it fills the box it is proposed.
      push('position', 'relative'); push('inset', 'auto'); push('margin', '0'); push('flex', 'none'); push('min-width', '0'); push('min-height', '0'); push('max-height', 'none');
      push('width', ax.x.fixed != null ? px(ax.x.fixed) : ax.x.fill && root.def.x ? '100%' : 'fit-content'); push('max-width', ax.x.fixed != null ? 'none' : '100%');
      push('height', ax.y.fixed != null ? px(ax.y.fixed) : ax.y.fill && root.def.y ? root.height : 'auto');
      return;
    }
    push('position', 'relative'); push('inset', 'auto'); push('flex', 'none'); push('align-self', 'flex-start');
    push('min-width', '0'); push('min-height', '0'); push('max-height', 'none');
    if (ax.x.fixed != null) push('width', vpx(ax.x.fixed));
    else if (ax.x.fill && root.def.x) push('width', '100%');
    else push('width', 'fit-content');
    push('max-width', ax.x.fixed != null ? 'none' : '100%');
    if (ax.y.fixed != null) push('height', vpx(ax.y.fixed));
    else if (ax.y.fill && root.def.y) push('height', root.height);
    else push('height', 'auto');
    const fills = ax.x.fill && root.def.x && ax.x.fixed == null;
    push('margin', fills ? '0' : `0 ${root.ax < 0.75 ? 'auto' : '0'} 0 ${root.ax > 0.25 ? 'auto' : '0'}`);
  }
  /** A NavigationStack's bar item: in the bar row, over the title (centred in its row, or in a large title's top 3rem
   * where the stylesheet keeps that row for the items, as its own flex box centres its content), leading, centred or
   * trailing, as wide as its content. An item with nothing to show is not shown. */
  barItem(n, item) {
    if (!item.shown) return ['display:none'];
    const e = n.element, title = e.hasAttribute('data-navigation-title') && e.getAttribute('data-navigation-bar-hidden') !== 'true';
    const large = title && e.getAttribute('data-navigation-title-display-mode') === 'large';
    // The stylesheet's bar look for the items the host places (`[data-toolbar-resolved="bar"]`): no background or border.
    const principals = shownOn(n, 'center').length > 1, several = shownOn(n, item.side).length > 1;
    const d = ['position:relative', 'inset:auto', 'grid-area:' + barArea(n, item), 'justify-self:' + item.side, 'width:max-content', 'max-width:100%', 'min-width:0',
      // Principal items touch, so the items on a side are 8 px apart by their margins, not by a gap (on both sides, so that
      // blocks of items as wide as each other leave the group centred on the bar).
      principals ? (item.side === 'start' ? 'margin:0 8px 0 0' : item.side === 'end' && several ? 'margin:0 0 0 8px' : 'margin:0') : 'margin:0', 'z-index:20',
      'border-bottom:0', 'background:transparent', '-webkit-backdrop-filter:none', 'backdrop-filter:none', 'transform:none'];
    if (large) d.push('align-self:start', 'min-height:3rem', 'box-sizing:border-box');
    else d.push('align-self:' + (title ? 'center' : 'start'));
    return d;
  }
  /** The child of `.position(x:y:)`: offered the position's proposal and centred on its point (as SwiftUI's position does), from the
   * leading edge (a global rule mirrors it in a right-to-left document, as SwiftUI does). */
  positioned(n, parent, push) {
    const x = num(parent.attr('data-position-x'), 0), y = num(parent.attr('data-position-y'), 0);
    push('position', 'absolute'); push('inset', 'auto'); push('left', vpx(x)); push('top', vpx(y)); push('--sl-px', vpx(x));
    push('translate', '-50% -50%'); push('margin', '0'); push('grid-area', 'auto');
    for (const [a, W, MIN, MAX] of [['x', 'width', 'min-width', 'max-width'], ['y', 'height', 'min-height', 'max-height']]) {
      const s = n.axis[a];
      // Offered the position's whole proposal, a view as large as its content wraps at that size.
      const hugs = s.fixed == null && !(s.fill && n.def[a]);
      push(MIN, s.min != null ? vpx(s.min) : '0'); push(MAX, s.max != null && s.max !== Infinity ? vpx(s.max) : hugs ? '100%' : 'none');
      push(W, s.fixed != null ? vpx(s.fixed) : hugs ? 'max-content' : '100%');
    }
  }
  /** A secondary child of an overlay or background: it fills the primary's box and is aligned inside it. */
  layer(n, parent, push, d) {
    push('position', 'absolute'); push('inset', '0');
    const mx = [['margin-left', 'margin-right'], ['margin-top', 'margin-bottom']];
    const ax = n.axis;
    ['x', 'y'].forEach((a, i) => {
      const al = a === 'x' ? parent.ax : parent.ay;
      if (ax[a].fixed != null) push(a === 'x' ? 'width' : 'height', vpx(ax[a].fixed));
      else if (ax[a].fill || n.kind === 'flexible') { push(a === 'x' ? 'width' : 'height', '100%'); return; }
      else {
        // A box that hugs its tracks has no free space, so its content alignment is a no-op; WebKit measures that space
        // from the containing block instead and would shift the content, so the hugging axis aligns at the start. WebKit
        // also grows a flexible row to the containing block's height, so the row is as tall as its content, as it is in
        // a box that hugs it anyway.
        push(a === 'x' ? 'width' : 'height', 'fit-content'); push(a === 'x' ? 'justify-content' : 'align-content', 'start');
        const rows = a === 'y' && d.findLast(x => x.startsWith('grid-template-rows:'));
        if (rows && rows.includes('1fr') && !rows.startsWith('grid-template-rows:repeat(')) d.push(rows.replaceAll('1fr', 'max-content'));
      }
      if (ax[a].fill || n.kind === 'flexible') return;
      const [m1, m2] = mx[i];
      push(m1, al > 0.25 ? 'auto' : '0'); push(m2, al < 0.75 ? 'auto' : '0');
    });
  }
  /** Writes the blocks of every node under `root` whose block changed. A node that was not analysed again and still has
   * the same parent object keeps its block, and so does everything below it (a change below it would have made it fresh). */
  assign(root, sink = null) {
    const top = this.cache.get(root);
    if (!top) return 0;
    let writes = 0;
    // A collapsed rail's blocks keep their lengths in the text (an element has one set of `--len<i>`, its expanded block's).
    const variables = this.roots.get(root)?.key !== 'rail', prefix = root === this.swiftRoot ? '--len' : '--cl-len';
    /** Gives `e` the rule of `built` (interned) and returns its id; the lengths it marks go to the element as `--len<i>`. */
    const apply = (e, built) => {
      const [block, lengths] = lengthVariables(built, variables, prefix);
      if (sink) { sink(e, block, lengths); return '0'; }
      let id = this.rules.get(block);
      if (id === undefined) {
        id = this.rules.size + 1; this.rules.set(block, id); this.blocks[id] = block;
        this.fresh.push(`[data-cl-${id}]{${block}}`);
        this.stats.rules++;
      }
      const value = String(id);
      // An element analysed again is a new node with nothing applied, but it may already carry this block: what it holds
      // decides (a write of the same value is a mutation record and, for the rule's attribute, a style invalidation).
      const held = e.getAttribute('data-cl');
      if (held !== value || !e.hasAttribute('data-cl-' + value)) {
        if (held && held !== value) e.removeAttribute('data-cl-' + held);
        if (held !== value) e.setAttribute('data-cl', value);
        if (!e.hasAttribute('data-cl-' + value)) e.setAttribute('data-cl-' + value, '');
        writes++;
      }
      if (!holdsLengths(e, lengths, prefix)) { writeLengths(e, lengths, prefix); writes++; }
      return value;
    };
    // Pre-order with an explicit stack: the DOM can be deeper than the JS call stack, and the order is the recursive one.
    const pending = [[top, null, 0]];
    while (pending.length) {
      const [n, parent, flag] = pending.pop();
      n.def = this.definite(n, parent, flag);
      n.prop = this.definite(n, parent, flag, true);
      // (The proposal a Layout is asked is read from `prop`, which a hugging Grid far above can change: it is part of the key.)
      const bits = (n.def.x ? 1 : 0) + '' + (n.def.y ? 1 : 0) + (n.prop.x ? 1 : 0) + (n.prop.y ? 1 : 0);
      n.cap = n.kind === 'aspect' ? this.aspectCap(n, parent) : null;
      const ctx = (parent ? parent.ctxKey + '|' + flag + '|' + bits : 'root' + bits) + (n.cap != null ? '|c' + n.cap : '');
      if (n.ctxSeen === ctx && n.applied !== undefined) continue;
      this.stats.nodes++;
      const value = apply(n.element, this.declarations(n, parent).map(x => x + '!important').join(';'));
      if (!sink) n.applied = value;
      n.ctxSeen = ctx;
      if (n.kind === 'navstack') for (const item of n.bar) apply(item.element, this.barItem(n, item).map(x => x + '!important').join(';'));
      // The element's children are proposed what its innermost layer proposes, and aligned as `chainPlan` says.
      let holder = n;
      n.heightOut = this.passHeight(n, Infinity);
      if (!n.layers && n.kind === 'padding') {
        const m = Object.fromEntries(['top', 'leading', 'bottom', 'trailing'].map(edge => [edge, Math.min(0, num(n.attr('data-padding-' + edge), 0))]));
        n.margin = m.top || m.leading || m.bottom || m.trailing ? m : null;
      }
      if (n.layers) {
        for (const layer of n.layers) {
          layer.def = this.definite(layer, holder); layer.prop = this.definite(layer, holder, undefined, true);
          layer.heightOut = holder.heightOut == null ? null : this.passHeight(layer, holder.heightOut);
          holder = layer;
        }
        holder.ax = n.plan.x.item; holder.ay = n.plan.y.item; holder.ctxKey = n.ctxKey + '|in';
        const m = n.plan.margin; holder.margin = m.top || m.leading || m.bottom || m.trailing ? m : null;
      }
      const layered = n.kind === 'overlay' || n.kind === 'background' || n.kind === 'grid';
      // Pushed in reverse so the first child is visited first; a ViewThatFits's other candidates are styled after the
      // children, as the one it shows.
      if (n.spare) for (let i = n.spare.length - 1; i >= 0; i--) pending.push([n.spare[i], holder, 0]);
      for (let i = n.kids.length - 1; i >= 0; i--) pending.push([n.kids[i], holder, layered ? (n.kind === 'overlay' ? i === 0 : n.kind === 'background' ? i === n.kids.length - 1 : i) : 0]);
    }
    this.stats.assigned += writes;
    if (!sink) this.adoptRules();
    return writes;
  }
  /** Adopts the rules Swift sent (`data-sl-rules`, one `[data-sl-<n>]{block}` a line) that it does not hold yet. */
  adoptSwiftRules(text) {
    const fresh = [];
    for (const line of text.split('\n')) {
      // `.sl<n>{block}`, or `.sr<n>{block}`: a sidebar slot element's block in a collapsed rail, scoped to it.
      const match = /^\.(sl|sr)(\d+)\{(.*)\}$/.exec(line);
      const key = match && (match[1] === 'sr' ? 'r' + match[2] : match[2]);
      // A block with braces or `</` would close the rule early and write other CSS: the page's text is not trusted that far.
      if (!match || this.swiftBlocks.has(key) || /[{}]|<\//.test(match[3])) continue;
      this.swiftBlocks.set(key, match[3]);
      fresh.push(swiftRule(key, match[3]));
    }
    if (!fresh.length || !this.sheet) return;
    this.fresh.push(...fresh);
    this.adoptRules();
  }
  /** Equivalence check of a root Swift styled (`window.__layoutVerify`): every element must carry the block a fresh
   * analysis of the page gives it. */
  verifySwift(root, proposal) {
    const fresh = new CssLayout(this.document, { ...this.options, detached: true });
    fresh.islands.add(root); fresh.roots.set(root, proposal);
    fresh.swiftRoot = root;
    if (!fresh.claim(root)) { this.mismatch({ what: 'swift css root', note: 'refused by the page' }); return; }
    fresh.assign(root, (element, block, lengths) => {
      // In a collapsed rail an element carries its rail block (`sr<n>`) where it differs from its own.
      const rail = proposal.key === 'rail' ? [...element.classList].find(name => /^sr\d+$/.test(name)) : null;
      const held = rail ? 'r' + rail.slice(2) : [...element.classList].find(name => /^sl\d+$/.test(name))?.slice(2) ?? null;
      if (this.swiftBlocks.get(held) !== block) this.mismatch({ what: 'swift css block', element: element.localName + '.' + String(element.className).split(' ')[0], held, swift: this.swiftBlocks.get(held) ?? null, fresh: block });
      // (An element of a collapsed rail carries the lengths of its expanded block.)
      else if (!rail && !holdsLengths(element, lengths)) this.mismatch({ what: 'swift css lengths', element: element.localName + '.' + String(element.className).split(' ')[0], held, fresh: lengths, swift: [...element.style].filter(name => name.startsWith('--len')).map(name => element.style.getPropertyValue(name)) });
    });
  }
  adoptRules() {
    if (!this.fresh.length) return;
    const window = this.document.defaultView, sheet = new window.CSSStyleSheet();
    sheet.replaceSync(this.fresh.join('\n'));
    this.fresh = [];
    this.ruleSheets.push(sheet);
    this.document.adoptedStyleSheets = [...this.document.adoptedStyleSheets, sheet];
    if (this.ruleSheets.length > 16 && !this.merging) {
      this.merging = true;
      const later = window.requestIdleCallback ? run => window.requestIdleCallback(run, { timeout: 2000 }) : run => window.setTimeout(run, 500);
      later(() => this.mergeRules());
    }
  }
  /** One stylesheet for the rules of every block again (a restyle of the elements the mapper styles, once). */
  mergeRules() {
    this.merging = false;
    if (this.ruleSheets.length < 2) return;
    const merged = new this.document.defaultView.CSSStyleSheet();
    // The mapper's own blocks and the ones Swift sent.
    const swift = [...this.swiftBlocks].map(([key, block]) => swiftRule(key, block));
    merged.replaceSync([...this.blocks.map((block, id) => block === undefined ? '' : `[data-cl-${id}]{${block}}`), ...swift].join('\n'));
    const old = new Set(this.ruleSheets);
    this.ruleSheets = [merged];
    this.document.adoptedStyleSheets = [...this.document.adoptedStyleSheets.filter(sheet => !old.has(sheet)), merged];
  }
}
