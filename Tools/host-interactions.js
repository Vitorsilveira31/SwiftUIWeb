/** Browser capability adapters. Swift owns state; these adapters deliver facts
 * and requests through the Embedded event ABI. No component state library. */
const EVENT='data-embedded-event-id';
const targetOf=e=>e?.nodeType===1?e:e?.parentElement;
const disabled=e=>!e||!!e.closest('[disabled],[aria-disabled="true"],[inert]');
const focusable='button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),summary,[tabindex]:not([tabindex="-1"])';
const visible=e=>e.getClientRects().length&&e.ownerDocument.defaultView.getComputedStyle(e).visibility!=='hidden';
const presentationSelector='.presentation-root,.alert-panel,.confirmation-dialog';
const focusSelector='[data-focus-request="true"],[data-focused="true"]';
const focusAttributes=['data-focus-request','data-focused'];

// FocusedModifier is semantic Swift state, not a browser-only side effect.
// Apply a newly asserted request after each retained-DOM commit, while the
// edge-triggered bookkeeping prevents a persistent focused binding from
// stealing focus back after the user intentionally moves elsewhere.
export class FocusCoordinator {
  constructor(root,{window=root.ownerDocument.defaultView,awaiting=()=>false}={}){this.root=root;this.document=root.ownerDocument;this.window=window;this.awaiting=awaiting;this.previous=null;this.wasPresent=false;this.watching=false;this.trace={focusMoves:0,deferred:0};this.window.__focusCoordinatorTrace=this.trace;}
  sync(){
    // Swift learns of a focus change one event later than the page performs it (a Worker answers later still). A
    // publication that does not yet reflect the last focus event still names the element the person just left:
    // acting on it would pull focus back from the field they moved to (and send the next keystrokes to the old
    // one). Leave focus alone until a publication reflects the event; it carries the request as Swift now holds it.
    if(this.awaiting()){this.trace.deferred++;return false;}
    const candidates=[...this.root.querySelectorAll(focusSelector)];
    const target=candidates.find(visible)||null;
    const present=!!target;
    // A candidate that is not visible now (in a hidden tab, say) becomes visible when an ancestor changes, which no change to
    // the candidate records: the next sync has to see it.
    this.watching=!present&&candidates.length>0;
    if(!present){this.previous=null;this.wasPresent=false;return false;}
    const entered=target!==this.previous||!this.wasPresent;
    this.previous=target;this.wasPresent=true;
    if(!entered||this.document.activeElement===target)return false;
    target.focus({preventScroll:true});this.trace.focusMoves++;return true;
  }
  // Whether a sync can change anything after a commit with these changes. A focus request or a focused control that the
  // patch adds, removes or changes is what the sync reads; a stopped match (an attribute removed from a control that was
  // focused) is found by `changedAttribute`. Two states are not in the patch: a focus event Swift has not yet reflected
  // (the sync clears that wait, so it must run), and a focused control, which an ancestor's change can hide, or a candidate
  // the last sync found hidden: while either holds, every commit syncs, because the sync is what notices the visibility change.
  needsSync(changes){
    if(changes.everything||this.awaiting()||this.wasPresent||this.watching)return true;
    return changes.touches(focusSelector)||changes.changedAttribute(focusAttributes);
  }
  dispose(){if(this.window.__focusCoordinatorTrace===this.trace)delete this.window.__focusCoordinatorTrace;this.previous=null;this.wasPresent=false;}
}

