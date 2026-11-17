/** SwiftUI presentations in the browser: sheets, covers, popovers, alerts and confirmation dialogs (focus containment,
 * Escape and backdrop dismissal, the page behind made inert, sheet detents dragged by the person).
 * The first screen does not need it: embedded-dom.js loads it with import() once the first publication is on screen
 * (deferred-hosts.js) and then syncs it with what the page shows. This module imports nothing, because a module it shared
 * with the first chunk would become a chunk of its own that the first screen loads; the helpers below are repeated from
 * host-interactions.js for that reason. */
const EVENT='data-embedded-event-id';
const targetOf=e=>e?.nodeType===1?e:e?.parentElement;
const disabled=e=>!e||!!e.closest('[disabled],[aria-disabled="true"],[inert]');
const focusable='button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),summary,[tabindex]:not([tabindex="-1"])';
const visible=e=>e.getClientRects().length&&e.ownerDocument.defaultView.getComputedStyle(e).visibility!=='hidden';
const presentationSelector='.presentation-root,.alert-panel,.confirmation-dialog';

export class PresentationCoordinator {
  // `listenKey(handler, capture)` adds a keydown listener to the document. embedded-dom.js passes one that puts it where the
  // coordinator's listeners always were among the page's own: the page registered those before this module arrived.
  constructor(root,dispatch,{listenKey=null}={}){this.root=root;this.dispatch=dispatch;this.document=root.ownerDocument;this.window=this.document.defaultView;this.abort=new this.window.AbortController();this.active=[];this.records=new Map();this.inert=new Map();this.trace={presenting:0,presented:0,dismissing:0,inactive:0,dismissals:0,focusMoves:0};this.window.__presentationTrace=this.trace;
    listenKey||=(handler,capture)=>this.document.addEventListener('keydown',handler,{capture,signal:this.abort.signal});
    // Tab containment runs in capture; Escape runs in the bubble phase so a
    // focused `onKeyPress(.escape)` or a cancel shortcut can handle it first.
    listenKey(e=>this.key(e),true);
    listenKey(e=>this.escape(e),false);
    this.drag=null;
    // Safari does not focus a button on click, so `activeElement` cannot name the control that presented.
    this.pressed=null;
    root.addEventListener('pointerdown',e=>{this.pressed=targetOf(e.target)?.closest(focusable)||null;},{capture:true,signal:this.abort.signal});
    root.addEventListener('pointerdown',e=>this.detentStart(e),{signal:this.abort.signal});
    this.window.addEventListener('pointermove',e=>this.detentMove(e),{signal:this.abort.signal});
    this.window.addEventListener('pointerup',e=>this.detentEnd(e),{signal:this.abort.signal});
    this.window.addEventListener('pointercancel',()=>this.detentCancel(),{signal:this.abort.signal});
    root.addEventListener('click',e=>{const target=targetOf(e.target),p=this.top();if(!p||!p.contains(target))return;
      const dialog=p.matches('.alert-panel,.confirmation-dialog')||p.querySelector('.alert-panel,.confirmation-dialog');
      if(dialog&&target.closest('button')&&!disabled(target))queueMicrotask(()=>{if(p.isConnected)this.dismiss(p,'action');});
      else if(target===p&&p.getAttribute('data-interactive-dismiss-disabled')!=='true')this.dismiss(p,'backdrop');
    },{signal:this.abort.signal});
  }
  identity(p,index){return p.getAttribute('data-presentation-id')||`${p.getAttribute('data-presentation-owner-id')||'root'}:${p.getAttribute('data-presentation')||'presentation'}:${index}`;}
  top(){return this.active[this.active.length-1]||null;}
  dismiss(p,reason='programmatic'){if(!p)return;const id=p.getAttribute('data-presentation-id');const record=id&&this.records.get(id);if(record){record.phase='dismissing';record.reason=reason;}p.setAttribute('data-presentation-phase','dismissing');p.setAttribute('data-presentation-dismiss-reason',reason);this.trace.dismissals++;const host=p.hasAttribute(EVENT)?p:p.querySelector(`[${EVENT}][data-embedded-events*="presentation-dismiss"]`);if(host)this.dispatch(host,'presentation-dismiss',reason);}
  escape(e){const p=this.top();if(!p||e.defaultPrevented||e.key!=='Escape')return;if(p.getAttribute('data-interactive-dismiss-disabled')!=='true'){e.preventDefault();this.dismiss(p,'escape');}}
  // Presentation detents: the sheet's grabber strip (top 28px) resizes a
  // multi-detent sheet; release snaps to the nearest detent, a click moves to
  // the next larger one. The chosen identifier goes back to Swift, which owns
  // the selection and re-renders the sheet at that detent's height.
  detents(sheet){return (sheet.getAttribute('data-presentation-detent-heights')||'').split(';').filter(Boolean).map(entry=>{const i=entry.indexOf('=');return {id:entry.slice(0,i),css:entry.slice(i+1)};});}
  pixels(css){const probe=this.document.createElement('div');probe.style.cssText='position:fixed;visibility:hidden;pointer-events:none;top:0;left:0;width:1px;height:'+css;this.document.body.append(probe);const value=probe.getBoundingClientRect().height;probe.remove();return value;}
  syncDetent(sheet){
    const source=sheet.querySelector('[data-presentation-detent-height]');if(!source||this.drag?.sheet===sheet)return;
    for(const name of ['data-presentation-detent-selection','data-presentation-detent-heights','data-presentation-detents'])if(source.hasAttribute(name)&&sheet.getAttribute(name)!==source.getAttribute(name))sheet.setAttribute(name,source.getAttribute(name));
    const height=source.getAttribute('data-presentation-detent-height');if(sheet.style.getPropertyValue('--presentation-detent-height')!==height)sheet.style.setProperty('--presentation-detent-height',height);
  }
  detentStart(e){
    const target=targetOf(e.target),sheet=target?.closest?.('.sheet-panel[data-presentation-resizable="true"]');
    if(!sheet||e.button!==0||sheet!==this.top())return;
    // Only a full-width bottom sheet resizes; the wide edge panel ignores detents.
    const box=sheet.getBoundingClientRect();if(e.clientY-box.top>28||box.width<this.window.innerWidth-1)return;
    this.drag={sheet,pointer:e.pointerId,startY:e.clientY,startHeight:box.height,moved:false};
  }
  detentMove(e){const d=this.drag;if(!d||e.pointerId!==d.pointer)return;const dy=e.clientY-d.startY;if(Math.abs(dy)>3)d.moved=true;if(!d.moved)return;e.preventDefault();d.sheet.style.height=Math.max(0,d.startHeight-dy)+'px';}
  detentEnd(e){
    const d=this.drag;if(!d||e.pointerId!==d.pointer)return;this.drag=null;
    const detents=this.detents(d.sheet).map(detent=>({...detent,px:this.pixels(detent.css)})).sort((a,b)=>a.px-b.px);if(!detents.length)return;
    const current=d.sheet.getAttribute('data-presentation-detent-selection');let next;
    if(d.moved){const height=d.sheet.getBoundingClientRect().height;next=detents.reduce((best,detent)=>Math.abs(detent.px-height)<Math.abs(best.px-height)?detent:best);}
    else{const index=detents.findIndex(detent=>detent.id===current);next=detents[(index+1)%detents.length];}
    d.sheet.style.removeProperty('height');d.sheet.style.setProperty('--presentation-detent-height',next.css);
    const host=d.sheet.hasAttribute(EVENT)&&(d.sheet.getAttribute('data-embedded-events')||'').split(',').includes('presentation-detent')?d.sheet:d.sheet.querySelector('['+EVENT+'][data-embedded-events*="presentation-detent"]');
    if(host&&next.id!==current)this.dispatch(host,'presentation-detent',next.id);
  }
  detentCancel(){const d=this.drag;this.drag=null;if(d?.moved)d.sheet.style.removeProperty('height');}
  key(e){const p=this.top();if(!p)return;if(e.key==='Tab'){const nodes=[...p.querySelectorAll(focusable)].filter(visible);if(!nodes.length){e.preventDefault();p.focus();return;}const current=this.document.activeElement,index=nodes.indexOf(current);if(index<0||(e.shiftKey&&index===0)||(!e.shiftKey&&index===nodes.length-1)){e.preventDefault();nodes[e.shiftKey?nodes.length-1:0].focus();}}}
  // The control focus returns to when `p` closes: what had focus when it appeared, else (focus on the body)
  // the control that was pressed to present it. Never an element inside `p`, which closing removes.
  returnTarget(p){const active=this.document.activeElement,pressed=this.pressed;this.pressed=null;
    for(const candidate of [active,pressed])if(candidate&&candidate!==this.document.body&&candidate.isConnected&&!p.contains(candidate))return candidate;return null;}
  focusRequested(scope){const request=[...scope.querySelectorAll('[data-focus-request="true"],[data-focused="true"]')].find(visible);if(request&&this.document.activeElement!==request){request.focus({preventScroll:true});this.trace.focusMoves++;return true;}return false;}
  // Whether a sync can change anything after a commit with these changes. While a presentation is shown the sync holds
  // state it undoes on the next sync (the inert siblings of the top one, each record's phase), and a commit can add to the
  // window root beside it, which the sync must make inert: every commit syncs then. Otherwise the sync reads the presentation
  // elements the patch adds or changes. A presentation that is hidden (its ancestor's change shows it) is found by `watching`.
  needsSync(changes){
    if(changes.everything||this.records.size||this.watching)return true;
    return changes.touches(presentationSelector);
  }
  sync(){
    // A presentation that plays its exit (the transition host keeps it in the page, marked leaving) is already dismissed.
    const candidates=[...this.root.querySelectorAll(presentationSelector)].filter(p=>!p.closest('[data-transition-leaving]')),next=candidates.filter(visible);
    // A candidate that is hidden now (an ancestor hides it) is shown by a change the candidate does not record.
    this.watching=candidates.length>next.length;
    const nextIDs=new Set(next.map((p,index)=>this.identity(p,index))),oldTop=this.top(),oldTopID=oldTop?.getAttribute('data-presentation-id');
    let restoreFocus=oldTopID&&this.records.get(oldTopID)?.focus;
    for(const [id,record] of this.records){if(nextIDs.has(id))continue;record.phase='dismissing';record.reason=record.reason||(!record.element?.isConnected?'owner-removal':'programmatic');this.trace.dismissing++;if(record.element?.isConnected){record.element.setAttribute('data-presentation-phase','dismissing');record.element.setAttribute('data-presentation-dismiss-reason',record.reason);}this.trace.inactive++;this.records.delete(id);}
    this.active=next;
    for(const [index,p] of next.entries()){
      const id=this.identity(p,index);p.setAttribute('data-presentation-id',id);const existing=this.records.get(id);const record=existing||{id,element:p,phase:'presenting',kind:p.getAttribute('data-presentation')||'presentation',owner:p.getAttribute('data-presentation-owner-id')||'root',focus:null,reason:null};record.element=p;this.records.set(id,record);
      if(!existing){record.phase='presenting';p.setAttribute('data-presentation-phase','presenting');this.trace.presenting++;this.window.queueMicrotask(()=>{if(record.element.isConnected&&this.records.get(id)===record&&record.phase==='presenting'){record.phase='presented';record.element.setAttribute('data-presentation-phase','presented');this.trace.presented++;}});}else if(record.phase!=='dismissing'){record.phase='presented';p.setAttribute('data-presentation-phase','presented');}
    }
    // Sheet content re-renders on its own when its detent changes; mirror the
    // semantic detent metadata onto the sheet surface after every commit.
    for(const sheet of next)if(sheet.matches('.sheet-panel'))this.syncDetent(sheet);
    for(const [element,state]of this.inert){element.inert=state.inert;if(state.aria===null)element.removeAttribute('aria-hidden');else element.setAttribute('aria-hidden',state.aria);}this.inert.clear();
    const p=this.top();if(!p){if(restoreFocus?.isConnected)this.window.queueMicrotask(()=>restoreFocus.focus({preventScroll:true}));return;}
    if(!p.hasAttribute('role'))p.setAttribute('role',p.matches('.alert-panel,.confirmation-dialog')?'alertdialog':'dialog');p.setAttribute('aria-modal','true');
    let child=p;for(let parent=p.parentElement;parent;child=parent,parent=parent.parentElement){for(const sibling of parent.children){if(sibling!==child&&!sibling.matches('script,style,[data-measurement-island]')){this.inert.set(sibling,{inert:sibling.inert,aria:sibling.getAttribute('aria-hidden')});sibling.inert=true;sibling.setAttribute('aria-hidden','true');}}if(parent===this.root)break;}
    const topID=p.getAttribute('data-presentation-id');if(oldTop!==p){const record=topID&&this.records.get(topID);if(record&&!record.focus)record.focus=this.returnTarget(p);const focused=this.focusRequested(p);if(!focused){if(!p.hasAttribute('tabindex'))p.tabIndex=-1;const first=[...p.querySelectorAll(focusable)].find(visible);(first||p).focus({preventScroll:true});this.trace.focusMoves++;}}
    else this.focusRequested(p);
  }
  dispose(){this.abort.abort();for(const[e,state]of this.inert){e.inert=state.inert;if(state.aria===null)e.removeAttribute('aria-hidden');else e.setAttribute('aria-hidden',state.aria);}this.inert.clear();this.active=[];this.records.clear();}
}
