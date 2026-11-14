// The main-thread media host makes <video>/<audio> match what Swift rendered and reports back.
import assert from 'node:assert/strict';
import { MediaHost } from './media-host.js';

class FakeMedia {
  constructor(attributes, { hls = false, refusePlay = false } = {}) {
    this.attributes = new Map(Object.entries(attributes));
    this.paused = true; this.ended = false; this.muted = false; this.volume = 1; this.playbackRate = 1;
    this.currentTime = 0; this.duration = 30; this.readyState = 4; this.seeking = false; this.error = null; this.src = ''; this.isConnected = true;
    this.hls = hls; this.refusePlay = refusePlay; this.plays = 0; this.fullscreens = 0;
  }
  getAttribute(name) { return this.attributes.has(name) ? this.attributes.get(name) : null; }
  hasAttribute(name) { return this.attributes.has(name); }
  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  canPlayType(type) { return this.hls && type === 'application/vnd.apple.mpegurl' ? 'maybe' : ''; }
  play() { this.plays++; if (this.refusePlay) return Promise.reject(new Error('NotAllowedError')); this.paused = false; return Promise.resolve(); }
  pause() { this.paused = true; }
  requestFullscreen() { this.fullscreens++; return Promise.resolve(); }
  closest(selector) { return selector.includes('avkit-video-player') ? this.player ?? null : null; }
  get localName() { return 'video'; }
}

// The element of a VideoPlayer's container: just enough of a DOM for the controls' keyboard and fullscreen paths.
class FakePlayer {
  constructor(media) { this.media = media; media.player = this; this.fullscreens = 0; this.attributes = new Map(); }
  closest(selector) { return selector.includes('avkit-video-player') ? this : null; }
  querySelector(selector) { return selector.startsWith('video') ? this.media : null; }
  querySelectorAll() { return []; }
  contains(node) { return node === this || node === this.media; }
  requestFullscreen() { this.fullscreens++; return Promise.resolve(); }
}

const listeners = new Map();
const elements = [];
const players = [];
const root = {
  querySelectorAll: (selector) => selector.includes('avkit-video-player') ? players.filter((p) => p.media.isConnected) : elements.filter((e) => e.isConnected),
  addEventListener: (type, fn) => listeners.set(type, [...(listeners.get(type) ?? []), fn]),
  contains: (e) => elements.includes(e) && e.isConnected,
};
const reports = [];
const adaptive = [];
const detached = [];
const frames = [];
const window = {
  HTMLMediaElement: FakeMedia, AbortController, performance: { now: () => clock }, Date: { now: () => 1700000000000 + clock },
  requestAnimationFrame: (f) => frames.push(f), cancelAnimationFrame: () => {},
  __loadAdaptiveMedia: (element, source) => { adaptive.push(source); element.src = 'blob:shaka'; return Promise.resolve(); },
  __detachAdaptiveMedia: (element) => detached.push(element),
};
let clock = 0;
const host = new MediaHost(root, { window, dispatchNamed: (element, name, value) => reports.push({ element, name, value }) });
const fire = (type, element) => { for (const fn of listeners.get(type)) fn({ target: element }); };
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

// Play, mute, volume and rate follow the attributes; a paused wish pauses.
const video = new FakeMedia({ 'data-player-id': 'm1', 'data-media-playing': '1', 'data-media-muted': '1', 'data-media-volume': '0.4', 'data-media-rate': '1.5' });
elements.push(video);
host.sync();
assert.equal(video.paused, false);
assert.equal(video.muted, true);
assert.equal(video.volume, 0.4);
assert.equal(video.playbackRate, 1.5);
host.sync();
assert.equal(video.plays, 1, 'an element already playing is not asked again');
video.setAttribute('data-media-playing', '0');
host.sync();
assert.equal(video.paused, true);

// A command runs once per sequence.
video.setAttribute('data-media-command', '1:seek:12.5');
host.sync(); host.sync();
assert.equal(video.currentTime, 12.5);
video.currentTime = 3;
host.sync();
assert.equal(video.currentTime, 3, 'the same sequence is not applied again');
video.setAttribute('data-media-command', '2:fullscreen');
host.sync(); host.sync();
assert.equal(video.fullscreens, 1);