export class ScrollCoordinator {
  constructor(root,{dispatch,ack=()=>{},prepare=()=>false,reducedMotion=()=>false,onError=console.error}) {
    this.root=root;this.document=root.ownerDocument;this.window=this.document.defaultView;
    this.dispatch=dispatch;this.ack=ack;this.prepare=prepare;this.reducedMotion=reducedMotion;this.onError=onError;
    this.states=new Map();this.targets=new Map();this.restoration=new Map();this.pending=new Map();this.completed=new Set();this.frame=0;
    this.trace={saved:0,restored:0,defaultAnchors:0,requests:0,materializationRequests:0,positions:0,animatedPositions:0,userReports:0};
    this.window.__scrollCoordinatorTrace=this.trace;
    this.abort=new this.window.AbortController();
    // Bubble phase: a focused SwiftUI `onKeyPress` handler that returns
    // `.handled` prevents the default and therefore also this scroll.
    this.document.addEventListener('keydown',event=>{if(!event.defaultPrevented)this.keydown(event);},{signal:this.abort.signal});
  }
  hostFor(node){return node?.parentElement?.closest('.scroll-view')||null;}
  registerTargets(host){
    const registry=new Map();
    for(const node of host.querySelectorAll('[data-view-id],[data-view-key],[data-scroll-target-id]')){
      if(this.hostFor(node)!==host)continue;
      for(const attr of ['data-scroll-target-id','data-view-id','data-view-key']){
        const id=node.getAttribute(attr);if(id&&!registry.has(id))registry.set(id,node);
      }
    }
    this.targets.set(host,registry);
  }
  find(id,scope=this.root,readerScope=null){
    if(scope&&this.targets.has(scope))return this.targets.get(scope).get(id)||null;
    return [...scope.querySelectorAll('[data-scroll-target-id],[data-view-id],[data-view-key]')].find(e=>{
      if(readerScope&&e.closest('.scroll-view-reader')?.getAttribute('data-scroll-reader-id')!==readerScope)return false;
      return e.getAttribute('data-scroll-target-id')===id||e.getAttribute('data-view-id')===id||e.getAttribute('data-view-key')===id;
    })||null;
  }
  margins(host){
    if(host.getAttribute('data-content-margins-placement')!=='scrollContent')return {top:0,leading:0,bottom:0,trailing:0};
    const values=(host.getAttribute('data-scroll-content-margins')||'0,0,0,0').split(',').map(Number);
    return {top:Number.isFinite(values[0])?Math.max(0,values[0]):0,leading:Number.isFinite(values[1])?Math.max(0,values[1]):0,bottom:Number.isFinite(values[2])?Math.max(0,values[2]):0,trailing:Number.isFinite(values[3])?Math.max(0,values[3]):0};
  }
  // The scroll position a host was given, keyed by what it names so that a commit which
  // repeats the same target is not applied twice. Value bindings name an ID, an edge, or
  // a point (an empty axis is left alone, as with `scrollTo(x:)`).
  positionRequest(host){
    const animated=host.hasAttribute('data-scroll-position-animated');
    const id=host.getAttribute('data-scroll-position-id'),edge=host.getAttribute('data-scroll-position-edge'),point=host.getAttribute('data-scroll-position-point');
    if(id)return {key:'id:'+id,id,edge:null,point:null,anchor:host.getAttribute('data-scroll-position-anchor'),animated};
    if(edge)return {key:'edge:'+edge,id:null,edge,point:null,anchor:null,animated};
    if(point!==null){const [x,y]=point.split(',');const parse=v=>v===undefined||v===''||!Number.isFinite(Number(v))?null:Number(v);
      return {key:'point:'+point,id:null,edge:null,point:{x:parse(x),y:parse(y)},anchor:null,animated};}
    return null;
  }
  // Every offset the coordinator writes is programmatic, so it cannot count as the user's scroll; it also ends
  // any input window still open from the user's last gesture, so its own scroll events are not misread.
  scrollProgrammatically(host,state,options){
    state.user=false;state.userUntil=0;
    host.scrollTo(options);
  }
  // The offsets an edge or point request names, clamped to the host's scrollable extent. An axis the
  // request leaves unnamed (and an axis the host does not scroll) keeps its current offset.
  offsets(host,request){
    const rtl=this.window.getComputedStyle(host).direction==='rtl';
    const maxX=Math.max(0,host.scrollWidth-host.clientWidth),maxY=Math.max(0,host.scrollHeight-host.clientHeight);
    let left=host.scrollLeft,top=host.scrollTop;
    if(request.edge==='top')top=0;
    else if(request.edge==='bottom')top=maxY;
    else if(request.edge==='leading')left=0;
    else if(request.edge==='trailing')left=rtl?-maxX:maxX;
    else if(request.point){if(request.point.x!==null)left=request.point.x;if(request.point.y!==null)top=request.point.y;}
    // Right-to-left scrollers count negative offsets from their trailing edge; leading stays at zero.
    return {left:rtl?Math.min(0,Math.max(-maxX,left)):Math.max(0,Math.min(maxX,left)),top:Math.max(0,Math.min(maxY,top))};
  }
  axes(host){
    return {horizontal:host.classList.contains('scroll-horizontal')||host.classList.contains('scroll-both'),
      vertical:!host.classList.contains('scroll-horizontal')||host.classList.contains('scroll-both')};
  }
  place(host,request){
    const state=this.states.get(host);if(!state||!host.isConnected||host.getAttribute('data-scroll-disabled')==='true')return false;
    const {horizontal,vertical}=this.axes(host),target=this.offsets(host,request);
    const animated=request.animated&&!this.reducedMotion();
    state.programmatic=animated;
    this.scrollProgrammatically(host,state,{left:horizontal?target.left:host.scrollLeft,top:vertical?target.top:host.scrollTop,behavior:animated?'smooth':'instant'});
    state.position=request.key;this.trace.positions++;if(animated)this.trace.animatedPositions++;
    return true;
  }
  // A placed edge or point holds until the user scrolls: lazily materialized rows grow the scrollable
  // extent after the first placement, so the offset is re-applied once it falls short of the target.
  holds(host,request){
    const {horizontal,vertical}=this.axes(host),target=this.offsets(host,request);
    return (!horizontal||Math.abs(target.left-host.scrollLeft)<=1)&&(!vertical||Math.abs(target.top-host.scrollTop)<=1);
  }
  move(target,anchor,host=this.hostFor(target),animated=false){
    if(!target||!host||!host.contains(target)||host.getAttribute('data-scroll-disabled')==='true')return false;
    const targetAnchor=target.getAttribute('data-scroll-target-anchor');anchor=anchor||targetAnchor;
    const [rawX,rawY]=(anchor||'').split(',').map(Number), explicit=!!anchor;
    const x=Number.isFinite(rawX)?rawX:.5,y=Number.isFinite(rawY)?rawY:.5;
    const a=target.getBoundingClientRect(),b=host.getBoundingClientRect();
    const inset=this.margins(host),viewportWidth=Math.max(0,host.clientWidth-inset.leading-inset.trailing),viewportHeight=Math.max(0,host.clientHeight-inset.top-inset.bottom);
    const dx=a.left-b.left-host.clientLeft-inset.leading,dy=a.top-b.top-host.clientTop-inset.top;
    const nearest=(offset,size,viewport)=>offset<0?offset:offset+size>viewport?offset+size-viewport:0;
    const left=host.scrollLeft+(explicit?dx-(viewportWidth-a.width)*x:nearest(dx,a.width,viewportWidth));
    const top=host.scrollTop+(explicit?dy-(viewportHeight-a.height)*y:nearest(dy,a.height,viewportHeight));
    const horizontal=host.classList.contains('scroll-horizontal')||host.classList.contains('scroll-both');
    const vertical=!host.classList.contains('scroll-horizontal')||host.classList.contains('scroll-both');
    const state=this.states.get(host);if(state)state.programmatic=animated&&!this.reducedMotion();
    this.scrollProgrammatically(host,state,{left:horizontal?Math.max(0,Math.min(host.scrollWidth-host.clientWidth,left)):host.scrollLeft,top:vertical?Math.max(0,Math.min(host.scrollHeight-host.clientHeight,top)):host.scrollTop,behavior:animated&&!this.reducedMotion()?'smooth':'instant'});
    return true;
  }
  keydown(event){
    const target=event.target?.nodeType===1?event.target:event.target?.parentElement,host=target?.closest?.('.scroll-view');
    if(!host)return;
    const key=event.key,editable=target?.matches?.('input,textarea,select,[contenteditable="true"]');
    const relevant=['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','PageUp','PageDown','Home','End',' '].includes(key);
    if(!relevant||editable)return;
    if(host.getAttribute('data-scroll-disabled')==='true'){event.preventDefault();return;}
    const horizontal=host.classList.contains('scroll-horizontal')||host.classList.contains('scroll-both');
    const vertical=!host.classList.contains('scroll-horizontal')||host.classList.contains('scroll-both');
    let dx=0,dy=0;
    if(key==='ArrowUp')dy=-40; else if(key==='ArrowDown')dy=40; else if(key==='ArrowLeft')dx=-40; else if(key==='ArrowRight')dx=40;
    else if(key==='PageUp')dy=-host.clientHeight; else if(key==='PageDown'||key===' ')dy=host.clientHeight;
    else if(key==='Home')dy=-host.scrollTop; else if(key==='End')dy=host.scrollHeight-host.clientHeight-host.scrollTop;
    if((dx&&horizontal)||(dy&&vertical)){event.preventDefault();const state=this.states.get(host);if(state){state.user=true;state.userUntil=this.window.performance.now()+500;}host.scrollBy({left:horizontal?dx:0,top:vertical?dy:0,behavior:'instant'});}
  }
  observe(host){
    if(this.states.has(host))return;
    const controller=new this.window.AbortController(),id=host.getAttribute('data-scroll-id')||host.getAttribute('data-view-id')||'',state={controller,id,last:'',phase:'idle',timer:0,programmatic:false,user:false,dismissed:null,gesture:false,userUntil:0,frame:0,initialized:false,position:null};this.states.set(host,state);
    const phase=value=>{if(value!==state.phase){state.phase=value;if(host.hasAttribute('data-scroll-phase-change'))this.dispatch(host,'scrollPhase',value);}};
    const measure=()=>{state.frame=0;if(!host.isConnected)return;
      // A scroller without a layout box (inactive tab panel) reports zeros; keep the
      // last geometry so hiding and showing it does not re-render its screen twice.
      if(host.getClientRects().length===0)return;const x=host.scrollLeft,y=host.scrollTop,w=host.clientWidth,h=host.clientHeight;const raw=[x,y,host.scrollWidth,host.scrollHeight,w,h,x,y,w,h].map(n=>Math.round(n*64)/64).join(',');if(raw!==state.last){state.last=raw;if(host.hasAttribute('data-scroll-geometry-change'))this.dispatch(host,'scrollGeometry',raw);}};
    const reportPosition=()=>{
      if(!host.isConnected||!host.hasAttribute('data-scroll-position'))return;
      const box=host.getBoundingClientRect();
      const horizontal=host.classList.contains('scroll-horizontal');
      const candidates=[...host.querySelectorAll('[data-view-id]')].filter(n=>this.hostFor(n)===host);
      let best=null,distance=Infinity;
      for(const node of candidates){const b=node.getBoundingClientRect();if(b.right<=box.left||b.left>=box.right||b.bottom<=box.top||b.top>=box.bottom)continue;
        const d=Math.abs(horizontal?b.left-box.left-host.clientLeft:b.top-box.top-host.clientTop);
        if(d<distance){best=node;distance=d;}}
      const id=best?.getAttribute('data-view-id');
      if(id&&state.position!=='id:'+id){state.position='id:'+id;this.dispatch(host,'scrollPosition',id);}
    };
    const update=()=>{if(!state.frame)state.frame=this.window.requestAnimationFrame(measure);};
    host.addEventListener('scroll',()=>{update();
      // A scroll the user's input started (pointer or touch on the surface, a wheel, a key the surface handles) is the
      // user's. Scrolls nothing started are layout: lazy rows and remounts move offsets without input.
      if(state.gesture||this.window.performance.now()<state.userUntil)state.user=true;if(state.id){this.restoration.set(state.id,{left:host.scrollLeft,top:host.scrollTop});this.trace.saved++;}phase(state.programmatic?'animating':'interacting');this.window.clearTimeout(state.timer);state.timer=this.window.setTimeout(()=>{state.programmatic=false;phase('idle');const user=state.user;state.user=false;
      // A value binding hears only the scrolls the user made; programmatic ones keep the value the program set.
      if(host.getAttribute('data-scroll-position-mode')==='value'){if(user&&host.isConnected){this.trace.userReports++;state.dismissed=state.position;state.position=null;this.dispatch(host,'scrollPositionUser','');}}else reportPosition();},140);},{passive:true,signal:controller.signal});
    for(const type of ['pointerdown','touchstart'])host.addEventListener(type,()=>{state.programmatic=false;state.gesture=true;},{passive:true,signal:controller.signal});
    host.addEventListener('wheel',()=>{state.programmatic=false;state.user=true;state.userUntil=this.window.performance.now()+500;},{passive:true,signal:controller.signal});
    host.addEventListener('touchmove',()=>{state.userUntil=this.window.performance.now()+500;},{passive:true,signal:controller.signal});
    for(const type of ['pointerup','pointercancel','touchend','touchcancel'])this.window.addEventListener(type,()=>{state.gesture=false;},{passive:true,signal:controller.signal});
    state.observer=new this.window.ResizeObserver(update);state.observer.observe(host);update();
  }
  // Whether a sync can change anything after a commit with these changes. The sync reads the scroll views and their position
  // attributes, the scroll requests, and what it kept from earlier syncs. A request still pending waits for content or a
  // target that a later commit brings, and a position that holds an edge or a point is re-applied once the content it
  // scrolls grows (a commit that adds rows, or a text that grows, which the changes do not record): both run every commit.
  // A tracked host that stops being a scroll view (its class changed) is not matched by `touches`, so a class change while
  // a host is tracked also syncs.
  needsSync(changes){
    if(changes.everything||this.pending.size)return true;
    // A host's position request is applied when it differs from the position the host recorded. Scroll events record a position
    // without a commit (a user's scroll reported as `id:`, a dismissal), so the sync can have work the patch did not touch:
    // compare each tracked host's request with its recorded state, as the sync does.
    for(const [host,state] of this.states){
      const request=this.positionRequest(host);
      if(request?request.key!==state.position&&request.key!==state.dismissed:(state.position!==null||state.dismissed!==null))return true;
    }
    for(const state of this.states.values())if(state.position!==null&&!state.position.startsWith('id:'))return true;
    if(changes.touches('.scroll-view')||changes.touches('[data-embedded-scroll-id]'))return true;
    return this.states.size>0&&changes.changedAttribute(['class']);
  }
  sync(){
    const hosts=[...this.root.querySelectorAll('.scroll-view')];
    for(const host of hosts)this.registerTargets(host);
    for(const [host,state] of this.states)if(!host.isConnected){if(state.id){this.restoration.set(state.id,{left:host.scrollLeft,top:host.scrollTop});this.trace.saved++;}state.controller.abort();state.observer.disconnect();this.window.clearTimeout(state.timer);this.window.cancelAnimationFrame(state.frame);this.states.delete(host);this.targets.delete(host);}
    for(const host of hosts)this.observe(host);
    for(const host of hosts){const state=this.states.get(host);if(!state||state.initialized)continue;const restored=state.id&&this.restoration.get(state.id);if(restored){this.scrollProgrammatically(host,state,{left:restored.left,top:restored.top,behavior:'instant'});this.trace.restored++;}else{const anchor=host.getAttribute('data-default-scroll-anchor')||host.getAttribute('data-scroll-position-initial-anchor');if(anchor&&host.scrollHeight>host.clientHeight){const [x,y]=anchor.split(',').map(Number);this.scrollProgrammatically(host,state,{left:Number.isFinite(x)?(host.scrollWidth-host.clientWidth)*x:0,top:Number.isFinite(y)?(host.scrollHeight-host.clientHeight)*y:0,behavior:'instant'});this.trace.defaultAnchors++;}}state.initialized=true;}
    for(const request of this.root.querySelectorAll('[data-embedded-scroll-id]')){
      const id=request.getAttribute('data-embedded-scroll-id'),seq=Number(request.getAttribute('data-embedded-scroll-sequence'));
      if(!Number.isInteger(seq)||seq<=0)continue;
      const key='request:'+seq;if(this.completed.has(key))continue;
      this.pending.set(key,{id,seq,scope:request.getAttribute('data-embedded-scroll-scope'),anchor:request.getAttribute('data-embedded-scroll-anchor'),animated:request.hasAttribute('data-animation-transaction'),attempts:this.pending.get(key)?.attempts||0});
    }
    for(const host of hosts){const state=this.states.get(host),request=this.positionRequest(host);
      if(!request){state.position=null;state.dismissed=null;this.pending.delete(host);continue;}
      // The user's report already dismissed this target; the binding's update removes it from the host.
      if(request.key===state.dismissed)continue;
      state.dismissed=null;
      if(state.position===request.key){
        this.pending.delete(host);
        if(request.id===null&&!state.user&&!state.programmatic&&!this.holds(host,request))this.place(host,request);
        continue;
      }
      // Edges and points need no content to materialize: they apply now, as SwiftUI's do.
      if(request.id===null){this.pending.delete(host);this.place(host,request);continue;}
      this.pending.set(host,{...request,host,attempts:this.pending.get(host)?.attempts||0});
    }
    for(const [key,request] of this.pending){
      const node=this.find(request.id,request.host||this.root,request.scope);
      if(node&&this.move(node,request.anchor,request.host||this.hostFor(node),request.animated)){
        if(request.seq){this.completed.add(key);this.ack(request.seq);if(this.completed.size>128)this.completed.delete(this.completed.values().next().value);}else{this.states.get(request.host).position=request.key;this.trace.positions++;if(request.animated)this.trace.animatedPositions++;}
        this.pending.delete(key);
      }else if(!node&&request.attempts<8){request.attempts++;this.trace.materializationRequests++;this.prepare(request.id);}
      // Missing targets remain pending across commits. Never acknowledge an
      // unexecuted request, and never fall back to scrolling the document.
    }
  }
  dispose(){this.abort.abort();for(const state of this.states.values()){state.controller.abort();state.observer.disconnect();this.window.clearTimeout(state.timer);this.window.cancelAnimationFrame(state.frame);}this.states.clear();this.targets.clear();this.pending.clear();this.restoration.clear();}
}

