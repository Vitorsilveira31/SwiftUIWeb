/** Dependency-free transport/server checks, executed by Bun. */
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {resolveRequest,isLoopbackHost} from './dev-server-policy.mjs';
import {minify} from './build-styles.mjs';
import {ownsLayoutAttribute} from './layout-host.js';
import {FocusCoordinator,ScrollCoordinator,HistoryCoordinator,isDeepLinkPath} from './host-interactions.js';
import {PresentationCoordinator} from './presentation-host.js';
import {shareContent} from './transfer-host.js';
import {GeometryHost} from './geometry-host.js';
import {motionTiming, isTransitionDeclaration} from './embedded-dom.js';
import {safeErrorMessage} from './BrowserIO/browser-io.mjs';
let passed=0;
const test=async(name,run)=>{await run();passed++;console.log(`PASS ${name}`);};
const root='/tmp/swui-public';
for(const route of ['/','/layout','/advanced','/layout?mode=light','/navigation/detail/2'])await test(`direct route ${route}`,()=>{
  const r=resolveRequest(`http://127.0.0.1:8080${route}`,'GET','text/html',root);
  assert.equal(r.status,200);assert.equal(r.fallback,join(root,'index.html'));
});
await test('WASM MIME and missing assets never fall back to HTML',()=>{
  for(const path of ['/app.wasm','/missing.js','/missing.css','/missing.png'])assert.equal(resolveRequest('http://localhost'+path,'GET','*/*',root).fallback,null);
  assert.equal(resolveRequest('http://localhost/app.wasm','GET','*/*',root).type,'application/wasm');
});
await test('HEAD keeps resource metadata; POST is refused',()=>{
  assert.equal(resolveRequest('http://localhost/layout','HEAD','text/html',root).head,true);
  assert.equal(resolveRequest('http://localhost/layout','POST','text/html',root).status,405);
});
await test('malformed encoding, encoded traversal and backslashes rejected',()=>{
  for(const path of ['/%zz','/%00','/a/%2f..%2fsecret','/a%5cb'])assert.notEqual(resolveRequest('http://localhost'+path,'GET','text/html',root).status,200);
});
await test('the development server answers only loopback hosts (DNS rebinding)',()=>{
  for(const url of ['http://127.0.0.1:8080/','http://localhost:3000/x','http://LOCALHOST/','http://[::1]:8080/'])assert.equal(isLoopbackHost(url),true,url);
  for(const url of ['http://evil.example:8080/','http://127.0.0.1.evil.example/','http://localhost.evil.example/','http://10.0.0.5:8080/','http://0.0.0.0:8080/','not a url'])assert.equal(isLoopbackHost(url),false,url);
});
await test('framework stylesheet is plain CSS: no Tailwind, no UI runtime dependency',()=>{
  const css=readFileSync(new URL('./styles.css',import.meta.url),'utf8');
  for(const marker of ['@import "tailwindcss"','@apply','@theme','@source','@custom-variant','--tw-'])assert.ok(!css.includes(marker),`Tools/styles.css must not contain ${marker}`);
  const manifest=JSON.parse(readFileSync(new URL('../package.json',import.meta.url),'utf8'));
  const packages=Object.keys({...manifest.dependencies,...manifest.devDependencies}).join(' ');
  assert.ok(!/tailwind|starting-point-ui/.test(packages),`unexpected styling dependency in package.json: ${packages}`);
});
await test('stylesheet minifier only drops comments and layout whitespace',()=>{
  assert.equal(minify('/* c */ .a { content: "x  y;"; margin: 1px  2px }'),'.a{content: "x  y;";margin: 1px 2px}');
  assert.equal(minify('.a > .b , .c{width: calc(1px + 2px)}'),'.a > .b,.c{width: calc(1px + 2px)}');
  assert.equal(minify('@media (min-width: 768px) and (max-width: 1000px) { .a { top: 0 } }'),'@media (min-width: 768px) and (max-width: 1000px){.a{top: 0}}');
  assert.throws(()=>minify('.a { top: 0 } /* open'));
});
await test('transition timing parses with and without the property name browsers drop',()=>{
  // `transition: all 900ms ease-out` is serialized as `900ms ease-out`; a repeating animation relies on this parse.
  assert.deepEqual(motionTiming('all 900ms ease-out'),{duration:900,easing:'ease-out',delay:0});
  assert.deepEqual(motionTiming('900ms ease-out'),{duration:900,easing:'ease-out',delay:0});
  assert.deepEqual(motionTiming('53028.6ms linear'),{duration:53028.6,easing:'linear',delay:0});
  assert.deepEqual(motionTiming('opacity 0.4s ease-in 90ms'),{duration:400,easing:'ease-in',delay:90});
  assert.deepEqual(motionTiming('0.4s ease-in 90ms'),{duration:400,easing:'ease-in',delay:90});
  assert.equal(motionTiming(''),null);
  assert.equal(motionTiming('none'),null);
});
await test('a repeating style patch recognizes every transition longhand',()=>{
  // CSSStyleDeclaration enumerates longhands only: a host that held back just `transition` restored the
  // transition before the style change flushed, so a CSS transition captured the repeating WAAPI target.
  for (const key of ['transition','transition-property','transition-duration','transition-timing-function','transition-delay','transition-behavior'])
    assert.equal(isTransitionDeclaration(key),true,key);
  for (const key of ['width','transform','--transition','animation-duration'])
    assert.equal(isTransitionDeclaration(key),false,key);
});
await test('attributes the layout writes cannot be removed by DOM diff',()=>{
  assert.equal(ownsLayoutAttribute('data-cl'),true);assert.equal(ownsLayoutAttribute('data-cl-12'),true);assert.equal(ownsLayoutAttribute('data-layout-hidden'),true);assert.equal(ownsLayoutAttribute('data-fit-selected'),true);assert.equal(ownsLayoutAttribute('class'),false);
  // The document scroll's marks are the layout's; Swift's `data-document-head` is not, so a patch keeps the document head current.
  assert.equal(ownsLayoutAttribute('data-document-scroller'),true);assert.equal(ownsLayoutAttribute('data-document-scroll-chain'),true);assert.equal(ownsLayoutAttribute('data-document-sticky'),true);assert.equal(ownsLayoutAttribute('data-document-head'),false);
});
await test('navigation push/replace/pop acknowledgments and typed restoration',()=>{
  const w=new EventTarget();w.AbortController=AbortController;w.location=new URL('https://example.test/layout');let entry=0;const entries=[{url:w.location.href,state:{docs:true}}],acks=[],restores=[],pops=[],roots=[];
  w.history={get state(){return entries[entry].state},replaceState(state,_,url){entries[entry]={url:new URL(url,w.location).href,state};w.location=new URL(entries[entry].url);},pushState(state,_,url){entries.splice(entry+1);entries.push({url:new URL(url,w.location).href,state});entry++;w.location=new URL(entries[entry].url);},go(distance){entry+=distance;w.location=new URL(entries[entry].url);const e=new Event('popstate');e.state=this.state;queueMicrotask(()=>w.dispatchEvent(e));}};
  let ops=[];const root={querySelector:()=>({getAttribute:()=>JSON.stringify(ops)})};
  const adapter=new HistoryCoordinator(root,{window:w,ack:n=>acks.push(n),restore:key=>restores.push(key),onPop:state=>pops.push(state?.key||null),onRoot:state=>roots.push(state.key)});
  const set=(sequence,kind,path,depth,oldDepth,key)=>{ops=[{sequence,kind,path,depth,oldDepth,key,rootKey:'root',adapter:'stack'}];adapter.sync();};
  set(1,'push','/detail/1',1,0,'one');assert.equal(w.location.pathname,'/detail/1');assert.equal(w.history.state.docs,true);
  set(2,'replace','/detail/2',1,1,'two');assert.equal(entries.length,2);assert.equal(w.location.pathname,'/detail/2');
  set(3,'back','/',0,1,'root');assert.equal(w.location.pathname,'/layout');
  return new Promise(resolve=>setTimeout(()=>{assert.deepEqual(restores,['root']);assert.deepEqual(pops,['root']);assert.deepEqual(roots,['root']);assert.deepEqual(acks,[1,2,3]);adapter.sync();assert.equal(acks.length,3);adapter.dispose();resolve();},0));
});
await test('deep links hydrate once and do not duplicate the current URL',()=>{
  const w=new EventTarget();w.AbortController=AbortController;w.location=new URL('https://example.test/navigation/detail/2?tab=work');let entries=[{url:w.location.href,state:null}],entry=0,locations=0,acks=[];
  w.history={get state(){return entries[entry].state},replaceState(state,_,url){entries[entry]={url:new URL(url,w.location).href,state};w.location=new URL(entries[entry].url);},pushState(state,_,url){entries.splice(entry+1);entries.push({url:new URL(url,w.location).href,state});entry++;w.location=new URL(entries[entry].url);},go(){}};
  let operations=[];const root={querySelector:()=>({getAttribute:()=>JSON.stringify(operations)})};
  const adapter=new HistoryCoordinator(root,{window:w,onLocation:()=>locations++,ack:n=>acks.push(n)});
  operations=[{sequence:1,kind:'push',path:'/navigation/detail/2?tab=work',depth:1,oldDepth:0,key:'one',rootKey:'root',adapter:'stack'}];adapter.sync();
  assert.equal(locations,1);assert.equal(entries.length,1);assert.equal(w.location.pathname,'/navigation/detail/2');assert.equal(w.location.search,'?tab=work');assert.deepEqual(acks,[1]);adapter.dispose();
});
await test('the site root is a plain launch, an address past it a deep link that reaches onOpenURL',()=>{
  for (const root of ['', '/', '/index.html']) assert.equal(isDeepLinkPath(root),false,root);
  for (const link of ['/orders/1204', '/navigation/detail/2', '/index.html/x']) assert.equal(isDeepLinkPath(link),true,link);
});
await test('reload replays the current URL even when history state survived',()=>{
  const w=new EventTarget();w.AbortController=AbortController;w.location=new URL('https://example.test/?tab-selection=scope%3Awi-fi');let entries=[{url:w.location.href,state:{swuiNavigation:{adapter:'old',key:'old',depth:1}}}],entry=0,locations=0,acks=[];
  w.history={get state(){return entries[entry].state},replaceState(state,_,url){entries[entry]={url:new URL(url,w.location).href,state};w.location=new URL(entries[entry].url)},pushState(state,_,url){entries.splice(entry+1);entries.push({url:new URL(url,w.location).href,state});entry++;w.location=new URL(entries[entry].url)},go(){}};
  let operations=[];const root={querySelector:()=>({getAttribute:()=>JSON.stringify(operations)})};
  const adapter=new HistoryCoordinator(root,{window:w,onLocation:()=>locations++,ack:n=>acks.push(n)});
  operations=[{sequence:1,kind:'push',path:'/?tab-selection=scope%3Awi-fi',depth:1,oldDepth:0,key:'new',rootKey:'root',adapter:'new'}];adapter.sync();
  assert.equal(locations,1);assert.equal(entries.length,1);assert.equal(w.location.search,'?tab-selection=scope%3Awi-fi');assert.deepEqual(acks,[1]);adapter.dispose();
});
await test('unsupported share returns an intentional capability result',async()=>{
  const node={getAttribute:name=>name==='data-share-item'?'A value':null};assert.deepEqual(await shareContent(node,{}),{status:'unsupported',text:'A value'});
});
await test('host diagnostics redact credentials and query secrets',()=>{
  const message=safeErrorMessage(new Error('fetch https://alice:pw@example.test/me?token=secret&ok=1 authorization: Bearer abc'));
  assert.ok(!message.includes('secret'));assert.ok(!message.includes('pw'));assert.ok(!message.includes('abc'));assert.ok(message.includes('[redacted]'));
});
// The change summary a commit hands the hosts' `needsSync`: `touches(selector)` names the selectors the patch added, removed
// or changed a match of, `changedAttribute(names)` the attributes it changed anywhere. A fake answers by the strings it was given.
const changesOf=({touches=[],attributes=[],everything=false}={})=>({everything,touches:s=>touches.includes(s),changedAttribute:n=>n.some(a=>attributes.includes(a))});
const fakeWindow=()=>{const win={AbortController,addEventListener(){},removeEventListener(){},requestAnimationFrame:()=>1,cancelAnimationFrame(){}};win.document={defaultView:win,activeElement:null,addEventListener(){},removeEventListener(){}};win.getComputedStyle=()=>({visibility:'visible',direction:'ltr'});return win;};
await test('needsSync: focus syncs for what the patch touches, a wait, and a candidate that is or may be shown',()=>{
  const win=fakeWindow(),doc=win.document;let candidates=[],waiting=false;
  const focus=new FocusCoordinator({ownerDocument:doc,querySelectorAll:()=>candidates},{window:win,awaiting:()=>waiting});
  const selector='[data-focus-request="true"],[data-focused="true"]';
  assert.equal(focus.needsSync(changesOf({touches:['.other']})),false,'an unrelated change');
  assert.equal(focus.needsSync(changesOf({everything:true})),true,'the first commit');
  assert.equal(focus.needsSync(changesOf({touches:[selector]})),true,'a focus request added or changed');
  assert.equal(focus.needsSync(changesOf({attributes:['data-focused']})),true,'a focused control stopped matching');
  waiting=true;assert.equal(focus.needsSync(changesOf()),true,'a focus event Swift has not reflected yet');waiting=false;
  candidates=[{ownerDocument:doc,getClientRects:()=>[]}];focus.sync();
  assert.equal(focus.needsSync(changesOf()),true,'a candidate that is hidden now may be shown by an ancestor');
  const target={ownerDocument:doc,getClientRects:()=>[1],focused:false,focus(){this.focused=true;}};
  candidates=[target];focus.sync();assert.equal(target.focused,true);
  assert.equal(focus.needsSync(changesOf()),true,'a focused control is held: an ancestor can hide it');
  candidates=[];focus.sync();
  assert.equal(focus.needsSync(changesOf({touches:['.other']})),false,'nothing focused again');
});
await test('needsSync: scroll syncs for scroll views, requests, pending requests, held edges and tracked hosts that stop matching',()=>{
  const win=fakeWindow();
  const scroll=new ScrollCoordinator({ownerDocument:win.document,querySelectorAll:()=>[]},{dispatch(){}});
  assert.equal(scroll.needsSync(changesOf({touches:['.other']})),false,'an unrelated change');
  assert.equal(scroll.needsSync(changesOf({touches:['.scroll-view']})),true,'a scroll view added, removed or changed');
  assert.equal(scroll.needsSync(changesOf({touches:['[data-embedded-scroll-id]']})),true,'a scroll request');
  assert.equal(scroll.needsSync(changesOf({attributes:['class']})),false,'a class change with no scroll view tracked');
  const attributes=new Map();
  const host={isConnected:true,getAttribute:n=>attributes.get(n)??null,hasAttribute:n=>attributes.has(n)};
  // With no binding, the next sync clears the recorded position: that sync must run.
  scroll.states.set(host,{position:'id:row-3',dismissed:null});
  assert.equal(scroll.needsSync(changesOf({touches:['.other']})),true,'a recorded position without a binding is cleared by the sync');
  scroll.states.set(host,{position:null,dismissed:null});
  assert.equal(scroll.needsSync(changesOf({touches:['.other']})),false,'an unbound host with nothing recorded');
  assert.equal(scroll.needsSync(changesOf({attributes:['class']})),true,'a tracked host whose class changed may no longer be a scroll view');
  // A position the host recorded without a commit (a user's scroll) differs from the binding's request: the sync applies it.
  attributes.set('data-scroll-position-id','row-7');
  assert.equal(scroll.needsSync(changesOf({touches:['.other']})),true,'a binding request that differs from the recorded position');
  scroll.states.set(host,{position:'id:row-7',dismissed:null});
  assert.equal(scroll.needsSync(changesOf({touches:['.other']})),false,'a binding request that the recorded position already names');
  attributes.clear();
  assert.equal(scroll.needsSync(changesOf({touches:['.other']})),true,'a removed binding while a position is recorded');
  scroll.states.set(host,{position:'edge:bottom',dismissed:null});
  attributes.set('data-scroll-position-edge','bottom');
  assert.equal(scroll.needsSync(changesOf()),true,'an edge the host holds is re-applied as the content grows');
  scroll.states.clear();
  scroll.pending.set('request:1',{id:'row-9'});
  assert.equal(scroll.needsSync(changesOf()),true,'a request waiting for its target');
});
await test('needsSync: presentations sync for presentation changes, shown or hidden presentations and nothing else',()=>{
  const win=fakeWindow();
  const presentations=new PresentationCoordinator({ownerDocument:win.document,addEventListener(){},querySelectorAll:()=>[]},()=>{});
  const selector='.presentation-root,.alert-panel,.confirmation-dialog';
  assert.equal(presentations.needsSync(changesOf({touches:['.other']})),false,'an unrelated change');
  assert.equal(presentations.needsSync(changesOf({touches:[selector]})),true,'a presentation added or changed');
  presentations.records.set('alert:0',{});
  assert.equal(presentations.needsSync(changesOf({touches:['.other']})),true,'a presentation is shown: the sync holds its inert siblings');
  presentations.records.clear();
  presentations.watching=true;
  assert.equal(presentations.needsSync(changesOf({touches:['.other']})),true,'a presentation the last sync found hidden');
});
await test('needsSync: history syncs for its operations, the first sync and a queue, not for other changes',()=>{
  const win=fakeWindow();
  const history=new HistoryCoordinator({querySelector:()=>null},{window:win,ack(){},restore(){}});
  assert.equal(history.needsSync(changesOf({touches:['.other']})),true,'the first sync replays the URL');
  history.sync();
  assert.equal(history.needsSync(changesOf({touches:['.other']})),false,'an unrelated change');
  assert.equal(history.needsSync(changesOf({touches:['[data-history-operations]']})),true,'an operation list added or changed');
  assert.equal(history.needsSync(changesOf({attributes:['data-history-operations']})),true,'an operation list that stopped matching');
  history.queue.push({sequence:9});
  assert.equal(history.needsSync(changesOf({touches:['.other']})),true,'a queued operation');
  history.queue=[];history.dispose();
});
await test('needsSync: geometry syncs for readers the patch adds or changes, and every commit while a reader is observed',()=>{
  const win=fakeWindow();
  const root={ownerDocument:win.document,querySelectorAll:()=>[],contains:()=>false};
  const geometry=new GeometryHost(root,{dispatch(){},eventIdAttribute:'data-embedded-event-id',eventsAttribute:'data-embedded-events'});
  assert.equal(geometry.needsSync(changesOf({touches:['.other']})),false,'an unrelated change');
  assert.equal(geometry.needsSync(changesOf({touches:[geometry.selector()]})),true,'a reader added or changed');
  assert.equal(geometry.needsSync(changesOf({attributes:['data-geometry-reader']})),true,'a reader that stopped matching');
  geometry.observed.add({});
  assert.equal(geometry.needsSync(changesOf({touches:['.other']})),true,'a reader observed: a patch can move it');
  geometry.dispose();
});
console.log(`${passed} runtime contracts passed (not a linked Swift application test).`);
