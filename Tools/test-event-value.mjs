// Covers both ways event values and SecureField text cross the Swift/JS
// boundary: the bulk exports (alloc/commit, secure_value_pointer, secure ids)
// and the per-byte fallback older builds rely on.
import assert from "node:assert/strict";
import { writeEventValue, readSecureBytes, readSecureIDs, concatBytes } from "./event-value.js";

const encoder = new TextEncoder();

// A stand-in for the Swift side: a bump region of WASM memory per buffer.
function bulkExports({ refuse = false } = {}) {
  const memory = new WebAssembly.Memory({ initial: 1 });
  const state = { committed: null, calls: [], secure: encoder.encode("s3cret"), ids: encoder.encode("1:0\n4:2") };
  const INPUT = 4096, SECURE = 8192, IDS = 12288;
  new Uint8Array(memory.buffer, SECURE, state.secure.length).set(state.secure);
  new Uint8Array(memory.buffer, IDS, state.ids.length).set(state.ids);
  const table = {
    event_value_alloc: length => { state.calls.push("alloc"); return refuse ? 0 : INPUT; },
    event_value_commit: length => { state.calls.push("commit"); state.committed = [...new Uint8Array(memory.buffer, INPUT, length)]; },
    event_value_reset: () => state.calls.push("reset"),
    event_value_push: byte => state.calls.push("push:" + byte),
    secure_value_pointer: () => SECURE,
    secure_value_byte: index => state.secure[index] ?? 0,
    secure_ids_length: () => state.ids.length,
    secure_ids_pointer: () => IDS,
  };
  return { get: name => table[name], memory, state };
}

// Bulk path: one alloc and one commit, no per-byte calls.
{
  const { get, memory, state } = bulkExports();
  assert.equal(writeEventValue(get, memory, encoder.encode("olá, mundo")), "bulk");
  assert.deepEqual(state.calls, ["alloc", "commit"]);
  assert.equal(new TextDecoder().decode(Uint8Array.from(state.committed)), "olá, mundo");
  // A 1 KB value is still two calls.
  state.calls.length = 0;
  assert.equal(writeEventValue(get, memory, new Uint8Array(1024).fill(97)), "bulk");
  assert.deepEqual(state.calls, ["alloc", "commit"]);
  assert.equal(state.committed.length, 1024);
  // An empty value is a valid commit.
  assert.equal(writeEventValue(get, memory, new Uint8Array(0)), "bulk");
  assert.deepEqual(state.committed, []);
}

// Swift refusing the allocation (returns 0) falls back to the byte exports.
{
  const { get, memory, state } = bulkExports({ refuse: true });
  assert.equal(writeEventValue(get, memory, Uint8Array.of(1, 2)), "bytes");
  assert.deepEqual(state.calls, ["alloc", "reset", "push:1", "push:2"]);
}

// A pointer outside memory is not trusted either.
{
  const { get, memory, state } = bulkExports();
  const wild = name => name === "event_value_alloc" ? () => memory.buffer.byteLength - 1 : get(name);
  assert.equal(writeEventValue(wild, memory, Uint8Array.of(1, 2, 3)), "bytes");
  assert.equal(state.committed, null);
}

// Hosts without the bulk exports (older builds) keep the per-byte path.
{
  const calls = [];
  const get = name => ({ event_value_reset: () => calls.push("reset"), event_value_push: byte => calls.push(byte) })[name];
  assert.equal(writeEventValue(get, undefined, Uint8Array.of(7, 8, 9)), "bytes");
  assert.deepEqual(calls, ["reset", 7, 8, 9]);
}

// The worker client has no memory and offers a one-call write instead.
{
  let written = null;
  const get = name => name === "event_value_write" ? bytes => { written = [...bytes]; } : undefined;
  assert.equal(writeEventValue(get, undefined, Uint8Array.of(5, 6)), "write");
  assert.deepEqual(written, [5, 6]);
}

// Secure values: pointer read, shim read and the per-byte fallback agree.
{
  const { get, memory, state } = bulkExports();
  assert.equal(new TextDecoder().decode(readSecureBytes(get, memory, state.secure.length)), "s3cret");
  const noPointer = name => name === "secure_value_pointer" ? undefined : get(name);
  assert.equal(new TextDecoder().decode(readSecureBytes(noPointer, memory, state.secure.length)), "s3cret");
  const shim = name => name === "secure_value_bytes" ? () => state.secure : undefined;
  assert.equal(new TextDecoder().decode(readSecureBytes(shim, undefined, state.secure.length)), "s3cret");
  // The result is a copy: wiping Swift's buffer afterwards cannot change it.
  const copy = readSecureBytes(get, memory, state.secure.length);
  new Uint8Array(memory.buffer, 8192, state.secure.length).fill(0);
  assert.equal(new TextDecoder().decode(copy), "s3cret");
}

// Secure ids come straight from Swift; builds without the export return null.
{
  const { get, memory } = bulkExports();
  assert.deepEqual(readSecureIDs(get, memory), ["1:0", "4:2"]);
  assert.equal(readSecureIDs(() => undefined, memory), null);
  const none = name => name === "secure_ids_length" ? () => 0 : get(name);
  assert.deepEqual(readSecureIDs(none, memory), []);
}

assert.deepEqual([...concatBytes(Uint8Array.of(1, 2), Uint8Array.of(3))], [1, 2, 3]);

// The path each host actually took is recorded once as a performance mark, so a
// build that fell back to the per-byte exports is visible instead of silent. A fresh
// module instance per case keeps the once-per-process rule from hiding a path.
{
  const marksFor = async (run) => {
    performance.clearMarks();
    const fresh = await import(`./event-value.js?marks=${Math.random()}`);
    run(fresh);
    return performance.getEntriesByType("mark").map(entry => entry.name).filter(name => /^(event-value|secure-value):/.test(name));
  };
  assert.deepEqual(await marksFor(({ writeEventValue }) => {
    const { get, memory } = bulkExports();
    writeEventValue(get, memory, encoder.encode("a"));
    writeEventValue(get, memory, encoder.encode("b"));
  }), ["event-value:bulk"], "the bulk path is marked once, not once per event");
  assert.deepEqual(await marksFor(({ writeEventValue }) => {
    const { get, memory } = bulkExports({ refuse: true });
    writeEventValue(get, memory, encoder.encode("c"));
  }), ["event-value:bytes"], "a build that refuses the bulk export is marked as the per-byte path");
  assert.deepEqual(await marksFor(({ writeEventValue }) => {
    const { get, memory } = bulkExports();
    // The worker client has no WebAssembly.Memory, so it offers the write shim instead.
    writeEventValue(name => name === "event_value_write" ? () => {} : get(name), undefined, encoder.encode("d"));
  }), ["event-value:write"], "the worker shim is marked");
  assert.deepEqual(await marksFor(({ readSecureBytes }) => {
    const { get, memory } = bulkExports();
    readSecureBytes(get, memory, 6);
  }), ["secure-value:pointer"]);
  assert.deepEqual(await marksFor(({ readSecureBytes }) => {
    const { get, memory } = bulkExports();
    readSecureBytes(name => name === "secure_value_pointer" ? undefined : get(name), memory, 6);
  }), ["secure-value:byte"]);
}

console.log("event value boundary: ok");
