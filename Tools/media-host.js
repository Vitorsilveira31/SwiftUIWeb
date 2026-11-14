// Media playback for SwiftUIWebAVFoundation, on the main thread.
//
// Swift renders what an AVPlayer wants as attributes on its <video>/<audio>:
//   data-media-playing  "1" | "0"
//   data-media-muted    "1" | "0"
//   data-media-volume   0…1
//   data-media-rate     playback rate
//   data-media-source   an adaptive (HLS/DASH) source; plain sources are the `src` attribute
//   data-media-command  "<sequence>:<verb>[:<argument>]" (seek, fullscreen, exitfullscreen, pip)
//   data-media-max-size, data-media-peak-bitrate   rendition limits ("<w>x<h>", bits/s)
//   data-media-audio, data-media-text              chosen track ids; text "off" hides
// The adaptive player's tracks go back as a `media-tracks-report` event (one record per line, see
// MediaSelection.swift); a plain file reports none once its metadata loads.
// After every commit this host makes each element match, and reports the element's events back as
// a `media-report` named event: "<event>|<currentTime>|<duration>|<paused>|<muted>|<volume>|<buffered>|<rate>|<readyState>|
// <seeking>|<ended>|<errorCode>|<seekSequence>|<hostTime>|<item>|<intent>", buffered being the loaded "start-end" ranges separated by ";",
// intent the request (`data-media-intent`: play, pause, mute, volume) the host had applied when it sampled: a report of an
// older intent than the player's newest does not change what the player wants (section 12.27),
// seekSequence the newest seek command the element has taken (what a `seeked` completes) and hostTime the `Date.now()` of
// the sample, which lets Swift age the sample by the delay between the two threads.
// The reports are state deltas: Swift keeps a mirror of each element and extrapolates its time from the last sample with
// the playback rate (MediaBackend.swift, `_MediaMirror`), so a `timeupdate` that the mirror already predicts is not sent
// (a sample every second at most while playback is steady); state transitions are sent at once. While a short periodic
// time observer is registered (`data-media-observe`, the interval in ms) a requestAnimationFrame stream samples the
// element at that interval to keep the mirror tight.
// A `VideoPlayer`'s own controls (SwiftUIWebAVKit/AVKitControls.swift) are drawn by Swift over a control-less element; the page-only part of
// them is `AVKitControls` below: the scrubber and volume drag, the auto-hide timer, the keyboard, fullscreen and Picture in Picture
// (which need the user's gesture), and the continuous values (elapsed and remaining time, the scrubber's position). Whatever should
// change the player goes back to Swift as one `avkit-action` event, "<verb>|<argument>".
// Everything goes through the publication, so it works the same whether Swift runs on this thread
// or in the worker, where there is no DOM to call into.

const MEDIA = 'data-player-id';
const REPORTED = ['loadedmetadata', 'durationchange', 'play', 'playing', 'pause', 'ended', 'timeupdate',
  'seeking', 'seeked', 'volumechange', 'ratechange', 'waiting', 'stalled', 'canplay', 'canplaythrough', 'emptied', 'progress', 'error',
  'enterpictureinpicture', 'leavepictureinpicture'];
const TIME_UPDATE_INTERVAL_MS = 100;
const PROGRESS_INTERVAL_MS = 250;
/** A steady `timeupdate` is dropped while the extrapolated time is this close (seconds), up to RESYNC_MS since the last sample. */
const PREDICTION_TOLERANCE = 0.05;
const RESYNC_MS = 1000;
/** While an element plays, its time is checked this often against what Swift's mirror predicts (`timeupdate` itself comes
 * about every 250 ms), and a drift past PREDICTION_TOLERANCE is sent: a browser's audio clock may start late or stall. */
const WATCH_MS = 50;
const STREAM_MIN_MS = 33;
const STREAM_MAX_MS = 250;
const TRACKS_CHANGED = 'swiftuiwebtrackschange';
// Headless wishes come from the page's publication: only these element kinds and attributes are applied, so a
// message cannot create a script-capable element or set an event handler.
const HEADLESS_KINDS = ['video', 'audio', 'source', 'track'];
const HEADLESS_ATTRIBUTES = new Set(['data-player-id', 'src', 'preload', 'controls', 'crossorigin', 'loop', 'autoplay', 'muted', 'playsinline',
  'kind', 'srclang', 'label', 'default', 'type', 'media',
  'data-media-audio', 'data-media-command', 'data-media-intent', 'data-media-item', 'data-media-max-size', 'data-media-muted',
  'data-media-observe', 'data-media-peak-bitrate', 'data-media-playing', 'data-media-rate', 'data-media-source',
  'data-media-start', 'data-media-text', 'data-media-volume']);
const HEADLESS_URL_ATTRIBUTES = new Set(['src', 'data-media-source']);
// A URL the page may load: http(s), blob:, or a relative path. Read as the URL parser reads it: leading and trailing C0
// controls and spaces are dropped, and every tab and line break, so "\u0001data:..." is a data: URL here too.
function allowedMediaURL(value) {
  const text = String(value).replace(/[\t\n\r]/g, '').replace(/^[\u0000-\u0020]+|[\u0000-\u0020]+$/g, '');
  if (/^(https?:|blob:)/i.test(text)) return true;
  return !/^[a-z][a-z0-9+.-]*:/i.test(text) && !text.startsWith('//');
}
// Sets one headless attribute if the name and value are allowed; anything else is ignored.
function setHeadlessAttribute(element, name, value) {
  if (name.toLowerCase().startsWith('on') || !HEADLESS_ATTRIBUTES.has(name)) return;
  if (HEADLESS_URL_ATTRIBUTES.has(name) && !allowedMediaURL(value)) return;
  if (element.getAttribute(name) !== String(value)) element.setAttribute(name, String(value));
}
const SELECTION =['data-media-max-size', 'data-media-peak-bitrate', 'data-media-audio', 'data-media-text'];

// The loaded ranges, for the buffer shown behind a progress bar.
function buffered(element) {
  const ranges = [];
  const loaded = element.buffered;
  for (let index = 0; index < (loaded?.length ?? 0); index++) {
    ranges.push(`${loaded.start(index)}-${loaded.end(index)}`);
  }
  return ranges.join(';');
}


