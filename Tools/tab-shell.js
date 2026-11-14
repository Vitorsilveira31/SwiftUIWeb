/** Browser presentation of `TabView` with `.tabViewStyle(.sidebarAdaptable)`.
 *
 * Swift emits one semantic sidebar surface (see TabViewAdaptiveChrome.swift);
 * this host adapter only decides the viewport presentation and owns the
 * browser-only interaction state:
 *
 * - `data-tab-layout` on the tab view: `mobile` (≤ first breakpoint), `rail`
 *   (≤ second breakpoint) or `sidebar` (wider).
 * - `data-tab-sidebar-expanded`: rail/sidebar expansion. The rail starts
 *   collapsed and its toggle is not persisted; the sidebar starts expanded and
 *   the toggle is persisted in localStorage.
 * - `data-tab-mobile-open`: the mobile navigation panel.
 *
 * Application configuration lives in the document head:
 *   <meta name="tab-breakpoints" content="720,1100">
 *   <meta name="tab-labels" content='{"expand":"Expandir menu",…}'>
 */
const DEFAULT_BREAKPOINTS = [767, 1199];
const DEFAULT_LABELS = {
  expand: 'Expand navigation',
  collapse: 'Collapse navigation',
  open: 'Open app navigation',
  close: 'Close app navigation',
  openWithBadge: '',
  activity: 'in progress',
  navigation: 'App navigation'
};
// A same-value setAttribute still queues a MutationObserver record, and the layout host reacts to those: write
// presentation state only when it changes.
function setIfChanged(element, name, value) {
  const text = String(value);
  if (element.getAttribute(name) !== text) element.setAttribute(name, text);
}
const ADAPTIVE = '.tab-view[data-tab-style="sidebar-adaptable"]';
const SIDEBAR = ':scope > [data-tab-sidebar]';
const FOCUSABLE = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';
const STORAGE_PREFIX = 'swiftuiweb.tab-sidebar.';

const elementOf = node => node?.nodeType === 1 ? node : node?.parentElement;

export class AdaptiveTabShell {
  constructor(root, {window, document, onLayoutChange = () => {}, signal}) {
    this.root = root; this.window = window; this.document = document;
    this.onLayoutChange = onLayoutChange;
    this.railExpanded = new WeakMap();
    this.mobileOpen = new WeakMap();
    this.layouts = new WeakMap();
    this.labelSource = null; this.labelCache = DEFAULT_LABELS;
    this.tooltip = null; this.tooltipOwner = null;
    const on = (target, name, handler, capture = false) => target.addEventListener(name, handler, {capture, signal});
    on(root, 'click', event => this.click(event), true);
    on(root, 'keydown', event => this.keydown(event), true);
    on(root, 'mouseover', event => this.hover(event));
    on(root, 'focusin', event => this.hover(event));
    on(root, 'mouseleave', () => this.hideTooltip());
    on(root, 'focusout', () => this.hideTooltip());
    // `window.innerWidth` makes the browser lay the page out when anything is dirty, and a commit asks for it
    // right after patching the DOM, ahead of the layout pass that needs that same layout. The width only changes
    // when the window or the visual viewport does, so it is read once and again after those events.
    this.widthCache = null;
    const resized = () => { this.widthCache = null; this.sync(); };
    on(window, 'resize', resized);
    if (window.visualViewport) on(window.visualViewport, 'resize', () => { this.widthCache = null; });
    // The sidebar animates its width; lay chrome content out again once the
    // final width is known.
    on(root, 'transitionend', event => {
      if (event.propertyName === 'width' && event.target?.hasAttribute?.('data-tab-sidebar')) this.onLayoutChange();
    });
    signal?.addEventListener('abort', () => { this.tooltip?.remove(); this.tooltip = null; });
  }

  views() { return [...this.root.querySelectorAll(ADAPTIVE)]; }

  meta(name) { return this.document.querySelector(`meta[name="${name}"]`)?.getAttribute('content') ?? null; }