// Adaptive sources: Shaka where the browser has Media Source Extensions, native HLS only without
// them (Safari on iPhone); Shaka is released when the element leaves the page.
const native = new FakeMedia({ 'data-player-id': 'm2', 'data-media-source': 'https://cdn/a.m3u8' }, { hls: true });
const shaka = new FakeMedia({ 'data-player-id': 'm3', 'data-media-source': 'https://cdn/b.m3u8', 'data-media-playing': '1' });
elements.push(native, shaka);
host.sync(); host.sync();
assert.equal(native.src, 'https://cdn/a.m3u8', 'no MediaSource here: native HLS');
assert.deepEqual(adaptive, ['https://cdn/b.m3u8'], 'Shaka is attached once');
assert.equal(shaka.plays, 0, 'no play() before Shaka has loaded the source');
await settle();
assert.equal(shaka.plays, 1, 'playback starts once the source is loaded');
window.MediaSource = function MediaSource() {};
const withMSE = new FakeMedia({ 'data-player-id': 'm7', 'data-media-source': 'https://cdn/c.m3u8' }, { hls: true });
elements.push(withMSE);
host.sync();
assert.deepEqual(adaptive, ['https://cdn/b.m3u8', 'https://cdn/c.m3u8'], 'with MSE, Shaka even where HLS is native');
delete window.MediaSource;
shaka.isConnected = false;
host.sync();
assert.deepEqual(detached, [shaka]);

// Events go back as "event|time|duration|paused|muted|volume|buffered|rate|readyState|seeking|ended|errorCode|seekSequence|hostTime",
// time updates at most every 100 ms, and not at all while Swift's mirror predicts them.
const fields = (report) => report.value.split('|');
video.playbackRate = 1; video.currentTime = 7; video.paused = false; video.muted = false; video.volume = 1;
fire('timeupdate', video); fire('timeupdate', video);
clock = 300; video.currentTime = 7.3; fire('timeupdate', video);
const updates = reports.filter((r) => r.value.startsWith('timeupdate'));
assert.equal(updates.length, 1, 'the second is throttled and the third is what the mirror predicts');
assert.equal(updates[0].name, 'media-report');
assert.equal(updates[0].value, 'timeupdate|7|30|0|0|1||1|4|0|0|0|1|' + (1700000000000 + 0) + '|0|');
clock = 600; video.currentTime = 9; fire('timeupdate', video);
assert.equal(fields(reports.at(-1))[1], '9', 'a jump is a new sample');
clock = 1900; video.currentTime = 10.3; fire('timeupdate', video);
assert.equal(fields(reports.at(-1))[1], '10.3', 'a steady sample is repeated once a second to resync');
video.duration = NaN; fire('durationchange', video);
assert.equal(fields(reports.at(-1))[2], '-1');
// What has loaded goes along, for the buffer behind a progress bar; unchanged ranges are not repeated.
video.buffered = { length: 2, start: (i) => [0, 20][i], end: (i) => [12.5, 25][i] };
clock = 2500;
fire('progress', video);
assert.equal(fields(reports.at(-1))[6], '0-12.5;20-25');
const count = reports.length;
clock = 3000; fire('progress', video);
assert.equal(reports.length, count, 'same ranges, no report');
delete video.buffered;
// State transitions are never held back; the element's own state rides along.
video.playbackRate = 2; video.readyState = 2; video.seeking = true; video.error = { code: 4 };
fire('ratechange', video); fire('waiting', video);
assert.deepEqual(reports.slice(-2).map((r) => fields(r).slice(7, 12)), [['2', '2', '1', '0', '4'], ['2', '2', '1', '0', '4']]);
video.playbackRate = 1; video.readyState = 4; video.seeking = false; video.error = null;

// A seek names its command sequence in the `seeked` that completes it.
video.setAttribute('data-media-command', '7:seek:1');
host.sync();
fire('seeked', video);
assert.equal(fields(reports.at(-1))[0], 'seeked');
assert.equal(fields(reports.at(-1))[12], '7');

