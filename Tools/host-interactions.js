/** Browser capability adapters. Swift owns state; these adapters deliver facts
 * and requests through the Embedded event ABI. No component state library.
 * The presentation coordinator and the drag, share and file mover adapters are in presentation-host.js and transfer-host.js,
 * which embedded-dom.js loads after the first screen; the ones here are part of it: a focus request, a scroll position,
 * the URL and a keyboard shortcut can matter on the first screen or to the first key pressed. */
const targetOf=e=>e?.nodeType===1?e:e?.parentElement;
const disabled=e=>!e||!!e.closest('[disabled],[aria-disabled="true"],[inert]');
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