  breakpoints(tabView) {
    const source = this.meta('tab-breakpoints') ?? tabView.getAttribute('data-tab-breakpoints') ?? '';
    const values = source.split(',').map(value => Number.parseFloat(value.trim()));
    return values.length === 2 && values.every(Number.isFinite) && values[0] < values[1] ? values : DEFAULT_BREAKPOINTS;
  }

  labels() {
    const source = this.meta('tab-labels');
    if (source !== this.labelSource) {
      this.labelSource = source;
      let parsed = {};
      try { parsed = source ? JSON.parse(source) : {}; } catch { parsed = {}; }
      this.labelCache = {...DEFAULT_LABELS};
      for (const key of Object.keys(DEFAULT_LABELS)) if (typeof parsed?.[key] === 'string') this.labelCache[key] = parsed[key];
    }
    return this.labelCache;
  }

  viewportWidth() { return this.widthCache ??= this.window.innerWidth; }

  layoutFor(tabView) {
    const [mobile, rail] = this.breakpoints(tabView);
    const width = this.viewportWidth();
    return width <= mobile ? 'mobile' : width <= rail ? 'rail' : 'sidebar';
  }

  storageKey(tabView) {
    return STORAGE_PREFIX + (tabView.querySelector(SIDEBAR)?.id || 'default');
  }

  storedSidebarCollapsed(tabView) {
    try { return this.window.localStorage.getItem(this.storageKey(tabView)) === 'collapsed'; } catch { return false; }
  }

  storeSidebarCollapsed(tabView, collapsed) {
    try { this.window.localStorage.setItem(this.storageKey(tabView), collapsed ? 'collapsed' : 'expanded'); } catch { /* private mode */ }
  }

  isExpanded(tabView, layout) {
    if (layout === 'sidebar') return !this.storedSidebarCollapsed(tabView);
    if (layout === 'rail') return this.railExpanded.get(tabView) === true;
    return false;
  }