// While a short periodic observer is registered a requestAnimationFrame stream samples the playing element.
const streamed = new FakeMedia({ 'data-player-id': 'm9', 'data-media-observe': '50', 'data-media-playing': '1' });
streamed.paused = false; streamed.play = () => { streamed.paused = false; return Promise.resolve(); };
elements.push(streamed);
host.sync();
assert.equal(frames.length, 1);
const sampled = () => reports.filter((r) => r.element === streamed).length;
clock = 4000; frames.shift()();
assert.equal(sampled(), 1);
clock = 4010; frames.shift()();
assert.equal(sampled(), 1, 'not before the interval');
clock = 4060; frames.shift()();
assert.equal(sampled(), 2);
streamed.setAttribute('data-media-observe', '');
clock = 4200; frames.shift()();
assert.equal(frames.length, 0, 'the stream stops with the observer');
streamed.isConnected = false;

// A refused play() reports a pause, so Swift stops asking.
const refused = new FakeMedia({ 'data-player-id': 'm4', 'data-media-playing': '1' }, { refusePlay: true });
elements.push(refused);
host.sync();
await settle();
assert.ok(reports.some((r) => r.element === refused && r.value.startsWith('pause|')));

// The keyboard works inside a VideoPlayer's container; each key asks Swift (the `avkit-action` event) and changes the element itself
// only when no Swift owner answers. Outside a container nothing happens.
const keyed = new FakeMedia({ 'data-player-id': 'm5' });
const container = new FakePlayer(keyed);
players.push(container);
elements.push(keyed);
const key = (k, extra = {}) => { let prevented = false; for (const fn of listeners.get('keydown')) fn({ target: keyed, key: k, preventDefault: () => { prevented = true; }, ...extra }); return prevented; };
reports.length = 0;
assert.ok(key('m'));
assert.deepEqual(reports.at(-1) && [reports.at(-1).name, reports.at(-1).value], ['avkit-action', 'mute|toggle'], 'Swift decides the toggle');
assert.equal(keyed.muted, false, 'with a Swift owner the element waits for Swift to answer');
keyed.volume = 0.5; keyed.currentTime = 10;
assert.ok(key('ArrowRight'));
assert.equal(reports.at(-1).value, 'seek|15.000');
assert.ok(key('ArrowLeft'));
assert.equal(reports.at(-1).value, 'seek|10.000', 'a second press starts from the first one\'s target, not from the element');
assert.ok(key('ArrowUp'));
assert.equal(reports.at(-1).value, 'volume|0.600');
assert.ok(key('k'));
assert.equal(keyed.paused, false, 'the element is asked inside the gesture');
assert.equal(reports.at(-1).value, 'play|');
assert.ok(key(' '));
assert.equal(keyed.paused, true);
assert.equal(reports.at(-1).value, 'pause|');
assert.ok(key('f'));
assert.equal(container.fullscreens, 1, 'the container goes fullscreen, not the bare element');
assert.equal(keyed.fullscreens, 0);
assert.equal(key('x'), false, 'other keys are left alone');
assert.equal(key('m', { metaKey: true }), false, 'shortcuts with a modifier are left alone');
video.player = null;
for (const fn of listeners.get('keydown')) fn({ target: video, key: 'm', preventDefault: () => assert.fail('not inside a player') });
// The fullscreen command from Swift enters the container's fullscreen too.
keyed.setAttribute('data-media-command', '1:fullscreen');
host.sync();
assert.equal(container.fullscreens, 2);
assert.equal(keyed.fullscreens, 0);
elements.splice(elements.indexOf(keyed), 1); players.pop();

// A new element for a player that already played starts at the player's position, once.
const handover = new FakeMedia({ 'data-player-id': 'm6', 'data-media-start': '42.5' });
handover.readyState = 0;
elements.push(handover);
host.sync();
assert.equal(handover.currentTime, 0, 'not before the metadata');
fire('loadedmetadata', handover);
assert.equal(handover.currentTime, 42.5);
handover.currentTime = 50;
fire('loadedmetadata', handover); host.sync();
assert.equal(handover.currentTime, 50, 'applied once');