const PLAYER = '.avkit-video-player';
const AUTO_HIDE_MS = 3000;
/** How long a released scrubber keeps showing where it was dropped while the seek travels to the element and back. */
const SEEK_SETTLE_MS = 2500;
const VOLUME_SEND_MS = 80;
const ARROW_SEEK = 5;
const ARROW_VOLUME = 0.1;
const CONTROL_EVENTS = ['loadedmetadata', 'durationchange', 'play', 'playing', 'pause', 'ended', 'timeupdate', 'seeking', 'seeked',
  'volumechange', 'ratechange', 'waiting', 'stalled', 'canplay', 'emptied', 'progress', 'error', 'enterpictureinpicture', 'leavepictureinpicture'];
/** Events that change whether the controls may hide; `timeupdate` must not restart the timer. */
const STATE_EVENTS = new Set(['play', 'playing', 'pause', 'ended', 'waiting', 'stalled', 'emptied', 'error', 'seeked', 'canplay', 'loadedmetadata']);

function clock(seconds) {
  const whole = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0;
  const hours = Math.floor(whole / 3600), minutes = Math.floor(whole % 3600 / 60), rest = whole % 60;
  const two = (value) => String(value).padStart(2, '0');
  return hours > 0 ? `${hours}:${two(minutes)}:${two(rest)}` : `${minutes}:${two(rest)}`;
}

function spoken(seconds) {
  const whole = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0;
  const hours = Math.floor(whole / 3600), minutes = Math.floor(whole % 3600 / 60), rest = whole % 60;
  const parts = [];
  if (hours > 0) parts.push(`${hours} ${hours === 1 ? 'hour' : 'hours'}`);
  if (minutes > 0) parts.push(`${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`);
  if (rest > 0 || parts.length === 0) parts.push(`${rest} ${rest === 1 ? 'second' : 'seconds'}`);
  return parts.join(', ');
}

const percent = (fraction) => `${(Math.min(1, Math.max(0, Number.isFinite(fraction) ? fraction : 0)) * 100).toFixed(1)}%`;
const clean = (value) => String(value ?? '').replace(/[\t\n\r]/g, ' ');

/** The menus of the control bar; one is open at a time. Each menu's toggle has the class `avkit-<name>`. */
const MENUS = ['speed', 'captions', 'audio'];

/** A plain element's subtitle and caption tracks (its `<track>` children), in the order Swift's menu lists them. */
function nativeCaptionTracks(element) {
  return [...(element.textTracks ?? [])].filter((track) => track.kind === 'subtitles' || track.kind === 'captions');
}

/** Shows the caption track with index `choice` and disables the others; `off` disables them all. */
function showTextTrack(element, choice) {
  nativeCaptionTracks(element).forEach((track, index) => {
    const mode = choice !== 'off' && String(index) === choice ? 'showing' : 'disabled';
    if (track.mode !== mode) track.mode = mode;
  });
}

/** The page's side of a `VideoPlayer`'s controls. One instance serves every player; its state is kept per player element. */
class AVKitControls {
  constructor(host) {
    this.host = host;
    this.window = host.window;
    this.state = new WeakMap();
    const root = host.root, signal = host.abort.signal, options = { capture: true, signal };
    root.addEventListener('click', (event) => this.click(event), options);
    root.addEventListener('dblclick', (event) => this.doubleClick(event), options);
    root.addEventListener('pointerdown', (event) => this.pointerDown(event), options);
    root.addEventListener('pointermove', (event) => this.pointerMove(event), options);
    root.addEventListener('pointerup', (event) => this.pointerUp(event), options);
    root.addEventListener('pointercancel', (event) => this.pointerUp(event, true), options);
    root.addEventListener('pointerover', (event) => this.pointerOver(event, true), options);
    root.addEventListener('pointerout', (event) => this.pointerOver(event, false), options);
    root.addEventListener('focusin', (event) => this.focusChanged(event), options);
    root.addEventListener('focusout', (event) => this.focusChanged(event), options);
    root.addEventListener('keydown', (event) => this.keydown(event), options);
    for (const type of CONTROL_EVENTS) root.addEventListener(type, (event) => this.mediaEvent(event.target, type), options);
    const doc = this.window.document;
    for (const type of ['fullscreenchange', 'webkitfullscreenchange']) doc?.addEventListener?.(type, () => this.refreshAll(), { signal });
    for (const type of ['webkitbeginfullscreen', 'webkitendfullscreen']) root.addEventListener(type, () => this.refreshAll(), options);
  }

  players() { return this.host.root.querySelectorAll?.(PLAYER) ?? []; }
  playerOf(target) { return target?.closest?.(PLAYER) ?? null; }
  media(player) { return player.querySelector('video[data-player-id],audio[data-player-id]'); }
  controlsOf(player) { return player.querySelector(':scope > .avkit-controls'); }
  stateOf(player) {
    let state = this.state.get(player);
    if (!state) { state = { hideTimer: 0, drag: null, settle: null, menu: null, pointerType: 'mouse', sentVolume: -Infinity }; this.state.set(player, state); }
    return state;
  }

  /** After every commit: new players get their first values; Swift's re-render never moves what the host owns. Returns the
   * number of players it found. */
  sync() {
    const players = this.players();
    for (const player of players) { this.refresh(player); if (!this.stateOf(player).armed) { this.stateOf(player).armed = true; this.arm(player); } }
    return players.length;
  }

  mediaEvent(target, type) {
    const player = this.playerOf(target);
    if (!player || target !== this.media(player)) return;
    const state = this.stateOf(player);
    if (type === 'seeked' || type === 'error' || type === 'emptied') state.settle = null;
    this.refresh(player);
    if (STATE_EVENTS.has(type)) this.arm(player);
  }

  refreshAll() { for (const player of this.players()) this.refresh(player); }

  // ---- Values the host owns -------------------------------------------------------------------------------------------------

  /** The time the controls show: the drag's preview, a released drag's target while its seek travels, else the element's. */
  shownTime(player, media, state) {
    if (state.drag?.kind === 'scrubber') return state.drag.value;
    if (state.settle) {
      if (this.clock() < state.settle.until) return state.settle.value;
      state.settle = null;
    }
    return media.currentTime || 0;
  }

  clock() { return this.window.performance?.now?.() ?? Date.now(); }

