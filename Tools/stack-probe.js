// Call-stack measurements for the WebAssembly the app runs in.
//
// The probe is a minimal recursive wasm function, `f(n)` calling itself n times. How many of its frames fit is the
// unit the runtime uses for "stack": WebKit's Worker holds about 560 of them, its main thread about 7,100, Chromium's
// Worker about 63,000. `createHeadroomMeter` (a debug aid, `?stack-depth=1`) answers a different question: when the
// app is at its deepest point, how many of those frames still fit?
export const STACK_PROBE_MODULE = [0,97,115,109,1,0,0,0, 1,6,1,96,1,127,1,127, 3,2,1,0, 7,5,1,1,102,0,0,
  10,23,1,21, 0,32,0,69,4,127,65,0,5,32,0,65,1,107,16,0,65,1,106,11,11];

const SEARCH_CAP = 1 << 16;

let moduleSerial = 0;

/** A probe function from a module no engine has compiled before: a custom section carries a serial number, so the
 * bytes are unique and the engine cannot hand back code it already tiered up. */
function probeFunction() {
  const name = new TextEncoder().encode(`p${++moduleSerial}-${Math.random().toString(36).slice(2)}`);
  const bytes = new Uint8Array([...STACK_PROBE_MODULE, 0, name.length + 1 + 1, name.length, ...name, 0]);
  return new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports.f;
}

// WebKit moves a function that has run about a hundred times to an optimizing tier whose frames are far smaller
// (a Worker went from 557 probe frames to 50,171), and the unit has to stay the frames of a cold function, which is
// also what the runtime's startup probe measures. A probe instance is therefore retired after a few calls.
const CALLS_PER_PROBE = 24;
let probe = null, probeCalls = 0;

/** True when the cold probe completes `n` nested calls; false on a stack overflow. */
function fits(n) {
  if (!probe || probeCalls >= CALLS_PER_PROBE) { probe = probeFunction(); probeCalls = 0; }
  probeCalls++;
  try { probe(n); return true; } catch (error) { if (error instanceof RangeError) return false; throw error; }
}

/** Greatest n (up to SEARCH_CAP) the cold probe completes, from the current stack position. */
function headroomOf(below = SEARCH_CAP) {
  probe = null;
  let lo = 0, hi = below;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (fits(mid)) lo = mid; else hi = mid - 1;
  }
  return lo;
}

/** Records, over the samples the app reports from inside its render recursion, the deepest render depth and the
 * least headroom left (in cold probe frames). `capacity` is the headroom of an empty stack, measured when the meter
 * is created (the least of three searches, since an engine tiering up in the middle of one only raises it); `used`
 * is what the deepest point cost. Sampling is cheap when nothing new is found: one probe call of the smallest
 * headroom seen so far. */
export function createHeadroomMeter() {
  const stats = { samples: 0, maxDepth: 0, capacity: Math.min(headroomOf(), headroomOf(), headroomOf()), minHeadroom: -1, minDepth: 0, used: 0 };
  return {
    sample(depth) {
      stats.samples++;
      if (depth > stats.maxDepth) stats.maxDepth = depth;
      if (stats.minHeadroom < 0 || !fits(stats.minHeadroom)) {
        stats.minHeadroom = headroomOf(stats.minHeadroom < 0 ? SEARCH_CAP : stats.minHeadroom);
        stats.minDepth = depth;
      }
      stats.used = Math.max(0, stats.capacity - stats.minHeadroom);
    },
    /** Forgets what was recorded (the capacity stays); the next render starts a fresh measurement. */
    reset() { Object.assign(stats, { samples: 0, maxDepth: 0, minHeadroom: -1, minDepth: 0, used: 0 }); },
    snapshot() { return { ...stats }; }
  };
}
