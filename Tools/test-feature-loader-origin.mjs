// The feature loader imports only modules served from the page's own origin.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const context = { location: { origin: 'https://app.example', href: 'https://app.example/' }, URL, Promise, Date, Map, Set, console };
context.globalThis = context;
vm.runInNewContext(readFileSync(new URL('./feature-loader.js', import.meta.url), 'utf8'), context);

await assert.rejects(context.__loadFeature('evil', 'https://evil.example/x.js'), /not same-origin/);
await assert.rejects(context.__loadFeature('data', 'data:text/javascript,1'), /not same-origin/);
console.log('feature loader origin: ok');