  refresh(player) {
    const media = this.media(player), controls = this.controlsOf(player);
    if (!media || !controls) return;
    const state = this.stateOf(player);
    const duration = Number.isFinite(media.duration) && media.duration > 0 ? media.duration : 0;
    const time = Math.min(this.shownTime(player, media, state), duration || Infinity);
    const elapsed = controls.querySelector('.avkit-elapsed'), remaining = controls.querySelector('.avkit-remaining');
    const text = (element, value) => { if (element && element.textContent !== value) element.textContent = value; };
    text(elapsed, clock(time));
    text(remaining, duration ? `-${clock(Math.max(0, duration - time))}` : '');
    const scrubber = controls.querySelector('.avkit-scrubber');
    if (scrubber) {
      this.setSlider(scrubber, duration ? time / duration : 0, {
        now: Math.round(time), max: Math.round(duration),
        text: duration ? `${spoken(time)} of ${spoken(duration)}` : spoken(time),
      });
      if (duration) scrubber.removeAttribute('aria-disabled'); else this.own(scrubber, 'aria-disabled', 'true');
      let loaded = 0;
      for (let index = 0; index < (media.buffered?.length ?? 0); index++) if (media.buffered.start(index) <= time + 0.5) loaded = Math.max(loaded, media.buffered.end(index));
      const loadedBar = scrubber.querySelector('.avkit-loaded');
      if (loadedBar) loadedBar.style.width = percent(duration ? loaded / duration : 0);
    }
    const volume = controls.querySelector('.avkit-volume');
    if (volume && state.drag?.kind !== 'volume') {
      const level = media.muted ? 0 : media.volume;
      this.setSlider(volume, level, { now: Math.round(level * 100), max: 100, text: `${Math.round(level * 100)} percent` });
    }
    const doc = this.window.document;
    const pip = media.localName === 'video' && doc?.pictureInPictureEnabled && !media.disablePictureInPicture;
    this.own(controls, 'data-ctl-pip', pip ? '1' : '0');
    const fullscreenElement = doc?.fullscreenElement ?? doc?.webkitFullscreenElement;
    const supported = !!(player.requestFullscreen || player.webkitRequestFullscreen || media.webkitEnterFullscreen);
    const fullscreen = !supported ? 'x' : fullscreenElement === player || media.webkitDisplayingFullscreen ? '1' : '0';
    this.own(controls, 'data-ctl-fullscreen', fullscreen);
    const button = controls.querySelector('.avkit-fullscreen');
    if (button) {
      const label = fullscreen === '1' ? 'Exit Full Screen' : 'Enter Full Screen';
      if (button.getAttribute('aria-label') !== label) { button.setAttribute('aria-label', label); button.setAttribute('title', label); }
    }
    this.own(controls, 'data-ctl-scrubbing', state.drag?.kind === 'scrubber' ? '1' : '0');
    this.own(controls, 'data-ctl-menu', state.menu ?? '');
    for (const name of MENUS) {
      const toggle = controls.querySelector(`.avkit-${name}`);
      if (toggle) this.own(toggle, 'aria-expanded', state.menu === name ? 'true' : 'false');
    }
  }

  own(element, name, value) { if (element.getAttribute(name) !== value) element.setAttribute(name, value); }

  setSlider(slider, fraction, { now, max, text }) {
    this.own(slider, 'aria-valuenow', String(now));
    this.own(slider, 'aria-valuemax', String(max));
    this.own(slider, 'aria-valuetext', text);
    const width = percent(fraction);
    const played = slider.querySelector('.avkit-played'), thumb = slider.querySelector('.avkit-thumb');
    if (played && played.style.width !== width) played.style.width = width;
    if (thumb && thumb.style.left !== width) thumb.style.left = width;
  }

  // ---- Showing and hiding ---------------------------------------------------------------------------------------------------

  /** Why the controls stay: '' (they may hide), 'hover' (the pointer is on the bar; it may leave without an event we see) or 'busy'. */
  keepsVisible(player, media, controls, state) {
    if (!media || media.paused || media.ended || media.error || media.readyState < 3) return 'busy';
    if (state.drag || state.menu) return 'busy';
    const active = this.window.document?.activeElement;
    if (active && controls.contains(active) && active.matches?.(':focus-visible')) return 'busy';
    // The pointer over the bar is read from `:hover`, not from enter/leave events: an element the pointer is on can be replaced
    // by a render. A finger leaves no hover.
    if (state.pointerType !== 'touch' && controls.querySelector('.avkit-bar')?.matches(':hover')) return 'hover';
    return '';
  }

  /** Shows the controls and, when playback allows, schedules their hiding. */
  arm(player) {
    const media = this.media(player), controls = this.controlsOf(player), state = this.stateOf(player);
    if (!controls) return;
    (this.window.clearTimeout ?? clearTimeout).call(this.window, state.hideTimer);
    state.hideTimer = 0;
    this.own(controls, 'data-ctl-hidden', '0');
    if (this.keepsVisible(player, media, controls, state) === 'busy') return;
    state.hideTimer = (this.window.setTimeout ?? setTimeout).call(this.window, () => {
      state.hideTimer = 0;
      const why = this.keepsVisible(player, media, controls, state);
      if (why === 'hover') this.arm(player);
      else if (!why) this.own(controls, 'data-ctl-hidden', '1');
    }, AUTO_HIDE_MS);
  }

  hideNow(player) {
    const media = this.media(player), controls = this.controlsOf(player), state = this.stateOf(player);
    if (!controls || this.keepsVisible(player, media, controls, state) !== '') return;
    (this.window.clearTimeout ?? clearTimeout).call(this.window, state.hideTimer);
    state.hideTimer = 0;
    this.own(controls, 'data-ctl-hidden', '1');
  }

  /** The pointer leaves the bar: the controls may start to hide. */
  pointerOver(event, entering) {
    const player = this.playerOf(event.target);
    if (!player || entering || !event.target.closest?.('.avkit-bar')) return;
    if (!event.relatedTarget || !event.target.closest('.avkit-bar').contains(event.relatedTarget)) this.arm(player);
  }

  focusChanged(event) {
    const player = this.playerOf(event.target);
    if (player && this.controlsOf(player)?.contains(event.target)) this.arm(player);
  }

  // ---- Pointer --------------------------------------------------------------------------------------------------------------

