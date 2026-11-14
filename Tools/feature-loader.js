// SwiftUIWeb's optional feature loader.
//
// This file is deliberately dependency-free and small.  It is not a bundler
// runtime: an opt-in Web workspace with any compatible bundler produces self-contained
// ESM chunks, and this loader only coordinates their activation.  Nothing is
// fetched or evaluated during bootstrap.  A feature is loaded only after a
// Swift wrapper asks for it, while route/viewport prefetch uses low-priority
// browser hints and does not execute the module.
(function (global) {
  "use strict";

  var modules = new Map();
  var styles = new Map();
  var manifestPromise = null;
  var metrics = {
    loadRequests: 0,
    loadHits: 0,
    loadFailures: 0,
    cssRequests: 0,
    cssHits: 0,
    prefetchRequests: 0,
    prefetchLinks: 0,
    manifestRequests: 0,
    manifestFailures: 0,
    totalLoadTimeMs: 0
  };

  function now() {
    return global.performance && typeof global.performance.now === "function"
      ? global.performance.now()
      : Date.now();
  }

  function absoluteURL(value) {
    try {
      return new URL(value, global.document && global.document.baseURI || global.location && global.location.href || undefined).href;
    } catch (_) {
      return String(value || "");
    }
  }

  // Feature code runs with the page's privileges, so a manifest may only name
  // modules, styles and workers served from the page's own origin.
  function isSameOrigin(value) {
    // An opaque origin ("null": a file: page, a sandboxed frame) has no same-origin module: nothing is loaded rather
    // than any URL.
    var origin = global.location && global.location.origin;
    if (!origin || origin === "null") return false;
    try {
      return new URL(absoluteURL(value)).origin === origin;
    } catch (_) {
      return false;
    }
  }

  function asArray(value) {
    if (!value) return [];
    return Array.isArray(value) ? value.filter(Boolean) : [value];
  }

  function prefetchAllowed() {
    // Keep the direct JavaScript loader aligned with the Swift coordinator's
    // opt-out. Hosts and tests can disable all speculative work without
    // changing application APIs; in particular, do not even fetch the
    // manifest when the document explicitly opts out.
    if (global.document) {
      var root = global.document.documentElement;
      var body = global.document.body;
      if ((root && root.getAttribute("data-route-prefetch") === "disabled") ||
          (body && body.getAttribute("data-route-prefetch") === "disabled")) {
        return false;
      }
    }
    if (!global.document || !global.document.visibilityState || global.document.visibilityState === "hidden") return false;
    var navigator = global.navigator || {};
    if (navigator.onLine === false) return false;
    var connection = navigator.connection;
    if (connection && (connection.saveData === true || connection.effectiveType === "slow-2g" || connection.effectiveType === "2g")) return false;
    return true;
  }

  function descriptor(id, value) {
    if (typeof value === "string") return { id: id, entry: value, css: [], workers: [] };
    value = value || {};
    return {
      id: value.id || id,
      entry: value.entry || value.url || "",
      css: asArray(value.css || value.styles),
      workers: asArray(value.workers)
    };
  }

  function findHint(url) {
    var absolute = absoluteURL(url);
    if (!global.document || !global.document.head) return null;
    // The Swift prefetch coordinator may have already emitted a hint for the
    // same URL (it uses its own marker so it can account for planner budget).
    // Search all low-priority links to avoid duplicate requests across the two
    // declarative registration paths.
    var links = global.document.head.querySelectorAll("link[href]");
    for (var i = 0; i < links.length; i += 1) {
      if (links[i].href === absolute &&
          (links[i].rel === "modulepreload" || links[i].rel === "prefetch" || links[i].rel === "preload")) return links[i];
    }
    return null;
  }

  function addHint(url, kind) {
    if (!url || !global.document || !global.document.head) return;
    if (findHint(url)) return;
    var link = global.document.createElement("link");
    link.setAttribute("data-feature-hint", kind || "resource");
    link.href = absoluteURL(url);
    if (kind === "module") {
      link.rel = "modulepreload";
    } else if (kind === "css") {
      // A stylesheet preload is cache-compatible with the activation path and
      // can be promoted without issuing a second request. `prefetch` is not
      // reliably reused when its rel is changed to stylesheet (notably on
      // Chromium with no-store development servers).
      link.rel = "preload";
      link.as = "style";
    } else {
      link.rel = "prefetch";
      if (kind === "worker") link.as = "worker";
    }
    link.setAttribute("fetchpriority", "low");
    global.document.head.appendChild(link);
    metrics.prefetchLinks += 1;
  }

  function loadCSS(url) {
    var key = absoluteURL(url);
    if (!key) return Promise.resolve();
    if (styles.has(key)) {
      metrics.cssHits += 1;
      return styles.get(key);
    }
    metrics.cssRequests += 1;
    var promise = new Promise(function (resolve, reject) {
      if (!global.document || !global.document.head) {
        resolve();
        return;
      }
      var existing = global.document.head.querySelectorAll("link[rel='stylesheet']");
      for (var i = 0; i < existing.length; i += 1) {
        if (existing[i].href === key) {
          if (existing[i].sheet) {
            resolve();
          } else {
            existing[i].addEventListener("load", function () { resolve(); }, { once: true });
            existing[i].addEventListener("error", function () { reject(new Error("Unable to load feature stylesheet: " + key)); }, { once: true });
          }
          return;
        }
      }
      // Promote a prior low-priority feature hint instead of inserting a
      // second stylesheet request. The browser cache normally deduplicates
      // either way, but promotion avoids an extra DOM node and keeps the
      // activation path deterministic.
      var hints = global.document.head.querySelectorAll("link[rel='prefetch'], link[rel='preload']");
      for (var hintIndex = 0; hintIndex < hints.length; hintIndex += 1) {
        if (hints[hintIndex].href === key && hints[hintIndex].as === "style") {
          var promoted = hints[hintIndex];
          promoted.rel = "stylesheet";
          promoted.setAttribute("data-feature-css", "true");
          promoted.addEventListener("load", function () { resolve(); }, { once: true });
          promoted.addEventListener("error", function () { reject(new Error("Unable to load feature stylesheet: " + key)); }, { once: true });
          return;
        }
      }
      var link = global.document.createElement("link");
      link.rel = "stylesheet";
      link.href = key;
      link.setAttribute("data-feature-css", "true");
      link.onload = function () { resolve(); };
      link.onerror = function () { reject(new Error("Unable to load feature stylesheet: " + key)); };
      global.document.head.appendChild(link);
    });
    styles.set(key, promise);
    return promise;
  }

  function prefetchFeature(value) {
    if (!prefetchAllowed()) return;
    var feature = descriptor(value && value.id || "feature", value);
    if (!feature.entry || !isSameOrigin(feature.entry)) return;
    metrics.prefetchRequests += 1;
    addHint(feature.entry, "module");
    feature.css.filter(isSameOrigin).forEach(function (url) { addHint(url, "css"); });
    feature.workers.filter(isSameOrigin).forEach(function (url) { addHint(url, "worker"); });
  }

  function loadFeature(id, entry, css, workers) {
    var featureID = String(id || entry || "feature");
    if (modules.has(featureID)) {
      metrics.loadHits += 1;
      return modules.get(featureID);
    }
    metrics.loadRequests += 1;
    var started = now();
    var cssURLs = asArray(css).filter(isSameOrigin);
    // Worker URLs are metadata for the provider.  Prefetching them is useful,
    // but constructing a Worker belongs to the feature wrapper so ownership
    // and termination stay attached to its WebMount lifecycle.
    asArray(workers).filter(isSameOrigin).forEach(function (url) { addHint(url, "worker"); });
    var promise = Promise.all(cssURLs.map(loadCSS)).then(function () {
      if (!entry) throw new Error("Feature '" + featureID + "' has no ESM entry");
      if (!isSameOrigin(entry)) throw new Error("Feature '" + featureID + "' entry is not same-origin");
      return import(entry);
    }).then(function (module) {
      metrics.totalLoadTimeMs += now() - started;
      return module;
    }).catch(function (error) {
      metrics.loadFailures += 1;
      // A failed dynamic import must be retryable after a transient network
      // error.  Keep successful modules cached forever, but remove failures.
      modules.delete(featureID);
      throw error;
    });
    modules.set(featureID, promise);
    return promise;
  }

  function readManifest() {
    if (manifestPromise) return manifestPromise;
    metrics.manifestRequests += 1;
    if (typeof global.fetch !== "function") return Promise.resolve({ version: 1, features: {}, routes: {} });
    manifestPromise = global.fetch("./features-manifest.json", {
      credentials: "same-origin",
      cache: "force-cache"
    }).then(function (response) {
      if (!response.ok) throw new Error("Feature manifest returned HTTP " + response.status);
      return response.json();
    }).catch(function (error) {
      metrics.manifestFailures += 1;
      manifestPromise = null;
      // A missing manifest is a valid configuration for applications that use
      // wrapper-owned manifests.  Do not turn a navigation hint into an error.
      return { version: 1, features: {}, routes: {}, error: String(error) };
    });
    return manifestPromise;
  }

  function normalizeRoute(route) {
    var value = String(route || "").split("#")[0];
    while (value.length > 1 && value[value.length - 1] === "/") value = value.slice(0, -1);
    return value || "/";
  }

  function featureFromManifest(manifest, id) {
    var features = manifest && manifest.features || {};
    return features[id] || null;
  }

  global.__loadFeature = loadFeature;
  global.__prefetchFeature = prefetchFeature;
  global.__featureMetrics = metrics;
  global.__featureManifest = readManifest;
  global.__prefetchFeatureRoute = function (route) {
    if (!prefetchAllowed()) return Promise.resolve(null);
    return readManifest().then(function (manifest) {
      var routes = manifest && manifest.routes || {};
      var value = routes[normalizeRoute(route)] || routes["*"];
      if (value) prefetchFeature(value);
      return value || null;
    });
  };
  global.__prefetchFeatureFromManifest = function (id) {
    if (!prefetchAllowed()) return Promise.resolve(null);
    return readManifest().then(function (manifest) {
      var value = featureFromManifest(manifest, id);
      if (value) prefetchFeature(value);
      return value || null;
    });
  };
  global.__loadFeatureFromManifest = function (id) {
    return readManifest().then(function (manifest) {
      var value = featureFromManifest(manifest, id);
      var feature = descriptor(id, value);
      if (!feature.entry) throw new Error("Feature '" + id + "' is not in the manifest");
      return loadFeature(feature.id, feature.entry, feature.css, feature.workers);
    });
  };
  // Built-in adaptive media is kept as an ordinary feature entry so the
  // initial route does not download its helper.  The helper installs its
  // private attach/detach hooks when evaluated, then immediately handles the
  // pending media element; subsequent mounts reuse the cached module.
  global.__loadAdaptiveMedia = function (element, source) {
    return loadFeature(
      "feature-adaptive-media",
      "./avfoundation.js",
      [],
      []
    ).then(function () {
      if (typeof global.__attachAdaptiveMedia !== "function") {
        throw new Error("Adaptive media feature did not install its attach hook");
      }
      return global.__attachAdaptiveMedia(element, source);
    });
  };
  global.__loadImagePipeline = function (document, initial) {
    return loadFeature(
      "feature-image-pipeline",
      "./image-pipeline.js",
      [],
      []
    ).then(function () {
      if (typeof global.__configureImages !== "function") {
        throw new Error("Image pipeline feature did not install its configure hook");
      }
      return global.__configureImages(document, initial);
    });
  };
  global.__cancelAdaptiveMedia = function (element) {
    if (!element) return;
    element.__shakaLoadToken = (element.__shakaLoadToken || 0) + 1;
  };
})(typeof globalThis !== "undefined" ? globalThis : window);
