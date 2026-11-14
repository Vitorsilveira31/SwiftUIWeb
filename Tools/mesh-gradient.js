// SwiftUIWeb's private MeshGradient rasterizer.
//
// Canvas 2D has no native mesh primitive. A single helper call therefore
// rasterizes a bilinear (or smoothstep) grid into ImageData, keeping all
// interpolation and animation work in JavaScript instead of crossing the
// Swift/WASM boundary for individual pixels. The helper is included in a
// release only when MeshGradient is reachable from the application.
(function (global) {
  "use strict";

  var colorCanvas = null;
  var colorContext = null;
  var colorCache = new Map();
  var generations = new WeakMap();

  function parser() {
    if (colorContext) return colorContext;
    colorCanvas = document.createElement("canvas");
    colorCanvas.width = 1;
    colorCanvas.height = 1;
    colorContext = colorCanvas.getContext("2d", { willReadFrequently: true });
    return colorContext;
  }

  function color(value) {
    value = value || "transparent";
    var resolvedValue = value;
    if (resolvedValue.indexOf("var(") >= 0 && global.getComputedStyle && global.document && global.document.documentElement) {
      var variables = global.getComputedStyle(global.document.documentElement);
      resolvedValue = resolvedValue.replace(/var\(\s*(--[-_a-zA-Z0-9]+)(?:\s*,\s*([^)]*))?\s*\)/g, function (whole, name, fallback) {
        var replacement = variables.getPropertyValue(name).trim();
        return replacement || fallback || whole;
      });
    }
    var cached = colorCache.get(resolvedValue);
    if (cached) return cached;
    var context = parser();
    var result = [0, 0, 0, 0];
    if (context) {
      context.clearRect(0, 0, 1, 1);
      // Reset before assigning so an invalid/custom-property color cannot
      // accidentally reuse the previous parsed fillStyle.
      context.fillStyle = "rgba(0,0,0,0)";
      context.fillStyle = resolvedValue;
      context.fillRect(0, 0, 1, 1);
      var data = context.getImageData(0, 0, 1, 1).data;
      result = [data[0], data[1], data[2], data[3]];
    }
    // Values come from the app; bound the cache so distinct colors cannot grow it forever.
    if (colorCache.size >= 1024) colorCache.clear();
    colorCache.set(resolvedValue, result);
    return result;
  }

  function mix(a, b, t) {
    return a + (b - a) * t;
  }

  function srgbToLinear(value) {
    value /= 255;
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  }

  function linearToSrgb(value) {
    value = Math.max(0, Math.min(1, value));
    return (value <= 0.0031308 ? value * 12.92 : 1.055 * Math.pow(value, 1 / 2.4) - 0.055) * 255;
  }

  function mixChannel(a, b, t, colorSpace) {
    return colorSpace === "perceptual" ? linearToSrgb(mix(srgbToLinear(a), srgbToLinear(b), t)) : mix(a, b, t);
  }

  function smooth(t) {
    return t * t * (3 - 2 * t);
  }

  function point(model, row, column) {
    var index = row * model.width + column;
    return model.points[index] || [column / Math.max(1, model.width - 1), row / Math.max(1, model.height - 1)];
  }

  function lerpPoint(a, b, t) {
    return [mix(a[0], b[0], t), mix(a[1], b[1], t)];
  }

  function cubicPoint(a, b, c, d, t) {
    var ab = lerpPoint(a, b, t);
    var bc = lerpPoint(b, c, t);
    var cd = lerpPoint(c, d, t);
    return lerpPoint(lerpPoint(ab, bc, t), lerpPoint(bc, cd, t), t);
  }

  // SwiftUI infers straight tangents for the points form. Explicit
  // BezierPoint values carry the four global control-point positions instead.
  function controls(model, row, column) {
    var index = row * model.width + column;
    var explicit = Array.isArray(model.bezierPoints) && model.bezierPoints[index];
    if (explicit) return explicit;
    var vertex = point(model, row, column);
    var left = point(model, row, Math.max(0, column - 1));
    var right = point(model, row, Math.min(model.width - 1, column + 1));
    var top = point(model, Math.max(0, row - 1), column);
    var bottom = point(model, Math.min(model.height - 1, row + 1), column);
    return {
      leading: lerpPoint(vertex, left, 1 / 3),
      top: lerpPoint(vertex, top, 1 / 3),
      trailing: lerpPoint(vertex, right, 1 / 3),
      bottom: lerpPoint(vertex, bottom, 1 / 3)
    };
  }

  // A Coons patch joins the four cubic boundary curves around a mesh cell.
  // It is evaluated only for explicit Bezier meshes; ordinary point meshes
  // retain the cheaper bilinear path below.
  function patchPoint(model, row, column, u, v) {
    var p00 = point(model, row, column);
    var p10 = point(model, row, column + 1);
    var p01 = point(model, row + 1, column);
    var p11 = point(model, row + 1, column + 1);
    var c00 = controls(model, row, column);
    var c10 = controls(model, row, column + 1);
    var c01 = controls(model, row + 1, column);
    var c11 = controls(model, row + 1, column + 1);
    var top = cubicPoint(p00, c00.trailing, c10.leading, p10, u);
    var bottom = cubicPoint(p01, c01.trailing, c11.leading, p11, u);
    var left = cubicPoint(p00, c00.bottom, c01.top, p01, v);
    var right = cubicPoint(p10, c10.bottom, c11.top, p11, v);
    var bilinear = lerpPoint(lerpPoint(p00, p10, u), lerpPoint(p01, p11, u), v);
    var horizontal = lerpPoint(top, bottom, v);
    var vertical = lerpPoint(left, right, u);
    return [
      horizontal[0] + vertical[0] - bilinear[0],
      horizontal[1] + vertical[1] - bilinear[1]
    ];
  }

  function patchCoordinates(model, row, column, x, y, initialU, initialV) {
    if (!Array.isArray(model.bezierPoints)) return [initialU, initialV];
    var u = initialU;
    var v = initialV;
    // One Newton step corrects the axis-aligned estimate for the common case
    // while keeping rasterization bounded for large canvases.
    var position = patchPoint(model, row, column, u, v);
    var epsilon = 1 / 256;
    var uPosition = patchPoint(model, row, column, Math.min(1, u + epsilon), v);
    var vPosition = patchPoint(model, row, column, u, Math.min(1, v + epsilon));
    var duX = (uPosition[0] - position[0]) / epsilon;
    var duY = (uPosition[1] - position[1]) / epsilon;
    var dvX = (vPosition[0] - position[0]) / epsilon;
    var dvY = (vPosition[1] - position[1]) / epsilon;
    var determinant = duX * dvY - duY * dvX;
    if (Math.abs(determinant) > 1e-6) {
      var errorX = x - position[0];
      var errorY = y - position[1];
      u += (errorX * dvY - errorY * dvX) / determinant;
      v += (duX * errorY - duY * errorX) / determinant;
    }
    return [Math.max(0, Math.min(1, u)), Math.max(0, Math.min(1, v))];
  }

  function vertexColor(model, row, column) {
    var index = row * model.width + column;
    if (model._resolvedColors) return model._resolvedColors[index] || model._backgroundColor;
    return color(model.colors[index] || model.background);
  }

  function locate(model, value, axis) {
    var count = axis === 0 ? model.width : model.height;
    if (count < 2) return 0;
    var best = 0;
    for (var i = 0; i < count - 1; i++) {
      var a = axis === 0 ? point(model, 0, i)[0] : point(model, i, 0)[1];
      var b = axis === 0 ? point(model, 0, i + 1)[0] : point(model, i + 1, 0)[1];
      if ((value >= a && value <= b) || (value >= b && value <= a)) { best = i; break; }
      if (value >= Math.min(a, b)) best = i;
    }
    return Math.max(0, Math.min(count - 2, best));
  }

  function sample(model, x, y) {
    if (model._bounds && (x < model._bounds.minX || x > model._bounds.maxX || y < model._bounds.minY || y > model._bounds.maxY)) return model._backgroundColor;
    if (model.width < 2 && model.height < 2) return vertexColor(model, 0, 0);
    if (model.width < 2) {
      var verticalRow = locate(model, y, 1);
      var verticalStart = point(model, verticalRow, 0);
      var verticalEnd = point(model, verticalRow + 1, 0);
      var verticalT = (y - verticalStart[1]) / ((verticalEnd[1] - verticalStart[1]) || 1);
      verticalT = Math.max(0, Math.min(1, model.smoothsColors ? smooth(verticalT) : verticalT));
      var verticalA = vertexColor(model, verticalRow, 0);
      var verticalB = vertexColor(model, verticalRow + 1, 0);
      return [
        mixChannel(verticalA[0], verticalB[0], verticalT, model.colorSpace),
        mixChannel(verticalA[1], verticalB[1], verticalT, model.colorSpace),
        mixChannel(verticalA[2], verticalB[2], verticalT, model.colorSpace),
        mix(verticalA[3], verticalB[3], verticalT)
      ];
    }
    if (model.height < 2) {
      var horizontalColumn = locate(model, x, 0);
      var horizontalStart = point(model, 0, horizontalColumn);
      var horizontalEnd = point(model, 0, horizontalColumn + 1);
      var horizontalT = (x - horizontalStart[0]) / ((horizontalEnd[0] - horizontalStart[0]) || 1);
      horizontalT = Math.max(0, Math.min(1, model.smoothsColors ? smooth(horizontalT) : horizontalT));
      var horizontalA = vertexColor(model, 0, horizontalColumn);
      var horizontalB = vertexColor(model, 0, horizontalColumn + 1);
      return [
        mixChannel(horizontalA[0], horizontalB[0], horizontalT, model.colorSpace),
        mixChannel(horizontalA[1], horizontalB[1], horizontalT, model.colorSpace),
        mixChannel(horizontalA[2], horizontalB[2], horizontalT, model.colorSpace),
        mix(horizontalA[3], horizontalB[3], horizontalT)
      ];
    }
    var column = locate(model, x, 0);
    var row = locate(model, y, 1);
    var p00 = point(model, row, column);
    var p10 = point(model, row, column + 1);
    var p01 = point(model, row + 1, column);
    var tx = (x - p00[0]) / ((p10[0] - p00[0]) || 1);
    var ty = (y - p00[1]) / ((p01[1] - p00[1]) || 1);
    tx = Math.max(0, Math.min(1, tx));
    ty = Math.max(0, Math.min(1, ty));
    var coordinates = patchCoordinates(model, row, column, x, y, tx, ty);
    tx = coordinates[0];
    ty = coordinates[1];
    if (model.smoothsColors) { tx = smooth(tx); ty = smooth(ty); }
    var c00 = vertexColor(model, row, column);
    var c10 = vertexColor(model, row, column + 1);
    var c01 = vertexColor(model, row + 1, column);
    var c11 = vertexColor(model, row + 1, column + 1);
    return [
      mixChannel(mixChannel(c00[0], c10[0], tx, model.colorSpace), mixChannel(c01[0], c11[0], tx, model.colorSpace), ty, model.colorSpace),
      mixChannel(mixChannel(c00[1], c10[1], tx, model.colorSpace), mixChannel(c01[1], c11[1], tx, model.colorSpace), ty, model.colorSpace),
      mixChannel(mixChannel(c00[2], c10[2], tx, model.colorSpace), mixChannel(c01[2], c11[2], tx, model.colorSpace), ty, model.colorSpace),
      mix(mix(c00[3], c10[3], tx), mix(c01[3], c11[3], tx), ty)
    ];
  }

  function rasterize(canvas, model) {
    var cssWidth = canvas.clientWidth || Number(model.logicalWidth) || 300;
    var cssHeight = canvas.clientHeight || Number(model.logicalHeight) || 150;
    var dpr = Math.max(1, global.devicePixelRatio || 1);
    var width = Math.max(1, Math.round(cssWidth * dpr));
    var height = Math.max(1, Math.round(cssHeight * dpr));
    // Avoid pathological allocations for an unconstrained canvas while
    // retaining native DPR for normal-sized surfaces.
    var maxPixels = 2200000;
    if (width * height > maxPixels) {
      var scale = Math.sqrt(maxPixels / (width * height));
      width = Math.max(1, Math.floor(width * scale));
      height = Math.max(1, Math.floor(height * scale));
    }
    canvas.width = width;
    canvas.height = height;
    // SwiftUI layout owns the CSS box (including percentage-sized background
    // meshes). Keep CSS width/height untouched; only the backing bitmap is
    // resized here, so a parent resize remains observable.
    var context = canvas.getContext("2d");
    if (!context) return;
    model._resolvedColors = model.colors.map(function (value) { return color(value); });
    model._backgroundColor = color(model.background);
    var bounds = { minX: Infinity, maxX: -Infinity, minY: Infinity, maxY: -Infinity };
    for (var pointIndex = 0; pointIndex < model.points.length; pointIndex++) {
      var meshPoint = model.points[pointIndex];
      bounds.minX = Math.min(bounds.minX, meshPoint[0]);
      bounds.maxX = Math.max(bounds.maxX, meshPoint[0]);
      bounds.minY = Math.min(bounds.minY, meshPoint[1]);
      bounds.maxY = Math.max(bounds.maxY, meshPoint[1]);
    }
    model._bounds = bounds;
    var image = context.createImageData(width, height);
    var data = image.data;
    var background = model._backgroundColor;
    var index = 0;
    for (var py = 0; py < height; py++) {
      var y = height > 1 ? py / (height - 1) : 0;
      for (var px = 0; px < width; px++) {
        var x = width > 1 ? px / (width - 1) : 0;
        var value = (x < 0 || y < 0 || x > 1 || y > 1) ? background : sample(model, x, y);
        data[index++] = Math.max(0, Math.min(255, Math.round(value[0])));
        data[index++] = Math.max(0, Math.min(255, Math.round(value[1])));
        data[index++] = Math.max(0, Math.min(255, Math.round(value[2])));
        data[index++] = Math.max(0, Math.min(255, Math.round(value[3])));
      }
    }
    context.putImageData(image, 0, 0);
  }

  function interpolate(from, to, t) {
    if (!from || from.width !== to.width || from.height !== to.height || from.points.length !== to.points.length || from.colors.length !== to.colors.length) return to;
    var model = {
      width: to.width, height: to.height, smoothsColors: to.smoothsColors,
      background: to.background, colorSpace: to.colorSpace, points: [], colors: [],
      bezierPoints: Array.isArray(from.bezierPoints) && Array.isArray(to.bezierPoints) ? [] : null
    };
    for (var i = 0; i < to.points.length; i++) {
      model.points.push([mix(from.points[i][0], to.points[i][0], t), mix(from.points[i][1], to.points[i][1], t)]);
    }
    if (model.bezierPoints) {
      for (var b = 0; b < to.bezierPoints.length; b++) {
        var fromControl = from.bezierPoints[b];
        var toControl = to.bezierPoints[b];
        if (!fromControl || !toControl) {
          model.bezierPoints.push(null);
          continue;
        }
        var control = {};
        ["leading", "top", "trailing", "bottom"].forEach(function (key) {
          control[key] = [
            mix(fromControl[key][0], toControl[key][0], t),
            mix(fromControl[key][1], toControl[key][1], t)
          ];
        });
        model.bezierPoints.push(control);
      }
    }
    // Colors stay as CSS strings in the payload; resolve them once per frame
    // and emit rgba values, which Canvas parses consistently across engines.
    for (var c = 0; c < to.colors.length; c++) {
      var a = color(from.colors[c]);
      var b = color(to.colors[c]);
      model.colors.push("rgba(" + Math.round(mixChannel(a[0], b[0], t, to.colorSpace)) + "," + Math.round(mixChannel(a[1], b[1], t, to.colorSpace)) + "," + Math.round(mixChannel(a[2], b[2], t, to.colorSpace)) + "," + (mix(a[3], b[3], t) / 255) + ")");
    }
    var fromBackground = color(from.background);
    var toBackground = color(to.background);
    model.background = "rgba(" + Math.round(mixChannel(fromBackground[0], toBackground[0], t, to.colorSpace)) + "," + Math.round(mixChannel(fromBackground[1], toBackground[1], t, to.colorSpace)) + "," + Math.round(mixChannel(fromBackground[2], toBackground[2], t, to.colorSpace)) + "," + (mix(fromBackground[3], toBackground[3], t) / 255) + ")";
    return model;
  }

  function durationFrom(animation) {
    var match = String(animation || "").match(/([0-9]*\.?[0-9]+)ms/);
    if (match) return Math.max(0, Number(match[1]));
    match = String(animation || "").match(/([0-9]*\.?[0-9]+)s/);
    return match ? Math.max(0, Number(match[1]) * 1000) : 260;
  }

  global.__renderMeshGradient = function (canvas, payload, previousPayload, animation, reduceMotion) {
    if (!canvas) return;
    var token = (generations.get(canvas) || 0) + 1;
    generations.set(canvas, token);
    var target;
    try { target = JSON.parse(String(payload || "{}")); } catch (_) { return; }
    target.logicalWidth = canvas.clientWidth || 300;
    target.logicalHeight = canvas.clientHeight || 150;
    var previous = null;
    try { previous = previousPayload ? JSON.parse(String(previousPayload)) : null; } catch (_) { previous = null; }
    var shouldAnimate = !reduceMotion && previous && animation && global.requestAnimationFrame && previous.width === target.width && previous.height === target.height;
    if (!shouldAnimate) { rasterize(canvas, target); return; }
    var start = null;
    var duration = durationFrom(animation);
    function frame(timestamp) {
      if (generations.get(canvas) !== token || canvas.isConnected === false) return;
      if (start == null) start = timestamp;
      var progress = Math.max(0, Math.min(1, (timestamp - start) / duration));
      var eased = progress < 0.5 ? 2 * progress * progress : 1 - Math.pow(-2 * progress + 2, 2) / 2;
      rasterize(canvas, progress >= 1 ? target : interpolate(previous, target, eased));
      if (progress < 1) global.requestAnimationFrame(frame);
    }
    global.requestAnimationFrame(frame);
  };
})(globalThis);