  /** Where along `slider` a pointer is, 0...1. */
  fractionAt(slider, event) {
    const rect = (slider.querySelector('.avkit-track') ?? slider).getBoundingClientRect();
    return rect.width > 0 ? Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width)) : 0;
  }

  pointerDown(event) {
    const player = this.playerOf(event.target);
    if (!player) return;
    const state = this.stateOf(player);
    state.pointerType = event.pointerType || 'mouse';
    // A touch on the surface toggles the controls (its click decides); anything else that touches the player shows them.
    state.shownAtDown = this.controlsOf(player)?.getAttribute('data-ctl-hidden') !== '1';
    if (state.pointerType !== 'touch' || !this.isSurface(player, event.target)) this.arm(player);
    const slider = event.target.closest?.('.avkit-slider');
    if (slider && player.contains(slider) && event.button === 0 && slider.getAttribute('aria-disabled') !== 'true') {
      const media = this.media(player);
      const kind = slider.classList.contains('avkit-scrubber') ? 'scrubber' : 'volume';
      state.drag = { kind, slider, pointerId: event.pointerId, value: 0 };
      try { slider.setPointerCapture(event.pointerId); } catch { /* a synthetic pointer */ }
      slider.focus?.({ preventScroll: true });
      this.drag(player, media, state, event);
      event.preventDefault();
      return;
    }
    // Anything but a click on the controls themselves closes the open menu.
    if (state.menu && !event.target.closest?.('.avkit-menu-group')) this.setMenu(player, null);
  }

  pointerMove(event) {
    const player = this.playerOf(event.target);
    if (!player) return;
    const state = this.stateOf(player);
    if (state.drag && event.pointerId === state.drag.pointerId) {
      this.drag(player, this.media(player), state, event);
    } else if (event.pointerType !== 'touch') {
      state.pointerType = event.pointerType || 'mouse';
      this.arm(player);
    }
  }

  drag(player, media, state, event) {
    const { kind, slider } = state.drag;
    const fraction = this.fractionAt(slider, event);
    if (kind === 'scrubber') {
      const duration = Number.isFinite(media.duration) ? media.duration : 0;
      state.drag.value = fraction * duration;
    } else {
      state.drag.value = fraction;
      this.setSlider(slider, fraction, { now: Math.round(fraction * 100), max: 100, text: `${Math.round(fraction * 100)} percent` });
      this.queueVolume(player, media, state, fraction);
    }
    this.refresh(player);
  }

  /** Sends a volume at most every VOLUME_SEND_MS, the newest one last: a dragged slider or a held key moves faster than a change
   * travels to Swift and back, and an element's own report of an older volume would undo a newer one. */
  queueVolume(player, media, state, level, fallback) {
    const send = () => { state.volumeTimer = 0; state.sentVolume = this.clock(); this.send(player, media, 'volume', state.volumeLevel.toFixed(3), fallback); };
    state.volumeLevel = level;
    const wait = VOLUME_SEND_MS - (this.clock() - state.sentVolume);
    if (wait <= 0) { send(); return; }
    if (!state.volumeTimer) state.volumeTimer = (this.window.setTimeout ?? setTimeout).call(this.window, send, wait);
  }

  flushVolume(player, media, state, level) {
    (this.window.clearTimeout ?? clearTimeout).call(this.window, state.volumeTimer);
    state.volumeTimer = 0;
    state.sentVolume = this.clock();
    this.send(player, media, 'volume', level.toFixed(3));
  }

  pointerUp(event, cancelled = false) {
    const player = this.playerOf(event.target);
    const state = player && this.stateOf(player);
    if (!state?.drag || event.pointerId !== state.drag.pointerId) return;
    const { kind, slider, value } = state.drag;
    const media = this.media(player);
    state.drag = null;
    try { slider.releasePointerCapture(event.pointerId); } catch { /* already released */ }
    if (!cancelled) {
      if (kind === 'scrubber') {
        // The element is asked once, on release (a seek per pointer move would stall a stream); the thumb stays where it was dropped
        // until the seek lands.
        state.settle = { value, until: this.clock() + SEEK_SETTLE_MS };
        this.send(player, media, 'seek', value.toFixed(3));
      } else {
        this.flushVolume(player, media, state, value);
      }
    }
    this.refresh(player);
    this.arm(player);
  }

  /** A click on the video itself or on the app's own overlay content, but not on a control or on something the overlay makes clickable. */
  isSurface(player, target) {
    for (let node = target; node && node !== player; node = node.parentElement) {
      if (node.classList?.contains('avkit-controls')) return false;
      if (node.matches?.('button,a,input,select,textarea,summary,[role="button"],[role="link"],[role="slider"],[tabindex]')) return false;
    }
    return true;
  }

  click(event) {
    const player = this.playerOf(event.target);
    if (!player) return;
    const state = this.stateOf(player);
    const control = event.target.closest?.('[data-control-action]');
    if (control && this.controlsOf(player)?.contains(control)) {
      this.arm(player);
      this.act(player, control.getAttribute('data-control-action'), control.getAttribute('data-control-argument'), event);
      return;
    }
    if (!this.isSurface(player, event.target)) return;
    if (state.menu) { this.setMenu(player, null); return; }
    if (state.pointerType === 'touch') {
      // A tap shows the controls, and hides them again while the video plays.
      if (state.shownAtDown) this.hideNow(player); else this.arm(player);
    } else {
      this.arm(player);
      this.togglePlayback(player);
    }
  }

  doubleClick(event) {
    const player = this.playerOf(event.target);
    if (!player || !this.isSurface(player, event.target) || this.stateOf(player).pointerType === 'touch') return;
    this.toggleFullscreen(player);
  }

  // ---- Actions ---------------------------------------------------------------------------------------------------------------

  /** Asks Swift to do `verb` to the player; without one (no event owner) the element is changed directly. */
  send(player, media, verb, argument, fallback) {
    if (this.host.dispatchNamed(player, 'avkit-action', `${verb}|${argument}`)) return;
    fallback?.(media);
  }

  act(player, action, argument, event) {
    const media = this.media(player);
    if (!media) return;
    switch (action) {
      case 'play-pause': this.togglePlayback(player); break;
      case 'skip-back': this.send(player, media, 'skip', '-10', (m) => { m.currentTime = Math.max(0, m.currentTime - 10); }); break;
      case 'skip-forward': this.send(player, media, 'skip', '10', (m) => { m.currentTime += 10; }); break;
      case 'mute': this.toggleMute(player, media); break;
      case 'speed': case 'captions': case 'audio': this.toggleMenu(player, action, event.detail === 0); break;
      case 'rate':
        this.send(player, media, 'rate', argument, (m) => { m.playbackRate = Number(argument); });
        this.closeMenu(player, 'speed');
        break;
      case 'caption':
        this.send(player, media, 'caption', argument, (m) => showTextTrack(m, argument));
        this.closeMenu(player, 'captions');
        break;
      case 'audio-track':
        this.send(player, media, 'audio', argument);
        this.closeMenu(player, 'audio');
        break;
      case 'pip': this.togglePictureInPicture(player, media); break;
      case 'fullscreen': this.toggleFullscreen(player); break;
      default: break;
    }
  }

  togglePlayback(player) {
    const media = this.media(player);
    if (!media) return;
    if (media.paused || media.ended) {
      // The element is asked directly, inside the user's gesture (a browser refuses sound otherwise), and Swift is told so its
      // wish follows; from the end, Swift's `play` starts over.
      if (!media.ended) media.play()?.catch?.(() => {});
      this.send(player, media, 'play', '', (m) => { if (m.ended) m.currentTime = 0; m.play()?.catch?.(() => {}); });
    } else {
      media.pause();
      this.send(player, media, 'pause', '');
    }
  }

  /** The toggle is Swift's to decide (`mute|toggle`): the element may not show the player's newest wish yet (section 12.27). */
  toggleMute(player, media) {
    this.send(player, media, 'mute', 'toggle', (m) => { m.muted = !(m.muted || m.volume === 0); });
  }

  menuItems(player, name) {
    return [...(this.controlsOf(player)?.querySelectorAll(`.avkit-${name}-menu .avkit-menu-item`) ?? [])];
  }

  /** Opens the menu `name`, or closes it when it is the one open. */
  toggleMenu(player, name, focus = false) {
    this.setMenu(player, this.stateOf(player).menu === name ? null : name, focus);
  }

  /** Opens the menu `name` (null closes the open one). */
  setMenu(player, name, focus = false) {
    const state = this.stateOf(player);
    state.menu = name;
    this.refresh(player);
    if (name) {
      const items = this.menuItems(player, name);
      for (const item of items) item.setAttribute('tabindex', '-1');
      if (focus) (items.find((item) => item.getAttribute('aria-checked') === 'true') ?? items[0])?.focus?.({ preventScroll: true });
    }
    this.arm(player);
  }

  /** Closes the menu `name` and returns the focus to its toggle. */
  closeMenu(player, name) {
    this.setMenu(player, null);
    this.controlsOf(player)?.querySelector(`.avkit-${name}`)?.focus?.({ preventScroll: true });
  }

  /** The container goes fullscreen, so the controls come along; the iPhone only presents a video element, with its own controls. */
  toggleFullscreen(player, enterOnly = false) {
    const doc = this.window.document, media = this.media(player);
    const current = doc?.fullscreenElement ?? doc?.webkitFullscreenElement;
    if (enterOnly && (current === player || media?.webkitDisplayingFullscreen)) return;
    if (current === player) { (doc.exitFullscreen ?? doc.webkitExitFullscreen)?.call(doc)?.catch?.(() => {}); return; }
    if (media?.webkitDisplayingFullscreen) { media.webkitExitFullscreen?.(); return; }
    const request = player.requestFullscreen ?? player.webkitRequestFullscreen;
    if (request) request.call(player)?.catch?.(() => {});
    else media?.webkitEnterFullscreen?.();
  }

  togglePictureInPicture(player, media) {
    const doc = this.window.document;
    if (doc?.pictureInPictureElement === media) doc.exitPictureInPicture?.()?.catch?.(() => {});
    else media.requestPictureInPicture?.()?.catch?.(() => {});
  }

  // ---- Keyboard --------------------------------------------------------------------------------------------------------------

  /** Shortcuts while the player, or anything inside it, has focus. */
  keydown(event) {
    const player = this.playerOf(event.target);
    if (!player || event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return;
    const target = event.target;
    if (target.closest?.('input,textarea,select,[contenteditable="true"]') && !target.closest('.avkit-controls')) return;
    const media = this.media(player), state = this.stateOf(player);
    if (!media) return;
    const slider = target.closest?.('.avkit-slider');
    const onButton = target.localName === 'button';
    const duration = Number.isFinite(media.duration) ? media.duration : 0;
    // Keys repeat faster than a change travels to Swift and back: each step starts from the one before it, not from the element.
    const stamp = this.clock();
    const seek = (seconds) => {
      const target = Math.min(duration || Infinity, Math.max(0, seconds));
      state.settle = { value: target, until: stamp + SEEK_SETTLE_MS };
      this.send(player, media, 'seek', target.toFixed(3), (m) => { m.currentTime = target; });
      this.refresh(player);
    };
    const volume = (delta) => {
      const base = state.volumeWish && stamp < state.volumeWish.until ? state.volumeWish.value : (media.muted ? 0 : media.volume);
      const level = Math.min(1, Math.max(0, base + delta));
      state.volumeWish = { value: level, until: stamp + 600 };
      this.queueVolume(player, media, state, level, (m) => { m.volume = level; m.muted = false; });
    };
    const now = this.shownTime(player, media, state);
    if (state.menu) {
      const items = this.menuItems(player, state.menu);
      const at = items.indexOf(this.window.document?.activeElement);
      if (event.key === 'Escape') this.closeMenu(player, state.menu);
      else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') items[(at + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus?.();
      else return;
      event.preventDefault();
      return;
    }
    switch (event.key) {
      case ' ': if (onButton) return; this.togglePlayback(player); break;
      case 'k': case 'K': this.togglePlayback(player); break;
      case 'Enter': return;
      case 'ArrowLeft': case 'ArrowDown':
        if (event.key === 'ArrowDown' && !slider) volume(-ARROW_VOLUME);
        else if (slider?.classList.contains('avkit-volume')) volume(-0.05);
        else if (duration) seek(now - ARROW_SEEK);
        else return;
        break;
      case 'ArrowRight': case 'ArrowUp':
        if (event.key === 'ArrowUp' && !slider) volume(ARROW_VOLUME);
        else if (slider?.classList.contains('avkit-volume')) volume(0.05);
        else if (duration) seek(now + ARROW_SEEK);
        else return;
        break;
      case 'Home': if (slider && duration) seek(0); else return; break;
      case 'End': if (slider && duration) seek(duration); else return; break;
      case 'm': case 'M': this.toggleMute(player, media); break;
      case 'f': case 'F': this.toggleFullscreen(player); break;
      case 'p': case 'P': if (media.localName === 'video') this.togglePictureInPicture(player, media); else return; break;
      default: return;
    }
    event.preventDefault();
    this.arm(player);
  }

  dispose() {
    for (const player of this.players()) (this.window.clearTimeout ?? clearTimeout).call(this.window, this.stateOf(player).hideTimer);
  }
}