// Rendition limits and track choices reach the adaptive player once per change; its tracks come
// back as `media-tracks-report`, and a plain file reports none once its metadata loads.
const selections = [];
window.__selectAdaptiveMedia = (element, wish) => selections.push(wish);
window.__adaptiveMediaTracks = () => 'v\t720\t1280\t2000000';
const choosing = new FakeMedia({ 'data-player-id': 'm8', 'data-media-source': 'https://cdn/d.m3u8', 'data-media-max-size': '720x1280', 'data-media-text': 'off' });
elements.push(choosing);
host.sync();
await settle();
host.sync();
assert.deepEqual(selections, [{ width: 720, height: 1280, peakBitRate: 0, audio: '', text: 'off' }]);
choosing.setAttribute('data-media-text', '3');
host.sync();
assert.equal(selections.length, 2);
assert.equal(selections[1].text, '3');
listeners.get('swiftuiwebtrackschange')[0]({ target: choosing });
assert.deepEqual(reports.at(-1), { element: choosing, name: 'media-tracks-report', value: 'v\t720\t1280\t2000000' });
fire('loadedmetadata', video);
assert.deepEqual(reports.at(-1), { element: video, name: 'media-tracks-report', value: '' });
fire('loadedmetadata', choosing);
assert.notEqual(reports.at(-1).name, 'media-tracks-report', 'the adaptive player reports its own tracks');

// A player without a view plays on an element of the host, reported through the reserved route; a view that mounts takes
// the element over at its position, and the host's element is released.
{
  const headlessReports = [];
  const made = [];
  class HeadlessMedia extends FakeMedia {
    constructor() { super({}); this.style = {}; this.listeners = new Map(); this.removed = false; }
    addEventListener(type, fn) { this.listeners.set(type, fn); }
    getAttributeNames() { return [...this.attributes.keys()]; }
    removeAttribute(name) { this.attributes.delete(name); }
    remove() { this.removed = true; }
    load() {}
  }
  let wishes = [{ id: 'p1', kind: 'audio', attrs: { 'data-player-id': 'p1', src: '/a.mp3', 'data-media-playing': '1', 'data-media-start': '12' } }];
  const holder = { getAttribute: (n) => n === 'data-headless-media-wishes' ? JSON.stringify(wishes) : n === 'data-headless-event-id' ? '4294967280' : null };
  const doc = { createElement: (tag) => { if (tag === 'div') return { setAttribute() {}, style: {}, append() {}, remove() {} }; const e = new HeadlessMedia(); made.push(e); return e; }, body: { append() {} }, documentElement: {} };
  const items = [];
  const hroot = { querySelector: (q) => (q.includes('headless') ? holder : null), querySelectorAll: (s) => s.includes('avkit-video-player') ? [] : items.filter((e) => e.isConnected), addEventListener() {}, contains: (e) => items.includes(e) };
  const hwindow = { ...window, document: doc, HTMLMediaElement: FakeMedia, Date: window.Date };
  const hhost = new MediaHost(hroot, { window: hwindow, dispatchNamed: () => assert.fail('no element owner'), dispatchHeadless: (id, value, name) => headlessReports.push({ id, value, name }) });
  hhost.sync();
  assert.equal(made.length, 1, 'one element for the player');
  assert.equal(made[0].plays, 1, 'it plays the wish');
  assert.equal(made[0].getAttribute('src'), '/a.mp3');
  made[0].currentTime = 20;
  made[0].listeners.get('pause')();
  assert.equal(headlessReports.at(-1).id, 4294967280);
  assert.equal(headlessReports.at(-1).name, 'media-report-headless');
  assert.ok(headlessReports.at(-1).value.startsWith('p1|pause|20|'), headlessReports.at(-1).value);
  hhost.sync();
  assert.equal(made.length, 1, 'the same element on the next commit');
  // A view mounts for the player.
  const view = new FakeMedia({ 'data-player-id': 'p1', 'data-media-playing': '1' });
  items.push(view);
  hhost.sync();
  assert.equal(view.getAttribute('data-media-start'), '20', 'the view starts where the host element was');
  assert.equal(made[0].removed, true, 'the host element is released');
  assert.equal(made[0].paused, true);
  // The view goes away: a new host element starts where the view stopped.
  view.currentTime = 31; view.isConnected = false; items.length = 0;
  hhost.sync();
  assert.equal(made.length, 2);
  assert.equal(made[1].getAttribute('data-media-start'), '31');
  // No wish, no element.
  wishes = [];
  hhost.sync();
  assert.equal(made[1].removed, true);
  hhost.dispose();
}

