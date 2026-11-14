// Private, optional adaptive-media facade for SwiftUIWebAVFoundation.
//
// Native HTMLMediaElement playback never touches this file.  The Swift
// wrapper calls the hook only for HLS/DASH (or an explicitly adaptive item),
// at which point the Shaka module is imported once and attached to the existing
// media element.  No Shaka symbols cross the Swift/WebMount boundary.
(function installSwiftUIWebAdaptiveMedia(global) {
  const TRACKS_CHANGED = "swiftuiwebtrackschange";
  let shakaPromise;
  // Where the helper is: next to this script when it loads as one (`currentScript`), else at the bundle root the
  // document's `<base>` names. The loader imports this file as a module, where `currentScript` is null, and the page
  // address of a nested route (/watch/item) is not the bundle root. Markup cannot add a `<base>` (it is refused).
  const scriptURL = (global.document && global.document.currentScript && global.document.currentScript.src)
    || (global.document && global.document.baseURI)
    || (global.location && global.location.href);

  global.__attachAdaptiveMedia = function attachAdaptiveMedia(element, source) {
    if (!shakaPromise) {
      // The same-origin helper the bundle ships next to this script. The URL is computed at run time so
      // the bundler leaves the import to the browser instead of inlining Shaka into this helper.
      shakaPromise = import(new URL("shaka-loader.js", scriptURL).href).then((module) => module.default || global.shaka, (error) => {
        // A failed import is not cached: a later call tries again.
        shakaPromise = undefined;
        throw error;
      });
    }

    const token = (element.__shakaLoadToken || 0) + 1;
    element.__shakaLoadToken = token;
    // Resolves once Shaka has loaded the source, so the host can start playback after it.
    return shakaPromise.then((shaka) => {
      if (element.__shakaLoadToken !== token) return;
      if (!shaka || !shaka.Player) throw new Error("Shaka Player failed to load");
      if (!element.__shakaPlayer) {
        // A player is attached to its element (Shaka 5 has no `new shaka.Player(element)`).
        const player = new shaka.Player();
        element.__shakaPlayer = player;
        element.__shakaAttached = player.attach(element);
        // Tell the media host whenever the tracks, or the ones in use, change.
        const changed = () => element.dispatchEvent(new CustomEvent(TRACKS_CHANGED, { bubbles: true }));
        for (const type of ["trackschanged", "variantchanged", "adaptation", "audiotrackschanged", "audiotrackchanged", "textchanged"]) {
          player.addEventListener(type, changed);
        }
      }
      const player = element.__shakaPlayer;
      return Promise.resolve(element.__shakaAttached).then(() => {
        if (element.__shakaLoadToken !== token || element.__shakaPlayer !== player) return;
        return player.load(source);
      }).then(() => {
        element.dispatchEvent(new CustomEvent(TRACKS_CHANGED, { bubbles: true }));
      });
    }).catch((error) => {
      element.dispatchEvent(new CustomEvent("error", { detail: error }));
    });
  };

  const clean = (value) => String(value ?? "").replace(/[\t\n\r]/g, " ");

  // One record per line, tab-separated (MediaSelection.swift): renditions `v width height bandwidth`,
  // audio `a language/role language label active`, subtitles `t id language label shown`.
  global.__adaptiveMediaTracks = function adaptiveMediaTracks(element) {
    const player = element && element.__shakaPlayer;
    if (!player) return "";
    const lines = [];
    const variants = player.getVariantTracks();
    const seen = new Set();
    for (const variant of variants) {
      const key = variant.width + "x" + variant.height + "@" + variant.bandwidth;
      if (!variant.height || seen.has(key)) continue;
      seen.add(key);
      lines.push(["v", variant.width || 0, variant.height, variant.bandwidth || 0].join("\t"));
    }
    // Shaka lists an audio track per codec and channel layout; Swift chooses by language and role.
    const audio = new Map();
    for (const track of player.getAudioTracks()) {
      // The language and role are escaped, so a "/" in either cannot make two options share one key.
      const key = encodeURIComponent(track.language) + "/" + encodeURIComponent((track.roles || [])[0] || "");
      const known = audio.get(key);
      if (!known) audio.set(key, { language: track.language, label: track.label, active: track.active });
      else known.active = known.active || track.active;
    }
    for (const [key, { language, label, active }] of audio) {
      lines.push(["a", clean(key), clean(language), clean(label), active ? 1 : 0].join("\t"));
    }
    // Shaka 5 shows the selected text track and none when no track is selected.
    for (const track of player.getTextTracks()) {
      lines.push(["t", clean(track.id), clean(track.language), clean(track.label), track.active ? 1 : 0].join("\t"));
    }
    return lines.join("\n");
  };

  // Applies what Swift chose: rendition limits as ABR restrictions (adaptation stays on, below the
  // limit), an audio language and role, a subtitle track or none.
  global.__selectAdaptiveMedia = function selectAdaptiveMedia(element, wish) {
    const player = element && element.__shakaPlayer;
    if (!player) return;
    player.configure({ abr: { restrictions: {
      maxWidth: wish.width > 0 ? wish.width : Infinity,
      maxHeight: wish.height > 0 ? wish.height : Infinity,
      maxBandwidth: wish.peakBitRate > 0 ? wish.peakBitRate : Infinity,
    } } });
    if (wish.audio) {
      const [language, role] = wish.audio.split("/").map((part) => decodeURIComponent(part || ""));
      const tracks = player.getAudioTracks().filter((track) => track.language === language && (!role || (track.roles || []).includes(role)));
      if (tracks.length && !tracks.some((track) => track.active)) player.selectAudioTrack(tracks[0]);
    }
    if (wish.text === "off") {
      player.selectTextTrack(null);
    } else if (wish.text) {
      const track = player.getTextTracks().find((candidate) => String(candidate.id) === wish.text);
      if (track) player.selectTextTrack(track);
    }
    element.dispatchEvent(new CustomEvent(TRACKS_CHANGED, { bubbles: true }));
  };

  global.__detachAdaptiveMedia = function detachAdaptiveMedia(element) {
    element.__shakaLoadToken = (element.__shakaLoadToken || 0) + 1;
    const player = element && element.__shakaPlayer;
    if (!player) return;
    element.__shakaPlayer = null;
    element.__shakaAttached = null;
    try {
      const result = player.destroy();
      if (result && typeof result.catch === "function") result.catch(() => {});
    } catch (_) {
      // Disposal is best effort during DOM teardown.
    }
  };
}(globalThis));
