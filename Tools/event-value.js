// Moves event values and SecureField text across the Swift/JS boundary in one
// copy. The Embedded runtime exports `event_value_alloc`/`event_value_commit`
// (host writes into WASM memory) and `secure_value_pointer` (host reads from
// it); the per-byte `event_value_push`/`secure_value_byte` exports remain the
// fallback for builds that lack them. `get(name)` returns the unprefixed
// export (or undefined); `memory` is the instance's WebAssembly.Memory when
// the caller can see it. The worker client has no memory, so it offers the
// non-WASM `event_value_write` and `secure_value_bytes` shims instead.

// A build without the bulk exports still works through the per-byte path, only
// slower, and nothing else would say so. The first use of each path is recorded
// as a performance mark (`event-value:bulk`, `secure-value:bytes`, ...), so
// a trace or `performance.getEntriesByType('mark')` shows which path the host took.
const usedPaths = new Set();
function notePath(kind, path) {
  const name = `${kind}:${path}`;
  if (usedPaths.has(name)) return path;
  usedPaths.add(name);
  try { globalThis.performance?.mark?.(name); } catch { /* marks are diagnostics only */ }
  return path;
}

/** Makes `bytes` (a Uint8Array) the pending event value. Returns the path used. */
export function writeEventValue(get, memory, bytes) {
  const alloc = get('event_value_alloc'), commit = get('event_value_commit');
  if (typeof alloc === 'function' && typeof commit === 'function' && memory instanceof WebAssembly.Memory) {
    const pointer = Number(alloc(bytes.length)) >>> 0;
    // Read memory.buffer AFTER the call: allocation may have grown (and moved) it.
    if (pointer !== 0 && pointer + bytes.length <= memory.buffer.byteLength) {
      new Uint8Array(memory.buffer, pointer, bytes.length).set(bytes);
      commit(bytes.length);
      return notePath('event-value', 'bulk');
    }
  }
  const write = get('event_value_write');
  if (typeof write === 'function') { write(bytes); return notePath('event-value', 'write'); }
  get('event_value_reset')();
  const push = get('event_value_push');
  for (let index = 0; index < bytes.length; index++) push(bytes[index]);
  return notePath('event-value', 'bytes');
}

/** Copies the `length` bytes `secure_value` just resolved. */
export function readSecureBytes(get, memory, length) {
  const pointerOf = get('secure_value_pointer');
  if (length > 0 && typeof pointerOf === 'function' && memory instanceof WebAssembly.Memory) {
    const pointer = Number(pointerOf()) >>> 0;
    if (pointer !== 0 && pointer + length <= memory.buffer.byteLength) {
      notePath('secure-value', 'pointer');
      return new Uint8Array(memory.buffer, pointer, length).slice();
    }
  }
  const bytesOf = get('secure_value_bytes');
  if (typeof bytesOf === 'function') { notePath('secure-value', 'bytes'); return Uint8Array.from(bytesOf() ?? []); }
  notePath('secure-value', 'byte');
  const byteAt = get('secure_value_byte');
  const bytes = new Uint8Array(length);
  for (let index = 0; index < length; index++) bytes[index] = Number(byteAt(index)) & 255;
  return bytes;
}

/** Ids of the SecureFields Swift published, or null when the build cannot say. */
export function readSecureIDs(get, memory) {
  const lengthOf = get('secure_ids_length'), pointerOf = get('secure_ids_pointer');
  if (typeof lengthOf !== 'function' || typeof pointerOf !== 'function' || !(memory instanceof WebAssembly.Memory)) return null;
  const length = Number(lengthOf());
  if (!Number.isSafeInteger(length) || length < 0) return null;
  if (length === 0) return [];
  const pointer = Number(pointerOf()) >>> 0;
  if (pointer === 0 || pointer + length > memory.buffer.byteLength) return null;
  return new TextDecoder().decode(new Uint8Array(memory.buffer, pointer, length)).split('\n');
}

/** `first` followed by `second` as one Uint8Array (event name + payload). */
export function concatBytes(first, second) {
  const bytes = new Uint8Array(first.length + second.length);
  bytes.set(first, 0); bytes.set(second, first.length);
  return bytes;
}
