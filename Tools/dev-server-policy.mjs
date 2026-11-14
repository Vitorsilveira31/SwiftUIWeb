import {resolve,relative,isAbsolute,extname} from 'node:path';
export const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.wasm':'application/wasm','.json':'application/json','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.webp':'image/webp','.ico':'image/x-icon','.woff2':'font/woff2'};
export function resolveRequest(rawURL,method,accept,root) {
  if(method!=='GET'&&method!=='HEAD')return {status:405,headers:{Allow:'GET, HEAD'}};
  let url,path;try{url=new URL(rawURL);path=decodeURIComponent(url.pathname);}catch{return {status:400};}
  if(path.includes('\0')||path.includes('\\')||path.split('/').some(p=>p==='..'))return {status:400};
  const file=resolve(root,'.'+(path==='/'?'/index.html':path));
  const rel=relative(resolve(root),file);
  if(rel.startsWith('..')||isAbsolute(rel))return {status:403};
  const extension=extname(path==='/'?'/index.html':path).toLowerCase();
  const acceptsHTML=!accept||accept.includes('text/html')||accept==='*/*';
  // `/` is the application document even though it resolves to `/index.html`
  // before we compute the extension. Keep it marked as an HTML navigation so
  // the SPA contract is identical for `/` and extensionless deep links.
  const htmlNavigation=acceptsHTML&&(path==='/'||!extension);
  return {status:200,file,fallback:htmlNavigation?resolve(root,'index.html'):null,type:mime[extension]||'application/octet-stream',head:method==='HEAD'};
}
// The server listens on 127.0.0.1, but a page on another site can still reach it through DNS rebinding (its own name
// resolving to 127.0.0.1), and then the browser sends that site's name as the Host. Only loopback names are served, so
// such a page cannot read the bundle or drive the API proxy as if it were the app's own origin.
export function isLoopbackHost(rawURL){
  let host;try{host=new URL(rawURL).hostname.toLowerCase();}catch{return false;}
  return host==='localhost'||host==='127.0.0.1'||host==='[::1]';
}