// Browser-side matching for SwiftUI `keyboardShortcut`. Swift publishes the
// shortcut as `data-keyboard-shortcut="key|modifiers"` on the control's
// activation element; a match clicks that element so the ordinary click
// ABI runs the SwiftUI action. `.command` is Meta on Apple platforms and Ctrl
// elsewhere. Only the topmost presentation (or the window when nothing is
// presented) is searched, and disabled/hidden/inert controls never fire.
export class KeyboardShortcutCoordinator {
  constructor(root,{presentations=()=>null,window=root.ownerDocument.defaultView}={}){
    this.root=root;this.window=window;this.presentations=presentations;this.abort=new window.AbortController();this.trace={triggered:0};
    const nav=window.navigator||{};this.apple=/Mac|iPhone|iPad|iPod/.test(nav.platform||'')||/mac|ios/i.test(nav.userAgentData?.platform||'');
    window.__keyboardShortcutTrace=this.trace;
    // Bubble phase at the document: focused handlers (onKeyPress/onKeyDown)
    // see the key first and may prevent it.
    root.ownerDocument.addEventListener('keydown',event=>this.keydown(event),{signal:this.abort.signal});
  }
  scope(){return this.presentations()||this.root;}
  names(event){
    const key=event.key===' '?'Space':event.key==='NumpadEnter'?'Enter':event.key||'';
    const names=new Set([key.length===1?key.toLowerCase():key]);
    const code=/^Key([A-Z])$/.exec(event.code||'')||/^Digit(\d)$/.exec(event.code||'');
    if(code)names.add(code[1].toLowerCase());
    return names;
  }
  modifiersMatch(event,tokens){
    const wants=new Set(tokens.split(',').filter(Boolean));
    const ctrl=wants.has('control')||(!this.apple&&wants.has('command')), meta=this.apple&&wants.has('command');
    return event.ctrlKey===ctrl&&event.metaKey===meta&&event.altKey===wants.has('option')&&event.shiftKey===wants.has('shift');
  }
  allowed(event,key,tokens){
    const target=targetOf(event.target);if(!target)return true;
    const modified=/command|control|option/.test(tokens);
    if(target.matches?.('input,textarea,select,[contenteditable=""],[contenteditable="true"]')||target.isContentEditable){
      if(modified||key==='Escape')return true;
      return key==='Enter'&&target.localName==='input';
    }
    if(!modified&&(key==='Space'||key==='Enter')&&target.closest?.('button,a[href],summary,[role="button"],[role="radio"],[role="tab"],input'))return false;
    return true;
  }
  candidates(){
    const scope=this.scope();
    const owner=scope===this.root?null:scope;
    // A control belongs to its nearest presentation; only the topmost
    // presentation's controls (or the window's, when none) are active.
    return [...scope.querySelectorAll('[data-keyboard-shortcut]')].filter(element=>!disabled(element)&&visible(element)&&(element.closest(presentationSelector)||null)===owner);
  }
  find(event){
    if(event.isComposing)return null;
    const names=this.names(event);
    for(const element of this.candidates()){
      const [key='',tokens='']=(element.getAttribute('data-keyboard-shortcut')||'').split('|');
      if(names.has(key)&&this.modifiersMatch(event,tokens)&&this.allowed(event,key,tokens))return element;
    }
    // Alerts and confirmation dialogs map Escape to their cancel-role button.
    const scope=this.presentations();
    if(scope&&event.key==='Escape'&&!event.ctrlKey&&!event.metaKey&&!event.altKey&&!event.shiftKey&&scope.matches('.alert-panel,.confirmation-dialog')){
      return [...scope.querySelectorAll('button[data-role="cancel"]')].find(element=>!disabled(element)&&visible(element))||null;
    }
    return null;
  }
  keydown(event){
    if(event.defaultPrevented||event.repeat&&event.key==='Enter')return;
    const element=this.find(event);if(!element)return;
    event.preventDefault();this.trace.triggered++;element.click();
  }
  dispose(){this.abort.abort();if(this.window.__keyboardShortcutTrace===this.trace)delete this.window.__keyboardShortcutTrace;}
}

