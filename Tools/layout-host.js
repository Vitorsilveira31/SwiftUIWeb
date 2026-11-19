/** The page's layout host. The browser lays the page out with CSS (Tools/css-layout.js, Documentation/Architecture/CSS_LAYOUT.md);
 * this module finds the semantic roots of the page, hands each to the CSS layout mapper, applies what the mapper styled
 * after every DOM patch, and keeps the DOM patch away from what the layout owns.
 * A root nobody can lay out is reported once (`metrics.unlaid`), not laid out.
 */
import {DocumentScroll} from './document-scroll.js';
// The `display: none` of an element the layout hides (`data-layout-hidden`): a DOM patch that writes Swift's own `display`
// there would show what the layout hides (a ViewThatFits's other candidates). The CSS layout's container lengths
// (`--sl-cw`, `--sl-ch`) are the layout's too, and so are the lengths of the blocks the mapper writes (`--cl-len<i>`, see
// `lengthVariables`).
// `--motion-` properties are the transition host's: the box and color of a screen under a push (transition-host.js).
// `--document-scroll-` and `--document-sticky-` properties are the document scroll's: how tall the page's chain stays and where a
// stuck view sits (document-scroll.js).
export function ownsLayoutStyle(element, name) { return (name === 'display' && element.hasAttribute('data-layout-hidden')) || name.startsWith('--sl-') || name.startsWith('--cl-') || name.startsWith('--motion-') || name.startsWith('--document-scroll-') || name.startsWith('--document-sticky-'); }
// The attributes the layout writes, which a DOM patch leaves alone. Swift renders a ViewThatFits with its first candidate
// selected (`data-fit-selected`); the CSS mapper moves the selection, which a later publication that patches the candidate
// must not undo.
// The document scroll marks the page's scroll view, its chain and what sticks (`data-document-scroll*`, `data-document-sticky*`;
// not `data-document-head`, which is Swift's and a patch keeps current).
export function ownsLayoutAttribute(name) { return name === 'data-layout-hidden' || name === 'data-text-fit' || name === 'data-fit-selected' || name === 'data-measuring' || name === 'data-cl' || name.startsWith('data-cl-') || name.startsWith('data-document-scroll') || name.startsWith('data-document-sticky'); }
// A window resize holds CSS transitions off for this many ms after its last step: an element with an `.animation` modifier
// (a progress bar) would otherwise run its transition on every step, and each frame of it is a commit and a layout pass.
export const RESIZE_SETTLE_MS = 300;
// Set on the document element while a resize settles; the resize rule of the bundle (Tools/scope-resize-transitions.mjs)
// turns the transitions off under it.
export const RESIZING_ATTRIBUTE = 'data-layout-resizing';
// Whether an element has a box (none when it or an ancestor is `display: none`, or it is `display: contents`), from its
// style alone: unlike `getClientRects`, `checkVisibility` does not lay the page out.
const displayed = element => element.checkVisibility ? element.checkVisibility() : element.getClientRects().length > 0;