  /** Re-applies presentation state after every DOM commit and resize. */
  sync() {
    const labels = this.labels();
    let changed = false;
    for (const tabView of this.views()) {
      const sidebar = tabView.querySelector(SIDEBAR);
      const toggle = sidebar?.querySelector('[data-tab-sidebar-toggle]');
      const fab = tabView.querySelector(':scope > [data-tab-mobile-toggle]');
      const backdrop = tabView.querySelector(':scope > [data-tab-mobile-backdrop]');
      if (!sidebar) continue;
      const layout = this.layoutFor(tabView);
      const previous = this.layouts.get(tabView);
      if (previous !== layout) { changed = previous !== undefined || changed; this.layouts.set(tabView, layout); }
      if (layout !== 'mobile') this.mobileOpen.set(tabView, false);
      const expanded = this.isExpanded(tabView, layout);
      const open = layout === 'mobile' && this.mobileOpen.get(tabView) === true;
      setIfChanged(tabView, 'data-tab-layout', layout);
      if (layout === 'mobile') tabView.removeAttribute('data-tab-sidebar-expanded');
      else setIfChanged(tabView, 'data-tab-sidebar-expanded', expanded ? 'true' : 'false');
      if (open) setIfChanged(tabView, 'data-tab-mobile-open', 'true');
      else tabView.removeAttribute('data-tab-mobile-open');
      if (toggle) {
        setIfChanged(toggle, 'aria-expanded', expanded ? 'true' : 'false');
        setIfChanged(toggle, 'aria-label', expanded ? labels.collapse : labels.expand);
      }
      if (fab) {
        const badge = fab.getAttribute('data-badge');
        const openLabel = badge && labels.openWithBadge ? labels.openWithBadge.replace('{count}', badge) : badge ? `${labels.open}, ${badge}` : labels.open;
        setIfChanged(fab, 'aria-expanded', open ? 'true' : 'false');
        setIfChanged(fab, 'aria-label', open ? labels.close : openLabel);
        setIfChanged(fab, 'aria-hidden', layout === 'mobile' ? 'false' : 'true');
      }
      if (backdrop && backdrop.hidden !== !open) backdrop.hidden = !open;
      // The mobile panel is a modal dialog while open and inert while closed;
      // the sidebar and rail are ordinary navigation landmarks.
      // With a handful of tabs a phone shows them as a bottom tab bar, as iOS does; more than five fall back to the
      // floating menu (iOS's "More").
      const tabCount = sidebar.querySelectorAll('[role="tab"]').length;
      const bar = layout === 'mobile' && tabCount > 0 && tabCount <= 5;
      if (tabView.hasAttribute('data-tab-mobile-bar') !== bar) tabView.toggleAttribute('data-tab-mobile-bar', bar);
      if (bar) {
        setIfChanged(sidebar, 'role', 'navigation');
        sidebar.removeAttribute('aria-modal');
        sidebar.removeAttribute('inert');
        sidebar.removeAttribute('aria-hidden');
      } else if (layout === 'mobile') {
        setIfChanged(sidebar, 'role', 'dialog');
        setIfChanged(sidebar, 'aria-modal', 'true');
        if (sidebar.hasAttribute('inert') === open) sidebar.toggleAttribute('inert', !open);
        if (open) sidebar.removeAttribute('aria-hidden'); else setIfChanged(sidebar, 'aria-hidden', 'true');
      } else {
        setIfChanged(sidebar, 'role', 'navigation');
        sidebar.removeAttribute('aria-modal');
        sidebar.removeAttribute('inert');
        sidebar.removeAttribute('aria-hidden');
      }
      if (!sidebar.hasAttribute('aria-label')) setIfChanged(sidebar, 'aria-label', labels.navigation);
      for (const tab of sidebar.querySelectorAll('[role="tab"]')) {
        tab.removeAttribute('title');
        const label = tab.getAttribute('data-tab-label') || '';
        const activity = tab.getAttribute('data-badge-style') === 'dot';
        setIfChanged(tab, 'aria-label', activity && labels.activity ? `${label}, ${labels.activity}` : label);
      }
    }
    if (this.tooltipOwner && !this.tooltipAllowed(this.tooltipOwner)) this.hideTooltip();
    if (changed) this.onLayoutChange();
  }

  tabViewOf(element) { return element?.closest?.(ADAPTIVE) || null; }

  setMobileOpen(tabView, open, {restoreFocus = false} = {}) {
    if (!tabView) return;
    const wasOpen = this.mobileOpen.get(tabView) === true;
    this.mobileOpen.set(tabView, this.layoutFor(tabView) === 'mobile' && open);
    this.sync();
    if (open && !wasOpen) {
      // Move focus into the panel once it is no longer inert.
      this.window.setTimeout(() => {
        const sidebar = tabView.querySelector(SIDEBAR);
        (sidebar?.querySelector('[role="tab"][aria-selected="true"]') || sidebar?.querySelector('[role="tab"]'))?.focus({preventScroll: true});
      }, 40);
    } else if (!open && restoreFocus) {
      tabView.querySelector(':scope > [data-tab-mobile-toggle]')?.focus({preventScroll: true});
    }
  }

  click(event) {
    const target = elementOf(event.target);
    if (!target || !this.root.contains(target)) return;
    const toggle = target.closest('[data-tab-sidebar-toggle]');
    if (toggle) {
      const tabView = this.tabViewOf(toggle);
      if (!tabView) return;
      event.preventDefault();
      const layout = this.layoutFor(tabView);
      const expanded = this.isExpanded(tabView, layout);
      if (layout === 'sidebar') this.storeSidebarCollapsed(tabView, expanded);
      else if (layout === 'rail') this.railExpanded.set(tabView, !expanded);
      this.hideTooltip();
      this.sync();
      this.onLayoutChange();
      return;
    }
    const fab = target.closest('[data-tab-mobile-toggle]');
    const backdrop = target.closest('[data-tab-mobile-backdrop]');
    if (fab || backdrop) {
      const tabView = this.tabViewOf(fab || backdrop);
      if (!tabView || this.layoutFor(tabView) !== 'mobile') return;
      event.preventDefault();
      event.stopPropagation();
      const open = this.mobileOpen.get(tabView) === true;
      this.setMobileOpen(tabView, backdrop ? false : !open, {restoreFocus: !!backdrop || open});
      return;
    }
    this.hideTooltip();
  }

