import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { gzipSync } from 'node:zlib';
import { moveFiles, reopenMovedFile } from '../transfer-host.js';
import { createBrowserIO, Writer, Reader, safeErrorMessage } from './browser-io.mjs';
import { createDOMViewHost, installDOMComponentRegistry } from './dom-view-host.mjs';
import { BrowserIOOperation } from './protocol.generated.mjs';
import { BINARY_ATOMS } from '../binary-atoms.generated.js';
class MemoryStorage {
  data = new Map(); get length() { return this.data.size; }
  key(i) { return [...this.data.keys()][i] ?? null; }
  getItem(k) { return this.data.get(k) ?? null; } setItem(k,v) { this.data.set(k,String(v)); } removeItem(k) { this.data.delete(k); }
}
class FailingStorage extends MemoryStorage {
  failSet = new Set(); failRemove = new Set();
  setItem(key, value) { if (this.failSet.delete(key)) { const error = new Error('quota exceeded'); error.name = 'QuotaExceededError'; throw error; } super.setItem(key, value); }
  removeItem(key) { if (this.failRemove.delete(key)) { const error = new Error('quota exceeded'); error.name = 'QuotaExceededError'; throw error; } super.removeItem(key); }
}
class FakeElement {
  constructor() { this.attributes = new Map(); this.listeners = new Map(); this.isConnected = true; this.value = ''; this.textContent = ''; this.currentTime = 2; this.duration = 10; this.playbackRate = 1; this.volume = .5; this.muted = false; this.readyState = 4; this.networkState = 1; this.buffered = { length: 1, start: () => 0, end: () => 2 }; this.seekable = { length: 1, start: () => 0, end: () => 10 }; this.play = () => Promise.reject(new Error('not allowed')); this.pause = () => { this.paused = true; }; this.load = () => { this.loaded = true; }; this.canPlayType = () => 'probably'; this.requestFullscreen = () => Promise.reject(new Error('not allowed')); this.requestPictureInPicture = () => Promise.reject(new Error('not allowed')); }
  getAttribute(key) { return this.attributes.has(key) ? this.attributes.get(key) : null; }
  setAttribute(key, value) { this.attributes.set(key, String(value)); }
  removeAttribute(key) { this.attributes.delete(key); }
  addEventListener(name, fn) { if (!this.listeners.has(name)) this.listeners.set(name, new Set()); this.listeners.get(name).add(fn); }
  removeEventListener(name, fn) { this.listeners.get(name)?.delete(fn); }
  dispatch(name, value = {}) { for (const fn of this.listeners.get(name) ?? []) fn(value); }
}
class FakeIDBDatabase {
  constructor(name, version, records) { this.name = name; this.version = version; this.records = records; this.objectStoreNames = { contains: name => name === 'records' && this.hasStore }; this.hasStore = true; this.onversionchange = null; this.openedTransactions = []; this.abortNextTransaction = false; }
  createObjectStore() { this.hasStore = true; return {}; }
  transaction(_name, _mode) { const tx = new FakeIDBTransaction(this.records, this.abortNextTransaction); this.abortNextTransaction = false; this.openedTransactions.push(tx); return tx; }
  close() { this.closed = true; }
}
class FakeIDBTransaction {
  constructor(records, abort = false) { this.records = records; this.snapshot = new Map(records); this.error = null; this.aborted = false; this.objectStore = () => new FakeIDBStore(records, this); this.oncomplete = null; this.onabort = null; this.onerror = null; if (abort) setTimeout(() => this.abort(), 0); }
  complete() { setTimeout(() => { if (!this.aborted) this.oncomplete?.(); }, 0); }
  abort() { if (this.aborted) return; this.aborted = true; this.records.clear(); for (const [key, value] of this.snapshot) this.records.set(key, value); this.error = new Error('simulated IndexedDB transaction failure'); this.onerror?.(); this.onabort?.(); }
}
class FakeIDBStore {
  constructor(records, transaction) { this.records = records; this.transaction = transaction; }
  request(value) { const result = {}; setTimeout(() => { result.result = value; result.onsuccess?.(); this.transaction.complete(); }, 0); return result; }
  get(key) { if (this.records.staleReads?.delete(key)) return this.request(undefined); return this.request(this.records.get(key)); }
  put(value, key) { this.records.set(key, value instanceof Uint8Array ? value.slice() : value); return this.request(key); }
  delete(key) { this.records.delete(key); return this.request(undefined); }
  clear() { this.records.clear(); return this.request(undefined); }
  getAllKeys() { return this.request([...this.records.keys()]); }
}
class FakeIndexedDB {
  databases = new Map();
  opened = [];
  open(name, version) {
    const request = { result: null, error: null, onupgradeneeded: null, onsuccess: null, onerror: null };
    setTimeout(() => {
      let entry = this.databases.get(name);
      let upgraded = false;
      if (!entry) { entry = { records: new Map(), version }; this.databases.set(name, entry); upgraded = true; }
      else if (version > entry.version) { entry.version = version; upgraded = true; }
      request.result ??= new FakeIDBDatabase(name, entry.version, entry.records);
      this.opened.push(request.result);
      if (upgraded) request.onupgradeneeded?.();
      request.onsuccess?.();
    }, 0);
    return request;
  }
}
const server = createServer((req,res) => {
  if (req.url.startsWith('/progress/')) {
    // A 256 KiB body in 16 KiB writes. `sized` declares Content-Length, `chunked` does not, and `gzip` is encoded.
    const kind = req.url.slice('/progress/'.length);
    const decoded = Buffer.alloc(256*1024, 7);
    const payload = kind === 'gzip' ? gzipSync(decoded) : decoded;
    const headers = { 'content-type': 'application/octet-stream' };
    if (kind === 'gzip') headers['content-encoding'] = 'gzip';
    if (kind !== 'chunked') headers['content-length'] = payload.length;
    res.writeHead(200, headers);
    let offset = 0;
    const timer = setInterval(() => {
      const end = Math.min(offset + 16*1024, payload.length);
      res.write(payload.subarray(offset, end));
      offset = end;
      if (offset >= payload.length) { clearInterval(timer); res.end(); }
    }, 2);
    req.on('close', () => clearInterval(timer));
    return;
  }
  if (req.url === '/slow') { const timer=setTimeout(()=>res.end('late'), 250); req.on('close',()=>clearTimeout(timer)); return; }
  if (req.url === '/chunks') { res.writeHead(200);res.write('one');setTimeout(()=>{res.write('two');setTimeout(()=>res.end('three'),15);},15);return; }
  if (req.url === '/session') { res.writeHead(200, {'set-cookie':'session=secret; HttpOnly; SameSite=Lax', 'x-session':'active'}); res.end('authenticated'); return; }
  if (req.url === '/missing') {res.writeHead(404,{'x-test':'yes'});res.end('missing');return;}
  if (req.url === '/empty') {res.writeHead(204);res.end();return;}
  const parts=[];req.on('data',x=>parts.push(x));req.on('end',()=>{res.writeHead(201,{'content-type':'application/octet-stream'});res.end(Buffer.concat(parts));});
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const baseURL=`http://127.0.0.1:${server.address().port}`;
const memory=new WebAssembly.Memory({initial:4});let top=16;let next=1;const pending=new Map();
const alloc=n=>{const p=top;top+=n+16;if(top>memory.buffer.byteLength)memory.grow(Math.ceil((top-memory.buffer.byteLength)/65536));return p;};
const instance={exports:{memory,browser_io_alloc:alloc,browser_io_deliver(id,status,p,n){pending.get(id)?.(status,new Uint8Array(memory.buffer,p,n).slice());}}};
const listeners=new Map();
const environment={fetch:globalThis.fetch,Intl:globalThis.Intl,localStorage:new MemoryStorage(),sessionStorage:new MemoryStorage(),navigator:{onLine:true},addEventListener(name,fn){if(!listeners.has(name))listeners.set(name,new Set());listeners.get(name).add(fn);},removeEventListener(name,fn){listeners.get(name)?.delete(fn);}};
let cookieWrites=0;
const host=createBrowserIO({getInstance:()=>instance,environment,baseURL,onCookieWrite:()=>{cookieWrites++;}});
function request(path,{method='GET',body=null,stream=false,timeout=1000,limit=1024,downloadProgress=false}={}){return new Writer().text(path).text(method).text('same-origin').text('follow').u32(timeout).u32(limit).u32((stream?1:0)|(downloadProgress?4:0)).u32(0).u32(body===null?0:1).data(body??new Uint8Array()).bytes();}
function send(op,packet,cancel=false,callbackTimeout=3000){return new Promise((resolve,reject)=>{const id=next++;const events=[];const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const timer=setTimeout(()=>reject(new Error('callback timeout')),callbackTimeout);pending.set(id,(status,bytes)=>{events.push({status,bytes});if(status<100){clearTimeout(timer);pending.delete(id);resolve(events);}});assert.equal(host.imports.request(id,op,p,packet.length),0);if(cancel)host.imports.cancel(id);});}
function storage(scope,space,action,key='',value=''){const data=new Writer().u32(scope).text(space).u32(action).text(key).text(value).bytes();const p=alloc(data.length);new Uint8Array(memory.buffer,p,data.length).set(data);const h=host.imports.sync(2,p,data.length);assert.ok(h);const n=host.imports.length(h);const out=alloc(n);assert.equal(host.imports.copy(h,out,n),n);const bytes=new Uint8Array(memory.buffer,out,n).slice();host.imports.release(h);const reader=new Reader(bytes);assert.equal(reader.u32(),0);return reader;}
function storageTransaction(scope,space,expected,mutations){const writer=new Writer().u32(scope).text(space).u32(expected===null?0:1).u64(expected??0).u32(mutations.length);for(const m of mutations)writer.u32(m.action).text(m.key).text(m.value??'');const packet=writer.bytes();const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const h=host.imports.sync(11,p,packet.length);const n=host.imports.length(h),out=alloc(n);assert.equal(host.imports.copy(h,out,n),n);const bytes=new Uint8Array(memory.buffer,out,n).slice();host.imports.release(h);return new Reader(bytes);}
function storageRevision(scope,space){const packet=new Writer().u32(scope).text(space).bytes();const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const h=host.imports.sync(12,p,packet.length);const n=host.imports.length(h),out=alloc(n);assert.equal(host.imports.copy(h,out,n),n);const bytes=new Uint8Array(memory.buffer,out,n).slice();host.imports.release(h);const reader=new Reader(bytes);assert.equal(reader.u32(),0);return reader.u64();}
function numberUnit(value,locale,identifier,display,fraction=3){const packet=new Writer().f64(value).text(locale).text(identifier).text(display).u32(fraction).bytes();const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const h=host.imports.sync(17,p,packet.length);const n=host.imports.length(h),out=alloc(n);assert.equal(host.imports.copy(h,out,n),n);const bytes=new Uint8Array(memory.buffer,out,n).slice();host.imports.release(h);const reader=new Reader(bytes);const status=reader.u32();if(status!==0)return null;return reader.u32()===0?null:reader.text();}
function intl(epoch,style,locale='en-US',calendar='gregory',offset=0){const packet=new Writer().f64(epoch).u32(style).text(locale).text(calendar).u32(offset>>>0).bytes();const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const h=host.imports.sync(13,p,packet.length);const n=host.imports.length(h),out=alloc(n);assert.equal(host.imports.copy(h,out,n),n);const bytes=new Uint8Array(memory.buffer,out,n).slice();host.imports.release(h);const reader=new Reader(bytes);const status=reader.u32();if(status!==0)return null;return reader.u32()===0?null:reader.text();}
function syncResult(operation, packet){const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const handle=host.imports.sync(operation,p,packet.length);const length=host.imports.length(handle);const out=alloc(length);assert.equal(host.imports.copy(handle,out,length),length);const bytes=new Uint8Array(memory.buffer,out,length).slice();host.imports.release(handle);return new Reader(bytes);}
function domPacket(action, id, name='', value=''){return new Writer().u32(action).u32(id).text(name).text(value).bytes();}
function mediaPacket(action, id, text='', number=0, flag=false){return new Writer().u32(action).u32(id).text(text).f64(number).u32(flag?1:0).bytes();}
function indexedPacket(name, action, key='', value=new Uint8Array(), version=1){return new Writer().text(name).u32(action).text(key).data(value).u32(version).bytes();}
function indexedTransactionPacket(name, version, mutations){const writer=new Writer().text(name).u32(version).u32(mutations.length);for(const mutation of mutations)writer.u32(mutation.action).text(mutation.key??'').data(mutation.value??new Uint8Array());return writer.bytes();}
let tests=0;
try {
  let events=await send(1,request('/echo',{method:'POST',body:new Uint8Array([0,255,11,22])}));assert.equal(events.at(-1).status,0);let r=new Reader(events[0].bytes);assert.equal(r.u32(),201);r.text();let h=r.u32();for(let i=0;i<h;i++){r.text();r.text();}assert.deepEqual([...r.data()],[0,255,11,22]);r.finish();tests++;
  events=await send(1,request('/missing'));r=new Reader(events[0].bytes);assert.equal(r.u32(),404);tests++;
  events=await send(1,request('/empty'));r=new Reader(events[0].bytes);assert.equal(r.u32(),204);r.text();const emptyHeaders=r.u32();for(let i=0;i<emptyHeaders;i++){r.text();r.text();}assert.deepEqual([...r.data()],[]);r.finish();tests++;
  events=await send(1,request('/session'));r=new Reader(events[0].bytes);assert.equal(r.u32(),200);r.text();const sessionHeaderCount=r.u32();const sessionHeaders={};for(let i=0;i<sessionHeaderCount;i++){sessionHeaders[r.text()]=r.text();}assert.equal(sessionHeaders['x-session'],'active');assert.equal(sessionHeaders['set-cookie'],undefined);assert.equal(sessionHeaders.cookie,undefined);assert.match(new TextDecoder().decode(events[0].bytes),/active/);assert.doesNotMatch(new TextDecoder().decode(events[0].bytes),/session=secret/);tests++;
  events=await send(1,request('/chunks',{stream:true}));assert.equal(events[0].status,100);assert.equal(events.at(-1).status,0);assert.equal(events.filter(x=>x.status===101).map(x=>new TextDecoder().decode(x.bytes)).join(''),'onetwothree');tests++;
  events=await send(1,request('/slow',{timeout:15}));assert.equal(events.at(-1).status,-5);tests++;
  events=await send(1,request('/slow'),true);assert.equal(events.at(-1).status,-4);tests++;
  // Cancel after a real response body has begun. Abort also errors the
  // stream; cleanup must consume reader.cancel()'s rejected promise.
  {
    const id=next++, seen=[], packet=request('/chunks',{stream:true});
    const pointer=alloc(packet.length);
    new Uint8Array(memory.buffer,pointer,packet.length).set(packet);
    await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>reject(new Error('stream cancellation timeout')),3000);
      pending.set(id,(status)=>{
        seen.push(status);
        if(status===101) host.imports.cancel(id);
        if(status<100) { clearTimeout(timeout); pending.delete(id); resolve(); }
      });
      assert.equal(host.imports.request(id,1,pointer,packet.length),0);
    });
    await new Promise(resolve=>setImmediate(resolve));
    assert.deepEqual(seen,[100,101,-4]);
    assert.equal(host.diagnostics().activeOperations,0);
    tests++;
  }
  events=await send(1,request('/chunks',{limit:2}));assert.equal(events.at(-1).status,-14);tests++;
  // Download progress for a buffered body (mode bit 4). Reports are monotonic, far fewer than the 16 writes (throttled),
  // end at the whole decoded body, and carry the length headers that Swift applies Foundation's rule to.
  for (const [kind, length] of [['sized',262144],['chunked',262144],['gzip',262144]]) {
    events=await send(1,request(`/progress/${kind}`,{downloadProgress:true,timeout:5000,limit:1024*1024}));
    assert.equal(events.at(-1).status,0,kind);
    const reports=events.filter(event=>event.status===103).map(event=>{const reader=new Reader(event.bytes);const received=Number(reader.u64());const contentLength=reader.text();const contentEncoding=reader.text();reader.finish();return {received,contentLength,contentEncoding};});
    assert.ok(reports.length>=2&&reports.length<16,`${kind}: ${reports.length} reports`);
    for(let i=1;i<reports.length;i++) assert.ok(reports[i].received>=reports[i-1].received,`${kind}: progress went backwards`);
    assert.equal(reports.at(-1).received,length,kind);
    assert.equal(reports.at(-1).contentLength !== '', kind !== 'chunked', kind);
    assert.equal(reports.at(-1).contentEncoding,kind==='gzip'?'gzip':'',kind);
    const body=events.at(-1).bytes;const finalReader=new Reader(body);assert.equal(finalReader.u32(),200);finalReader.text();const finalHeaders=finalReader.u32();for(let i=0;i<finalHeaders;i++){finalReader.text();finalReader.text();}assert.equal(finalReader.data().length,length,kind);
  }
  // A streamed body reports through its chunks instead, so the download bit adds no progress events.
  events=await send(1,request('/progress/sized',{stream:true,downloadProgress:true,timeout:5000,limit:1024*1024}));
  assert.equal(events.filter(event=>event.status===103).length,0);assert.equal(events.at(-1).status,0);tests++;
  events=await send(1,request('/progress/sized',{downloadProgress:true,timeout:5000,limit:1024*1024}));assert.equal(events.at(-1).status,0);tests++;
  const beforeWriteRevision=storageRevision(0,'a');storage(0,'a',1,'key','');assert.equal(storageRevision(0,'a'),beforeWriteRevision+1n);r=storage(0,'a',0,'key');assert.equal(r.u32(),1);assert.equal(r.text(),'');r=storage(0,'a',0,'missing');assert.equal(r.u32(),0);tests++;
  storage(0,'a',1,'unicode','ação 日本');r=storage(0,'a',0,'unicode');assert.equal(r.u32(),1);assert.equal(r.text(),'ação 日本');storage(1,'a',1,'key','session');r=storage(0,'a',0,'key');assert.equal(r.u32(),1);assert.equal(r.text(),'');storage(0,'a',2,'key');assert.equal(storageRevision(0,'a'),beforeWriteRevision+3n);tests++;
  storage(0,'b',1,'other','keep');const beforeClearRevision=storageRevision(0,'a');storage(0,'a',3);assert.equal(storageRevision(0,'a'),beforeClearRevision+1n);r=storage(0,'b',0,'other');assert.equal(r.u32(),1);assert.equal(r.text(),'keep');assert.equal(host.diagnostics().resultBuffers,0);tests++;
  let revision=storageRevision(0,'tx');r=storageTransaction(0,'tx',revision,[{action:1,key:'a',value:'one'},{action:1,key:'b',value:'two'}]);assert.equal(r.u32(),0);const nextRevision=r.u64();assert.equal(nextRevision,revision+2n);r=storage(0,'tx',0,'a');assert.equal(r.u32(),1);assert.equal(r.text(),'one');r=storageTransaction(0,'tx',revision,[{action:1,key:'stale',value:'no'}]);assert.equal(r.u32(),-9>>>0);tests++;
  events=await send(9,new Writer().f64(.001).bytes());assert.equal(events.at(-1).status,0);tests++;
  events=await send(1,new Uint8Array([1,2]));assert.equal(events.at(-1).status,-1);tests++;
  assert.equal(numberUnit(5,'pt_BR','kilogram','short'),'5 kg');assert.equal(numberUnit(5,'en-US','pound','short'),'5 lb');assert.equal(numberUnit(20,'en-US','celsius','short'),'20°C');assert.equal(numberUnit(70.25,'pt-BR','kilogram','short',1),'70,2 kg');assert.equal(numberUnit(Number.NaN,'en-US','kilogram','short'),null);assert.equal(numberUnit(1,'en-US','kelvin','long'),null);assert.equal(numberUnit(1,'en-US','kilogram','bogus'),null);tests++;
  // The text operation: a number formatted (kind 0), text folded (kind 1), a malformed request absent, an unknown kind an error.
  { const answer=(packet)=>{const r=syncResult(20,packet);assert.equal(r.u32(),0);const present=r.u32();const text=present?r.text():null;r.finish();return text;};
    assert.equal(answer(new Writer().u32(0).text('1027.5').text('style=currency;currency=BRL;locale=pt_BR').bytes()),'R$\u00a01.027,50');
    assert.equal(answer(new Writer().u32(0).text('abc').text('').bytes()),null);
    assert.equal(answer(new Writer().u32(0).text('1').text('style=hex').bytes()),null);
    assert.equal(answer(new Writer().u32(1).u32(3).text('Maré de SANGUE').bytes()),'mare de sangue');
    assert.equal(answer(new Writer().u32(1).u32(1).text('Maré').bytes()),'Mare');
    assert.notEqual(syncResult(20,new Writer().u32(2).bytes()).u32(),0); tests++; }
  // OSLog's Logger (WebOSLog): each level reaches its console method; an unknown level is an error.
  { const seen=[];const saved={};for(const m of ['debug','info','log','warn','error']){saved[m]=console[m];console[m]=text=>seen.push([m,text]);}
    try { for(const [level,text] of [[0,'d'],[1,'i'],[2,'l'],[3,'w'],[4,'e%c']]){const reader=syncResult(18,new Writer().u32(level).text(text).bytes());assert.equal(reader.u32(),0);reader.finish();}
      const bad=syncResult(18,new Writer().u32(9).text('x').bytes());assert.notEqual(bad.u32(),0); }
    finally { Object.assign(console,saved); }
    assert.deepEqual(seen,[['debug','d'],['info','i'],['log','l'],['warn','w'],['error','e%c']]);tests++; }
  // NSPredicate (WebFoundation): describe a format, then evaluate it under the same id; the verdicts are 0 or 1, 2 where Foundation raises, 3 for a format that does not parse.
  { const wire=(text)=>new Writer().u32(text.length).raw(new TextEncoder().encode(text)).bytes();const string=(text)=>new Uint8Array([4,...wire(text)]);
    const object=new Uint8Array([8,1,0,0,0,...wire('name'),...string('Alice')]);const none=new Uint8Array();
    const ask=(id,format,args,bindings,target)=>{const answer=syncResult(19,new Writer().u32(id).text(format).data(args).data(bindings).data(target).bytes());assert.equal(answer.u32(),0);return answer;};
    let reader=ask(1,'name == %@',string('Alice'),none,none);assert.equal(reader.u32(),1);assert.equal(reader.text(),'name == "Alice"');assert.equal(reader.u32(),1);assert.equal(reader.u32(),1);assert.equal(reader.text(),'name');reader.finish();
    reader=ask(1,'name == %@',string('Alice'),none,object);assert.equal(reader.u32(),1);reader.finish();
    reader=ask(2,'name == 1 AND',none,none,none);assert.equal(reader.u32(),0);reader.finish();
    reader=ask(3,'name < 1',none,none,object);assert.equal(reader.u32(),2);reader.finish();
    reader=ask(4,'name >',none,none,object);assert.equal(reader.u32(),3);reader.finish();tests++; }
  assert.match(intl(0,0),/1969|1970/);assert.ok(intl(0,1));assert.equal(intl(Number.NaN,0),null);tests++;
  assert.throws(()=>new Writer().u64(-1),/Unsigned 64-bit/);
  const oversized=new Writer();oversized.size=64*1024*1024+1;assert.throws(()=>oversized.bytes(),/packet exceeds/);
  assert.throws(()=>new Reader(new Uint8Array([1])).u32(),/Truncated/);
  assert.throws(()=>new Reader(new Uint8Array([1])).f64(),/Truncated/);
  assert.throws(()=>new Reader(new Uint8Array([2,0,0,0,0xff])).data(),/Invalid host packet length/);
  assert.throws(()=>new Reader(new Uint8Array([0])).finish(),/Unexpected trailing/);
  assert.throws(()=>new Reader(new Uint8Array([2,0,0,0,0xff,0xff])).text(),/encoded/);
  assert.match(safeErrorMessage(new Error('https://user:secret@example.test/a?token=abc&x=1 Authorization: Bearer xyz Cookie: sid=secret')),/example.test\/a/);
  assert.doesNotMatch(safeErrorMessage(new Error('https://user:secret@example.test/a?token=abc')),/secret|abc/);tests++;
  assert.equal(safeErrorMessage(new Error('https://[malformed')), '[redacted-url]');
  { const failing=new FailingStorage(); const original=environment.localStorage; environment.localStorage=failing;
    const prefix='swui:4:fail:'; failing.setItem(`${prefix}keep`,'old');
    failing.failSet.add(`${prefix}__revision`);
    let failed=syncResult(2,new Writer().u32(0).text('fail').u32(1).text('new').text('value').bytes());assert.equal(failed.u32(),-3>>>0);failed.text();
    let check=storage(0,'fail',0,'new');assert.equal(check.u32(),0);
    failing.failRemove.add(`${prefix}keep`);failed=syncResult(2,new Writer().u32(0).text('fail').u32(3).text('').text('').bytes());assert.equal(failed.u32(),-3>>>0);failed.text();
    check=storage(0,'fail',0,'keep');assert.equal(check.u32(),1);assert.equal(check.text(),'old');
    let list=storage(0,'fail',4);assert.equal(list.u32(),1);assert.equal(list.text(),'keep');
    // A revision another script made unreadable is replaced by a fresh one, written back, rather than failing every write.
    failing.setItem(`${prefix}__revision`,'1'+'0'.repeat(25));{const repaired=syncResult(12,new Writer().u32(0).text('fail').bytes());assert.equal(repaired.u32(),0);const value=repaired.u64();repaired.finish();assert.ok(value>0n);assert.equal(failing.getItem(`${prefix}__revision`),String(value));}
    failing.removeItem(`${prefix}__revision`);failing.setItem(`${prefix}tx`,'old');failing.failSet.add(`${prefix}__revision`);failed=syncResult(11,new Writer().u32(0).text('fail').u32(0).u64(0).u32(1).u32(1).text('tx').text('new').bytes());assert.equal(failed.u32(),-3>>>0);failed.text();check=storage(0,'fail',0,'tx');assert.equal(check.u32(),1);assert.equal(check.text(),'old');
    environment.localStorage=original;tests++; }
  assert.equal(intl(0,99),null);assert.ok(intl(0,0,'bad locale'));assert.equal(intl(1e20,0),null);
  { const originalIntl=environment.Intl;environment.Intl={};assert.equal(intl(0,0),null);environment.Intl={DateTimeFormat:class { constructor(){throw new Error('invalid locale');} }};assert.equal(intl(0,0),null);environment.Intl=originalIntl;tests++; }
  { const element=new FakeElement();element.setAttribute('data-web-mount-key','root');element.setAttribute('data-web-mount-token','token');environment.document={pictureInPictureEnabled:true,querySelectorAll:()=>[element],exitFullscreen:()=>Promise.reject(new Error('not allowed')),exitPictureInPicture:()=>Promise.reject(new Error('not allowed'))};
    let dom=syncResult(7,domPacket(0,0));assert.equal(dom.u32(),0);assert.equal(dom.u32(),1);const elementID=dom.u32();assert.equal(dom.text(),'root');assert.equal(dom.text(),'token');
    dom=syncResult(7,domPacket(1,elementID));assert.equal(dom.u32(),0);assert.equal(dom.u32(),1);
    dom=syncResult(7,domPacket(2,elementID,'missing'));assert.equal(dom.u32(),0);assert.equal(dom.u32(),0);
    dom=syncResult(7,domPacket(3,elementID,'data-value','42'));assert.equal(dom.u32(),0);dom=syncResult(7,domPacket(2,elementID,'data-value'));assert.equal(dom.u32(),0);assert.equal(dom.u32(),1);assert.equal(dom.text(),'42');
    dom=syncResult(7,domPacket(4,elementID,'data-value'));assert.equal(dom.u32(),0);dom=syncResult(7,domPacket(5,elementID,'','typed'));assert.equal(dom.u32(),0);dom=syncResult(7,domPacket(8,elementID));assert.equal(dom.u32(),0);assert.equal(dom.u32(),1);assert.equal(dom.text(),'typed');
    dom=syncResult(7,domPacket(6,elementID));assert.equal(dom.u32(),0);assert.equal(dom.u32(),1);assert.equal(dom.text(),'');dom=syncResult(7,domPacket(7,elementID,'','content'));assert.equal(dom.u32(),0);dom=syncResult(7,domPacket(6,elementID));assert.equal(dom.u32(),0);assert.equal(dom.u32(),1);assert.equal(dom.text(),'content');
    element.isConnected=false;dom=syncResult(7,domPacket(1,elementID));assert.equal(dom.u32(),0);assert.equal(dom.u32(),0);element.isConnected=true;
    dom=syncResult(7,domPacket(99,elementID));assert.equal(dom.u32(),-1>>>0);dom.text();dom=syncResult(7,domPacket(1,9999));assert.equal(dom.u32(),-8>>>0);dom.text();
    const originalDocument=environment.document;environment.document=null;dom=syncResult(7,domPacket(0,0));assert.equal(dom.u32(),-7>>>0);dom.text();environment.document=originalDocument;
    for(const [action,text,number,flag] of [[0,'',0,false],[1,'',8,false],[2,'',0,false],[3,'',1.5,false],[4,'',2,false],[5,'',0,false],[6,'',2,false],[7,'',0,false],[8,'',0,true],[9,'',0,false],[10,'',0,false],[11,'movie.mp4',0,false],[12,'video/mp4',0,false],[13,'',0,false],[14,'',0,false],[15,'',0,false],[16,'',0,false],[17,'',0,false],[18,'',0,false],[19,'',0,false],[20,'',0,true]]) { dom=syncResult(8,mediaPacket(action,elementID,text,number,flag));assert.equal(dom.u32(),0); }
    dom=syncResult(8,mediaPacket(20,elementID,'',0,false));assert.equal(dom.u32(),0);await new Promise(resolve=>setTimeout(resolve,0));
    environment.__attachAdaptiveMedia=(el,text)=>{el.attached=text;};environment.__detachAdaptiveMedia=el=>{el.detached=true;};dom=syncResult(8,mediaPacket(21,elementID,'adaptive'));assert.equal(dom.u32(),0);assert.equal(element.attached,'adaptive');dom=syncResult(8,mediaPacket(22,elementID));assert.equal(dom.u32(),0);assert.equal(element.detached,true);delete environment.__attachAdaptiveMedia;delete environment.__detachAdaptiveMedia;environment.__loadAdaptiveMedia=(el,text)=>{el.loadedAdaptive=text;};environment.__cancelAdaptiveMedia=el=>{el.cancelledAdaptive=true;};syncResult(8,mediaPacket(21,elementID,'adaptive2'));syncResult(8,mediaPacket(22,elementID));assert.equal(element.loadedAdaptive,'adaptive2');assert.equal(element.cancelledAdaptive,true);delete environment.__loadAdaptiveMedia;delete environment.__cancelAdaptiveMedia;
    dom=syncResult(8,mediaPacket(99,elementID));assert.equal(dom.u32(),-1>>>0);dom.text();
    const observeID=next++;const seen=[];const observePacket=new Writer().u32(elementID).text('__keydown').bytes();const observePtr=alloc(observePacket.length);new Uint8Array(memory.buffer,observePtr,observePacket.length).set(observePacket);pending.set(observeID,(status,bytes)=>seen.push({status,bytes}));assert.equal(host.imports.request(observeID,8,observePtr,observePacket.length),0);await new Promise(resolve=>setTimeout(resolve,0));element.dispatch('keydown',{key:'Enter',repeat:true});assert.equal(seen[0].status,100);let keyReader=new Reader(seen[0].bytes);assert.equal(keyReader.text(),'Enter');assert.equal(keyReader.u32(),1);host.imports.cancel(observeID);pending.delete(observeID);tests++; }
  { const connectivityID=next++;const seen=[];pending.set(connectivityID,(status,bytes)=>seen.push({status,bytes}));assert.equal(host.imports.request(connectivityID,6,0,0),0);await new Promise(resolve=>setTimeout(resolve,0));assert.equal(seen[0].status,100);environment.navigator.onLine=false;for(const fn of listeners.get('offline')??[])fn();assert.equal(seen.at(-1).bytes[0],0);host.imports.cancel(connectivityID);pending.delete(connectivityID);environment.navigator.onLine=true;tests++; }
  { // secureStore: AES-GCM under a non-extractable key; nothing readable lands in IndexedDB.
    const indexedDB=new FakeIndexedDB();environment.indexedDB=indexedDB;environment.crypto=globalThis.crypto;
    const securePacket=(action,key='',value=new Uint8Array())=>new Writer().text('keychain').u32(action).text(key).data(value).bytes();
    const secret=new TextEncoder().encode('s3cret-value');
    events=await send(14,securePacket(1,'item-a',secret));assert.equal(events.at(-1).status,0);
    events=await send(14,securePacket(1,'item-b',new Uint8Array([7])));assert.equal(events.at(-1).status,0);
    const db=indexedDB.opened.find(d=>d.name==='swui:security:keychain');
    const key=db.records.get('key');assert.equal(key.extractable,false);assert.equal(key.algorithm.name,'AES-GCM');assert.equal(key.algorithm.length,256);
    assert.deepEqual([...key.usages].sort(),['decrypt','encrypt'],'the key can only encrypt and decrypt: no export, wrap or derive');
    // IndexedDB holds the non-extractable key and, per item, only the format version, the IV and the ciphertext.
    assert.deepEqual([...db.records.keys()].sort(),['item:item-a','item:item-b','key']);
    assert.deepEqual(Object.keys(db.records.get('item:item-a')).sort(),['iv','sealed','v']);
    assert.equal(db.records.get('item:item-a').iv.length,12);
    const stored=db.records.get('item:item-a');assert.ok(!new TextDecoder().decode(stored.sealed).includes('s3cret'));
    events=await send(14,securePacket(0));assert.equal(events.at(-1).status,0);r=new Reader(events.at(-1).bytes);
    const loaded=new Map();for(let n=r.u32();n>0;n--){const id=r.text();loaded.set(id,new TextDecoder().decode(r.data()));}
    assert.equal(loaded.get('item-a'),'s3cret-value');assert.equal(loaded.size,2);
    // A ciphertext moved onto another id no longer decrypts and is not returned.
    db.records.set('item:item-b',db.records.get('item:item-a'));
    events=await send(14,securePacket(0));r=new Reader(events.at(-1).bytes);assert.equal(r.u32(),1);assert.equal(r.text(),'item-a');
    events=await send(14,securePacket(2,'item-a'));assert.equal(events.at(-1).status,0);
    events=await send(14,securePacket(3));assert.equal(events.at(-1).status,0);assert.equal(db.records.size,0);
    // A read of the key that missed a key another tab just stored must not replace it: the item
    // encrypted under the stored key still decrypts and the key object is the same.
    events=await send(14,securePacket(1,'first',new Uint8Array([1])));assert.equal(events.at(-1).status,0);
    const storedKey=db.records.get('key');db.records.staleReads=new Set(['key']);
    events=await send(14,securePacket(1,'second',new Uint8Array([2])));assert.equal(events.at(-1).status,0);
    assert.equal(db.records.get('key'),storedKey,'the key already stored is kept');
    events=await send(14,securePacket(0));r=new Reader(events.at(-1).bytes);assert.equal(r.u32(),2,'both items decrypt under the one key');
    events=await send(14,securePacket(3));
    // Without IndexedDB, or without Web Crypto (an insecure context), the store reports unavailable (-7).
    const savedIndexedDB=environment.indexedDB;delete environment.indexedDB;
    events=await send(14,securePacket(0));assert.equal(events.at(-1).status,-7);
    environment.indexedDB=savedIndexedDB;
    const savedCrypto=environment.crypto;delete environment.crypto;
    events=await send(14,securePacket(0));assert.equal(events.at(-1).status,-7);
    environment.crypto=savedCrypto;delete environment.indexedDB;tests++; }
  { const indexedDB=new FakeIndexedDB();environment.indexedDB=indexedDB;
    events=await send(3,indexedPacket('records',1,'alpha',new Uint8Array([1,2,3])));assert.equal(events.at(-1).status,0);
    events=await send(3,indexedPacket('records',0,'alpha'));assert.equal(events.at(-1).status,0);r=new Reader(events.at(-1).bytes);assert.equal(r.u32(),1);assert.deepEqual([...r.data()],[1,2,3]);
    events=await send(3,indexedPacket('records',4));assert.equal(events.at(-1).status,0);r=new Reader(events.at(-1).bytes);assert.equal(r.u32(),1);assert.equal(r.text(),'alpha');
    events=await send(3,indexedPacket('records',2,'alpha'));assert.equal(events.at(-1).status,0);events=await send(3,indexedPacket('records',3));assert.equal(events.at(-1).status,0);
    events=await send(10,indexedTransactionPacket('batch',1,[{action:1,key:'one',value:new Uint8Array([9])},{action:2,key:'one'},{action:3}]));assert.equal(events.at(-1).status,0);
    const recordsDB=indexedDB.opened.find(db=>db.name==='swui:records');recordsDB.abortNextTransaction=true;
    events=await send(3,indexedPacket('records',0,'alpha'));assert.equal(events.at(-1).status,-6);
    const batchDB=indexedDB.opened.find(db=>db.name==='swui:batch');batchDB.abortNextTransaction=true;
    events=await send(10,indexedTransactionPacket('batch',1,[{action:1,key:'rolled-back',value:new Uint8Array([7])}]));assert.equal(events.at(-1).status,-6);
    events=await send(3,indexedPacket('batch',0,'rolled-back'));assert.equal(events.at(-1).status,0);r=new Reader(events.at(-1).bytes);assert.equal(r.u32(),0);
    events=await send(3,indexedPacket('records',0,'alpha',new Uint8Array(),2));assert.equal(events.at(-1).status,0);assert.equal(recordsDB.closed,true);
    const recordsDBv2=indexedDB.opened.at(-1);assert.equal(recordsDBv2.version,2);recordsDBv2.onversionchange();assert.equal(recordsDBv2.closed,true);
    events=await send(3,new Writer().text('').u32(0).text('').data(new Uint8Array()).u32(1).bytes());assert.equal(events.at(-1).status,-1);tests++;delete environment.indexedDB; }
  { const failedOpen={open(){const request={result:null,error:new Error('IndexedDB open failed'),onupgradeneeded:null,onsuccess:null,onerror:null};setTimeout(()=>request.onerror?.(),0);return request;}};environment.indexedDB=failedOpen;
    events=await send(3,indexedPacket('open-error',4));assert.equal(events.at(-1).status,-6);
    environment.indexedDB={open(){return {result:null,error:null,onupgradeneeded:null,onsuccess:null,onerror:null};}};
    const nativeSetTimeout=globalThis.setTimeout;globalThis.setTimeout=(callback,delay,...args)=>nativeSetTimeout(callback,delay===10000?1:delay,...args);
    try { events=await send(3,indexedPacket('open-timeout',4),false,1000);assert.equal(events.at(-1).status,-5); }
    finally { globalThis.setTimeout=nativeSetTimeout;delete environment.indexedDB; }
    tests++; }
  { const received=[];instance.exports.browser_io_receive=(id,status,p,n)=>pending.get(id)?.(status,new Uint8Array(memory.buffer,p,n).slice());instance.exports.browser_io_free=p=>received.push(p);events=await send(9,new Writer().f64(0).bytes());assert.equal(events.at(-1).status,0);assert.equal(received.length,1);delete instance.exports.browser_io_receive;delete instance.exports.browser_io_free;tests++; }
  { const i=next++; const packet=new Writer().text('a').bytes(); const p=alloc(packet.length); new Uint8Array(memory.buffer,p,packet.length).set(packet); const seen=[]; pending.set(i,(status,bytes)=>seen.push({status,bytes})); assert.equal(host.imports.request(i,4,p,packet.length),0); await new Promise(r=>setTimeout(r,0)); const fire=(key)=>{for(const fn of listeners.get('storage')??[]) fn({storageArea:environment.localStorage,key});}; fire('swui:1:a:key'); fire('swui:1:a:other'); assert.equal(seen.length,0,'held until the revision'); fire('swui:1:a:__revision'); assert.equal(seen.length,2); seen.splice(1); assert.equal(seen[0].status,100); r=new Reader(seen[0].bytes); assert.equal(r.u32(),0); assert.equal(r.u32(),1); assert.equal(r.text(),'key'); host.imports.cancel(i); pending.delete(i); tests++; }
  { // cookies (sync 16): the page's own jar. A read reports document.cookie, the host and whether the page is
    // secure; a write assigns one Set-Cookie line; a page without a document is an error, never an empty jar.
    environment.document={cookie:'session=abc; theme=dark'};environment.location={hostname:'shop.example.test',protocol:'https:'};
    let cookie=syncResult(16,new Writer().u32(0).text('').bytes());assert.equal(cookie.u32(),0);assert.equal(cookie.text(),'session=abc; theme=dark');assert.equal(cookie.text(),'shop.example.test');assert.equal(cookie.u32(),1);cookie.finish();
    cookie=syncResult(16,new Writer().u32(1).text('pref=compact; Path=/').bytes());assert.equal(cookie.u32(),0);cookie.finish();assert.equal(environment.document.cookie,'pref=compact; Path=/');
    // The page announces its own write to its cookie watcher (Tools/cookie-watch.js), so it does not return as a change.
    assert.equal(cookieWrites,1);
    cookie=syncResult(16,new Writer().u32(1).text('x'.repeat(4097)).bytes());assert.equal(cookie.u32()|0,-1);cookie.text();assert.equal(cookieWrites,1,'a refused write was announced');
    cookie=syncResult(16,new Writer().u32(9).text('').bytes());assert.equal(cookie.u32()|0,-1);cookie.text();
    environment.document=null;cookie=syncResult(16,new Writer().u32(0).text('').bytes());assert.equal(cookie.u32()|0,-7);cookie.text();
    delete environment.document;delete environment.location;tests++; }
  { // cookies in a worker: the host's jar mirrors the page's cookies and hands writes to the main thread.
    const written=[];environment.cookieJar={snapshot:()=>({cookieString:'a=1',host:'worker.test',secure:true}),write:line=>written.push(line)};
    let cookie=syncResult(16,new Writer().u32(0).text('').bytes());assert.equal(cookie.u32(),0);assert.equal(cookie.text(),'a=1');assert.equal(cookie.text(),'worker.test');assert.equal(cookie.u32(),1);cookie.finish();
    cookie=syncResult(16,new Writer().u32(1).text('b=2; Path=/').bytes());assert.equal(cookie.u32(),0);cookie.finish();assert.deepEqual(written,['b=2; Path=/']);
    // The worker jar refuses a write longer than 4096 characters and an unknown action; neither reaches the main thread.
    cookie=syncResult(16,new Writer().u32(1).text('y'.repeat(4097)).bytes());assert.equal(cookie.u32()|0,-1);assert.equal(cookie.text(),'Cookie is too large');
    cookie=syncResult(16,new Writer().u32(9).text('').bytes());assert.equal(cookie.u32()|0,-1);assert.equal(cookie.text(),'Invalid cookie action');
    assert.deepEqual(written,['b=2; Path=/']);
    delete environment.cookieJar;tests++; }
  { const packet=new Uint8Array(); const p=alloc(1); const h=host.imports.sync(5,p,0); const n=host.imports.length(h), out=alloc(n); host.imports.copy(h,out,n); r=new Reader(new Uint8Array(memory.buffer,out,n).slice()); host.imports.release(h); assert.equal(r.u32(),0); assert.equal(r.u32(),1); tests++; }
  { const errorMemory=new WebAssembly.Memory({initial:1});const errorInstance={exports:{memory:errorMemory,browser_io_alloc:()=>0,browser_io_deliver(){}}};const errorHost=createBrowserIO({getInstance:()=>errorInstance,environment:{fetch:async()=>{throw new Error('simulated request failure');}},baseURL:'https://example.test'});
    const packet=request('/delivery-failure');const pointer=32;new Uint8Array(errorMemory.buffer,pointer,packet.length).set(packet);const logs=[];const originalError=console.error;console.error=(...values)=>logs.push(values.join(' '));
    try { assert.equal(errorHost.imports.request(1,1,pointer,packet.length),0);await new Promise(resolve=>setTimeout(resolve,0));assert.equal(errorHost.diagnostics().activeOperations,0);assert.match(logs.join(' '),/WASM allocation failed/); }
    finally { console.error=originalError;errorHost.dispose(); }
    tests++; }
  { // Fetch failures keep their phase so the Swift side can throw the matching URLError code.
    const memory = new WebAssembly.Memory({ initial: 2 });
    const statuses = new Map();
    let top = 64;
    const fetchInstance = { exports: { memory, browser_io_alloc: (n) => { const p = top; top += n + 16; return p; }, browser_io_deliver(id, status) { statuses.set(id, status); }, browser_io_free() {} } };
    let online = true; let mode = 'connect';
    const fetchEnvironment = {
      navigator: { get onLine() { return online; } },
      fetch: async () => {
        if (mode === 'connect') throw new TypeError('Failed to fetch');
        if (mode === 'body') return new Response(new ReadableStream({ start(controller) { controller.error(new TypeError('network error')); } }));
        return new Response('ok');
      }
    };
    const failureHost = createBrowserIO({ getInstance: () => fetchInstance, environment: fetchEnvironment, baseURL: 'https://example.test' });
    const run = async (id, path) => {
      const packet = request(path);
      const pointer = fetchInstance.exports.browser_io_alloc(packet.length);
      new Uint8Array(memory.buffer, pointer, packet.length).set(packet);
      assert.equal(failureHost.imports.request(id, 1, pointer, packet.length), 0);
      for (let i = 0; i < 1000 && !statuses.has(id); i++) await new Promise(resolve => setTimeout(resolve, 1));
      return statuses.get(id);
    };
    assert.equal(await run(1, '/connect-failure'), -9);
    online = false; assert.equal(await run(2, '/offline'), -12); online = true;
    mode = 'body'; assert.equal(await run(3, '/body-failure'), -13);
    mode = 'ok';
    assert.equal(await run(4, 'ftp://example.test/scheme'), -15);
    assert.equal(await run(5, 'http://[bad/url'), -16);
    failureHost.dispose();
    tests++; }
  { // Upload progress comes from XMLHttpRequest, the only browser API that reports request-body bytes.
    const memory = new WebAssembly.Memory({ initial: 2 });
    const events = [];
    let top = 64;
    const xhrInstance = { exports: { memory, browser_io_alloc: (n) => { const p = top; top += n + 16; return p; }, browser_io_deliver(id, status, p, n) { events.push({ id, status, payload: new Uint8Array(memory.buffer, p, n).slice() }); }, browser_io_free() {} } };
    const created = [];
    let failTransfer = false;
    let holdTransfer = false;
    class FakeXMLHttpRequest {
      constructor() { this.upload = {}; this.requestHeaders = {}; created.push(this); }
      open(method, url) { this.method = method; this.url = url; }
      setRequestHeader(name, value) { this.requestHeaders[name.toLowerCase()] = value; }
      getAllResponseHeaders() { return 'content-type: text/plain\r\nset-cookie: secret=1\r\nx-upload: accepted\r\n'; }
      send(body) {
        this.body = body;
        if (failTransfer) { queueMicrotask(() => this.onerror?.()); return; }
        if (holdTransfer) return;
        const total = body.length;
        this.upload.onprogress?.({ lengthComputable: true, loaded: 2, total });
        this.upload.onprogress?.({ lengthComputable: true, loaded: total, total });
        queueMicrotask(() => { this.status = 201; this.responseURL = this.url; this.response = new TextEncoder().encode('accepted').buffer; this.onload?.(); });
      }
      abort() { this.onabort?.(); }
    }
    const xhrHost = createBrowserIO({ getInstance: () => xhrInstance, environment: { navigator: { onLine: true }, fetch: async () => new Response('fetched'), XMLHttpRequest: FakeXMLHttpRequest }, baseURL: 'https://example.test' });
    const packetFor = (path, { credentials = 'same-origin', mode = 2, body = new Uint8Array([1, 2, 3, 4, 5, 6]) } = {}) => new Writer().text(path).text('POST').text(credentials).text('follow').u32(1000).u32(1024).u32(mode).u32(0).u32(1).data(body).bytes();
    const deliverAt = (id, packet) => { const pointer = xhrInstance.exports.browser_io_alloc(packet.length); new Uint8Array(memory.buffer, pointer, packet.length).set(packet); return xhrHost.imports.request(id, 1, pointer, packet.length); };
    const waitFor = async (predicate) => { for (let i = 0; i < 1000 && !predicate(); i++) await new Promise(resolve => setTimeout(resolve, 1)); };
    const statusOf = (id) => events.find(e => e.id === id && e.status < 100)?.status;

    assert.equal(deliverAt(1, packetFor('/upload')), 0);
    await waitFor(() => statusOf(1) !== undefined);
    const progress = events.filter(e => e.id === 1 && e.status === 102).map(e => { const r = new Reader(e.payload); return [Number(r.u64()), Number(r.u64())]; });
    assert.deepEqual(progress, [[2, 6], [6, 6]]);
    assert.equal(statusOf(1), 0);
    assert.equal(created.length, 1);
    assert.equal(created[0].method, 'POST');
    assert.equal(created[0].withCredentials, false);
    assert.deepEqual([...created[0].body], [1, 2, 3, 4, 5, 6]);
    const finalReader = new Reader(events.find(e => e.id === 1 && e.status === 0).payload);
    assert.equal(finalReader.u32(), 201);
    assert.equal(finalReader.text(), 'https://example.test/upload');
    assert.equal(finalReader.u32(), 2);
    assert.deepEqual([finalReader.text(), finalReader.text()], ['content-type', 'text/plain']);
    assert.deepEqual([finalReader.text(), finalReader.text()], ['x-upload', 'accepted']);
    assert.equal(finalReader.data().length, 'accepted'.length);

    // Credentials 'omit' cannot be honored by XMLHttpRequest, so the request uses fetch without progress.
    assert.equal(deliverAt(2, packetFor('/omit', { credentials: 'omit' })), 0);
    await waitFor(() => statusOf(2) !== undefined);
    assert.equal(created.length, 1);
    assert.equal(events.some(e => e.id === 2 && e.status === 102), false);
    assert.equal(statusOf(2), 0);

    // include is passed to XMLHttpRequest as withCredentials.
    assert.equal(deliverAt(3, packetFor('/include', { credentials: 'include' })), 0);
    await waitFor(() => statusOf(3) !== undefined);
    assert.equal(created[created.length - 1].withCredentials, true);

    // A transfer that fails before the response is a connection failure, as with fetch.
    failTransfer = true;
    assert.equal(deliverAt(4, packetFor('/refused')), 0);
    await waitFor(() => statusOf(4) !== undefined);
    failTransfer = false;
    assert.equal(statusOf(4), -9);
    // A request header reaches the XMLHttpRequest (names are case-insensitive there).
    const headered=new Writer().text('/headers').text('POST').text('same-origin').text('follow').u32(1000).u32(1024).u32(2).u32(1).text('X-Trace').text('abc').u32(1).data(new Uint8Array([7])).bytes();
    assert.equal(deliverAt(5, headered), 0);
    await waitFor(() => statusOf(5) !== undefined);
    assert.equal(created[created.length - 1].requestHeaders['x-trace'], 'abc');
    assert.equal(statusOf(5), 0);
    // Cancelling a transfer that is still in flight aborts the XMLHttpRequest and reports the call as cancelled.
    holdTransfer = true;
    assert.equal(deliverAt(6, packetFor('/held')), 0);
    await waitFor(() => created[created.length - 1]?.url?.endsWith('/held'));
    xhrHost.imports.cancel(6);
    await waitFor(() => statusOf(6) !== undefined);
    holdTransfer = false;
    assert.equal(statusOf(6), -4);
    xhrHost.dispose();
    tests++; }
  // Style 10 carries a Swift FormatStyle as `name=value;...`. Only allow-listed
  // Intl.DateTimeFormat options reach the formatter; malformed pairs and unknown
  // names are dropped, and `timeZone=local` opts out of the explicit offset shift.
  { const custom=(options,{offset=0,epoch=0}={})=>{const reader=syncResult(13,new Writer().f64(epoch).u32(10).text('en-US').text('gregory').u32(offset>>>0).text(options).bytes());assert.equal(reader.u32(),0);const value=reader.u32()===0?null:reader.text();reader.finish();return value;};
    assert.equal(custom('year=numeric'),'1970');
    assert.equal(custom('year=numeric',{offset:-3600}),'1969');
    assert.equal(custom('year=numeric;month=bogus;weekday=;=long;noequals;script=alert(1);timeZone=UTC'),'1970');
    assert.equal(custom('hour=2-digit;hour12=false',{offset:3600}),'01');
    assert.match(custom('hour=numeric;hour12=true'),/^12\sAM$/u);
    assert.equal(custom('month=long;day=numeric'),'January 1');
    assert.equal(custom(''),'1/1/1970');
    const localHour=new Intl.DateTimeFormat('en-US',{hour:'2-digit',hour12:false}).format(new Date(0));
    assert.equal(custom('hour=2-digit;hour12=false;timeZone=local',{offset:7200}),localHour);
    tests++; }
  // A sign-in popup: the page-level `openWindow` hook wins (a worker has no window),
  // otherwise `window.open` is used with fixed popup features. Only http(s) URLs pass.
  { const open=(url)=>{const reader=syncResult(15,new Writer().text(url).bytes());const status=reader.u32()|0;const value=status===0?reader.u32():reader.text();reader.finish();return {status,value};};
    const hooked=[];environment.openWindow=url=>{hooked.push(url);return undefined;};
    assert.deepEqual(open('https://example.test/login'),{status:0,value:1});assert.deepEqual(hooked,['https://example.test/login']);
    environment.openWindow=()=>false;assert.deepEqual(open('https://example.test/login'),{status:0,value:0});delete environment.openWindow;
    // The opened window shows another site: it must not keep a way back (`opener`) to navigate this tab.
    const popups=[];const opened={opener:'app'};environment.open=(url,name,features)=>{popups.push([url,name,features]);return opened;};
    assert.deepEqual(open('HTTP://example.test/a'),{status:0,value:1});assert.deepEqual(popups,[['HTTP://example.test/a','popup-window','popup,width=520,height=720']]);assert.equal(opened.opener,null);
    environment.open=()=>null;assert.deepEqual(open('https://example.test/blocked'),{status:0,value:0});
    delete environment.open;assert.deepEqual(open('https://example.test/no-window'),{status:0,value:0});
    assert.equal(open('javascript:alert(1)').status,-1);assert.equal(open('https://example.test/'+'a'.repeat(8192)).status,-1);assert.equal(popups.length,1);
    tests++; }
  // DOM component lifecycle (DOM actions 9 mount, 11 update, 12 unmount): the application registers components in the page
  // (SwiftUIWebDOMComponents.define); the host mounts them against an open ShadowRoot and owns instance state, disposal
  // and cleanup on every failure path. Swift only names the component and sends its state.
  { class FakeShadowRoot { children=[]; append(value){this.children.push(value);} replaceChildren(){this.children=[];} }
    const element=new FakeElement();element.log=[];element.shadowRoot=null;let shadowCount=0;
    element.attachShadow=({mode})=>{assert.equal(mode,'open');shadowCount++;element.shadowRoot=new FakeShadowRoot();return element.shadowRoot;};
    const dispatched=[];element.dispatchEvent=event=>{dispatched.push(event);return true;};
    element.setAttribute('data-web-mount-key','dom-view');element.setAttribute('data-web-mount-token','view-token');
    const originalDocument=environment.document;environment.document={querySelectorAll:()=>[element]};
    environment.CustomEvent=class { constructor(type,init){this.type=type;this.bubbles=init.bubbles;this.composed=init.composed;this.detail=init.detail;} };
    let dom=syncResult(7,domPacket(0,0));assert.equal(dom.u32(),0);assert.equal(dom.u32(),1);const id=dom.u32();dom.text();dom.text();dom.finish();
    const call=(action,name='',value='')=>{const reader=syncResult(7,domPacket(action,id,name,value));const status=reader.u32()|0;const message=status===0?'':reader.text();reader.finish();return {status,message};};
    const mount=(component,state='')=>call(9,component,state), update=state=>call(11,'',state), unmount=()=>call(12);
    const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
    const registry=environment.SwiftUIWebDOMComponents;assert.equal(typeof registry.define,'function','the host installs the page registry');
    const probe=(label)=>({
      mount(host,root,emit,state){host.log.push(`${label}:mount:${state}`);root.append(`content:${state}`);emit('ready');emit();return {label:state};},
      update(instance,state){element.log.push(`${label}:update:${state}`);instance.label=state;element.shadowRoot.append('updated');},
      dispose(instance){element.log.push(`${label}:dispose:${instance.label}`);}
    });
    registry.define('probe',()=>probe('probe'));
    // A defined component mounts at once, with state as data, and emits through the element.
    assert.deepEqual(mount('probe','first'),{status:0,message:''});
    assert.equal(shadowCount,1);assert.deepEqual(element.shadowRoot.children,['content:first']);
    assert.deepEqual(dispatched.map(event=>[event.type,event.bubbles,event.composed,event.detail.name,event.detail.value]),[['dom-view-event',true,true,'domView','ready'],['dom-view-event',true,true,'domView','']]);
    {const r=update('second');assert.equal(r.status,0,r.message);}assert.deepEqual(element.shadowRoot.children,['content:first','updated']);
    // Re-mounting disposes the previous instance, reuses the ShadowRoot and clears it.
    assert.equal(mount('probe','third').status,0);
    assert.equal(shadowCount,1);assert.deepEqual(element.shadowRoot.children,['content:third']);
    assert.equal(unmount().status,0);assert.deepEqual(element.shadowRoot.children,[]);
    assert.deepEqual(element.log,['probe:mount:first','probe:update:second','probe:dispose:second','probe:mount:third','probe:dispose:third']);
    assert.deepEqual(update('stale'),{status:-8,message:'DOMView instance is not mounted'});
    assert.equal(unmount().status,0);assert.equal(element.log.length,5,'a second unmount changes nothing');
    // An emit after the component was disposed goes nowhere.
    let lateEmit;registry.define('late-emit',()=>({mount(host,root,emit){lateEmit=emit;return {};},update(){}}));
    assert.equal(mount('late-emit').status,0);unmount();const emitted=dispatched.length;lateEmit('ghost');assert.equal(dispatched.length,emitted);
    // A component nobody defined yet leaves the mount pending: the call returns at once, the LATEST state is kept, and the
    // definition mounts it. An unmount before that cancels the mount.
    element.log.length=0;
    assert.equal(mount('later','one').status,0);assert.equal(update('two').status,0);assert.equal(update('three').status,0);
    assert.deepEqual(element.log,[],'nothing mounts before the definition');
    registry.define('later',()=>probe('later'));
    assert.deepEqual(element.log,['later:mount:three'],'the pending mount uses the latest state');
    assert.equal(unmount().status,0);
    element.log.length=0;
    assert.equal(mount('cancelled','x').status,0);assert.equal(unmount().status,0);
    registry.define('cancelled',()=>probe('cancelled'));
    assert.deepEqual(element.log,[],'a mount cancelled before its definition never runs');
    // A factory that loads asynchronously: the mount waits for it, takes the latest state, and a mount replaced in
    // the meantime is not revived by the load.
    let finishLoad;registry.define('slow',()=>new Promise(resolve=>{finishLoad=()=>resolve(probe('slow'));}));
    assert.equal(mount('slow','a').status,0);assert.equal(update('b').status,0);assert.deepEqual(element.log,[]);
    finishLoad();await tick();
    assert.deepEqual(element.log,['slow:mount:b']);assert.equal(unmount().status,0);
    element.log.length=0;registry.define('slow-replaced',()=>new Promise(resolve=>{finishLoad=()=>resolve(probe('slow-replaced'));}));
    assert.equal(mount('slow-replaced','a').status,0);assert.equal(mount('probe','other').status,0);finishLoad();await tick();
    assert.deepEqual(element.log,['probe:mount:other'],'a replaced mount is not revived');assert.equal(unmount().status,0);
    // A factory runs once, on the first mount, and its result serves every later mount.
    let factoryCalls=0;registry.define('counted',()=>{factoryCalls++;return probe('counted');});
    assert.equal(factoryCalls,0,'defining does not load');mount('counted');unmount();mount('counted');unmount();assert.equal(factoryCalls,1);
    // Failures are lifecycle errors with codes, never an EvalError: a throwing or invalid factory fails the mount
    // call, a throwing mount leaves no partial content, and a component that is async in mount is refused.
    registry.define('broken',()=>{throw new Error('boom');});
    let failed=mount('broken');assert.equal(failed.status,-1);assert.match(failed.message,/DOM component "broken" failed to load: boom/);assert.equal(update('x').status,-8);
    registry.define('shapeless',()=>({}));
    failed=mount('shapeless');assert.equal(failed.status,-1);assert.match(failed.message,/must provide mount\(host, root, emit, state\) and update\(instance, state\)/);
    registry.define('throws',()=>({mount(host,root){root.append('partial');throw new Error('mount failed');},update(){}}));
    failed=mount('throws');assert.equal(failed.status,-6);assert.match(failed.message,/mount failed/);assert.deepEqual(element.shadowRoot.children,[]);assert.equal(update('x').status,-8);
    registry.define('async-mount',()=>({mount(host,root){root.append('async');return Promise.resolve({});},update(){}}));
    failed=mount('async-mount');assert.equal(failed.status,-1);assert.match(failed.message,/must mount synchronously/);assert.deepEqual(element.shadowRoot.children,[]);assert.equal(update('x').status,-8);
    assert.equal(mount('').status,-1);
    // A failure the host can only see later is reported on the element: a factory that rejects, an update that rejects.
    element.removeAttribute('data-dom-view-error');
    registry.define('rejecting',async()=>{throw new Error('chunk 404');});
    assert.equal(mount('rejecting').status,0);await tick();
    assert.match(element.getAttribute('data-dom-view-error')??'',/DOM component "rejecting" failed to load: chunk 404/);assert.equal(update('x').status,-8,'a failed mount leaves nothing mounted');
    element.removeAttribute('data-dom-view-error');
    registry.define('bad-update',()=>({mount(){return {};},update:async()=>{throw new Error('update failed');}}));
    assert.equal(mount('bad-update').status,0);assert.equal(update('x').status,0);await tick();assert.match(element.getAttribute('data-dom-view-error')??'',/update failed/);unmount();
    // A throwing dispose during re-mount still clears and forgets the old instance.
    registry.define('bad-dispose',()=>({mount(){return {};},update(){},dispose(){throw new Error('dispose failed');}}));
    assert.equal(mount('bad-dispose').status,0);
    failed=mount('probe');assert.equal(failed.status,-6);assert.match(failed.message,/dispose failed/);assert.deepEqual(element.shadowRoot.children,[]);assert.equal(update('x').status,-8);
    // The registry refuses a duplicate or malformed definition.
    assert.throws(()=>registry.define('probe',()=>probe('again')),/already defined/);
    assert.throws(()=>registry.define('',()=>probe('x')),TypeError);assert.throws(()=>registry.define('x','not a function'),TypeError);
    assert.deepEqual(call(13),{status:-1,message:'Unknown DOM bridge action'});
    // A removed mount is reported by one reconciliation (mounts) and then unmounted by it: its handle must survive
    // that call, so the unmount still reaches the element; it is dropped only after the next reconciliation.
    element.isConnected=true;environment.document={querySelectorAll:()=>[element]};element.log.length=0;
    assert.equal(mount('probe','again').status,0);
    element.isConnected=false;environment.document={querySelectorAll:()=>[]};
    dom=syncResult(7,domPacket(0,0));assert.equal(dom.u32(),0);assert.equal(dom.u32(),0);dom.finish();
    assert.equal(unmount().status,0);assert.equal(element.log.at(-1),'probe:dispose:again');
    dom=syncResult(7,domPacket(0,0));assert.equal(dom.u32(),0);assert.equal(dom.u32(),0);dom.finish();
    assert.deepEqual(unmount(),{status:-8,message:'Unknown DOM element handle'});
    environment.document=originalDocument;delete environment.CustomEvent;tests++; }
  // The host alone: an unknown name is reported once after the grace period (and the mount still completes when the
  // definition arrives later), definitions queued before the framework started are adopted, and nothing is evaluated.
  { const timers=[];const reports=[];
    const win={CustomEvent:class{constructor(type,init){this.type=type;this.detail=init.detail;}},setTimeout:(fn,ms)=>{timers.push({fn,ms});return timers.length;},clearTimeout:handle=>{timers[handle-1]=null;}};
    win.SwiftUIWebDOMComponents={queue:[['queued',()=>({mount(){return {};},update(){}})]],define(){throw new Error('replaced by the host');}};
    const early=win.SwiftUIWebDOMComponents;
    const hostOnly=createDOMViewHost(win,{report:(element,error)=>reports.push([element.id,error.code,error.message])});
    assert.equal(win.SwiftUIWebDOMComponents,early,'the queued global becomes the registry');assert.equal(installDOMComponentRegistry(win),early,'installing twice shares one registry');
    class Host{constructor(id){this.id=id;this.attributes=new Map();this.shadowRoot=null;this.log=[];}
      attachShadow(){this.shadowRoot={replaceChildren(){}};return this.shadowRoot;}removeAttribute(name){this.attributes.delete(name);}dispatchEvent(){return true;}}
    const hostA=new Host('a');hostOnly.lifecycle('mount',hostA,{component:'queued',state:''});assert.deepEqual(reports,[],'a queued definition mounts');hostOnly.lifecycle('unmount',hostA);
    const hostB=new Host('b');hostOnly.lifecycle('mount',hostB,{component:'nobody',state:'s'});
    assert.equal(timers.length,1);assert.equal(timers[0].ms,10_000);timers[0].fn();
    assert.deepEqual(reports,[['b',-8,'DOM component "nobody" is not defined: call SwiftUIWebDOMComponents.define("nobody", factory)']]);
    let mounted;win.SwiftUIWebDOMComponents.define('nobody',()=>({mount(host,root,emit,state){mounted=state;return {};},update(){}}));
    assert.equal(mounted,'s','the late definition still mounts the waiting view');
    hostOnly.lifecycle('unmount',hostB);
    const hostC=new Host('c');hostOnly.lifecycle('mount',hostC,{component:'never',state:''});hostOnly.lifecycle('unmount',hostC);assert.equal(timers[1],null,'an unmount cancels the pending timer');
    assert.throws(()=>hostOnly.lifecycle('refresh',hostC,{}),/Unknown DOMView lifecycle phase/);
    tests++; }
  // Worker mode of the DOM bridge: there is no document, so reads come from the table the main
  // thread reported, writes and lifecycle calls are queued in order, and a failed DOM lookup
  // is an error (never a silent success).
  { const remoteHost=createBrowserIO({getInstance:()=>instance,environment:{},baseURL,remoteDOM:true});
    // Each reply is a status word, then the payload (success) or the error text.
    const remote=(action,id,name='',value='')=>{const packet=domPacket(action,id,name,value);const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const handle=remoteHost.imports.sync(7,p,packet.length);const length=remoteHost.imports.length(handle);const out=alloc(length);assert.equal(remoteHost.imports.copy(handle,out,length),length);const bytes=new Uint8Array(memory.buffer,out,length).slice();remoteHost.imports.release(handle);const reader=new Reader(bytes);reader.status=reader.u32()|0;return reader;};
    let reader=remote(0,0);assert.equal(reader.status,0);assert.equal(reader.u32(),0,'no mounts before the first table');reader.finish();
    remoteHost.domTable(3,[{node:7,key:'view',token:'view-token',attributes:{'data-role':'chart'},value:null,text:'label'}]);
    // The mirror a taking-over host reads holds the table as the main thread reported it.
    assert.deepEqual(remoteHost.domState(),{seq:3,table:[{node:7,key:'view',token:'view-token',attributes:{'data-role':'chart'},value:null,text:'label'}]});
    reader=remote(0,0);assert.equal(reader.u32(),1);assert.equal(reader.u32(),7);assert.equal(reader.text(),'view');assert.equal(reader.text(),'view-token');reader.finish();
    reader=remote(2,7,'data-role');assert.equal(reader.u32(),1);assert.equal(reader.text(),'chart');reader.finish();
    reader=remote(1,7);assert.equal(reader.u32(),1);reader.finish();
    reader=remote(6,7);assert.equal(reader.u32(),1);assert.equal(reader.text(),'label');reader.finish();
    reader=remote(3,7,'data-x','1');assert.equal(reader.status,0);reader.finish();
    reader=remote(9,7,'probe','first');assert.equal(reader.status,0);reader.finish();
    reader=remote(11,7,'','second');assert.equal(reader.status,0);reader.finish();
    reader=remote(10,0,'','missing root');assert.equal(reader.status,0);reader.finish();
    assert.deepEqual(remoteHost.domFlush(),{seq:3,ops:[{op:'attr',node:7,name:'data-x',value:'1'},{op:'dom-view',node:7,phase:'mount',component:'probe',state:'first'},{op:'dom-view',node:7,phase:'update',state:'second'},{op:'report',node:0,message:'missing root'}]});
    assert.equal(remoteHost.domFlush(),null,'a flush hands the queue over once');
    // A repeated report is queued once; a media call has no element in the worker and says so (status -7).
    reader=remote(10,0,'','missing root');assert.equal(reader.status,0);reader.finish();
    assert.equal(remoteHost.domFlush(),null,'a repeated report is not queued twice');
    { const packet=mediaPacket(0,7,'',0,false);const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);const handle=remoteHost.imports.sync(8,p,packet.length);const length=remoteHost.imports.length(handle);const out=alloc(length);remoteHost.imports.copy(handle,out,length);const bytes=new Uint8Array(memory.buffer,out,length).slice();remoteHost.imports.release(handle);const media=new Reader(bytes);assert.equal(media.u32()|0,-7);assert.match(media.text(),/not bridged from the worker runtime/);media.finish();}
    // An unknown handle fails the call; an unknown action is rejected before anything is queued.
    reader=remote(2,99,'x');assert.equal(reader.status,-8);assert.equal(reader.text(),'Unknown DOM element handle');
    reader=remote(13,7,'refresh','');assert.equal(reader.status,-1);assert.equal(reader.text(),'Unknown DOM bridge action');
    assert.equal(remoteHost.domFlush(),null,'nothing is queued for a rejected call');
    // An element that has just left the table still gets its unmount queued.
    reader=remote(12,42);assert.equal(reader.status,0);reader.finish();
    assert.deepEqual(remoteHost.domFlush(),{seq:3,ops:[{op:'dom-view',node:42,phase:'unmount'}]});
    tests++; }
  // On the main thread, a DOM error the page reports (action 10) is logged and written to the app root's error attribute
  // when no element is named; the call still succeeds.
  { const logs=[];const body=new FakeElement();environment.console={error:(message)=>logs.push(message)};environment.document={getElementById:()=>null,body};
    const reply=syncResult(7,domPacket(10,0,'','layout broke'));assert.equal(reply.u32()|0,0);reply.finish();
    assert.deepEqual(logs,['[SwiftUIWeb] layout broke']);assert.equal(body.getAttribute('data-dom-view-error'),'layout broke');
    delete environment.console;delete environment.document;tests++; }
  // A secure-store transaction the browser aborts reports the IndexedDB error, and the
  // per-store queue keeps serving later operations instead of staying rejected.
  { const indexedDB=new FakeIndexedDB();environment.indexedDB=indexedDB;environment.crypto=globalThis.crypto;
    const securePacket=(action,key='',value=new Uint8Array())=>new Writer().text('aborting').u32(action).text(key).data(value).bytes();
    events=await send(14,securePacket(1,'kept',new Uint8Array([4,2])));assert.equal(events.at(-1).status,0);
    const db=indexedDB.opened.find(d=>d.name==='swui:security:aborting');db.abortNextTransaction=true;
    events=await send(14,securePacket(3));assert.equal(events.at(-1).status,-6);assert.match(new TextDecoder().decode(events.at(-1).bytes),/simulated IndexedDB transaction failure/);
    assert.ok(db.records.has('item:kept'),'the aborted clear rolled back');
    events=await send(14,securePacket(0));assert.equal(events.at(-1).status,0);r=new Reader(events.at(-1).bytes);assert.equal(r.u32(),1);assert.equal(r.text(),'kept');assert.deepEqual([...r.data()],[4,2]);r.finish();
    delete environment.crypto;delete environment.indexedDB;tests++; }
  // `wake` asks the page to drain the Swift executor; a disposed host never wakes it.
  { let woken=0;const wakingHost=createBrowserIO({getInstance:()=>instance,environment,baseURL,wake:()=>{woken++;}});
    wakingHost.imports.wake();wakingHost.imports.wake();assert.equal(woken,2);
    wakingHost.dispose();wakingHost.imports.wake();assert.equal(woken,2);
    host.imports.wake();tests++; }
  // A host that takes over from another (the app moved from a Worker to the main thread) restarts the timers, observers
  // and read-only fetches the first one listed, shortens a timer to the time left, and reports the rest as cancelled.
  { let alive=true;const first=createBrowserIO({getInstance:()=>alive?instance:null,environment,baseURL,onError:()=>{}});
    const ids={timer:9001,get:9002,post:9003};const seen=new Map();
    for(const id of Object.values(ids))pending.set(id,(status)=>{seen.set(id,[...(seen.get(id)||[]),status]);});
    const start=(id,operation,packet)=>{const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);assert.equal(first.imports.request(id,operation,p,packet.length),0);};
    start(ids.timer,BrowserIOOperation.timer,new Writer().f64(0.3).bytes());
    start(ids.get,BrowserIOOperation.fetch,request('/slow'));
    start(ids.post,BrowserIOOperation.fetch,request('/slow',{method:'POST',body:new Uint8Array([1])}));
    await new Promise(resolve=>setTimeout(resolve,60));
    const list=first.inflight();alive=false;first.dispose();
    assert.deepEqual(list.map(item=>item.id),[ids.timer,ids.get,ids.post]);
    assert.ok(list[0].packet&&new Reader(list[0].packet).f64()<0.3,'the timer restarts with the time left');
    assert.ok(list[1].packet,'a read-only fetch can run again');assert.equal(list[2].packet,null,'a write cannot');
    seen.clear();alive=true;
    const second=createBrowserIO({getInstance:()=>instance,environment,baseURL});second.resume(list);
    await new Promise(resolve=>setTimeout(resolve,700));
    assert.deepEqual(seen.get(ids.timer),[0]);assert.deepEqual(seen.get(ids.get),[0]);assert.deepEqual(seen.get(ids.post),[-4]);
    assert.equal(second.diagnostics().activeOperations,0);second.dispose();for(const id of Object.values(ids))pending.delete(id);tests++; }
  // The thread takeover fences side effects. A write that has not started is dropped when the app moves; a read-only
  // request is kept. A write the Worker already sent is listed by `sentSinceSnapshot`, and a replay of it fails on the
  // main thread instead of being sent again, until `refuseReplayed` is called with an empty list. A snapshot forgets sends.
  { const seen=new Map();const watch=(id)=>{seen.delete(id);pending.set(id,(status,bytes)=>{seen.set(id,[...(seen.get(id)??[]),{status,bytes}]);});};
    const start=(h,id,operation,packet)=>{watch(id);const p=alloc(packet.length);new Uint8Array(memory.buffer,p,packet.length).set(packet);assert.equal(h.imports.request(id,operation,p,packet.length),0);};
    const settle=()=>new Promise(resolve=>setTimeout(resolve,100));
    let fetches=0;const replayEnv={...environment,fetch:(...args)=>{fetches++;return globalThis.fetch(...args);}};
    const worker=createBrowserIO({getInstance:()=>instance,environment:replayEnv,baseURL,onError:()=>{}});
    start(worker,7101,BrowserIOOperation.fetch,request('/echo',{method:'POST',body:new Uint8Array([9])}));
    start(worker,7102,BrowserIOOperation.fetch,request('/missing'));
    worker.fenceUnstarted();
    assert.equal(worker.diagnostics().activeOperations,1,'only the unstarted write is dropped');
    await settle();
    assert.equal(seen.get(7101),undefined,'a fenced write never runs or reports');
    assert.equal(new Reader(seen.get(7102)[0].bytes).u32(),404,'a read-only request that was not started still completes');
    assert.equal(fetches,1,'only the read-only request was sent');
    const sentPacket=request('/echo',{method:'POST',body:new Uint8Array([0,255,11,22])});
    start(worker,7103,BrowserIOOperation.fetch,sentPacket);await settle();
    assert.equal(seen.get(7103).at(-1).status,0);
    const sentList=worker.sentSinceSnapshot();
    assert.deepEqual(sentList.map(item=>item.id),[7103]);assert.equal(sentList[0].operation,BrowserIOOperation.fetch);assert.deepEqual(sentList[0].packet,sentPacket);
    worker.snapshotTaken();assert.deepEqual(worker.sentSinceSnapshot(),[],'a snapshot forgets the sends it covers');
    // The main thread takes over with the Worker's sends: the replay of 7103 is refused and not sent again.
    const main=createBrowserIO({getInstance:()=>instance,environment:replayEnv,baseURL,onError:()=>{}});
    main.refuseReplayed(sentList);
    const before=fetches;
    // A replay with another body (same length, then a different length) is not the refused request: it is sent and
    // leaves the refusal in place.
    start(main,7103,BrowserIOOperation.fetch,request('/echo',{method:'POST',body:new Uint8Array([0,255,11,23])}));await settle();
    assert.equal(seen.get(7103).at(-1).status,0);
    start(main,7103,BrowserIOOperation.fetch,request('/echo',{method:'POST',body:new Uint8Array([0,255,11])}));await settle();
    assert.equal(seen.get(7103).at(-1).status,0);
    assert.equal(fetches,before+2,'the two other bodies were sent');
    // The exact request is refused once, and the refusal is then used up.
    start(main,7103,BrowserIOOperation.fetch,sentPacket);await settle();
    assert.equal(seen.get(7103).at(-1).status,-6);assert.match(new TextDecoder().decode(seen.get(7103).at(-1).bytes),/already sent before the app moved/);
    assert.equal(fetches,before+2,'the refused replay sends nothing');
    // An empty list clears any refusals still listed.
    main.refuseReplayed(sentList);main.refuseReplayed([]);
    start(main,7103,BrowserIOOperation.fetch,sentPacket);await settle();
    assert.equal(seen.get(7103).at(-1).status,0);assert.equal(new Reader(seen.get(7103)[0].bytes).u32(),201);
    for(const id of [7101,7102,7103])pending.delete(id);
    main.dispose();worker.dispose();tests++; }
  // The stack meter receives each depth the WASM stack reports, read as an unsigned number.
  { const samples=[];const metered=createBrowserIO({getInstance:()=>instance,environment,baseURL,stackMeter:{sample:(depth)=>samples.push(depth)}});
    metered.imports.stack_headroom(7);metered.imports.stack_headroom(-1);assert.deepEqual(samples,[7,4294967295]);metered.dispose();tests++; }
  // The binary publication atoms a release app.wasm reads instead of carrying them: the length when they do not fit, then the
  // NUL-separated bytes at the pointer.
  { const atomsMemory=new WebAssembly.Memory({initial:1});const atomsHost=createBrowserIO({getInstance:()=>({exports:{memory:atomsMemory}}),environment,baseURL,binaryAtoms:BINARY_ATOMS.join('\0')});
    const expected=new TextEncoder().encode(BINARY_ATOMS.join('\0'));const view=new Uint8Array(atomsMemory.buffer);
    assert.equal(atomsHost.imports.binary_atoms(64,0),expected.length);assert.equal(view[64],0);
    assert.equal(atomsHost.imports.binary_atoms(64,expected.length),expected.length);assert.deepEqual(view.slice(64,64+expected.length),expected);
    atomsHost.dispose();tests++; }
  { const bare=createBrowserIO({getInstance:()=>instance,environment,baseURL});assert.equal(bare.imports.binary_atoms(0,0),0);bare.dispose();tests++; }
  // `fileMover`: a File System Access picker writes the bytes and persists a reopenable handle; a browser
  // without one downloads copies and reports it so the sources are kept.
  { const written=new Map();
    class FakeDirectory { constructor(){this.files=new Map();} async getFileHandle(name,{create=false}={}){ if(!this.files.has(name)){ if(!create){const e=new Error('missing');e.name='NotFoundError';throw e;} this.files.set(name,new Uint8Array()); } const dir=this; return { name, async createWritable(){ return { async write(bytes){dir.files.set(name,bytes.slice());}, async close(){} }; }, async getFile(){ const bytes=dir.files.get(name); return { type:'text/plain', async arrayBuffer(){return bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength);} }; } }; } async removeEntry(name){this.files.delete(name);} }
    const directory=new FakeDirectory(); directory.files.set('a.txt',new Uint8Array([9]));
    const indexedDB=new FakeIndexedDB(); let pickerCalls=0;
    const env={ indexedDB, crypto:{randomUUID:()=>'fixed'+(++pickerCalls)}, showDirectoryPicker:()=>Promise.resolve(directory) };
    const entries=[{name:'a.txt',type:'text/plain',bytes:new Uint8Array([1,2])},{name:'é.bin',type:'application/octet-stream',bytes:new Uint8Array([3])}];
    const result=await moveFiles(entries,env);
    assert.match(result,/^moved:moved-fixed1,[^;]+;moved-fixed2,[^;]+$/);
    assert.deepEqual([...directory.files.get('a.txt')],[9],'an existing file is never overwritten');
    assert.deepEqual([...directory.files.get('a 2.txt')],[1,2]);assert.deepEqual([...directory.files.get('é.bin')],[3]);
    const [, first] = result.slice(6).split(';')[0].split(',');assert.equal(atob(first),'a 2.txt');
    const reopened=await reopenMovedFile('moved-fixed1',env);assert.equal(reopened.name,'a 2.txt');assert.deepEqual([...reopened.bytes],[1,2]);
    assert.equal(await reopenMovedFile('absent',env),null);
    // A cancelled picker and a write failure report without leaving partial files behind.
    assert.equal(await moveFiles(entries,{...env,showDirectoryPicker:()=>Promise.reject(Object.assign(new Error('x'),{name:'AbortError'}))}),'cancelled');
    const failing=new FakeDirectory();const original=failing.getFileHandle.bind(failing);let n=0;
    failing.getFileHandle=async(name,o)=>{const h=await original(name,o);if(o?.create&&++n===2)h.createWritable=async()=>{throw new Error('disk full');};return h;};
    assert.equal(await moveFiles(entries,{...env,showDirectoryPicker:()=>Promise.resolve(failing)}),'error:disk full');
    assert.equal(failing.files.size,0,'files written before the failure are removed');
    // A handle the browser cannot persist (a DataCloneError inside the transaction) still completes the move.
    const put=FakeIDBStore.prototype.put;FakeIDBStore.prototype.put=()=>{throw new Error('could not be cloned');};
    try{assert.match(await moveFiles([entries[0]],{...env,indexedDB:new FakeIndexedDB(),showDirectoryPicker:()=>Promise.resolve(new FakeDirectory())}),/^moved:moved-/);}finally{FakeIDBStore.prototype.put=put;}
    // Bytes the app does not hold, and an empty list, never open a picker.
    assert.match(await moveFiles([{name:'x',type:'',bytes:null}],{...env,showDirectoryPicker:()=>{throw new Error('must not open');}}),/^error:/);
    assert.equal(await moveFiles([],env),'cancelled');
    // A single file on a browser with only a save picker.
    const saved=new FakeDirectory();const saveHandle=await saved.getFileHandle('picked.txt',{create:true});
    assert.match(await moveFiles([entries[0]],{indexedDB:new FakeIndexedDB(),showSaveFilePicker:({suggestedName})=>{assert.equal(suggestedName,'a.txt');return Promise.resolve(saveHandle);}}),/^moved:moved-/);
    assert.deepEqual([...saved.files.get('picked.txt')],[1,2]);
    // No File System Access API: sequential downloads of copies, sources kept.
    const clicks=[],urls=[];
    const doc={createElement:()=>({style:{},click(){clicks.push([this.download,this.href]);},remove(){}}),body:{appendChild(){}}};
    const download=await moveFiles(entries,{document:doc,Blob,URL:{createObjectURL:b=>{urls.push(b.size);return 'blob:'+urls.length;},revokeObjectURL(){}},setTimeout:(fn)=>{fn();return 0;}});
    assert.equal(download,'downloaded:2');assert.deepEqual(clicks.map(c=>c[0]),['a.txt','é.bin']);assert.deepEqual(urls,[2,1]);
    tests++; }
  { // The browser's zone and week: a negative (Sao Paulo) and a positive (Lisbon in summer) offset read back signed, the IANA
    // name, and the week of a few locales. `process.env.TZ` changes the zone Node reports, and is restored afterwards.
    const priorZone = process.env.TZ;
    const offsetAt = (epoch) => { const r = syncResult(21, new Writer().f64(epoch).bytes()); assert.equal(r.u32(), 0); const present = r.u32(); const seconds = present ? r.u32() | 0 : null; r.finish(); return seconds; };
    try {
      process.env.TZ = 'America/Sao_Paulo';
      assert.equal(offsetAt(Date.UTC(2026, 10, 11, 13) / 1000), -3 * 3600);
      const name = syncResult(22, new Uint8Array(0)); assert.equal(name.u32(), 0); assert.equal(name.u32(), 1); assert.equal(name.text(), 'America/Sao_Paulo'); name.finish();
      process.env.TZ = 'Europe/Lisbon';
      assert.equal(offsetAt(Date.UTC(2026, 6, 1, 12) / 1000), 3600);
      const week = (tag) => { const r = syncResult(23, new Writer().text(tag).bytes()); assert.equal(r.u32(), 0); const present = r.u32(); const firstDay = present ? r.u32() : null; if (present) r.u32(); r.finish(); return firstDay; };
      // pt-PT is Sunday-first in the Intl data this runtime ships; the answer follows the host, whatever the locale table says.
      assert.equal(week('en-GB'), 1); assert.equal(week('de-DE'), 1); assert.equal(week('pt-PT'), 7);
      assert.equal(week('en-US'), 7); assert.equal(week('pt-BR'), 7);
      assert.equal(week(''), null); // no tag and no navigator language: the host answers nothing
      tests++;
    } finally {
      if (priorZone === undefined) delete process.env.TZ; else process.env.TZ = priorZone;
    }
  }
  assert.equal(host.diagnostics().activeOperations,0);host.dispose();assert.equal(host.diagnostics().disposed,true);tests++;
  console.log(JSON.stringify({status:'PASS',groups:tests,network:'real local HTTP server',memory:'WebAssembly.Memory with JS callback fixture',storage:'in-memory test fixture, not browser persistence',swiftFacade:'compiled by make embedded-network-storage-test before this host suite'},null,2));
} finally {host.dispose();server.closeAllConnections?.();await new Promise(resolve=>server.close(resolve));}
