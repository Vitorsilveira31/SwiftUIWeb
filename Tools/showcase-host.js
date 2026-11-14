/** Optional documentation plugin. Page names are emitted by the Swift app;
 * the framework renderer has no knowledge of Showcase sections or breakpoints.
 */
export function mountShowcaseHost(root, {dispatchNamed, window, document}) {
  const abort=new window.AbortController(), compact=window.matchMedia('(max-width: 999px)');
  let initialized=false, restoring=false, previousOpen=false, lastFocus=null, backdrop=null, owed=null, owedSyncs=0;
  const routes=new Set(), savedInert=new Map();
  const shell=()=>root.querySelector('[data-native-layout="document"]');
  const sidebar=()=>root.querySelector('[data-docs-part="sidebar"]');
  const toggle=()=>root.querySelector('[data-docs-part="menu-toggle"]');
  const close=()=>root.querySelector('[data-docs-part="drawer-close"]')?.click();
  const route=()=>root.querySelector('[data-docs-route][aria-current="page"]')?.getAttribute('data-docs-route');
  const openPath=path=>{const target=root.querySelector('[data-open-url-handler]');if(target)dispatchNamed(target,'openURL',path);};
  function fromLocation(){
    const path=window.location.pathname.replace(/\/$/,'')||'/';
    // Typed NavigationStack entries (depth above zero) are restored by the framework history adapter, not by resetting
    // the documentation section's bound path. A depth-zero entry is a plain route: its section is switched here and the
    // adapter restores the empty stack.
    if(window.history.state?.swuiNavigation?.depth>0)return;
    // The first render already shows the route the address names (the app reads it from the environment), so only a
    // different current route needs the navigation.
    if(routes.has(path)&&route()!==path){restoring=true;openPath(path);queueMicrotask(()=>{restoring=false;});}
  }
  function drawer(){
    const panel=sidebar(), button=toggle();if(!panel||!button)return;
    const open=compact.matches&&panel.getAttribute('data-docs-drawer')==='open';
    panel.inert=compact.matches&&!open;button.setAttribute('aria-expanded',String(open));
    if(open===previousOpen)return;
    previousOpen=open;
    if(open){
      // WebKit does not focus a button on click, so activeElement can be the body: the toggle that opened the drawer is where focus returns.
      lastFocus=document.activeElement&&document.activeElement!==document.body&&document.activeElement!==document.documentElement?document.activeElement:button;document.documentElement.setAttribute('data-docs-drawer-open','');
      backdrop=document.createElement('div');backdrop.setAttribute('data-docs-part','backdrop');backdrop.setAttribute('aria-hidden','true');
      backdrop.addEventListener('click',close,{signal:abort.signal});document.body.append(backdrop);
      for(const element of root.querySelectorAll('[data-docs-part="main"],[data-docs-part="toc"]')){savedInert.set(element,element.inert);element.inert=true;}
      panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');panel.setAttribute('aria-label','Documentation topics');
      queueMicrotask(()=>panel.querySelector('button,input,a[href]')?.focus({preventScroll:true}));
    }else{
      document.documentElement.removeAttribute('data-docs-drawer-open');backdrop?.remove();backdrop=null;
      for(const [element,inert] of savedInert)if(element.isConnected)element.inert=inert;savedInert.clear();
      panel.removeAttribute('role');panel.removeAttribute('aria-modal');
      if(lastFocus?.isConnected)lastFocus.focus({preventScroll:true});lastFocus=null;
    }
  }
  root.addEventListener('click',event=>{
    if(event.defaultPrevented||event.ctrlKey||event.metaKey||event.altKey||event.shiftKey||event.button!==0)return;
    const link=event.target.closest?.('[data-docs-route]');if(!link||link.closest('[disabled],[aria-disabled="true"],[inert]'))return;
    const path=link.getAttribute('data-docs-route');if(!routes.has(path))return;
    if(link.localName==='a')event.preventDefault();
    if(!restoring&&window.location.pathname!==path)window.history.pushState({swuiDocs:path},'',path);
    // Native button action remains owned by Swift. Links additionally dispatch
    // openURL instead of relying on a second client-side application state.
    if(link.localName==='a')openPath(path);
    if(compact.matches&&previousOpen)queueMicrotask(close);
    window.scrollTo({top:0,left:0,behavior:'instant'});
  },{signal:abort.signal});
  document.addEventListener('keydown',event=>{
    if(!previousOpen)return;
    if(event.key==='Escape'){event.preventDefault();event.stopImmediatePropagation();close();return;}
    if(event.key!=='Tab')return;
    const focusable=[...sidebar().querySelectorAll('button:not(:disabled),input:not(:disabled),a[href],[tabindex="0"]')].filter(e=>e.getClientRects().length);
    if(!focusable.length){event.preventDefault();return;}
    const first=focusable[0],last=focusable.at(-1);
    if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
    else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
  },{capture:true,signal:abort.signal});
  window.addEventListener('popstate',fromLocation,{signal:abort.signal});
  compact.addEventListener('change',()=>{if(!compact.matches&&sidebar()?.getAttribute('data-docs-drawer')==='open')close();drawer();},{signal:abort.signal});
  return {
    sync(){
      for(const e of root.querySelectorAll('[data-docs-route]'))routes.add(e.getAttribute('data-docs-route'));
      if(!initialized&&shell()){
        initialized=true;
        // An app that does not read the initial address still shows its start screen first: the mount marker waits for
        // the navigation this host is about to send (see `settled`).
        const wanted=window.location.pathname.replace(/\/$/,'')||'/';
        if(!(window.history.state?.swuiNavigation?.depth>0)&&routes.has(wanted)&&route()!==wanted){owed=wanted;owedSyncs=0;}
        queueMicrotask(()=>{
          const path=window.location.pathname.replace(/\/$/,'')||'/';
          if(routes.has(path)){window.history.replaceState({...window.history.state,swuiDocs:path},'',window.location.href);fromLocation();}
        });
      }
      if(owed!==null&&initialized&&(route()===owed||++owedSyncs>2))owed=null;
      drawer();
    },
    /** False while the navigation to the address the page was opened at is still on its way. */
    settled(){return owed===null;},
    dispose(){abort.abort();document.documentElement.removeAttribute('data-docs-drawer-open');backdrop?.remove();for(const [e,v] of savedInert)if(e.isConnected)e.inert=v;savedInert.clear();}
  };
}

// The Advanced page's DOM component fixture (Tests/Apps/ShowcaseApp/DOMComponentFixture.swift). Components are registered
// from the application's own files; this module is imported before the framework starts, so it queues the definition
// the way Documentation/BROWSER_APP_SHELL.md describes. Swift sends the count as the state string.
(globalThis.SwiftUIWebDOMComponents ??= { queue: [], define(name, factory) { this.queue.push([name, factory]); } }).define('showcase-counter', () => ({
  mount(host, root, emit, state) {
    globalThis.__domMounts = (globalThis.__domMounts || 0) + 1;
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = 'Tap in DOM';
    button.setAttribute('data-testid', 'dom-counter-button');
    const label = document.createElement('span');
    label.setAttribute('data-testid', 'dom-counter-label');
    label.textContent = `Count: ${state}`;
    button.addEventListener('click', () => emit('tap'));
    root.append(button, label);
    return { label };
  },
  update(instance, state) { instance.label.textContent = `Count: ${state}`; },
  dispose() { globalThis.__domDismantles = (globalThis.__domDismantles || 0) + 1; }
}));
