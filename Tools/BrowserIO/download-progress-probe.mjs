// Browser check for BrowserIO download progress. The probe runs the real host (browser-io.mjs) against a
// test origin, in whichever context imports it: the page's main thread or a worker. It returns, for each body, the
// progress reports (status 103) and the final response, so the driver can check their sequence.
import { createBrowserIO, Writer, Reader } from './browser-io.mjs';

const CASES = ['sized', 'chunked', 'gzip'];

export async function runDownloadProgressProbe(origin) {
  const memory = new WebAssembly.Memory({ initial: 4 });
  let top = 16; let next = 1; const pending = new Map();
  const alloc = (length) => {
    const pointer = top; top += length + 16;
    if (top > memory.buffer.byteLength) memory.grow(Math.ceil((top - memory.buffer.byteLength) / 65536));
    return pointer;
  };
  const instance = { exports: { memory, browser_io_alloc: alloc, browser_io_deliver(id, status, pointer, length) {
    pending.get(id)?.(status, new Uint8Array(memory.buffer, pointer, length).slice());
  } } };
  const host = createBrowserIO({ getInstance: () => instance, baseURL: origin });
  const results = {};
  for (const kind of CASES) {
    const packet = new Writer().text(`${origin}/progress/${kind}`).text('GET').text('same-origin').text('follow')
      .u32(10000).u32(1024 * 1024).u32(4).u32(0).u32(0).data(new Uint8Array()).bytes();
    const events = await new Promise((resolve, reject) => {
      const id = next++; const collected = [];
      const timer = setTimeout(() => reject(new Error(`${kind}: no final status`)), 15000);
      pending.set(id, (status, bytes) => {
        collected.push({ status, bytes });
        if (status < 100) { clearTimeout(timer); pending.delete(id); resolve(collected); }
      });
      const pointer = alloc(packet.length);
      new Uint8Array(memory.buffer, pointer, packet.length).set(packet);
      const code = host.imports.request(id, 1, pointer, packet.length);
      if (code !== 0) reject(new Error(`${kind}: host rejected the request with ${code}`));
    });
    const final = events.at(-1);
    const reports = events.filter((event) => event.status === 103).map((event) => {
      const reader = new Reader(event.bytes);
      const received = Number(reader.u64()); const contentLength = reader.text(); const contentEncoding = reader.text();
      return { received, contentLength, contentEncoding };
    });
    // The final response carries the decoded body, so its length is the total the reports should end at.
    const reader = new Reader(final.bytes);
    const status = reader.u32(); reader.text(); const headerCount = reader.u32();
    for (let i = 0; i < headerCount; i++) { reader.text(); reader.text(); }
    const bodyLength = reader.data().length;
    results[kind] = { finalStatus: final.status, httpStatus: status, bodyLength, reports };
  }
  return results;
}
