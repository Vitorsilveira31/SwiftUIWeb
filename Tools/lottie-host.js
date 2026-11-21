// Lottie playback for SwiftUIWebMotion's `MotionView`, on the main thread.
//
// Swift renders what a `MotionView` wants as attributes on its `div.motion-view` (Sources/SwiftUIWebMotion/MotionView.swift):
//   data-motion-animation     the Lottie JSON text
//   data-motion-mode          "play" | "pause"
//   data-motion-loop          "once" | "loop" | "autoreverse" | "repeat:<n>" | "repeat-backwards:<n>"
//   data-motion-speed         the speed multiplier
//   data-motion-from, data-motion-to         the progress range a playback covers (0…1)
//   data-motion-progress, data-motion-frame  where a paused animation stands
//   data-motion-content-mode  "fit" | "fill"
// After a commit that touches one, this host makes its lottie-web player match, and reports the end of a playback as a
// `motion-complete` named event: "1" when it ran to its end, "0" when a new playback or a pause cut it short (lottie-ios's
// `animationDidFinish`). An infinite loop never ends by itself.
//
// lottie-web is not in the page's bundle: `lottie-loader.js`, served next to it, is imported the first time a
// `MotionView` is on the page, so a page without one downloads none of it. The element's content is the SVG lottie-web
// draws, which the DOM patcher leaves to this host (`data-host-managed="*children"`).
// Everything goes through the publication, so it works the same whether Swift runs on this thread or in the worker.

const SELECTOR = '.motion-view[data-motion-animation]';
const COMPLETE = 'motion-complete';

let lottiePromise;
/** lottie-web, imported once from the bundle root the document's `<base>` names (a nested route is not the root). */
export function loadLottie(host = globalThis.window) {
  if (!lottiePromise) {
    const base = host?.document?.baseURI || host?.location?.href;
    // Computed at run time so that the bundler leaves the import to the browser instead of inlining lottie-web here.
    lottiePromise = import(new URL('lottie-loader.js', base).href).then((module) => module.default, (error) => {
      // A failed import is not cached: the next commit that shows an animation tries again.
      lottiePromise = undefined;
      throw error;
    });
  }
  return lottiePromise;
}

/** `{kind, count}` from `data-motion-loop`; anything else loops forever, SkipMotion's default. */
export function parseLoop(value) {
  if (value === 'once' || value === 'autoreverse' || value === 'loop') return { kind: value, count: 0 };
  const counted = /^(repeat|repeat-backwards):(\d+)$/.exec(value || '');
  if (counted) return { kind: counted[1], count: Number(counted[2]) };
  return { kind: 'loop', count: 0 };
}