export class MediaHost {
  constructor(root, { dispatchNamed, dispatchHeadless = () => false, window: host = globalThis.window }) {
    this.root = root;
    this.window = host;
    this.dispatchNamed = dispatchNamed;
    // A player without a view is reported through one route that belongs to no element: (media id, kind, payload).
    this.dispatchHeadless = dispatchHeadless;
    // media id -> { element, kind, abort } of the elements this host owns, and the last element a view showed for an id.
    this.headless = new Map();
    this.lastMounted = new Map();
    this.headlessOf = new WeakMap();
    this.applied = new WeakMap();
    this.adaptive = new Set();
    // Whether the last sync found media on the page (an element, a player, a headless player or an adaptive source).
    this.present = false;
    this.abort = new host.AbortController();
    for (const type of REPORTED) {
      root.addEventListener(type, (event) => this.report(event.target, type), { capture: true, signal: this.abort.signal });
    }
    this.controls = new AVKitControls(this);
    root.addEventListener(TRACKS_CHANGED, (event) => this.reportTracks(event.target), { capture: true, signal: this.abort.signal });
  }

  // Players the app holds without showing them (an audiobook, a sound): Swift publishes each one's wish as the attributes a
  // `VideoPlayer` would render (`data-headless-media-wishes` on the app root, section 12.17), and this host plays it with an
  // element of its own, hidden, until a view shows the player. The view's element then takes over at the position the host
  // element had (a mounted element starts at `data-media-start`), and the host element is released so nothing plays
  // twice; when the view goes away the host element starts again where the view's stopped.
  syncHeadless() {
    const holder = this.root.querySelector?.('[data-headless-media-wishes]') ?? null;
    let wishes = [];
    if (holder) {
      try { wishes = JSON.parse(holder.getAttribute('data-headless-media-wishes') || '[]'); } catch { wishes = []; }
      this.headlessEventID = Number(holder.getAttribute('data-headless-event-id')) || 0;
    }
    const mounted = new Map();
    for (const element of this.elements()) mounted.set(element.getAttribute(MEDIA), element);
    const wanted = new Set();
    for (const wish of wishes) {
      wanted.add(wish.id);
      const view = mounted.get(wish.id);
      const own = this.headless.get(wish.id);
      if (view) {
        // A view shows the player: it takes over from the host's element.
        if (own) {
          const at = own.element.currentTime || 0;
          if (at > 0 && !this.applied.has(view)) view.setAttribute('data-media-start', String(at));
          this.releaseHeadless(wish.id);
        }
        this.lastMounted.set(wish.id, view);
        continue;
      }
      let start = 0;
      const previous = this.lastMounted.get(wish.id);
      if (previous) {
        // The view is gone; a removed element is paused where it was.
        start = previous.currentTime || 0;
        this.lastMounted.delete(wish.id);
      }
      this.applyHeadless(wish, start);
    }
    for (const id of [...this.headless.keys()]) if (!wanted.has(id)) this.releaseHeadless(id);
    for (const id of [...this.lastMounted.keys()]) if (!wanted.has(id) || !this.lastMounted.get(id).isConnected) this.lastMounted.delete(id);
  }