export class SemanticLayoutHost {
  constructor(root, options={}) {
    this.root=root;this.document=root.ownerDocument;this.window=this.document.defaultView;this.options=options;
    this.performanceDiagnostics=options.performanceDiagnostics===true;
    // `unlaid`: the semantic roots of the last pass that CSS could not lay out.
    this.metrics={passes:0,passesSkipped:0,unlaid:0,cssMs:0};
    this.epoch=0;this.changed=false;this.windowResized=false;this.disposed=false;this.scheduled=0;this.updating=false;this.updateRequested=false;
    this.passed=null;this.lastCssRoots=null;this.orphans=[];this.orphanSet=new Set();this.unlaid=new Set();this.reported=new WeakSet();
    this.onSettled=options.onSettled||(()=>{});this.onError=options.onError||console.error;
    this.abort=new this.window.AbortController();
    this.window.addEventListener('resize',()=>{this.markResize();this.epoch++;this.windowResized=true;this.schedule();},{signal:this.abort.signal});
    // A control's input can change the width the mapper gives a menu Picker (its selected label).
    for(const type of ['input','change'])root.addEventListener(type,()=>this.schedule(),{capture:true,signal:this.abort.signal});
    const fontsChanged=()=>{if(!this.disposed){this.epoch++;this.schedule();}};
    this.document.fonts?.ready.then(fontsChanged);
    this.document.fonts?.addEventListener('loadingdone',fontsChanged,{signal:this.abort.signal});
    // A DOM patch inside a root CSS lays out reaches the mapper only (`collect`); one anywhere else asks for a pass.
    // `loading`, `fetchpriority` and `decoding` choose when and how an image loads, never its box: none is a layout change.
    this.ownAttributes=new Set(['data-layout-hidden','data-fit-selected','data-cl','data-measuring','fetchpriority','loading','decoding']);
    // The mapper's factory (`options.cssLayout`, from Tools/css-layout.js): the page's CSS layout.
    this.css=options.cssLayout(this.document,{onProposal:options.onProposal,onLayoutSizes:options.onLayoutSizes});
    // On a touch screen the page's scroll view hands its scrolling to the document (document-scroll.js); a pointer that
    // changes (a tablet's keyboard and trackpad) asks for a pass that hands it back or over.
    this.documentScroll=new DocumentScroll(root);
    this.documentScroll.media?.addEventListener?.('change',()=>{this.epoch++;this.schedule();},{signal:this.abort.signal});
    if(this.performanceDiagnostics)this.window.__cssLayoutInstance=this.css;
    this.mutations=new this.window.MutationObserver(records=>this.collect(records));
    this.observeMutations=()=>this.mutations.observe(root,{attributes:true,attributeOldValue:true,childList:true,subtree:true,characterData:true});
    this.observeMutations();
    // Anything outside the observed subtree that changes computed style (theme, direction, viewport media queries) asks for a
    // pass. A commit rewrites some of these attributes with their current value, which changes nothing.
    this.globals=new this.window.MutationObserver(records=>{for(const r of records){if(r.type==='attributes'&&r.target.getAttribute(r.attributeName)===r.oldValue)continue;this.epoch++;this.schedule();return;}});
    for(const target of [this.document.documentElement,this.document.body])if(target&&target!==root)this.globals.observe(target,{attributes:true,attributeOldValue:true});
  }
  collect(records){
    for(const r of records){
      const target=r.target.nodeType===1?r.target:r.target.parentElement;if(!target)continue;
      // A change inside a CSS island concerns the mapper only.
      const island=this.css.islandOf(target);
      if(island){this.css.note(r,target,island);continue;}
      if(r.type==='attributes'){
        if(this.ownAttributes.has(r.attributeName))continue;
        // A text field's `value` is what it shows, not its box, and Swift writes it on every key.
        if(r.attributeName==='value'&&(target.localName==='input'||target.localName==='textarea'))continue;
        // A write that leaves the attribute as it was (a patch that removes and re-adds it) changes nothing.
        if(r.oldValue===target.getAttribute(r.attributeName))continue;
      }
      this.changed=true;
    }
  }
  roots(){
    const native=this.root.querySelector('[data-native-layout="document"]');
    const roots=native?[...this.root.querySelectorAll('[data-layout-root]')]:[...this.root.children].filter(e=>!e.classList.contains('presentation-backdrop')&&!e.classList.contains('presentation-root'));
    if(native){
      for(const examples of native.querySelectorAll('[data-docs-part="examples"]')){
        for(const child of examples.children)if(!child.hasAttribute('data-docs-part')&&!child.querySelector('[data-layout-root]'))roots.push(child);
      }
    }
    // Presentations are excluded from their source tree because the browser
    // owns their viewport position. Their Swift content still needs its own
    // semantic root, in applications as well as document previews.
    for(const content of this.root.querySelectorAll('.presentation-content'))for(const child of content.children)if(!child.classList.contains('presentation-actions'))roots.push(child);
    // TabView sidebar content (header, footer, bottom bar) is Swift content
    // hosted by browser chrome. Each placement is its own semantic root sized
    // by its chrome slot; slots the current presentation hides are skipped.
    for(const content of this.root.querySelectorAll('[data-tab-sidebar-content]'))if(displayed(content))for(const child of content.children)roots.push(child);
    // The subviews of a user-defined Layout are placed by Swift at the size it chose; the content of each
    // is its own semantic root proposed exactly that size.
    for(const island of this.root.querySelectorAll('.layout-box[data-layout-proposal]'))if(displayed(island))for(const child of island.children)if(child.hasAttribute('data-layout-child-proposal'))roots.push(child);
    // A native table sizes its columns from its cells; the layout tree a cell hosts is its own semantic root.
    for(const cell of this.root.querySelectorAll('td,th'))if(displayed(cell))for(const child of cell.children)if(child.hasAttribute('data-layout-kind'))roots.push(child);
    // NavigationSplitView is a CSS grid of columns, so the Swift content each column hosts is its own semantic root,
    // sized by the column the browser grid gives it.
    for(const column of this.root.querySelectorAll('.navigation-column'))if(displayed(column)&&!column.hasAttribute('data-column-hidden'))for(const child of column.children)if(!child.hasAttribute('data-compact-back'))roots.push(child);
    // The views a chart draws (custom axis labels, annotations) sit in the SVG foreignObjects the chart places; each is
    // its own semantic root, proposed its foreignObject's box.
    for(const box of this.root.querySelectorAll('.data-chart foreignObject > div'))if(displayed(box))for(const child of box.children)if(child.hasAttribute('data-layout-kind'))roots.push(child);
    // The panes of an HSplitView or VSplitView sit in items Swift's split layout places (each item's box is inline);
    // each pane is its own semantic root, proposed its item's box.
    for(const item of this.root.querySelectorAll('.split-pane > .split-item'))if(displayed(item))for(const child of item.children)roots.push(child);
    return [...new Set(roots)].filter(e=>!e.hidden&&!e.closest('[hidden],[data-layout-hidden],[data-navigation-inactive="true"]'));
  }
  /** Topmost laid-out elements that no CSS layout styles: a Grid a native widget (Form, List, Table) keeps its children in. */
  findOrphans(){
    const found=[];
    for(const element of this.root.querySelectorAll('[data-layout-kind="table"]')){
      // A Grid CSS layout styles (`data-cl`) is not an orphan, nor one an island
      // claimed in this pass holds (its block is written at the end of the pass): its parent places it, as a frame centres
      // what it holds. One that is itself a root of the mapper is, so that it stays one.
      if(!element.getClientRects().length||((element.hasAttribute('data-cl')||this.css.holds(element))&&!this.css.roots.has(element)))continue;
      if(element.closest('[hidden],[data-layout-hidden],[data-navigation-inactive="true"],.presentation-backdrop'))continue;
      // Only the topmost: an orphan under another orphan belongs to it.
      if(found.some(o=>o.contains(element)))continue;
      found.push(element);
    }
    return found;
  }
  /** Whether `update` has a pass to run after a commit, asked before the call. The answer is the one `update` reaches by
   * itself: a pass runs when one was scheduled or requested, or when the records of the page changed something since the last
   * completed pass (`unchangedSincePass`). The records are collected here, as `update` would collect them: they are the
   * observer's own, so they include what the syncs before the layout wrote, which the commit's changes do not. A commit that
   * changed nothing the layout reads skips the call (and is counted as a skipped pass, as `update` counts it). */
  needsSync(){
    if(this.disposed)return false;
    this.collect(this.mutations.takeRecords());
    if(this.scheduled!==0||this.updateRequested||!this.unchangedSincePass())return true;
    this.metrics.passesSkipped++;
    return false;
  }
  update(){
    if(this.disposed)return;
    // A prerendered first screen (Documentation/Architecture/FIRST_PAINT.md) is a picture its own rules lay out
    // (`#first-paint-style`) until the first commit replaces it. A pass before that (one a font, a global attribute or the
    // window asked for) would claim its elements and number their blocks again, and for a frame the picture would lose the
    // rules it was captured with (a ViewThatFits showed every candidate). The first commit's own pass runs after the release.
    if(this.root.hasAttribute?.('data-first-paint'))return;
    // Swift publication can schedule another DOM commit while the current frame is synchronizing layout: fold that request
    // into one follow-up animation frame.
    if(this.updating){this.updateRequested=true;return;}
    // Every change that does not reach the DOM (fonts, a global attribute, a control's input, a window resize) asks for a
    // pass through `schedule`. A full pass covers everything a pending scheduled pass would: drop it rather than repeat the work.
    const requested=this.scheduled!==0;
    if(this.scheduled){this.window.cancelAnimationFrame(this.scheduled);this.scheduled=0;}
    this.updating=true;
    let completed=false;
    try {
    this.collect(this.mutations.takeRecords());
    // A commit whose patch wrote nothing the layout reads, with nothing scheduled, finds nothing to claim or to style.
    if(!requested&&this.unchangedSincePass()){this.metrics.passesSkipped++;this.metrics.unlaid=this.unlaid.size;completed=true;return;}
    this.unlaid=new Set();
    this.documentScroll.begin();
    // The CSS of the islands the mapper already holds goes in
    // before the first read below: the analysis reads attributes only, so the patch and the CSS are recalculated by one
    // forced style recalculation instead of one each. An island claimed during this pass is styled at its end.
    this.flushCss();
    // Grids a native widget hosts (a Grid in a Form row) are roots of their own; the previous pass found them, this one keeps them.
    const roots=this.roots();
    for(const e of this.orphans)if(e.isConnected&&!roots.includes(e))roots.push(e);
    const claimed=this.claimCssRoots(roots);
    this.lastCssRoots=claimed;
    const found=this.findOrphans();
    for(const e of found)if(!claimed.has(e)){
      this.orphanSet.add(e);
      if(this.css.claimRoot(e,this.cssRootProposal(e)))claimed.add(e);else this.refuse(e);
    }
    this.orphans=found;this.orphanSet=new Set(found);
    this.flushCss();
    // The texts are measured once the pass laid everything out: each takes the width of the lines it draws (`fitTexts`).
    // Its own writes are not records of the page.
    this.mutations.disconnect();
    // The page's scroll view follows the pass: which one it is, what sticks and how tall the chain stays.
    try{this.css.fitTexts();this.documentScroll.sync();}finally{this.observeMutations();}
    this.metrics.passes++;
    this.metrics.unlaid=this.unlaid.size;
    this.passed={epoch:this.epoch,resizedAt:this.resizedAt};
    this.onSettled(this.metrics);
    completed=true;
    } finally {
      this.mutations.takeRecords();this.changed=false;this.windowResized=false;
      if(!completed)this.passed=null;
      this.updating=false;
      if(this.updateRequested){this.updateRequested=false;this.schedule();}
    }
  }
  /** Hands the mapper the semantic roots CSS can lay out whole and returns them; a root it cannot is reported. A mutation
   * inside one of those is not the mapper's even where an island holds it. */
  claimCssRoots(roots){
    const claimed=new Set();
    for(const element of this.lastCssRoots||[])if(!roots.includes(element))this.css.release(element);
    const native=this.root.querySelector('[data-native-layout="document"]')!==null;
    const t=this.performanceDiagnostics?performance.now():0;
    this.mutations.disconnect();
    try{
      for(const element of roots){
        // A documentation page's roots are its examples, laid out where the page puts them (`cssRootProposal`), and the
        // roots inside its native widgets; its presentations are the same as an application's.
        const proposal=this.cssRootProposal(element,native);
        if(proposal&&this.css.claimRoot(element,proposal))claimed.add(element);
        else{
          // A root that was an island and no longer qualifies stops being one.
          if(this.css.roots.has(element))this.css.release(element);
          this.refuse(element);
        }
      }
    }finally{this.observeMutations();}
    this.css.setForeign(roots.filter(e=>!claimed.has(e)));
    if(this.performanceDiagnostics)this.metrics.cssMs+=performance.now()-t;
    return claimed;
  }
  /** A semantic root nothing lays out (CSS refuses what it holds, or its container proposes it nothing): counted for the
   * pass and logged once, since the page shows it unplaced. */
  refuse(element){
    // A surface playing its exit (the transition host keeps it in the page, marked leaving) keeps the box it last had.
    if(element.closest('[data-transition-leaving]'))return;
    this.unlaid.add(element);
    if(this.reported.has(element))return;
    this.reported.add(element);
    console.warn('[SwiftUIWeb] no layout for a semantic root: CSS layout cannot lay it out',element.localName+'.'+String(element.className).split(' ')[0]);
  }
  /** What the container of a semantic root proposes it, as `build` works it out, for the roots CSS can be given: the
   * application's root view (the window: the root's width and the viewport's height, centred), the content of a sidebar
   * slot (its width, the content's height, leading; centred in a collapsed rail), a presentation's content (its
   * content box, centred) and an alert's message (its width, the message's height), a subview of a user-defined Layout (what
   * the Layout placed it with), the layout tree of a table cell (its ideal size), of a chart's foreignObject (its box) and
   * of a Grid inside a native widget (the width of its container), and, in a documentation page, an example's preview
   * (its container's width, the example's height). `null` for the others. */
  cssRootProposal(element,native=false){
    const parent=element.parentElement;
    if(!parent)return null;
    // A Grid a native widget hosts (a Form row, a disclosure) is proposed its container's width and chooses its height.
    if(this.orphanSet.has(element))return {def:{x:true,y:false},ax:0,height:'auto',key:'orphan'};
    // An example's preview is proposed its container's width and nothing along the height, and sits at the top, centred.
    if(native&&(element.hasAttribute('data-layout-root')||parent.getAttribute('data-docs-part')==='examples')&&!parent.classList.contains('presentation-content'))return {def:{x:true,y:false},ax:.5,height:'auto',key:'preview'};
    if(parent===this.root){
      if(element.classList.contains('presentation-root')||element.classList.contains('presentation-backdrop'))return null;
      return {def:{x:true,y:true},ax:.5,height:'100dvh',key:'window'};
    }
    // A slot proposes its width; a collapsed rail centres what it keeps of the content (the mapper knows what the
    // stylesheet hides there).
    if(parent.hasAttribute('data-tab-sidebar-content'))return parent.closest('[data-tab-sidebar-expanded="false"]')?{def:{x:true,y:false},ax:.5,height:'auto',key:'rail'}:{def:{x:true,y:false},ax:0,height:'auto',key:'slot'};
    // A NavigationSplitView column proposes its content its content box: the stylesheet makes the column a flex column
    // whose height is definite (the split view's grid row). The compact back button is the stylesheet's.
    if(parent.classList.contains('navigation-column')&&!element.hasAttribute('data-compact-back'))return native?{def:{x:true,y:false},ax:.5,height:'auto',key:'column-document'}:{def:{x:true,y:true},ax:.5,height:'100%',key:'column'};
    // A presentation's content proposes its root its content box (a popover's or an alert's grows with what it holds):
    // the mapper makes the content a one-cell grid, so only a content that holds the root alone.
    if(parent.classList.contains('presentation-content')&&parent.childElementCount===1)return {def:{x:true,y:true},ax:.5,height:'cell',key:'presentation'};
    // An alert's message sits above its actions (the stylesheet's flex row) in the content, which is no grid: the message
    // is proposed the content's width and is as tall as it needs.
    if(parent.classList.contains('presentation-content')&&element.classList.contains('presentation-message'))return {def:{x:true,y:false},ax:.5,height:'auto',key:'message'};
    // A subview of a user-defined Layout is proposed what the Layout placed it with (the mapper reads the sizes).
    if(parent.classList.contains('layout-box')&&parent.hasAttribute('data-layout-proposal')&&element.hasAttribute('data-layout-child-proposal')){
      const [w,h]=element.getAttribute('data-layout-child-proposal').split(',').map(v=>v!=='');
      return {def:{x:w,y:h},ax:0,height:'auto',key:'item'+(w?1:0)+(h?1:0),item:true};
    }
    // A table cell proposes nothing: the content takes its ideal size and the browser sizes the table's columns from it.
    if(/^(TD|TH)$/.test(parent.tagName))return {def:{x:false,y:false},ax:0,height:'auto',key:'cell',ideal:true};
    // The views a chart draws sit in the SVG foreignObject the chart places and are proposed its box (in the chart's
    // coordinates, which the box fills). The box is a flex container Swift justified and aligned for the view (centred
    // against the mark's edge), which places it.
    if(parent.parentElement?.localName==='foreignObject')return {def:{x:true,y:true},ax:.5,height:'100%',key:'foreign',aligned:true};
    // A pane of an HSplitView or VSplitView is proposed the box Swift's split layout gave its item (a one-cell grid): centred across, at the top.
    if(parent.classList.contains('split-item')&&parent.parentElement?.classList.contains('split-pane'))return {def:{x:true,y:true},ax:.5,height:'cell',key:'pane'};
    return null;
  }
  /** Applies the CSS layout mapper's pending islands (its own `data-cl` writes are not recorded as mutations). */
  flushCss(){
    if(!this.css.pending.size){this.css.flush();return;} // forgets islands that left the document
    const t=this.performanceDiagnostics?performance.now():0;
    this.mutations.disconnect();
    try{this.css.flush();}finally{this.observeMutations();}
    // An island the mapper gave up (something it cannot express appeared in it) has no layout any more.
    for(const island of this.css.released)this.refuse(island);
    if(this.performanceDiagnostics)this.metrics.cssMs+=performance.now()-t;
  }
  /** Whether a pass now would find what the last completed pass found: no DOM change since (the records are collected
   * first), no epoch moved (fonts, global attributes), no resize, and nothing pending in the mapper. A page that holds a
   * user-defined Layout always takes the pass: the sizes it reports to Swift (`reportLayouts`) follow the content of its subviews,
   * and a change of a text there is not one the mapper notes (the browser lays text out). */
  unchangedSincePass(){
    const last=this.passed;
    if(!last||this.windowResized||this.changed||this.css.pending.size||this.css.layouts.size)return false;
    return last.epoch===this.epoch&&last.resizedAt===this.resizedAt;
  }
  /** The window changed size: hold CSS transitions off until it settles. */
  markResize(){
    this.resizedAt=performance.now();
    const root=this.document.documentElement;
    if(!root.hasAttribute(RESIZING_ATTRIBUTE))root.setAttribute(RESIZING_ATTRIBUTE,'');
    this.window.clearTimeout(this.resizeTimer);
    this.resizeTimer=this.window.setTimeout(()=>{if(!this.disposed)this.document.documentElement.removeAttribute(RESIZING_ATTRIBUTE);},RESIZE_SETTLE_MS);
  }
  // A control's input event schedules a pass while the host is about to commit the publication that event
  // causes, and the commit runs its own pass. When that commit is pending in this frame the scheduled pass waits
  // a frame; the commit's pass then cancels it (`update`), so a keystroke or a slider step costs one pass, not two.
  schedule(){if(!this.scheduled&&!this.disposed)this.scheduled=this.window.requestAnimationFrame(()=>this.runScheduled());}
  runScheduled(){
    this.scheduled=0;
    if(this.options.commitPending?.()){this.schedule();return;}
    try{this.update();}catch(e){this.onError(e);}
  }
  get pending(){return this.scheduled!==0;}
  dispose(){this.disposed=true;this.abort.abort();this.documentScroll.dispose();this.window.clearTimeout(this.resizeTimer);this.document.documentElement.removeAttribute(RESIZING_ATTRIBUTE);this.mutations.disconnect();this.globals.disconnect();if(this.scheduled)this.window.cancelAnimationFrame(this.scheduled);}
}
