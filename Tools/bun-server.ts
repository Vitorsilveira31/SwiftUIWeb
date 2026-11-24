import {resolve,relative,isAbsolute,basename,dirname,join} from 'node:path';
import {realpath} from 'node:fs/promises';
import {resolveRequest,mime,isLoopbackHost} from './dev-server-policy.mjs';
import {createLiveReload} from './live-reload.mjs';
import {isDictionaryModule,useAsDictionary,parseAvailableDictionary,acceptsDcb,differenceName,VARY} from './dictionary-transport.mjs';
const root=await realpath(resolve(process.argv[2]||'.'));
const port=Number(process.env.PORT||process.argv[3]||8080);
if(!Number.isInteger(port)||port<1||port>65535)throw Error('PORT must be an integer from 1 to 65535');
// Optional development proxy: requests under SWIFTUIWEB_API_PATH (for example `/api`) go to
// SWIFTUIWEB_API_ORIGIN with that prefix removed, so an application whose API expects to share the
// page's origin can be developed against a separately running server. Both must be set; the
// framework itself assumes no API path, origin or deployment.
const apiOrigin=String(process.env.SWIFTUIWEB_API_ORIGIN||'').replace(/\/+$/,'');
const apiPath=String(process.env.SWIFTUIWEB_API_PATH||'').replace(/\/+$/,'');
if(apiOrigin&&!apiPath.startsWith('/'))throw Error('SWIFTUIWEB_API_ORIGIN needs SWIFTUIWEB_API_PATH, a path such as /api');
// The proxied request must stay on the configured backend origin. A remainder that begins with `//` (or contains a
// backslash) names an authority, not a path, so it is refused before it is resolved; the resolved URL is then pinned to
// the backend origin as a second check. A refused request gets REFUSED, never a fallback to the static files.
const REFUSED=Symbol('refused');
function apiTarget(request){
  if(!apiOrigin)return null;
  const incoming=new URL(request.url);
  if(incoming.pathname!==apiPath&&!incoming.pathname.startsWith(apiPath+'/'))return null;
  const backendPath=incoming.pathname.slice(apiPath.length)||'/';
  if(backendPath.startsWith('//')||backendPath.includes('\\'))return REFUSED;
  const backend=new URL(apiOrigin+'/');
  const target=new URL(backendPath+incoming.search,backend);
  if(target.origin!==backend.origin)return REFUSED;
  return target;
}
// Headers that describe this hop, not the request: the backend gets its own Host.
const hopHeaders=new Set(['host','connection','keep-alive','proxy-authorization','proxy-connection','te','trailer','transfer-encoding','upgrade']);
function proxyHeaders(request){
  const headers=new Headers();
  for(const [name,value] of request.headers)if(!hopHeaders.has(name.toLowerCase()))headers.set(name,value);
  return headers;
}
// A state-changing request must come from this server's own page: another
// site open in the same browser cannot drive the API through the proxy.
function crossOrigin(request){
  if(request.method==='GET'||request.method==='HEAD'||request.method==='OPTIONS')return false;
  const origin=request.headers.get('Origin');
  return origin!==null&&origin!==new URL(request.url).origin;
}
// Content-hashed names written by Tools/hash-release-bundle.mjs: `name.<8 lowercase hex>.ext`.
const HASHED_NAME=/\.[0-9a-f]{8}\.[a-z0-9]+$/;
// The precompressed siblings Tools/precompress-bundle.mjs writes, in preference order.
const CODINGS=[{name:'br',suffix:'.br'},{name:'gzip',suffix:'.gz'}];
// The codings a request accepts (q-value above zero); `Accept-Encoding: br;q=0` refuses brotli.
function acceptedCodings(header){
  const accepted=new Set();
  for(const item of (header||'').split(',')){
    const [coding,...params]=item.trim().toLowerCase().split(';');
    const quality=params.map(p=>p.trim()).find(p=>p.startsWith('q='));
    if(coding&&(!quality||Number(quality.slice(2))>0))accepted.add(coding.trim());
  }
  return accepted;
}
// The precompressed sibling to send for `actual`, when the request accepts its coding and the sibling stays in the root.
async function negotiatedCoding(header,actual,root){
  const accepted=acceptedCodings(header);
  for(const coding of CODINGS){
    if(!accepted.has(coding.name))continue;
    const sibling=actual+coding.suffix;
    if(!(await Bun.file(sibling).exists()))continue;
    const real=await realpath(sibling),rel=relative(root,real);
    if(rel.startsWith('..')||isAbsolute(rel))continue;
    return coding;
  }
  return null;
}
// The difference file that updates `actual` (a content-hashed module) from the module the request names in
// `Available-Dictionary`, when the request accepts `dcb`, the file exists and it stays in the root. The name is built from the
// parsed hash (64 hex digits), never from the header. Tools/dictionary-transport.mjs, Tools/delta-compress-bundle.mjs.
async function differenceFile(request,actual,root){
  const hash=parseAvailableDictionary(request.headers.get('Available-Dictionary'));
  if(!hash||!acceptsDcb(request.headers.get('Accept-Encoding')))return null;
  const sibling=join(dirname(actual),differenceName(basename(actual),hash));
  if(!(await Bun.file(sibling).exists()))return null;
  const real=await realpath(sibling),rel=relative(root,real);
  if(rel.startsWith('..')||isAbsolute(rel))return null;
  return {file:Bun.file(real),label:'dcb-'+hash.slice(0,16)};
}
// A strong validator for one representation: its size and modification time, tagged by the coding it is sent with.
function entityTag(body,coding){
  return `"${body.size.toString(16)}-${Math.trunc(body.lastModified).toString(16)}${coding?'-'+coding:''}"`;
}
function notModified(header,etag){
  if(!header)return false;
  return header.trim()==='*'||header.split(',').some(tag=>tag.trim().replace(/^W\//,'')===etag);
}
// Development live reload (`swiftuiweb-run --watch`): on only when the watcher passes a token. See Tools/live-reload.mjs.
const liveToken=process.env.SWIFTUIWEB_LIVE_RELOAD_TOKEN||'';
const live=liveToken?createLiveReload(liveToken):null;
Bun.serve({port,hostname:'127.0.0.1',async fetch(request,server){
  if(!isLoopbackHost(request.url))return new Response('Forbidden: this development server answers only to localhost, 127.0.0.1 and [::1]',{status:403});
  if(live){const reply=await live.handle(request,server);if(reply)return reply;}
  const target=apiTarget(request);
  if(target===REFUSED)return new Response('Forbidden: the API path does not name a location on the API origin',{status:403});
  if(target){
    if(crossOrigin(request))return new Response(null,{status:403});
    try{
      // A redirect is returned to the browser unfollowed: following it would forward the cookies and authorization to another host.
      const init={method:request.method,headers:proxyHeaders(request),redirect:'manual'};
      if(request.method!=='GET'&&request.method!=='HEAD')init.body=request.body;
      // Keep the browser same-origin: cookies and CSRF headers pass through
      // the local proxy, while the backend remains a separate process.
      return await fetch(target,init);
    }catch{return new Response(JSON.stringify({error:{code:'API_UNAVAILABLE',message:'API unavailable'}}),{status:502,headers:{'Content-Type':'application/json'}});}
  }
  const policy=resolveRequest(request.url,request.method,request.headers.get('Accept')||'',root);
  if(policy.status!==200)return new Response(null,{status:policy.status,headers:policy.headers});
  try{
    let path=policy.file,type=policy.type;
    if(!(await Bun.file(path).exists())){if(!policy.fallback)return new Response('Not found',{status:404});path=policy.fallback;type=mime['.html'];}
    // Symlink targets must also remain inside the output directory.
    const actual=await realpath(path),rel=relative(root,actual);
    if(rel.startsWith('..')||isAbsolute(rel))return new Response(null,{status:403});
    const file=Bun.file(actual);if(!(await file.exists()))return new Response('Not found',{status:404});
    if(live&&type===mime['.html']&&!policy.head){
      const html=live.inject(await file.text());
      return new Response(html,{headers:{'Content-Type':type,'Content-Length':String(new TextEncoder().encode(html).length),'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff'}});
    }
    // A release bundle names its framework files by content (`app.3f9a1c2e.wasm`, Tools/hash-release-bundle.mjs) and
    // ships precompressed siblings (`app.3f9a1c2e.wasm.br` and `.gz`, Tools/precompress-bundle.mjs). A hashed name never
    // changes its bytes, so it is cached for a year. Everything else (index.html above all) is revalidated by its ETag.
    const hashed=path===policy.file&&HASHED_NAME.test(basename(path));
    // A content-hashed wasm module names itself as a dictionary for the next version, and a visitor who still has an earlier
    // version gets the difference file (`Content-Encoding: dcb`) when the release build wrote one for it.
    const participates=hashed&&isDictionaryModule(basename(actual));
    const difference=participates?await differenceFile(request,actual,root):null;
    const coding=difference?{name:'dcb'}:await negotiatedCoding(request.headers.get('Accept-Encoding'),actual,root);
    const body=difference?difference.file:coding?Bun.file(actual+coding.suffix):file;
    const etag=entityTag(body,difference?difference.label:coding?.name);
    const cacheHeaders={'Cache-Control':hashed?'public, max-age=31536000, immutable':'no-cache','ETag':etag,'Vary':participates?VARY:'Accept-Encoding'};
    const dictionary=participates?useAsDictionary(new URL(request.url).pathname):null;
    if(dictionary)cacheHeaders['Use-As-Dictionary']=dictionary;
    if(notModified(request.headers.get('If-None-Match'),etag))return new Response(null,{status:304,headers:cacheHeaders});
    const headers={...cacheHeaders,'Content-Type':type,'Content-Length':String(body.size),'X-Content-Type-Options':'nosniff'};
    if(coding)headers['Content-Encoding']=coding.name;
    return new Response(policy.head?null:body,{headers});
  }catch{return new Response('Not found',{status:404});}
}});
// Under the watcher the page is not ready until the first build ends, and the watcher says when it is.
if (!process.env.SWIFTUIWEB_LIVE_RELOAD_TOKEN) console.log(`SwiftUIWeb Bun development server: http://127.0.0.1:${port}`);