  applyHeadless(wish, start) {
    const doc = this.window.document;
    if (!doc?.createElement) return;
    if (!HEADLESS_KINDS.includes(wish.kind)) return;
    let own = this.headless.get(wish.id);
    if (own && own.kind !== wish.kind) { this.releaseHeadless(wish.id); own = null; }
    if (!own) {
      const element = doc.createElement(wish.kind);
      const abort = new this.window.AbortController();
      own = { element, kind: wish.kind, abort };
      this.headless.set(wish.id, own);
      this.headlessOf.set(element, wish.id);
      for (const type of REPORTED) element.addEventListener(type, () => this.report(element, type), { signal: abort.signal });
      element.addEventListener(TRACKS_CHANGED, () => this.reportTracks(element), { signal: abort.signal });
      element.style.cssText = 'position:fixed;width:0;height:0;opacity:0;pointer-events:none';
      element.setAttribute('aria-hidden', 'true');
      for (const [name, value] of Object.entries(wish.attrs)) setHeadlessAttribute(element, name, value);
      // Where the view stopped wins over where Swift thought the player was.
      if (start > 0) element.setAttribute('data-media-start', String(start));
      // Held in the document, as a view's element is: some engines do not play a detached video.
      (this.container ??= this.makeContainer(doc)).append(element);
    } else {
      for (const [name, value] of Object.entries(wish.attrs)) {
        // The position is applied once, when an element is made; a changed item brings its own.
        if (name === 'data-media-start') continue;
        setHeadlessAttribute(own.element, name, value);
      }
      for (const name of own.element.getAttributeNames?.() ?? []) {
        if (name.startsWith('data-media-') && name !== 'data-media-start' && !(name in wish.attrs)) own.element.removeAttribute(name);
      }
      if (!('src' in wish.attrs) && own.element.hasAttribute('src')) own.element.removeAttribute('src');
    }
    this.reconcile(own.element);
  }

  makeContainer(doc) {
    const container = doc.createElement('div');
    container.setAttribute('data-headless-media', '');
    container.setAttribute('aria-hidden', 'true');
    container.style.cssText = 'position:fixed;width:0;height:0;overflow:hidden;pointer-events:none';
    (doc.body ?? doc.documentElement).append(container);
    return container;
  }

  releaseHeadless(id) {
    const own = this.headless.get(id);
    if (!own) return;
    this.headless.delete(id);
    own.abort.abort();
    const state = this.applied.get(own.element);
    if (state?.stream) state.unframe?.(state.stream);
    if (state?.watch) (this.window.clearInterval ?? clearInterval).call(this.window, state.watch);
    try { own.element.pause(); } catch { /* not playing */ }
    if (this.adaptive.has(own.element)) { this.adaptive.delete(own.element); this.window.__detachAdaptiveMedia?.(own.element); }
    own.element.removeAttribute('src');
    try { own.element.load?.(); } catch { /* nothing loaded */ }
    own.element.remove?.();
  }

  /** Sends a report of `element` to Swift: through the element's event owner, or the headless route. */
  emit(element, name, payload) {
    const id = this.headlessOf.get(element);
    if (id === undefined) return this.dispatchNamed(element, name, payload);
    return this.dispatchHeadless(this.headlessEventID, `${id}|${payload}`, `${name}-headless`);
  }

  elements() { return this.root.querySelectorAll(`video[${MEDIA}],audio[${MEDIA}]`); }

  // Whether `sync` can change anything after a commit with these changes. Media is reconciled by what the commit changes and
  // by what the element is doing, which the page reports through events: its playback, its controls' values (the text the
  // patch writes over, which the changes do not record), a headless player, and an adaptive source's element are all read by
  // every sync, so while the last sync found any of them, every commit syncs. Otherwise the sync reads the players the
  // patch adds or changes and the headless wishes holder, and a player that stops matching is found by its changed attribute.
  needsSync(changes) {
    if (changes.everything || this.present) return true;
    return changes.touches('video[data-player-id],audio[data-player-id],.avkit-video-player')
      || changes.touches('[data-headless-media-wishes]')
      || changes.changedAttribute(['data-player-id', 'data-headless-media-wishes', 'data-headless-event-id']);
  }

