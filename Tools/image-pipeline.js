// SwiftUIWeb's browser image pipeline.  The helper keeps image policy in one
// small JavaScript boundary so Swift/WASM does not perform one bridge call per
// image.  It deliberately uses native HTMLImageElement/network caches rather
// than downloading image bytes into Swift.
(function (global) {
  "use strict";

  var MAX_DIMENSION_CACHE = 256;
  var MAX_CRITICAL_PRELOADS = 4;
  var state = {
    document: null,
    observer: null,
    observed: new Set(),
    images: new Set(),
    dimensions: new Map(),
    preloads: new Map(),
    timedSources: new Set(),
    loadHandler: null,
    errorHandler: null,
    metrics: {
      synchronizations: 0,
      discovered: 0,
      configured: 0,
      intersected: 0,
      decoded: 0,
      decodeDurationMs: 0,
      failed: 0,
      dimensionCacheHits: 0,
      dimensionCacheEntries: 0,
      criticalPreloads: 0,
      removedTargets: 0,
      resourceTransferBytes: 0,
      resourceDecodedBytes: 0,
      resourceDurationMs: 0
    }
  };

  function imageSource(image) {
    // currentSrc includes the browser's selected srcset candidate once
    // sizes/viewport information is available. Fall back to src before the
    // first selection so cache keys remain stable during initial mount.
    if (image.getAttribute("srcset")) {
      return image.currentSrc || image.getAttribute("src") || "";
    }
    return image.getAttribute("src") || image.currentSrc || "";
  }

  function isRemote(source) {
    return /^(https?:)?\/\//i.test(source);
  }

  function sameOrigin(source) {
    try {
      return new URL(source, global.location && global.location.href).origin ===
        (global.location && global.location.origin);
    } catch (_) {
      return false;
    }
  }

  function rememberDimensions(source, width, height) {
    if (!source || width <= 0 || height <= 0) return;
    if (state.dimensions.has(source)) state.dimensions.delete(source);
    state.dimensions.set(source, { width: width, height: height });
    while (state.dimensions.size > MAX_DIMENSION_CACHE) {
      state.dimensions.delete(state.dimensions.keys().next().value);
    }
    state.metrics.dimensionCacheEntries = state.dimensions.size;
  }

  function cachedDimensions(source) {
    var dimensions = state.dimensions.get(source);
    if (!dimensions) return null;
    // Refresh the LRU position without retaining a DOM node or decoded pixel
    // buffer in Swift. The browser remains the owner of decoded resources.
    state.dimensions.delete(source);
    state.dimensions.set(source, dimensions);
    state.metrics.dimensionCacheHits += 1;
    return dimensions;
  }

  function applyDimensions(image, dimensions) {
    if (!dimensions) return;
    // HTML width/height attributes establish an intrinsic ratio before the
    // next network response. CSS width/height still wins for SwiftUI frames.
    if (!image.getAttribute("width")) {
      var width = String(dimensions.width);
      image.setAttribute("width", width);
      image.__managedWidth = true;
      image.__managedWidthValue = width;
    }
    if (!image.getAttribute("height")) {
      var height = String(dimensions.height);
      image.setAttribute("height", height);
      image.__managedHeight = true;
      image.__managedHeightValue = height;
    }
    if (image.style && !image.style.aspectRatio) {
      image.style.aspectRatio = dimensions.width + " / " + dimensions.height;
      image.__managedAspectRatio = true;
    }
    // AsyncImage keeps its loader hidden while the placeholder is visible.
    // Give the semantic wrapper the same ratio so the placeholder reserves a
    // stable box before the success phase swaps in the real image.
    if (image.classList && image.classList.contains("async-image-loader")) {
      var wrapper = image.parentElement;
      if (wrapper && wrapper.classList && wrapper.classList.contains("async-image") &&
          wrapper.style && !wrapper.style.aspectRatio) {
        wrapper.style.aspectRatio = dimensions.width + " / " + dimensions.height;
        wrapper.setAttribute("data-image-ratio", "true");
      }
    }
  }

  function resetManagedDimensions(image, requestKey, selectedSource) {
    if (image.__requestKey === requestKey &&
        image.__selectedSource === selectedSource) return;
    if (image.__managedWidth &&
        image.getAttribute("width") === image.__managedWidthValue) {
      image.removeAttribute("width");
    }
    if (image.__managedHeight &&
        image.getAttribute("height") === image.__managedHeightValue) {
      image.removeAttribute("height");
    }
    if (image.__managedAspectRatio && image.style) {
      image.style.removeProperty("aspect-ratio");
    }
    if (image.classList && image.classList.contains("async-image-loader")) {
      var wrapper = image.parentElement;
      if (wrapper && wrapper.getAttribute("data-image-ratio") === "true") {
        if (wrapper.style) wrapper.style.removeProperty("aspect-ratio");
        wrapper.removeAttribute("data-image-ratio");
      }
    }
    image.__managedWidth = false;
    image.__managedHeight = false;
    image.__managedAspectRatio = false;
    image.__managedWidthValue = null;
    image.__managedHeightValue = null;
    image.removeAttribute("data-image-ready");
    image.removeAttribute("data-image-error");
    image.__requestKey = requestKey;
    image.__selectedSource = selectedSource;
  }

  function removePreload(source) {
    var link = state.preloads.get(source);
    if (!link) return;
    state.preloads.delete(source);
    if (link.parentNode) link.parentNode.removeChild(link);
  }

  function resourceTiming(source) {
    if (!global.performance || !global.performance.getEntriesByName) return;
    if (state.timedSources.has(source)) return;
    var entries = global.performance.getEntriesByName(source);
    if (!entries || !entries.length) return;
    var entry = entries[entries.length - 1];
    state.timedSources.add(source);
    state.metrics.resourceTransferBytes += Number(entry.transferSize || 0);
    state.metrics.resourceDecodedBytes += Number(entry.decodedBodySize || 0);
    state.metrics.resourceDurationMs += Number(entry.duration || 0);
  }

  function settle(image, succeeded) {
    var source = imageSource(image);
    if (!source) return;
    if (succeeded && image.naturalWidth > 0 && image.naturalHeight > 0) {
      var wasReady = image.getAttribute("data-image-ready") === "true";
      rememberDimensions(source, image.naturalWidth, image.naturalHeight);
      applyDimensions(image, cachedDimensions(source));
      if (!wasReady) {
        image.setAttribute("data-image-ready", "true");
        state.metrics.decoded += 1;
        resourceTiming(source);
      }
      removePreload(source);
    } else if (!succeeded) {
      var wasError = image.getAttribute("data-image-error") === "true";
      if (!wasError) {
        image.setAttribute("data-image-error", "true");
        state.metrics.failed += 1;
      }
      removePreload(source);
    }
  }

  function decode(image) {
    if (image.__decodeRequested || typeof image.decode !== "function") return;
    image.__decodeRequested = true;
    try {
      var started = global.performance && global.performance.now ? global.performance.now() : 0;
      var promise = image.decode();
      if (promise && typeof promise.then === "function") {
        promise.then(function () {
          var ended = global.performance && global.performance.now ? global.performance.now() : started;
          state.metrics.decodeDurationMs += Math.max(0, ended - started);
        }).catch(function () {});
      }
    } catch (_) {
      // A decode race with removal is normal for virtualized rows. The native
      // load/error event remains authoritative for SwiftUI AsyncImage.
    }
  }

  function configureResponsiveSize(image, measuredWidth, correctFallback) {
    if (!image.getAttribute("srcset")) return;
    var width = Number(measuredWidth || 0);
    var existing = image.getAttribute("sizes");
    if (existing && !(correctFallback && existing === "100vw" && width > 0)) return;
    image.setAttribute("sizes", width > 0 ? width + "px" : "100vw");
  }

  function configureImage(image, initial, critical, measuredWidth, correctFallback) {
    var source = imageSource(image);
    if (!source) return;
    resetManagedDimensions(
      image,
      image.getAttribute("src") || image.getAttribute("srcset") || source,
      source
    );
    if (!image.getAttribute("decoding")) image.setAttribute("decoding", "async");
    configureResponsiveSize(image, measuredWidth, correctFallback);

    var asyncLoader = image.classList &&
      image.classList.contains("async-image-loader");
    if (asyncLoader && image.getAttribute("loading") !== "eager") {
      // AsyncImage owns its visible phase through the native load/error event;
      // a hidden loader must still begin promptly once its logical cell mounts.
      image.setAttribute("loading", "eager");
    } else if (isRemote(source) && !image.getAttribute("loading")) {
      image.setAttribute("loading", "lazy");
    }
    if (critical) {
      if (image.getAttribute("loading") !== "eager") image.setAttribute("loading", "eager");
      if (image.getAttribute("fetchpriority") !== "high") image.setAttribute("fetchpriority", "high");
    } else if (!image.getAttribute("fetchpriority")) {
      image.setAttribute("fetchpriority", isRemote(source) ? "low" : "auto");
    }

    var dimensions = cachedDimensions(source);
    if (dimensions) applyDimensions(image, dimensions);
    // `complete` may be true for a lazy image whose request has not started
    // (and for an element with no successful resource). Only infer success
    // here; the capture error handler remains authoritative for failures.
    if (image.complete && image.naturalWidth > 0) settle(image, true);
    // Calling decode() on an unloaded lazy image can eagerly start its
    // request. Defer remote decoding until the image is visible/critical (or
    // until AsyncImage's mounted loader explicitly owns the request).
    if (image.complete || critical || asyncLoader || !isRemote(source)) decode(image);
    state.metrics.configured += 1;

    // A small bounded preload set is useful for above-the-fold feed heroes.
    // Restricting this to same-origin URLs avoids duplicate CORS requests;
    // ordinary images still use the browser's HTTP cache and priority queue.
    if (initial && critical && isRemote(source) && sameOrigin(source) &&
        state.preloads.size < MAX_CRITICAL_PRELOADS && !state.preloads.has(source)) {
      var head = state.document && state.document.head;
      if (head) {
        var link = state.document.createElement("link");
        link.rel = "preload";
        link.as = "image";
        link.href = source;
        if (image.getAttribute("srcset")) {
          link.setAttribute("imagesrcset", image.getAttribute("srcset"));
          link.setAttribute("imagesizes", image.getAttribute("sizes") || "100vw");
        }
        link.setAttribute("fetchpriority", "high");
        link.setAttribute("data-image-preload", "true");
        head.appendChild(link);
        state.preloads.set(source, link);
        state.metrics.criticalPreloads += 1;
      }
    }
  }

  function insideViewport(entry) {
    var rect = entry.boundingClientRect;
    var root = entry.rootBounds;
    if (!rect) return false;
    if (!root) return rect.top < (global.innerHeight || 0) && rect.bottom > 0;
    return rect.top < root.bottom && rect.bottom > root.top &&
      rect.left < root.right && rect.right > root.left;
  }

  function handleIntersection(entries) {
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i];
      var image = entry.target;
      if (!state.images.has(image)) continue;
      state.metrics.intersected += 1;
      var visible = entry.isIntersecting && insideViewport(entry);
      if (visible) {
        if (image.getAttribute("fetchpriority") !== "high") {
          image.setAttribute("fetchpriority", "high");
        }
        // Once an image is genuinely near the viewport, let the native loader
        // start it even if the first render marked it lazy.
        if (image.getAttribute("loading") !== "eager") {
          image.setAttribute("loading", "eager");
        }
        configureImage(
          image,
          false,
          true,
          entry.boundingClientRect && entry.boundingClientRect.width,
          true
        );
      } else if (!image.getAttribute("fetchpriority")) {
        image.setAttribute("fetchpriority", "low");
      }
    }
  }

  function detachDocument() {
    if (!state.document) return;
    if (state.loadHandler) state.document.removeEventListener("load", state.loadHandler, true);
    if (state.errorHandler) state.document.removeEventListener("error", state.errorHandler, true);
    if (state.observer) state.observer.disconnect();
    state.observer = null;
    state.observed.clear();
    state.images.clear();
    state.document = null;
    state.loadHandler = null;
    state.errorHandler = null;
  }

  function synchronize(document, initial) {
    if (!document) return state.metrics;
    state.metrics.synchronizations += 1;
    if (state.document !== document) {
      detachDocument();
      state.document = document;
      state.loadHandler = function (event) {
        if (event && event.target && event.target.tagName === "IMG") settle(event.target, true);
      };
      state.errorHandler = function (event) {
        if (event && event.target && event.target.tagName === "IMG") settle(event.target, false);
      };
      document.addEventListener("load", state.loadHandler, true);
      document.addEventListener("error", state.errorHandler, true);
      if (typeof global.IntersectionObserver === "function") {
        state.observer = new global.IntersectionObserver(handleIntersection, {
          root: null,
          rootMargin: "900px 0px",
          threshold: [0, 0.01, 0.5, 1]
        });
      }
    }

    var nodes = document.querySelectorAll("img.picture-view, img.async-image-loader");
    var current = new Set();
    var currentSources = new Set();
    var measuredWidths = new Map();
    var criticalImages = new Set();
    var discovered = 0;
    // Read all geometry before writing loading/priority/size attributes. This
    // keeps responsive sizing and above-the-fold classification from creating
    // a read-after-write layout cycle for every image in a feed.
    for (var readIndex = 0; readIndex < nodes.length; readIndex++) {
      var candidate = nodes[readIndex];
      if (candidate.getAttribute("srcset") && !candidate.getAttribute("sizes")) {
        var measuredWidth = 0;
        try { measuredWidth = Math.round(candidate.getBoundingClientRect().width); } catch (_) {}
        measuredWidths.set(candidate, measuredWidth);
      }
      if (initial && readIndex < 8) {
        try {
          var rect = candidate.getBoundingClientRect();
          if (rect.top < (global.innerHeight || 0) && rect.bottom > 0) {
            criticalImages.add(candidate);
          }
        } catch (_) {}
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      var image = nodes[i];
      current.add(image);
      var source = imageSource(image);
      if (source) currentSources.add(source);
      discovered += 1;
      configureImage(image, initial, criticalImages.has(image), measuredWidths.get(image));
      if (state.observer && !state.observed.has(image)) {
        state.observed.add(image);
        state.observer.observe(image);
      }
    }
    state.metrics.discovered += discovered;
    state.images = current;
    state.observed.forEach(function (image) {
      if (!current.has(image)) {
        if (state.observer) state.observer.unobserve(image);
        state.observed.delete(image);
        state.metrics.removedTargets += 1;
      }
    });
    // A virtualized image may leave the document before its bounded critical
    // preload resolves. Drop that hint as soon as no live node needs it; the
    // browser then remains free to cancel/evict the request under its normal
    // cache policy.
    state.preloads.forEach(function (link, source) {
      if (!currentSources.has(source)) removePreload(source);
    });
    return state.metrics;
  }

  global.__configureImages = synchronize;
  global.__imageMetrics = state.metrics;
  global.__disposeImages = function () {
    detachDocument();
    state.preloads.forEach(function (link) { if (link.parentNode) link.parentNode.removeChild(link); });
    state.preloads.clear();
  };
})(globalThis);