function number(element, name) {
  const value = element.getAttribute(name);
  if (value === null || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/** What the element asks for, read from its attributes. */
export function readConfig(element) {
  const speed = number(element, 'data-motion-speed');
  return {
    mode: element.getAttribute('data-motion-mode') === 'pause' ? 'pause' : 'play',
    loop: parseLoop(element.getAttribute('data-motion-loop')),
    speed: speed === null ? 1 : speed,
    from: number(element, 'data-motion-from'),
    to: number(element, 'data-motion-to'),
    progress: number(element, 'data-motion-progress'),
    frame: number(element, 'data-motion-frame'),
    fill: element.getAttribute('data-motion-content-mode') === 'fill',
  };
}

const clamp = (value) => Math.min(1, Math.max(0, value));

export class LottieHost {
  constructor(root, { dispatchNamed, window: host = globalThis.window, load = loadLottie }) {
    this.root = root;
    this.window = host;
    this.dispatchNamed = dispatchNamed;
    this.load = load;
    // element -> its player: { text, animation, loading, token, config, applied, playback, running, plays, direction }
    this.players = new Map();
  }

  // Only a commit that adds, removes or changes a `MotionView` can change a player; between commits lottie-web runs alone.
  needsSync(changes) {
    return changes.touches('.motion-view');
  }

  sync() {
    const elements = new Set(this.root.querySelectorAll?.(SELECTOR) ?? []);
    for (const [element, player] of this.players) {
      if (!elements.has(element) || !element.isConnected) this.release(element, player);
    }
    for (const element of elements) this.reconcile(element);
  }

  dispose() {
    for (const [element, player] of this.players) this.release(element, player);
  }

  reconcile(element) {
    let player = this.players.get(element);
    if (!player) {
      player = { text: null, animation: null, loading: false, token: 0, config: null, applied: null, playback: null, running: false, plays: 0, direction: 1 };
      this.players.set(element, player);
    }
    const text = element.getAttribute('data-motion-animation');
    if (player.text !== text) this.start(element, player, text);
    else if (player.animation) this.apply(element, player);
  }

  /** Builds the player for a new animation text, once lottie-web is here; a newer text or a release drops a stale one. */
  start(element, player, text) {
    this.destroy(player);
    player.text = text;
    player.loading = true;
    const token = ++player.token;
    this.load(this.window).then((lottie) => {
      if (player.token !== token || this.players.get(element) !== player) return;
      player.loading = false;
      let data;
      try { data = JSON.parse(text); } catch { return; }
      const animation = lottie.loadAnimation({
        container: element, renderer: 'svg', loop: false, autoplay: false, animationData: data,
        rendererSettings: { preserveAspectRatio: 'xMidYMid meet' },
      });
      player.animation = animation;
      player.firstFrame = Number(data.ip) || 0;
      player.lastFrame = Number(data.op) || 0;
      animation.addEventListener('complete', () => { if (player.animation === animation) this.completed(element, player); });
      const ready = () => { if (player.animation === animation) { player.applied = null; this.apply(element, player); } };
      // An animation with images is ready once they load; one without is ready at once.
      if (animation.isLoaded) ready(); else animation.addEventListener('DOMLoaded', ready);
    }, (error) => {
      if (player.token !== token) return;
      player.loading = false;
      this.window?.console?.warn?.('[SwiftUIWeb] lottie-web did not load; the MotionView stays empty', error);
    });
  }

  apply(element, player) {
    const config = readConfig(element);
    const key = JSON.stringify(config);
    if (key === player.applied) return;
    player.applied = key;
    player.config = config;
    const animation = player.animation;
    element.querySelector('svg')?.setAttribute('preserveAspectRatio', config.fill ? 'xMidYMid slice' : 'xMidYMid meet');
    animation.setSpeed(config.speed);
    const span = Math.max(0, player.lastFrame - player.firstFrame);
    if (config.mode === 'pause') {
      this.interrupt(element, player);
      player.playback = null;
      // The last frame is `op - 1`: lottie-web wraps a frame at `op` back to the first.
      const last = Math.max(0, span - 0.001);
      if (config.progress !== null) animation.goToAndStop(Math.min(last, clamp(config.progress) * span), true);
      else if (config.frame !== null) animation.goToAndStop(Math.min(last, Math.max(0, config.frame - player.firstFrame)), true);
      else animation.pause();
      return;
    }
    // A change of speed or content mode leaves the playback as it is (running, or finished); a new loop mode or range,
    // or playing after a pause, starts a new one.
    const playback = `${config.loop.kind}:${config.loop.count}|${config.from}|${config.to}`;
    if (playback === player.playback) return;
    this.interrupt(element, player);
    player.playback = playback;
    player.running = true;
    player.plays = 0;
    player.direction = 1;
    animation.setLoop(config.loop.kind === 'loop');
    animation.setDirection(1);
    if (config.from !== null && config.to !== null) {
      animation.playSegments([player.firstFrame + clamp(config.from) * span, player.firstFrame + clamp(config.to) * span], true);
    } else {
      // Back to the whole animation, from its start (`playSegments` left a range behind), else from where it stands.
      if (player.segmented) animation.resetSegments(true);
      animation.play();
    }
    player.segmented = config.from !== null && config.to !== null;
  }

  /** lottie-web stopped at an end of the playback (its `loop` is off for every mode but `.loop`). */
  completed(element, player) {
    const config = player.config;
    if (!config || config.mode !== 'play' || !player.running) return;
    const animation = player.animation;
    player.plays += 1;
    const reverse = () => {
      player.direction = -player.direction;
      animation.setDirection(player.direction);
      animation.play();
    };
    switch (config.loop.kind) {
      case 'autoreverse':
        reverse();
        return;
      case 'repeat':
        if (player.plays < Math.max(1, config.loop.count)) { animation.goToAndPlay(0, true); return; }
        break;
      case 'repeat-backwards':
        // Each repetition is a pass forward and one back.
        if (player.plays < 2 * Math.max(1, config.loop.count)) { reverse(); return; }
        break;
      default:
        break;
    }
    player.running = false;
    this.dispatchNamed?.(element, COMPLETE, '1');
  }

  /** A playback still running that a pause or a new playback ends: reported as not finished. */
  interrupt(element, player) {
    if (!player.running) return;
    player.running = false;
    if (element.isConnected) this.dispatchNamed?.(element, COMPLETE, '0');
  }

  destroy(player) {
    player.token += 1;
    player.loading = false;
    player.running = false;
    player.playback = null;
    player.applied = null;
    player.segmented = false;
    if (player.animation) {
      try { player.animation.destroy(); } catch { /* an animation whose container is gone */ }
      player.animation = null;
    }
  }

  release(element, player) {
    this.destroy(player);
    this.players.delete(element);
  }
}