// Play intent (section 12.27): every report names the intent the host applied, an aborted play is not reported as a pause (the
// pause that aborted it is a request, and its own event says what happened), and a refused play names the intent it was asked
// under, so a refusal of a play that Swift has since replaced is stale to Swift rather than a pause.
{
  const intentReports = [];
  const intentRoot = { querySelectorAll: () => [], addEventListener: () => {}, contains: () => true };
  const intentHost = new MediaHost(intentRoot, { window, dispatchNamed: (element, name, value) => intentReports.push({ element, name, value }) });
  const element = new FakeMedia({ 'data-player-id': 'i1', 'data-media-playing': '1', 'data-media-intent': '5' });
  intentHost.reconcile(element);
  assert.equal(element.plays, 1, 'the play is asked once');
  intentHost.report(element, 'playing');
  assert.equal(intentReports.at(-1).value.split('|').at(-1), '5', 'the report names the applied intent');
  // An aborted play (a pause interrupted it) is not reported.
  element.paused = true;
  element.play = () => Promise.reject(Object.assign(new Error('interrupted by a call to pause()'), { name: 'AbortError' }));
  const before = intentReports.length;
  element.setAttribute('data-media-intent', '6');
  intentHost.reconcile(element);
  await settle();
  assert.equal(intentReports.length, before, 'an AbortError reports nothing');
  // A refusal reports a pause under the intent it was asked under, even after a newer intent was applied.
  element.paused = true;
  let refuse;
  element.play = () => new Promise((_, reject) => { refuse = reject; });
  element.setAttribute('data-media-intent', '7');
  intentHost.reconcile(element);
  element.setAttribute('data-media-intent', '8');
  refuse(Object.assign(new Error('not allowed'), { name: 'NotAllowedError' }));
  await settle();
  const refusal = intentReports.at(-1);
  assert.equal(refusal.name, 'media-report');
  assert.ok(refusal.value.startsWith('pause|'), refusal.value);
  assert.equal(refusal.value.split('|').at(-1), '7', 'the refusal names the intent of the play it refused');
  // Sound follows the same intents: a `volumechange` the element sends for a mute the host applied names that intent, so a
  // change the player has asked for since does not take the element's answer (section 12.27).
  const sound = new FakeMedia({ 'data-player-id': 'i2', 'data-media-muted': '1', 'data-media-intent': '11' });
  intentHost.reconcile(sound);
  assert.equal(sound.muted, true, 'the mute is applied');
  intentHost.report(sound, 'volumechange');
  assert.equal(intentReports.at(-1).value.split('|').at(-1), '11', 'the volumechange names the intent that muted the element');
  intentHost.dispose();
}

// needsSync: a page without media syncs for what a commit adds or changes; a page with media syncs every commit, because the
// controls' values and the players' events are read by every sync.
{
  const changesOf = ({ touches = [], attributes = [], everything = false } = {}) => ({
    everything, touches: (selector) => touches.includes(selector), changedAttribute: (names) => names.some((name) => attributes.includes(name)),
  });
  const page = (media) => ({
    querySelectorAll: (selector) => (selector.startsWith('video') ? media : []),
    addEventListener: () => {}, contains: () => false,
  });
  const empty = new MediaHost(page([]), { window, dispatchNamed: () => {} });
  assert.equal(empty.needsSync(changesOf({ everything: true })), true, 'the first commit');
  empty.sync();
  assert.equal(empty.needsSync(changesOf({ touches: ['.unrelated'], attributes: ['class'] })), false, 'an unrelated change on a page without media');
  assert.equal(empty.needsSync(changesOf({ touches: ['video[data-player-id],audio[data-player-id],.avkit-video-player'] })), true, 'a player added or changed');
  assert.equal(empty.needsSync(changesOf({ touches: ['[data-headless-media-wishes]'] })), true, 'the headless wishes changed');
  assert.equal(empty.needsSync(changesOf({ attributes: ['data-player-id'] })), true, 'a player that stopped matching');
  assert.equal(empty.needsSync(changesOf({ attributes: ['data-headless-event-id'] })), true, 'the headless event id changed');
  const withMedia = new MediaHost(page([new FakeMedia({ 'data-player-id': 'idle' })]), { window, dispatchNamed: () => {} });
  withMedia.sync();
  assert.equal(withMedia.present, true);
  assert.equal(withMedia.needsSync(changesOf({ touches: ['.unrelated'] })), true, 'a page with media syncs every commit');
  withMedia.dispose();
  empty.dispose();
}

host.dispose();
console.log('media host: ok');