  sync() {
    this.syncHeadless();
    const elements = this.elements();
    for (const element of elements) this.reconcile(element);
    const players = this.controls.sync();
    this.present = elements.length + players > 0 || this.headless.size > 0 || this.adaptive.size > 0;
    // Shaka keeps network and decoder resources until it is destroyed; a removed element releases them.
    for (const element of this.adaptive) {
      if (element.isConnected) continue;
      this.adaptive.delete(element);
      this.window.__detachAdaptiveMedia?.(element);
    }
  }

  reconcile(element) {
    let state = this.applied.get(element);
    if (!state) {
      // A new element for a player that already played starts where the player is.
      const start = Number(element.getAttribute('data-media-start'));
      state = { source: '', command: 0, seekSequence: 0, lastTime: -Infinity, lastProgress: -Infinity, lastBuffered: '', sent: null, stream: 0, lastStream: -Infinity, watch: 0, start: Number.isFinite(start) && start > 0 ? start : 0, tracksSent: null };
      this.applied.set(element, state);
      // A caption track that is added, removed or changes mode (the browser's default included) is reported to Swift.
      // A track added or removed after the metadata loaded changes the menu. Earlier changes come with `loadedmetadata`: a report
      // at startup (or on every mode change, which the browser makes during its own start) re-renders the player while its first
      // commands are in flight, and Swift's stale state would then be applied over them.
      for (const type of ['addtrack', 'removetrack']) {
        element.textTracks?.addEventListener?.(type, () => { if (element.readyState >= 1) this.syncNativeTracks(element); });
      }

      if (state.start && element.readyState >= 1) this.applyStart(element, state);
    }

    // The play intent this commit applies: every report of the element from now on names it (section 12.27). It is applied
    // before the element's sound, play and pause, so the `volumechange` and `pause` events the commit causes name it too.
    state.intent = element.getAttribute('data-media-intent') ?? '';
    const source = element.getAttribute('data-media-source') || '';
    if (source && source !== state.source) {
      state.source = source;
      if (this.playsNatively(element, source)) {
        element.src = source;
      } else if (typeof this.window.__loadAdaptiveMedia === 'function') {
        this.adaptive.add(element);
        // Until Shaka has loaded the source the element has none: a play() now would be refused.
        state.attaching = true;
        Promise.resolve(this.window.__loadAdaptiveMedia(element, source)).then(
          () => { state.attaching = false; if (element.isConnected) this.reconcile(element); },
          () => { state.attaching = false; this.report(element, 'error'); });
      } else {
        element.src = source;
      }
    }

    const muted = element.getAttribute('data-media-muted') === '1';
    if (element.muted !== muted) element.muted = muted;
    const volume = Number(element.getAttribute('data-media-volume'));
    if (Number.isFinite(volume) && Math.abs(element.volume - volume) > 0.001) element.volume = Math.min(1, Math.max(0, volume));
    const rate = Number(element.getAttribute('data-media-rate'));
    if (Number.isFinite(rate) && rate > 0 && element.playbackRate !== rate) element.playbackRate = rate;

    this.stream(element, state);
    if (state.attaching) return;
    this.command(element, state);
    this.select(element, state);

    const playing = element.getAttribute('data-media-playing') === '1';
    if (playing && element.paused && !element.ended) {
      const intent = state.intent;
      const started = element.play();
      // A browser that refuses to start (autoplay policy, no source) reports a pause, so Swift's desired state follows what
      // actually happens instead of asking again on every commit. A play that a pause() interrupted (AbortError) is not
      // reported: the pause came from a request, and the element's own `pause` event says what happened. The refusal names the
      // intent it was asked under, so a refusal of a play that Swift has since replaced does not undo the newer request.
      started?.catch?.((error) => { if (error?.name !== 'AbortError') this.report(element, 'pause', true, intent); });
    } else if (!playing && !element.paused) {
      element.pause();
    }
  }

  command(element, state) {
    const raw = element.getAttribute('data-media-command') || '';
    const [sequenceText, verb, argument] = raw.split(':');
    const sequence = Number(sequenceText);
    if (!Number.isInteger(sequence) || sequence <= state.command) return;
    state.command = sequence;
    if (verb === 'seek') {
      const seconds = Number(argument);
      if (Number.isFinite(seconds)) {
        state.seekSequence = sequence;
        element.currentTime = Math.max(0, seconds);
      }
    } else if (verb === 'fullscreen') {
      // A player with controls goes fullscreen as a whole, so its controls stay.
      const player = element.closest?.(PLAYER);
      if (player) this.controls.toggleFullscreen(player, true); else element.requestFullscreen?.()?.catch?.(() => {});
    } else if (verb === 'exitfullscreen') {
      const target = element.closest?.(PLAYER) ?? element;
      if (this.window.document?.fullscreenElement === target) this.window.document.exitFullscreen?.()?.catch?.(() => {});
    } else if (verb === 'pip') {
      if (argument === '1') element.requestPictureInPicture?.()?.catch?.(() => this.report(element, 'leavepictureinpicture'));
      else if (this.window.document?.pictureInPictureElement === element) this.window.document.exitPictureInPicture?.()?.catch?.(() => {});
    }
  }

  // A plain file's subtitle choice (`off` or a track's index) shows that track; without a choice the browser's default stays.
  selectNativeText(element) {
    const choice = element.getAttribute('data-media-text');
    if (choice !== null) showTextTrack(element, choice);
  }

  // Rendition limits and track choices go to the adaptive player only when they change.
  select(element, state) {
    if (!this.adaptive.has(element)) { this.selectNativeText(element); return; }
    const wish = SELECTION.map((name) => element.getAttribute(name) ?? '').join('|');
    if (wish === (state.selection ?? '|||')) return;
    state.selection = wish;
    const [size, peak, audio, text] = wish.split('|');
    const [width, height] = size ? size.split('x').map(Number) : [0, 0];
    this.window.__selectAdaptiveMedia?.(element, { width, height, peakBitRate: Number(peak) || 0, audio, text });
  }

  reportTracks(target) {
    const element = target instanceof this.window.HTMLMediaElement ? target : null;
    if (!element || !element.hasAttribute(MEDIA) || !(this.headlessOf.has(element) || this.root.contains(element))) return;
    const payload = this.window.__adaptiveMediaTracks?.(element) ?? '';
    this.emit(element, 'media-tracks-report', payload);
  }

