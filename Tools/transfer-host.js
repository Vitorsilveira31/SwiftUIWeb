/** What moves content in and out of the page: native drag and drop (`onDrag`, `onDrop`, `draggable`, `dropDestination`),
 * `ShareLink` and `fileMover`.
 * The first screen does not need it: embedded-dom.js loads it with import() once the first publication is on screen
 * (deferred-hosts.js). This module imports nothing, because a module it shared with the first chunk would become a chunk of
 * its own that the first screen loads; the helpers below are repeated from host-interactions.js for that reason. */
const EVENT='data-embedded-event-id';
const targetOf=e=>e?.nodeType===1?e:e?.parentElement;
const disabled=e=>!e||!!e.closest('[disabled],[aria-disabled="true"],[inert]');

export async function shareContent(element,navigator=globalThis.navigator){
  const item=element.getAttribute('data-share-item')||'',title=element.getAttribute('data-share-subject')||undefined,message=element.getAttribute('data-share-message')||undefined;
  let url;try{const parsed=new URL(item);if(['https:','http:'].includes(parsed.protocol))url=parsed.href;}catch{}
  const data={...(title?{title}:{}),...(url?{url}:{}),...((message||!url)?{text:message||item}:{})};
  if(navigator.share&&(!navigator.canShare||navigator.canShare(data))){try{await navigator.share(data);return {status:'shared'};}catch(error){if(error?.name==='AbortError')return {status:'cancelled'};if(!['NotAllowedError','NotSupportedError','TypeError'].includes(error?.name))throw error;}}
  if(navigator.clipboard?.writeText){await navigator.clipboard.writeText([message,item].filter(Boolean).join('\n'));return {status:'copied'};}
  // A meaningful result is exposed to the host instead of silently succeeding.
  return {status:'unsupported',text:[message,item].filter(Boolean).join('\n')};
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