  /** Called after a tab click has been dispatched to Swift. */
  didSelect(tab) {
    const tabView = this.tabViewOf(tab);
    if (!tabView || this.mobileOpen.get(tabView) !== true) return;
    // Let the click reach the normal Swift/ABI handler before the panel
    // becomes inert again.
    this.window.setTimeout(() => {
      if (tabView.isConnected && this.mobileOpen.get(tabView) === true) this.setMobileOpen(tabView, false, {restoreFocus: true});
    }, 0);
  }

  keydown(event) {
    const tabView = this.tabViewOf(elementOf(event.target));
    if (!tabView || this.mobileOpen.get(tabView) !== true) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      this.setMobileOpen(tabView, false, {restoreFocus: true});
      return;
    }
    if (event.key !== 'Tab') return;
    // Focus trap: the open panel's controls followed by the floating button.
    const sidebar = tabView.querySelector(SIDEBAR);
    const fab = tabView.querySelector(':scope > [data-tab-mobile-toggle]');
    const focusable = [...(sidebar?.querySelectorAll(FOCUSABLE) || [])]
      .filter(element => element.getClientRects().length > 0 && !element.closest('[inert]'));
    if (fab) focusable.push(fab);
    if (!focusable.length) return;
    const index = focusable.indexOf(this.document.activeElement);
    if (event.shiftKey && index <= 0) { event.preventDefault(); focusable[focusable.length - 1].focus(); }
    else if (!event.shiftKey && index === focusable.length - 1) { event.preventDefault(); focusable[0].focus(); }
  }

  tooltipAllowed(element) {
    const tabView = this.tabViewOf(element);
    return !!tabView && tabView.getAttribute('data-tab-layout') !== 'mobile'
      && tabView.getAttribute('data-tab-sidebar-expanded') === 'false';
  }

  tooltipText(element) {
    if (element.getAttribute('role') === 'tab') {
      const label = element.getAttribute('data-tab-label') || '';
      const badge = element.getAttribute('data-badge');
      return badge && element.getAttribute('data-badge-style') !== 'dot' ? `${label} · ${badge}` : label;
    }
    return element.getAttribute('aria-label') || element.textContent.replace(/\s+/g, ' ').trim();
  }

  hover(event) {
    const target = elementOf(event.target);
    const sidebar = target?.closest?.('[data-tab-sidebar]');
    if (!sidebar) { this.hideTooltip(); return; }
    const owner = target.closest('[role="tab"],[data-tab-sidebar-toggle],.tab-sidebar-bottom-bar-content button,.tab-sidebar-bottom-bar-content a');
    if (!owner || !sidebar.contains(owner) || !this.tooltipAllowed(owner)) { this.hideTooltip(); return; }
    const text = this.tooltipText(owner);
    if (!text) { this.hideTooltip(); return; }
    this.showTooltip(owner, text);
  }

  showTooltip(owner, text) {
    if (!this.tooltip) {
      this.tooltip = this.document.createElement('div');
      this.tooltip.className = 'tab-tooltip';
      this.tooltip.setAttribute('role', 'tooltip');
      this.tooltip.setAttribute('aria-hidden', 'true');
      this.document.body.append(this.tooltip);
    }
    this.tooltipOwner = owner;
    this.tooltip.textContent = text;
    this.tooltip.hidden = false;
    const rect = owner.getBoundingClientRect();
    this.tooltip.style.left = `${Math.round(rect.right + 12)}px`;
    this.tooltip.style.top = `${Math.round(rect.top + rect.height / 2 - this.tooltip.offsetHeight / 2)}px`;
  }

  hideTooltip() {
    this.tooltipOwner = null;
    if (this.tooltip) this.tooltip.hidden = true;
  }
}