  /** A plain element's caption tracks, one `t` record per track (MediaSelection.swift): the index is the option's identifier. */
  nativeTracks(element) {
    return nativeCaptionTracks(element)
      .map((track, index) => ['t', index, clean(track.language), clean(track.label), track.mode === 'showing' ? 1 : 0].join('\t'))
      .join('\n');
  }

  /** Sends a plain element's caption tracks to Swift when they differ from the last report (its menu lists them and shows what
   * the browser's default chose). An adaptive element reports its own tracks. */
  syncNativeTracks(element) {
    const state = this.applied.get(element);
    if (!state || this.adaptive.has(element)) return;
    const payload = this.nativeTracks(element);
    if (payload === state.tracksSent) return;
    state.tracksSent = payload;
    this.emit(element, 'media-tracks-report', payload);
  }

  applyStart(element, state) {
    if (!state.start) return;
    element.currentTime = state.start;
    state.start = 0;
  }

  // Shaka (Media Source Extensions) wherever the browser has them: native HLS outside Safari is new
  // and stalls on seeks, while MSE playback is the same everywhere. Native HLS is the fallback for
  // browsers without MSE, such as Safari on iPhone.
  playsNatively(element, source) {
    if (!source.toLowerCase().includes('.m3u8')) return false;
    const hasMediaSource = typeof this.window.MediaSource === 'function' || typeof this.window.ManagedMediaSource === 'function';
    return !hasMediaSource && element.canPlayType('application/vnd.apple.mpegurl') !== '';
  }

  // The now of the host's own timers (milliseconds; the injected performance in tests).
  clock() { return this.window.performance?.now?.() ?? Date.now(); }

  /** Samples the element at the observer's interval, for as long as one is registered and the element plays. */
  stream(element, state) {
    const interval = Number(element.getAttribute('data-media-observe'));
    if (!(interval > 0)) return;
    state.streamInterval = Math.min(STREAM_MAX_MS, Math.max(STREAM_MIN_MS, interval));
    if (state.stream) return;
    const frame = this.window.requestAnimationFrame ? (f) => this.window.requestAnimationFrame(f) : (f) => setTimeout(f, 16);
    const unframe = this.window.cancelAnimationFrame ? (id) => this.window.cancelAnimationFrame(id) : (id) => clearTimeout(id);
    state.unframe = unframe;
    const tick = () => {
      state.stream = 0;
      if (this.abort.signal.aborted || !element.isConnected || !(Number(element.getAttribute('data-media-observe')) > 0)) return;
      const now = this.clock();
      if (!element.paused && now - state.lastStream >= state.streamInterval) {
        state.lastStream = now;
        this.report(element, 'timeupdate', true);
      }
      state.stream = frame(tick);
    };
    state.stream = frame(tick);
  }

  /** Whether Swift's mirror, extrapolating from `sent`, already predicts the element's time. */
  predicted(element, state, now) {
    const sent = state.sent;
    if (!sent || element.paused !== sent.paused || element.playbackRate !== sent.rate || element.readyState !== sent.readyState
      || element.seeking || element.ended || now - sent.at >= RESYNC_MS) return false;
    const expected = !sent.paused && sent.readyState >= 3 ? sent.time + (now - sent.at) / 1000 * sent.rate : sent.time;
    return Math.abs(element.currentTime - expected) < PREDICTION_TOLERANCE;
  }

  /** Starts the playing element's drift check; it stops itself when the element pauses, ends or leaves the page. */
  watch(element, state) {
    if (state.watch) return;
    const timers = this.window;
    state.watch = (timers.setInterval ?? setInterval).call(timers, () => {
      if (this.abort.signal.aborted || element.paused || element.ended || !element.isConnected) {
        (timers.clearInterval ?? clearInterval).call(timers, state.watch);
        state.watch = 0;
        return;
      }
      this.report(element, 'watch');
    }, WATCH_MS);
  }

  report(target, type, force = false, intent = undefined) {
    const element = target instanceof this.window.HTMLMediaElement ? target : null;
    if (!element || !element.hasAttribute(MEDIA) || !(this.headlessOf.has(element) || this.root.contains(element))) return;
    const state = this.applied.get(element);
    if (type === 'loadedmetadata' && state) this.applyStart(element, state);
    const now = this.clock();
    const ranges = buffered(element);
    if (state && !element.paused && !element.ended) this.watch(element, state);
    if (!force && state) {
      if (type === 'timeupdate' || type === 'watch') {
        if ((type === 'timeupdate' && now - state.lastTime < TIME_UPDATE_INTERVAL_MS) || this.predicted(element, state, now)) return;
        state.lastTime = now;
      } else if (type === 'progress') {
        if (now - state.lastProgress < PROGRESS_INTERVAL_MS || ranges === state.lastBuffered) return;
        state.lastProgress = now;
      }
    }
    if (state) state.lastBuffered = ranges;
    const duration = Number.isFinite(element.duration) ? element.duration : -1;
    const time = element.currentTime || 0;
    if (state) state.sent = { time, at: now, rate: element.playbackRate, paused: element.paused, readyState: element.readyState };
    const hostTime = (this.window.Date ?? Date).now();
    const payload = [type === 'watch' ? 'timeupdate' : type, time, duration, element.paused ? 1 : 0, element.muted ? 1 : 0, element.volume, ranges,
      element.playbackRate, element.readyState, element.seeking ? 1 : 0, element.ended ? 1 : 0, element.error?.code ?? 0,
      state?.seekSequence ?? 0, hostTime, element.getAttribute('data-media-item') || 0, intent ?? state?.intent ?? ''].join('|');
    this.emit(element, 'media-report', payload);
    // The adaptive player reports its own tracks once loaded; a plain file reports its caption tracks (syncNativeTracks).
    if (type === 'loadedmetadata') this.syncNativeTracks(element);
  }

  dispose() {
    this.controls.dispose();
    this.abort.abort();
    for (const id of [...this.headless.keys()]) this.releaseHeadless(id);
    this.container?.remove?.();
    for (const element of this.elements()) {
      const state = this.applied.get(element);
      if (state?.stream) state.unframe?.(state.stream);
      if (state?.watch) (this.window.clearInterval ?? clearInterval).call(this.window, state.watch);
    }
    for (const element of this.adaptive) this.window.__detachAdaptiveMedia?.(element);
    this.adaptive.clear();
  }
}
