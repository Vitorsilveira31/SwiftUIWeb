/** The browser hosts the first screen does not run, built as one chunk (`runtime-deferred.js`, Tools/build-runtime-bundle.mjs)
 * that embedded-dom.js requests with import() as soon as the first publication is on screen: not on first use, so nothing a
 * person does waits for a download, and not before, so the first screen does not download it. Until it arrives, embedded-dom.js
 * holds a stand-in for each host; when it does, each host is synced with what the page shows by then.
 *
 * Every module listed here imports nothing. A module that both this chunk and the first one import would be split by the
 * bundler into a chunk of its own, which the first screen would then have to load as well: the build refuses one.
 */
import {NativeDragDropCoordinator as DragDrop} from './transfer-host.js';

export {PresentationCoordinator} from './presentation-host.js';
export {shareContent, moveFiles} from './transfer-host.js';
export {textLayoutPayload, paintKey, clearFontMetrics} from './text-layout-host.js';
// Left out of a release without drag and drop, as before the split (`SWIFTUIWEB_HAS_DRAG_DROP`, build-runtime-bundle.mjs).
export const NativeDragDropCoordinator = (typeof SWIFTUIWEB_HAS_DRAG_DROP === 'undefined' || SWIFTUIWEB_HAS_DRAG_DROP) ? DragDrop : null;