export class PresentationCoordinator {
  constructor(root,dispatch){this.root=root;this.dispatch=dispatch;this.document=root.ownerDocument;this.window=this.document.defaultView;this.abort=new this.window.AbortController();this.active=[];this.records=new Map();this.inert=new Map();this.trace={presenting:0,presented:0,dismissing:0,inactive:0,dismissals:0,focusMoves:0};this.window.__presentationTrace=this.trace;
    // Tab containment runs in capture; Escape runs in the bubble phase so a
    // focused `onKeyPress(.escape)` or a cancel shortcut can handle it first.
    this.document.addEventListener('keydown',e=>this.key(e),{capture:true,signal:this.abort.signal});
    this.document.addEventListener('keydown',e=>this.escape(e),{signal:this.abort.signal});
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

export async function shareContent(element,navigator=globalThis.navigator){
  const item=element.getAttribute('data-share-item')||'',title=element.getAttribute('data-share-subject')||undefined,message=element.getAttribute('data-share-message')||undefined;
  let url;try{const parsed=new URL(item);if(['https:','http:'].includes(parsed.protocol))url=parsed.href;}catch{}
  const data={...(title?{title}:{}),...(url?{url}:{}),...((message||!url)?{text:message||item}:{})};
  if(navigator.share&&(!navigator.canShare||navigator.canShare(data))){try{await navigator.share(data);return {status:'shared'};}catch(error){if(error?.name==='AbortError')return {status:'cancelled'};if(!['NotAllowedError','NotSupportedError','TypeError'].includes(error?.name))throw error;}}
  if(navigator.clipboard?.writeText){await navigator.clipboard.writeText([message,item].filter(Boolean).join('\n'));return {status:'copied'};}
  // A meaningful result is exposed to the host instead of silently succeeding.
  return {status:'unsupported',text:[message,item].filter(Boolean).join('\n')};
}

export class HistoryCoordinator {
  constructor(root,{restore,ack,onLocation=()=>{},onPop=()=>{},onRoot=()=>{},window=root.ownerDocument.defaultView}){
    this.root=root;this.window=window;this.restore=restore;this.ack=ack;this.onLocation=onLocation;this.onPop=onPop;this.onRoot=onRoot;this.last=0;this.waiting=false;this.queue=[];this.bases=new Map();this.hydrated=false;this.hydrating=false;this.abort=new window.AbortController();
    window.addEventListener('popstate',event=>{const entry=event.state?.swuiNavigation;if(entry?.key){this.restore(entry.key);this.onPop(entry);if(entry.depth===0)this.onRoot(entry);}else {this.hydrating=true;this.onPop(null);this.onLocation();}this.waiting=false;this.drain();},{signal:this.abort.signal});
  }
  // Whether a sync can change anything after a commit with these changes. The sync reads only the operations a publication
  // names (`data-history-operations`, a JSON list that grows by sequence), and the first sync replays the URL. Popstate is
  // handled by its own listener, not by a sync. Queued operations are drained by a sync, so a non-empty queue syncs too.
  needsSync(changes){
    if(changes.everything||!this.hydrated||this.queue.length)return true;
    return changes.touches('[data-history-operations]')||changes.changedAttribute(['data-history-operations']);
  }
  sync(){
    if(!this.hydrated){
      this.hydrated=true;
      // A reload keeps `history.state`, but the Swift session and its typed
      // adapter are new objects.  Always replay the current URL on the first
      // sync so a tab/deep-link selection is restored even when the browser
      // retained an old `swuiNavigation` record.  `drain()` replaces the
      // matching entry instead of pushing a duplicate.
      this.hydrating=true;
      this.onLocation();
    }
    const host=this.root.querySelector('[data-history-operations]');if(!host)return;let operations;try{operations=JSON.parse(host.getAttribute('data-history-operations'));}catch{throw new Error('Invalid Swift navigation history payload');}for(const op of operations){if(op.sequence<=this.last)continue;this.last=op.sequence;this.queue.push(op);}this.drain();
  }
  drain(){while(!this.waiting&&this.queue.length){const op=this.queue.shift(),w=this.window,h=w.history;let base=this.bases.get(op.adapter);if(!base){base=w.location.pathname+w.location.search+w.location.hash;this.bases.set(op.adapter,base);h.replaceState({...h.state,swuiNavigation:{adapter:op.adapter,key:op.rootKey,depth:0}},'',base);}
      const url=new URL(op.path==='/'?base:op.path,w.location.href);if(url.origin!==w.location.origin)throw new Error('Navigation must remain same-origin');
      const state={...h.state,swuiNavigation:{adapter:op.adapter,key:op.key,depth:op.depth}};
      if(op.kind==='back'){const current=h.state?.swuiNavigation;const distance=Math.max(1,op.oldDepth-op.depth);if(current?.adapter===op.adapter&&current.depth>=distance){this.waiting=true;h.go(-distance);}else h.replaceState(state,'',url.pathname+url.search+url.hash);}
      else if(op.kind==='push'){
        const target=url.pathname+url.search+url.hash, current=w.location.pathname+w.location.search+w.location.hash;
        // A deep link/reload is hydrated through openURL. The first Swift
        // update acknowledges that same URL instead of adding a duplicate.
        if(this.hydrating && target===current){h.replaceState(state,'',target);}else h.pushState(state,'',target);
        this.hydrating=false;
      }
      else if(op.kind==='replace')h.replaceState(state,'',url.pathname+url.search+url.hash);
      else throw new Error('Unknown Swift navigation history operation');this.ack(op.sequence);
    }}
  dispose(){this.abort.abort();this.queue=[];}
}

const mimeForType = type => ({'public.plain-text':'text/plain','public.utf8-plain-text':'text/plain','public.text':'text/*','public.url':'text/uri-list','public.html':'text/html','public.json':'application/json','public.png':'image/png','public.jpeg':'image/jpeg','public.image':'image/*','public.data':'*/*','public.item':'*/*','public.content':'*/*'}[type] || type);
const toBase64 = bytes => {let text='';for(let i=0;i<bytes.length;i+=32768)text+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(text);};
export class NativeDragDropCoordinator {
  constructor(root,dispatch){this.root=root;this.dispatch=dispatch;this.window=root.ownerDocument.defaultView;this.abort=new this.window.AbortController();this.targeted=new Set();this.encoder=new TextEncoder();
    const listen=(name,handler)=>root.addEventListener(name,handler,{signal:this.abort.signal});
    listen('dragstart',event=>{const source=targetOf(event.target)?.closest('[data-drag-source]');if(!source||disabled(source)||!event.dataTransfer)return;
      const text=source.getAttribute('data-embedded-drag-text');
      if(text===null)return; // Never manufacture a Transferable from rendered labels.
      event.dataTransfer.setData('text/plain',text);event.dataTransfer.effectAllowed='copyMove';
      this.dispatch(source,'embeddedDragStarted','');});
    listen('dragenter',e=>this.enter(e));listen('dragover',e=>this.enter(e));
    listen('dragleave',e=>{const target=this.target(e);if(target&&!target.contains(targetOf(e.relatedTarget)))this.mark(target,false);});
    listen('dragend',()=>this.clear());listen('drop',e=>{this.drop(e).catch(error=>{this.clear();this.window.dispatchEvent(new this.window.CustomEvent('drop-failure',{detail:String(error)}));});});
  }
  target(event){const node=targetOf(event.target)?.closest('[data-drop-target]');return node&&this.root.contains(node)&&!disabled(node)?node:null;}
  accepts(target,mime){const types=(target.getAttribute('data-drop-types')||'public.data').split(',').map(mimeForType);return types.some(type=>type==='*/*'||type===mime||type.endsWith('/*')&&mime.startsWith(type.slice(0,-1)));}
  eligible(target,data){return [...(data?.types||[])].some(type=>type==='Files'||this.accepts(target,type));}
  mark(target,active){if(this.targeted.has(target)===active)return;active?this.targeted.add(target):this.targeted.delete(target);if(target.isConnected)this.dispatch(target,'embeddedDropTargeted',String(active));}
  clear(){for(const target of [...this.targeted])this.mark(target,false);}
  enter(event){const target=this.target(event);if(!target||!this.eligible(target,event.dataTransfer))return;event.preventDefault();if(event.dataTransfer)event.dataTransfer.dropEffect=event.dataTransfer.effectAllowed==='copy'?'copy':'move';this.mark(target,true);}
  async drop(event){const target=this.target(event),data=event.dataTransfer;if(!target||!data||!this.eligible(target,data))return;
    event.preventDefault();const box=target.getBoundingClientRect(),x=event.clientX-box.left,y=event.clientY-box.top;
    const identity=target.getAttribute(EVENT),files=[...data.files];
    // Read the protected DataTransfer store synchronously before any await.
    const strings=[...data.types].filter(type=>type!=='Files'&&this.accepts(target,type)).map(type=>({type,text:data.getData(type)}));
    const payloads=[];let total=0;const limit=16*1024*1024;
    for(const file of files){const type=file.type||'application/octet-stream';if(!this.accepts(target,type))continue;total+=file.size;if(total>limit)throw new Error('Drop payload exceeds 16 MiB');payloads.push({type,name:file.name,bytes:new Uint8Array(await file.arrayBuffer())});}
    for(const value of strings){const bytes=this.encoder.encode(value.text);total+=bytes.length;if(total>limit)throw new Error('Drop payload exceeds 16 MiB');payloads.push({type:value.type,name:'',bytes});}
    this.clear();if(!payloads.length||!target.isConnected||target.getAttribute(EVENT)!==identity)return;
    const rows=payloads.map(p=>[toBase64(this.encoder.encode(p.type)),toBase64(this.encoder.encode(p.name)),toBase64(p.bytes)].join('\t'));
    this.dispatch(target,'embeddedDrop',`v2:${x},${y}\n${rows.join('\n')}`);
  }
  dispose(){this.abort.abort();this.clear();}
}

// SwiftUI `fileMover`. `entries` are `{name,type,bytes}`; the result is the string the Swift modifier decodes:
// `moved:<id>,<base64 name>;...` (written into the chosen location through the File System Access API, so the
// app may drop its copies), `downloaded:<n>` (only copies were handed out, the sources stay), `cancelled` or
// `error:<message>`. The picker is opened before any `await` so it runs inside the user activation of the click
// that presented it, in main-thread and worker mode alike (the worker only sends the presentation back).
const fileHandleDatabase='swui:file-handles';
const utf8Base64=text=>{const bytes=new TextEncoder().encode(text);let binary='';for(const byte of bytes)binary+=String.fromCharCode(byte);return btoa(binary);};
function fileHandleStore(env,mode,run){
  return new Promise((resolve,reject)=>{
    if(!env.indexedDB){reject(new Error('IndexedDB is unavailable'));return;}
    const request=env.indexedDB.open(fileHandleDatabase,1);
    request.onupgradeneeded=()=>{request.result.createObjectStore('handles');};
    request.onerror=()=>reject(request.error);
    request.onsuccess=()=>{
      const db=request.result;
      try{
        const tx=db.transaction('handles',mode),result=run(tx.objectStore('handles'));
        tx.oncomplete=()=>{db.close();resolve(result?.result);};
        tx.onerror=tx.onabort=()=>{db.close();reject(tx.error);};
      }catch(error){db.close();reject(error);}
    };
  });
}
async function uniqueFileHandle(directory,name){
  const dot=name.lastIndexOf('.'),stem=dot>0?name.slice(0,dot):name,extension=dot>0?name.slice(dot):'';
  for(let index=1;;index+=1){
    const candidate=index===1?name:`${stem} ${index}${extension}`;
    try{await directory.getFileHandle(candidate);}catch(error){if(error?.name==='NotFoundError')return {name:candidate,handle:await directory.getFileHandle(candidate,{create:true})};throw error;}
  }
}
async function writeFileHandle(handle,bytes){const writable=await handle.createWritable();try{await writable.write(bytes);await writable.close();}catch(error){try{await writable.abort?.();}catch{}throw error;}}
function newFileId(env){return 'moved-'+(env.crypto?.randomUUID?.()??`${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`);}
async function downloadFiles(entries,env){
  const doc=env.document;
  for(const [index,entry] of entries.entries()){
    const url=env.URL.createObjectURL(new env.Blob([entry.bytes],{type:entry.type||'application/octet-stream'})),a=doc.createElement('a');
    a.href=url;a.download=entry.name;a.style.display='none';doc.body.appendChild(a);a.click();a.remove();
    env.setTimeout(()=>env.URL.revokeObjectURL(url),1000);
    if(index+1<entries.length)await new Promise(resolve=>env.setTimeout(resolve,150));
  }
  return `downloaded:${entries.length}`;
}
export function moveFiles(entries,env=globalThis){
  if(!entries.length)return Promise.resolve('cancelled');
  if(entries.some(entry=>!entry.bytes))return Promise.resolve('error:One or more files are not held in browser memory and cannot be moved');
  const useDirectory=typeof env.showDirectoryPicker==='function',useSave=!useDirectory&&entries.length===1&&typeof env.showSaveFilePicker==='function';
  if(!useDirectory&&!useSave)return downloadFiles(entries,env).catch(error=>`error:${error?.message||error}`);
  let picked;
  try{picked=useDirectory?env.showDirectoryPicker({id:'file-mover',mode:'readwrite'}):env.showSaveFilePicker({suggestedName:entries[0].name});}
  catch(error){picked=Promise.reject(error);}
  return (async()=>{
    const written=[];let directory=null;
    try{
      const target=await picked,results=[];
      if(useDirectory){
        directory=target;
        for(const entry of entries){const {name,handle}=await uniqueFileHandle(directory,entry.name);written.push(name);await writeFileHandle(handle,entry.bytes);results.push({name,handle,entry});}
      }else{await writeFileHandle(target,entries[0].bytes);results.push({name:target.name||entries[0].name,handle:target,entry:entries[0]});}
      for(const result of results){
        result.id=newFileId(env);
        // Best effort: a browser that cannot store handles still moved the file.
        try{await fileHandleStore(env,'readwrite',store=>store.put({handle:result.handle,name:result.name,type:result.entry.type},result.id));}catch{}
      }
      return 'moved:'+results.map(result=>`${result.id},${utf8Base64(result.name)}`).join(';');
    }catch(error){
      if(directory)for(const name of written)try{await directory.removeEntry(name);}catch{}
      if(error?.name==='AbortError')return 'cancelled';
      return `error:${error?.message||error}`;
    }
  })();
}
// Reopens a file written by `moveFiles` in a later session; the browser may ask the person to grant access again.
export async function reopenMovedFile(id,env=globalThis){
  const record=await fileHandleStore(env,'readonly',store=>store.get(id));
  if(!record?.handle)return null;
  const handle=record.handle;
  if(handle.queryPermission&&await handle.queryPermission({mode:'read'})!=='granted'&&await handle.requestPermission?.({mode:'read'})!=='granted')return null;
  const file=await handle.getFile();
  return {name:record.name,type:record.type||file.type,bytes:new Uint8Array(await file.arrayBuffer())};
}
