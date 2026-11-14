// Main-thread side of the worker's DOM bridge (see BrowserIO's remoteDOM mode).
//
// The worker has no document, so it cannot find or touch the mounted elements.
// Before each WebMount reconciliation the host reports a snapshot of them
// (`snapshot`), with a stable numeric handle per element node. The worker answers
// its reads from that snapshot and sends back the writes it decided on, tagged
// with the snapshot's sequence number; `apply` runs them in order, after the
// same commit's DOM patch, so the batch sees exactly the DOM the worker saw.
//
// An element that left the DOM keeps its handle until a batch at or after its
// removal has been applied, so the `unmount` for it still finds the element.
import { createDOMViewHost, DOMViewError } from './BrowserIO/dom-view-host.mjs';
import { safeErrorMessage } from './BrowserIO/browser-io.mjs';

const MOUNT_TOKEN = 'data-web-mount-token';
const MOUNT_KEY = 'data-web-mount-key';
const ERROR_ATTRIBUTE = 'data-dom-view-error';

export function createRemoteDOMHost({ document, window }) {
  const handles = new WeakMap();
  // handle -> { element, retiredAt } where retiredAt is null while the element is mounted.
  const elements = new Map();
  let nextHandle = 1;
  let seq = 0;
  const domViews = createDOMViewHost(window, { report: (element, error) => report(element, error) });

  function handleOf(element) {
    let handle = handles.get(element);
    if (!handle) {
      handle = nextHandle++;
      handles.set(element, handle);
    }
    // A pruned handle whose node is back in the document gets its entry again.
    const entry = elements.get(handle);
    if (entry) entry.retiredAt = null;
    else elements.set(handle, { element, retiredAt: null });
    return handle;
  }

  function report(element, message) {
    const text = safeErrorMessage(message);
    console.error(`[SwiftUIWeb] ${text}`);
    const target = element ?? document.getElementById?.('embedded-app-root') ?? document.body;
    try { target?.setAttribute(ERROR_ATTRIBUTE, text); } catch { /* not an element */ }
  }

  function applyOp(op) {
    if (op.op === 'report') { report(elements.get(op.node)?.element, op.message); return; }
    const entry = elements.get(op.node);
    if (!entry) throw new DOMViewError(-8, `Unknown mount handle for ${op.op}`);
    const element = entry.element;
    if (op.op === 'attr') element.setAttribute(op.name, op.value);
    else if (op.op === 'remove-attr') element.removeAttribute(op.name);
    else if (op.op === 'value') element.value = op.value;
    else if (op.op === 'text') element.textContent = op.value;
    else if (op.op === 'dom-view') domViews.lifecycle(op.phase, element, op);
    else throw new DOMViewError(-1, 'Unknown DOM bridge operation');
  }

  return {
    /** The mounted elements, numbered for the worker. Call right before reconciliation. */
    snapshot() {
      seq += 1;
      const entries = [];
      const live = new Set();
      for (const element of document.querySelectorAll(`[${MOUNT_TOKEN}]`)) {
        const handle = handleOf(element);
        live.add(handle);
        entries.push({
          node: handle,
          key: element.getAttribute(MOUNT_KEY) || '',
          token: element.getAttribute(MOUNT_TOKEN) || '',
          attributes: Object.fromEntries([...element.attributes].map(attribute => [attribute.name, attribute.value])),
          value: typeof element.value === 'string' ? element.value : null,
          text: element.textContent ?? null
        });
      }
      for (const [handle, entry] of elements) {
        if (!live.has(handle) && entry.retiredAt === null) entry.retiredAt = seq;
      }
      return { seq, entries };
    },
    /** Applies one batch of worker writes in order; a failed write is reported, not dropped. */
    apply(batchSeq, ops) {
      for (const op of Array.isArray(ops) ? ops : []) {
        try { applyOp(op); }
        catch (error) {
          const handle = op?.node;
          report(elements.get(handle)?.element, error);
        }
      }
      // Handles retired by this snapshot or an earlier one have now been reported to the worker.
      for (const [handle, entry] of elements) {
        if (entry.retiredAt !== null && entry.retiredAt <= batchSeq) elements.delete(handle);
      }
    },
  };
}
