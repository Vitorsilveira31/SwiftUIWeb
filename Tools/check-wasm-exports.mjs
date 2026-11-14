import {existsSync, readFileSync, readdirSync, statSync} from 'node:fs';
import {join} from 'node:path';
const usage = 'Usage: bun Tools/check-wasm-exports.mjs app.wasm [--side app-side.wasm] [--product NAME] [lowering-report.json | reports-directory ...]';
const args = process.argv.slice(2);
// A hot build of the development loop is two modules, and the host calls the exports of both as one instance.
const sideIndex = args.indexOf('--side');
const side = sideIndex >= 0 ? args.splice(sideIndex, 2)[1] : null;
const productIndex = args.indexOf('--product');
const product = productIndex >= 0 ? args.splice(productIndex, 2)[1] : null;
const [path, ...reportPaths] = args;
if (!path) throw Error(usage);
const module = await WebAssembly.compile(readFileSync(path));
const exports = new Set(WebAssembly.Module.exports(module).map(e => e.name));
if (side) for (const entry of WebAssembly.Module.exports(await WebAssembly.compile(readFileSync(side)))) exports.add(entry.name);
const required = ['memory', ...['viewport', 'scroll_ack', 'scroll_prepare', 'history_ack', 'history_restore', 'history_location', 'dispatch_named'].map(n => 'embedded_browser_' + n)];

// The bulk event/secure value block moves text across the boundary in one copy. A build
// that lacks it still works through the per-byte exports, only slower and without any
// signal, so when the source lowering says it generated the browser entry points the
// whole block is mandatory.
const bulkEventValueExports = ['event_value_alloc', 'event_value_commit', 'secure_value_pointer', 'secure_ids_length', 'secure_ids_pointer'].map(n => 'embedded_browser_' + n);
const reportFiles = reportPaths.flatMap(value => !existsSync(value) ? [] : statSync(value).isDirectory()
  ? readdirSync(value).filter(name => name.endsWith('.json')).map(name => join(value, name)) : [value]);
const lowererGeneratedBrowserEntry = reportFiles.some(file => {
  try {
    const report = JSON.parse(readFileSync(file, 'utf8'));
    // A shared report directory may still hold another product's report.
    if (product && report.product !== product) return false;
    return Number(report.rules?.['browser-reactor-entry-and-html-exports'] ?? 0) > 0;
  } catch { return false; }
});
if (lowererGeneratedBrowserEntry) required.push(...bulkEventValueExports);

const missing = required.filter(n => !exports.has(n));
if (missing.length) throw Error('WASM is missing required integration exports: ' + missing.join(', '));
console.log('WASM event ABI exports: PASS' + (lowererGeneratedBrowserEntry ? ' (bulk event/secure value block required and present)' : ''));
