/** Browser measurement host for GeometryReader and onGeometryChange.
 *
 * Host-only adapter: it measures DOM boxes and reports them through the named
 * value-event channel. Coordinate-space semantics (`.local`, `.global`,
 * `.named`, `.scrollView`, `bounds(of:)`) and change detection live in Swift
 * (Sources/SwiftUIWebCore/GeometryMeasurement.swift), which also documents
 * the wire format produced by `measurementPayload`.
 */
const RS = '\u001e', US = '\u001f';
const round = n => Math.round(n * 64) / 64;
const box = (x, y, width, height) => [x, y, width, height].map(round).join(',');

const TRANSFORM_PROPERTIES = ['transform', 'translate', 'rotate', 'scale'];

/** The frame of `element`. A `data-geometry-untransformed` element (the target of a visual effect) is measured without the
 * transform the effect writes inline on it: measured with it, the effect would move its own input each commit and never settle.
 * Its transition is held meanwhile, so neither style change starts one. */
function frameOf(element) {
  const marker = element.getAttribute('data-geometry-untransformed');
  const rect = untransformedFrame(element, marker);
  // A geometry effect is handed the size its content lays out at (`local`), not the viewport's size of it.
  return marker === 'local' ? withLayoutSize(element, rect) : rect;
}

/** Where the transforms of `element` and its ancestors take its own x and y axes in the window, as the matrix [a, b, c, d]
 * (one CSS pixel along x lands a across and b down, one along y lands c across and d down); the identity without a transform,
 * null where the browser has no `DOMMatrix`. */
function axisMap(element, window) {
  // One pass of measurements asks for the views of one page: the map of each ancestor is kept until the pass is over.
  if (!axisMap.cache) { axisMap.cache = new Map(); window.queueMicrotask(() => { axisMap.cache = null; }); }
  const cache = axisMap.cache;
  if (cache.has(element)) return cache.get(element);
  const above = element.parentElement ? axisMap(element.parentElement, window) : IDENTITY_AXES;
  let result = above;
  const style = window.getComputedStyle(element);
  if (above !== null && TRANSFORM_PROPERTIES.some((property) => style[property] && style[property] !== 'none')) {
    if (!window.DOMMatrix) result = null;
    else {
      const [a, b, c, d] = above;
      let matrix = new window.DOMMatrix();
      if (style.rotate && style.rotate !== 'none') {
        const [, number, unit] = /(-?[\d.e+-]+)(deg|rad|turn|grad)?\s*$/.exec(style.rotate) ?? [];
        const angle = parseFloat(number);
        if (Number.isFinite(angle)) matrix = matrix.rotate(unit === 'rad' ? angle * 180 / Math.PI : unit === 'turn' ? angle * 360 : unit === 'grad' ? angle * 0.9 : angle);
      }
      if (style.scale && style.scale !== 'none') {
        const [x, y = x] = style.scale.split(/\s+/).map(Number);
        if (Number.isFinite(x) && Number.isFinite(y)) matrix = matrix.scale(x, y);
      }
      if (style.transform && style.transform !== 'none') matrix = matrix.multiply(new window.DOMMatrix(style.transform));
      // The element's own transform applies before those above it.
      result = [a * matrix.a + c * matrix.b, b * matrix.a + d * matrix.b, a * matrix.c + c * matrix.d, b * matrix.c + d * matrix.d];
    }
  }
  cache.set(element, result);
  return result;
}
const IDENTITY_AXES = Object.freeze([1, 0, 0, 1]);
/** Whether a view's axes are turned or mirrored: something its box and layout size do not show (a square turned a quarter
 * has the box it had). */
const turnedAxes = map => map !== null && (Math.abs(map[1]) > 1e-6 || Math.abs(map[2]) > 1e-6 || map[0] < 0 || map[3] < 0);

/** How many window pixels one CSS pixel of `element` is along its own x and y axes: the lengths of its axes in the window,
 * whatever rotation is among its transforms. A bounding box against the layout size is not this under a rotation, which trades
 * the box's width for its height. */
function axisScales(element, window) {
  const map = axisMap(element, window);
  return map ? [Math.hypot(map[0], map[1]) || 1, Math.hypot(map[2], map[3]) || 1] : null;
}

/** The size `element` lays out at, in its own CSS pixels, or null when the browser reports none (an inline element). */
function layoutBox(element) {
  const computed = element.ownerDocument.defaultView.getComputedStyle(element);
  let width = parseFloat(computed.width), height = parseFloat(computed.height);
  if (!(width >= 0) || !(height >= 0)) return null;
  const px = value => parseFloat(value) || 0;
  if (computed.boxSizing !== 'border-box') {
    width += px(computed.paddingLeft) + px(computed.paddingRight) + px(computed.borderLeftWidth) + px(computed.borderRightWidth);
    height += px(computed.paddingTop) + px(computed.paddingBottom) + px(computed.borderTopWidth) + px(computed.borderBottomWidth);
  }
  return {width, height};
}

/** `rect` with the size the element lays out at when a scale or rotation above it makes the two differ. */
function withLayoutSize(element, rect) {
  const local = layoutBox(element);
  if (!local || (Math.abs(local.width - rect.width) <= 0.5 && Math.abs(local.height - rect.height) <= 0.5)) return rect;
  return {left: rect.left, top: rect.top, width: local.width, height: local.height};
}

function untransformedFrame(element, marker) {
  const style = element.style;
  if (marker === null || !TRANSFORM_PROPERTIES.some((property) => style[property])) {
    return element.getBoundingClientRect();
  }
  const saved = TRANSFORM_PROPERTIES.map((property) => style[property]), transition = style.transition;
  style.transition = 'none';
  for (const property of TRANSFORM_PROPERTIES) style[property] = 'none';
  const rect = element.getBoundingClientRect();
  TRANSFORM_PROPERTIES.forEach((property, index) => { style[property] = saved[index]; });
  element.getBoundingClientRect();
  style.transition = transition;
  return rect;
}

/** The payload for `element`: its window frame followed by the ancestor
 * coordinate spaces (nearest first) that Swift may resolve against. */

export function measurementPayload(element, root) {
  const rect = frameOf(element);
  let payload = withLocal(box(rect.left, rect.top, rect.width, rect.height), rect, layoutBox(element), element);
  for (let node = element; node; node = node.parentElement) {
    const name = node.getAttribute('data-coordinate-space');
    if (name !== null && !name.includes(RS) && !name.includes(US)) {
      const r = node === element ? rect : node.getBoundingClientRect();
      payload += RS + 'n' + US + name + US + withLocal(box(r.left, r.top, r.width, r.height), r, layoutBox(node), node);
    }
    // A view is never inside its own scroll view's coordinate space.
    if (node !== element && node.classList?.contains('scroll-view')) {
      const r = node.getBoundingClientRect();
      const axes = node.classList.contains('scroll-both') ? 'both'
        : node.classList.contains('scroll-horizontal') ? 'horizontal' : 'vertical';
      // The scroll view's space is its visible (padding-box) area. Under a scale above it the area is the window's pixels
      // (its axes' scale) and the client size is in its own points.
      const [kx, ky] = axisScales(node, node.ownerDocument.defaultView) ?? [node.offsetWidth > 0 ? r.width / node.offsetWidth : 1, node.offsetHeight > 0 ? r.height / node.offsetHeight : 1];
      const scaled = Math.abs(kx - 1) > 0.005 || Math.abs(ky - 1) > 0.005;
      const map = axisMap(node, node.ownerDocument.defaultView), local = layoutBox(node);
      if (turnedAxes(map) && local) {
        // Turned or mirrored: the visible area is the box its padding box has in the window, through the scroll view's map
        // from its own corner, and the record says where its axes go, as a view's does.
        const [a, b, c, d] = map;
        const cornerX = r.left - Math.min(0, a * local.width) - Math.min(0, c * local.height), cornerY = r.top - Math.min(0, b * local.width) - Math.min(0, d * local.height);
        const xs = [], ys = [];
        for (const [x, y] of [[node.clientLeft, node.clientTop], [node.clientLeft + node.clientWidth, node.clientTop], [node.clientLeft, node.clientTop + node.clientHeight], [node.clientLeft + node.clientWidth, node.clientTop + node.clientHeight]]) {
          xs.push(cornerX + a * x + c * y); ys.push(cornerY + b * x + d * y);
        }
        const left = Math.min(...xs), top = Math.min(...ys);
        payload += RS + 's' + US + axes + US + box(left, top, Math.max(...xs) - left, Math.max(...ys) - top) + ',' + round(node.clientWidth) + ',' + round(node.clientHeight)
          + ',' + map.map(value => Math.round(value * 1e6) / 1e6).join(',');
        if (node === root) break;
        continue;
      }
      const visible = box(r.left + node.clientLeft * kx, r.top + node.clientTop * ky, node.clientWidth * kx, node.clientHeight * ky);
      payload += RS + 's' + US + axes + US + (scaled ? visible + ',' + round(node.clientWidth) + ',' + round(node.clientHeight) : visible);
    }
    if (node === root) break;
  }
  return payload;
}

/** `frame` (the box in the window) with the size the element lays out at, when a scale or rotation above it makes the two
 * differ, and then where its axes go in the window (`axisMap`) when they are turned or mirrored: the two sizes give a plain
 * scale, not a rotation, which trades the box's width for its height. */
function withLocal(frame, rect, local, element) {
  if (!local) return frame;
  // A square turned a quarter, or a mirrored view, has the box it would have anyway: its axes say what its sizes do not.
  const map = local.width > 0 && local.height > 0 ? axisMap(element, element.ownerDocument.defaultView) : null;
  const turned = turnedAxes(map);
  if (!turned && Math.abs(local.width - rect.width) <= 0.5 && Math.abs(local.height - rect.height) <= 0.5) return frame;
  const sized = frame + ',' + round(local.width) + ',' + round(local.height);
  if (!turned) return sized;
  // Finer than a box's 1/64 pixel: the axes multiply offsets of hundreds of pixels.
  return sized + ',' + map.map(value => Math.round(value * 1e6) / 1e6).join(',');
}

/** The size a payload reports: the one the view lays out at when it carries one, else its box's. */
const payloadSize = payload => { const head = payload.split(RS, 1)[0].split(','); return (head.length >= 6 ? head.slice(4, 6) : head.slice(-2)).join(','); };

/** The ascent and descent of a CSS font, from a canvas measurement, cached per font. */
const fontMetrics = new Map();
function metricsOf(document, font) {
  let metrics = fontMetrics.get(font);
  if (metrics) return metrics;
  const context = (metricsOf.context ??= document.createElement('canvas').getContext('2d'));
  context.font = font;
  const measured = context.measureText('Hg');
  const ascent = measured.fontBoundingBoxAscent ?? measured.actualBoundingBoxAscent ?? 0;
  const descent = measured.fontBoundingBoxDescent ?? measured.actualBoundingBoxDescent ?? 0;
  metrics = {ascent, descent};
  fontMetrics.set(font, metrics);
  return metrics;
}
/** A font a canvas can draw with, from computed style (the `font` shorthand is empty in some engines). */
const cssFont = style => [style.fontStyle, style.fontVariantCaps === 'small-caps' ? 'small-caps' : '', style.fontWeight, style.fontSize, style.fontFamily].filter(Boolean).join(' ');
const clean = text => String(text).replace(/[\u001e\u001f]/g, ' ');
const pixels = value => { const n = parseFloat(value); return Number.isFinite(n) ? n : 0; };

/** The top-level comma-separated parts of a CSS value. */
function splitTop(text, separator = ',') {
  const parts = []; let depth = 0, start = 0;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (character === '(') depth++;
    else if (character === ')') depth--;
    else if (depth === 0 && (separator === ' ' ? /\s/.test(character) : character === separator)) { parts.push(text.slice(start, index)); start = index + 1; }
  }
  parts.push(text.slice(start));
  return parts.map(part => part.trim()).filter(Boolean);
}

const POSITION = /^-?[\d.]+(%|px|deg|turn|rad|grad)?$/;
const toRadians = (value) => {
  const number = parseFloat(value);
  if (value.endsWith('turn')) return number * 2 * Math.PI;
  if (value.endsWith('grad')) return number * Math.PI / 200;
  if (value.endsWith('rad')) return number;
  return number * Math.PI / 180;
};

/** The color stops of a gradient: a color and its places along the gradient, as fractions (`length` converts pixels,
 * 360 degrees is a whole turn); a stop without a place sits between its neighbors. */
function gradientStops(parts, length) {
  const stops = [];
  for (const part of parts) {
    const tokens = splitTop(part, ' ');
    const places = [];
    while (tokens.length > 1 && POSITION.test(tokens[tokens.length - 1])) places.unshift(tokens.pop());
    const color = tokens.join(' ');
    const fraction = place => place.endsWith('%') ? parseFloat(place) / 100 : place.endsWith('px') ? parseFloat(place) / (length || 1)
      : /deg|turn|rad|grad/.test(place) ? toRadians(place) / (2 * Math.PI) : parseFloat(place);
    if (!places.length) stops.push([color, null]);
    for (const place of places) stops.push([color, fraction(place)]);
  }
  if (!stops.length) return stops;
  if (stops[0][1] === null) stops[0][1] = 0;
  if (stops[stops.length - 1][1] === null) stops[stops.length - 1][1] = 1;
  for (let index = 1; index < stops.length; index++) {
    if (stops[index][1] === null) {
      let next = index; while (stops[next][1] === null) next++;
      const from = stops[index - 1][1], to = stops[next][1];
      for (let step = index; step < next; step++) stops[step][1] = from + (to - from) * (step - index + 1) / (next - index + 1);
    }
    stops[index][1] = Math.max(stops[index][1], stops[index - 1][1]);
  }
  return stops.map(([color, place]) => [color, round(place)]);
}

/** A point of a box from a CSS position (`50% 30%`, `left top`, pixels), the center by default. */
function boxPoint(text, x, y, width, height) {
  const tokens = splitTop(text || '', ' ');
  const keyword = {left: 0, center: 0.5, right: 1, top: 0, bottom: 1};
  let horizontal = tokens[0] ?? 'center', vertical = tokens[1] ?? 'center';
  if (tokens.length === 1 && (horizontal === 'top' || horizontal === 'bottom')) { vertical = horizontal; horizontal = 'center'; }
  if (horizontal === 'top' || horizontal === 'bottom' || vertical === 'left' || vertical === 'right') [horizontal, vertical] = [vertical, horizontal];
  const along = (token, origin, size) => token in keyword ? origin + keyword[token] * size : token.endsWith('%') ? origin + parseFloat(token) / 100 * size : origin + (parseFloat(token) || 0);
  return [along(horizontal, x, width), along(vertical, y, height)];
}

/** The canvas shading of a CSS gradient over the box at x, y (in the text's coordinates): the shape the canvas painter
 * fills with (embedded-dom.js, `canvasShading`), or null for what is not a gradient the canvas can paint. A radial
 * ellipse is drawn as a circle of its mean radius. */
export function gradientShading(text, x, y, width, height) {
  const match = /^\s*(linear|radial|conic)-gradient\((.*)\)\s*$/s.exec(text || '');
  if (!match) return null;
  const kind = match[1], parts = splitTop(match[2]);
  if (!parts.length) return null;
  const first = parts[0];
  const geometry = kind === 'linear' ? /^(to\s|-?[\d.]+(deg|rad|turn|grad)$)/.test(first)
    : kind === 'radial' ? /^(circle|ellipse|closest|farthest|at\s|[\d.]+(px|%))/.test(first) : /^(from\s|at\s)/.test(first);
  const head = geometry ? parts.shift() : '';
  if (kind === 'linear') {
    let angle = Math.PI;
    if (head.startsWith('to ')) {
      const sides = new Set(head.slice(3).trim().split(/\s+/)), corner = Math.atan2(height, width);
      const top = sides.has('top'), bottom = sides.has('bottom'), left = sides.has('left'), right = sides.has('right');
      angle = top && right ? corner : bottom && right ? Math.PI - corner : bottom && left ? Math.PI + corner : top && left ? 2 * Math.PI - corner
        : top ? 0 : right ? Math.PI / 2 : bottom ? Math.PI : left ? 1.5 * Math.PI : Math.PI;
    } else if (head) angle = toRadians(head);
    const length = Math.abs(width * Math.sin(angle)) + Math.abs(height * Math.cos(angle));
    const cx = x + width / 2, cy = y + height / 2, dx = Math.sin(angle) * length / 2, dy = -Math.cos(angle) * length / 2;
    return {k: 'l', x0: round(cx - dx), y0: round(cy - dy), x1: round(cx + dx), y1: round(cy + dy), s: gradientStops(parts, length)};
  }
  const at = head.indexOf('at ');
  const shape = (at >= 0 ? head.slice(0, at) : head).trim(), place = at >= 0 ? head.slice(at + 3) : '';
  const [px, py] = boxPoint(place, x, y, width, height);
  if (kind === 'conic') {
    const from = /from\s+(\S+)/.exec(shape);
    return {k: 'n', a: round((from ? toRadians(from[1]) : 0) - Math.PI / 2), x: round(px), y: round(py), s: gradientStops(parts, 1)};
  }
  const sizes = splitTop(shape, ' ').filter(token => /^[\d.]+(px|%)$/.test(token));
  const corners = [[x, y], [x + width, y], [x, y + height], [x + width, y + height]].map(([cx, cy]) => Math.hypot(cx - px, cy - py));
  const sides = [px - x, x + width - px, py - y, y + height - py];
  let radius;
  if (sizes.length) {
    const lengths = sizes.map((token, index) => token.endsWith('%') ? parseFloat(token) / 100 * (index === 0 ? width : height) : parseFloat(token));
    radius = lengths.reduce((sum, value) => sum + value, 0) / lengths.length;
  } else if (shape.includes('closest-side')) radius = Math.min(...sides);
  else if (shape.includes('farthest-side')) radius = Math.max(...sides);
  else if (shape.includes('closest-corner')) radius = Math.min(...corners);
  else radius = Math.max(...corners);
  return {k: 'r', x: round(px), y: round(py), r0: 0, r1: round(radius), s: gradientStops(parts, radius)};
}

/** The gradient the glyphs of `parent` are painted with: a background clipped to the text on it or an ancestor
 * (`foregroundStyle` with a gradient, on the text or on a view around it), as a canvas shading in the text's
 * coordinates; '' for a color. A text a renderer draws keeps the gradient it had in `data-text-paint-image`. The search
 * stops at the first ancestor that sets a color of its own. */
function paintOf(parent, element, origin, window) {
  for (let node = parent, inside = true; node && node !== window.document.body; node = node.parentElement) {
    const saved = node.getAttribute('data-text-paint-image');
    let image = saved;
    if (!image) {
      const style = window.getComputedStyle(node);
      if (style.backgroundClip === 'text' || style.webkitBackgroundClip === 'text') image = style.backgroundImage;
    }
    if (image && image !== 'none') {
      const rect = node.getBoundingClientRect();
      // In the text's own coordinates, like the glyphs: under a scale the rectangle the page reports is scaled once already.
      const local = origin.toLocal(rect);
      const shading = gradientShading(image, local.x, local.y, local.width, local.height);
      return shading ? JSON.stringify(shading) : '';
    }
    // Outside the text, an ancestor with a color of its own paints the glyphs with it.
    if (!inside && node.style.color && node.style.color !== 'transparent') break;
    if (node === element) inside = false;
  }
  return '';
}

/** The underline and strikethrough drawn through the glyphs of `parent` (its own and its ancestors' within the text):
 * `lines|color|thickness|underline offset|strikethrough offset`, offsets from the baseline; '' for none. A text a renderer
 * draws keeps the decoration color it had in `data-text-paint-decoration`. */
function decorationOf(parent, element, style, window) {
  const lines = new Set();
  let color = '', thickness = 0;
  for (let node = parent; node; node = node.parentElement) {
    const own = node === parent ? style : window.getComputedStyle(node);
    const line = own.textDecorationLine || '';
    if (line && line !== 'none') {
      for (const part of line.split(/\s+/)) if (part === 'underline' || part === 'line-through') lines.add(part);
      if (!color) {
        const saved = node.getAttribute('data-text-paint-decoration');
        color = saved && saved !== 'currentcolor' ? saved : saved ? own.color : own.textDecorationColor || own.color;
      }
      if (!thickness) thickness = pixels(own.textDecorationThickness);
    }
    if (node === element) break;
  }
  if (!lines.size) return '';
  const size = pixels(style.fontSize) || 16;
  if (!(thickness > 0)) thickness = Math.max(1, size / 14);
  // An underline sits below the baseline; a strikethrough through the middle of the lowercase letters.
  return [[...lines].join(' '), color, round(thickness), round(Math.max(thickness * 1.5, size * 0.1)), round(-size * 0.28)].join('|');
}

/** What the glyphs of `element` are painted with as it computes now: the colors of the text and its runs, and the gradient of
 * the view around it. A color a view around the text sets changes the glyphs' paint without any style of the text changing. */
function paintKey(element) {
  const window = element.ownerDocument.defaultView;
  const colors = [element, ...element.querySelectorAll('[data-text-run]')].map((node) => {
    const style = window.getComputedStyle(node);
    return style.color + '/' + style.textDecorationColor + '/' + cssFont(style) + '/' + style.letterSpacing;
  });
  // The gradient comes from the inline styles and classes of the text and of the views around it, and from the color scheme
  // that resolves its colors: read as attributes, they cost no style computation however deep the text is.
  let around = window.document.documentElement.getAttribute('data-color-scheme') + ';';
  for (let node = element; node && node !== window.document.body; node = node.parentElement) {
    around += (node.getAttribute('data-text-paint-image') || '') + '|' + (node.getAttribute('style') || '') + '|' + (node.getAttribute('class') || '') + ';';
  }
  return colors.join(',') + '#' + around;
}

/** The text layout a `TextRenderer` draws (Swift's `Text.Layout`, see TextRenderer.swift for the wire format): the text's
 * box, then its lines, each with its runs and the glyphs of each run, in the text's coordinates. A glyph is a grapheme;
 * a run is a stretch of one line drawn by one styled span (`data-text-run`). Collapsed white space has no glyph. */
/** The text's window box, with the scale a transform of the text or of a view around it gives it (a scale effect, an animated
 * transition): the glyph rects the page reports are in the window, and the layout is in the text's own coordinates, where the
 * canvas that draws it is too. Without a transform the scale is 1 and the rects are used as they are. `toLocal` takes a rectangle of
 * the window to the text's coordinates: under a rotation through the text's full map, its center by the inverse and its size from
 * the box a turned rectangle has (near an eighth of a turn, where that cannot be solved, with the height the caller knows). */
function localBox(element, window) {
  const rect = element.getBoundingClientRect();
  let transformed = false;
  for (let node = element; node && !transformed; node = node.parentElement) {
    const style = window.getComputedStyle(node);
    transformed = TRANSFORM_PROPERTIES.some((property) => style[property] && style[property] !== 'none');
  }
  const plain = (left, top, scaleX, scaleY) => r => ({x: (r.left - left) / scaleX, y: (r.top - top) / scaleY, width: r.width / scaleX, height: r.height / scaleY});
  if (!transformed) return {left: rect.left, top: rect.top, width: rect.width, height: rect.height, scaleX: 1, scaleY: 1, toLocal: plain(rect.left, rect.top, 1, 1)};
  // The layout size without transforms: the computed size of a block (fractional), else its offset size (whole pixels).
  const style = window.getComputedStyle(element);
  const border = style.boxSizing === 'border-box';
  const extra = (a, b, c, d) => (border ? 0 : pixels(style[a]) + pixels(style[b]) + pixels(style[c]) + pixels(style[d]));
  const width = style.width.endsWith('px') ? pixels(style.width) + extra('paddingLeft', 'paddingRight', 'borderLeftWidth', 'borderRightWidth') : element.offsetWidth;
  const height = style.height.endsWith('px') ? pixels(style.height) + extra('paddingTop', 'paddingBottom', 'borderTopWidth', 'borderBottomWidth') : element.offsetHeight;
  // The scale of the element's axes, from the transforms themselves: its box against its layout size is not that under a rotation.
  const [scaleX, scaleY] = axisScales(element, window) ?? [width > 0 && rect.width > 0 ? rect.width / width : 1, height > 0 && rect.height > 0 ? rect.height / height : 1];
  const local = {left: rect.left, top: rect.top, width: width > 0 ? width : rect.width / scaleX, height: height > 0 ? height : rect.height / scaleY, scaleX, scaleY};
  const map = axisMap(element, window);
  if (!turnedAxes(map)) return {...local, toLocal: plain(rect.left, rect.top, scaleX, scaleY)};
  const [a, b, c, d] = map, determinant = a * d - b * c;
  if (Math.abs(determinant) < 1e-9) return {...local, toLocal: plain(rect.left, rect.top, scaleX, scaleY)};
  // The text's own corner in the window, from its box there, and the box a w by h rectangle has under the map:
  // |a| w + |c| h wide and |b| w + |d| h high.
  const cornerX = rect.left - Math.min(0, a * local.width) - Math.min(0, c * local.height), cornerY = rect.top - Math.min(0, b * local.width) - Math.min(0, d * local.height);
  const A = Math.abs(a), B = Math.abs(b), C = Math.abs(c), D = Math.abs(d), solvable = A * D - C * B;
  const toLocal = (r, knownHeight) => {
    let w, h;
    if (Math.abs(solvable) > 0.2 * scaleX * scaleY) { w = (r.width * D - r.height * C) / solvable; h = (r.height * A - r.width * B) / solvable; }
    else { h = knownHeight ?? r.height / scaleY; w = A >= B ? (r.width - C * h) / A : (r.height - D * h) / B; }
    w = Math.max(0, w); h = Math.max(0, h);
    const dx = r.left + r.width / 2 - cornerX, dy = r.top + r.height / 2 - cornerY;
    const x = (d * dx - c * dy) / determinant, y = (a * dy - b * dx) / determinant;
    return {x: x - w / 2, y: y - h / 2, width: w, height: h};
  };
  return {...local, toLocal};
}

export function textLayoutPayload(element) {
  const document = element.ownerDocument, window = document.defaultView;
  const origin = localBox(element, window);
  const segmenter = window.Intl?.Segmenter ? new window.Intl.Segmenter(undefined, {granularity: 'grapheme'}) : null;
  const range = document.createRange();
  const glyphs = [], gaps = [], elided = [];
  const styles = new Map();
  let character = 0;
  const walker = document.createTreeWalker(element, window.NodeFilter.SHOW_TEXT);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const parent = node.parentElement;
    if (!parent || parent.closest('canvas')) continue;
    const owner = parent.closest('[data-text-run]');
    const run = owner && element.contains(owner) ? Number(owner.getAttribute('data-text-run')) || 0 : 0;
    let entry = styles.get(parent);
    if (!entry) {
      const style = window.getComputedStyle(parent), font = cssFont(style);
      entry = {style, font, metrics: metricsOf(document, font), decoration: decorationOf(parent, element, style, window), paint: paintOf(parent, element, origin, window),
        collapses: !/^(pre|pre-wrap|pre-line|break-spaces)$/.test(style.whiteSpace)};
      styles.set(parent, entry);
    }
    const {style, font, metrics} = entry;
    const text = node.data;
    const pieces = segmenter ? Array.from(segmenter.segment(text), part => [part.index, part.segment]) : [];
    if (!segmenter) { let offset = 0; for (const point of text) { pieces.push([offset, point]); offset += point.length; } }
    for (const [offset, segment] of pieces) {
      range.setStart(node, offset); range.setEnd(node, offset + segment.length);
      const rects = range.getClientRects();
      let rect = null;
      for (const candidate of rects) if (candidate.width > 0) { rect = candidate; break; }
      if (rect) {
        // In the text's own coordinates (a glyph's box is as high as its font's ascent and descent, when the map cannot say).
        const local = origin.toLocal(rect, metrics.ascent + metrics.descent);
        const top = local.y, height = local.height;
        const baseline = top + (height - metrics.ascent - metrics.descent) / 2 + metrics.ascent;
        glyphs.push({run, parent, style, font, metrics, decoration: entry.decoration, paint: entry.paint, x: local.x, width: local.width, top, bottom: top + height, baseline, character, text: segment});
      } else if (/^\s+$/.test(segment)) {
        // White space without a box: at the end of a line, or a line break. A collapsed run of it counts once.
        const newline = !entry.collapses && /\n/.test(segment);
        const last = gaps[gaps.length - 1];
        if (newline || !entry.collapses || !last || last.character !== character - 1) {
          const context = (metricsOf.context ??= document.createElement('canvas').getContext('2d'));
          context.font = font;
          gaps.push({character, width: newline ? 0 : context.measureText(' ').width + pixels(style.letterSpacing), newline});
        }
      } else {
        // A grapheme with a width and no box was left out of the page by the browser itself (WebKit gives the glyphs an
        // ellipsis replaces none): it is part of a cut text.
        const context = (metricsOf.context ??= document.createElement('canvas').getContext('2d'));
        context.font = font;
        const width = context.measureText(segment).width + pixels(style.letterSpacing);
        if (width > 0) elided.push({run, parent, style, font, metrics, decoration: entry.decoration, paint: entry.paint, character, text: segment, width});
      }
      character++;
    }
  }
  // Lines: a glyph below the bottom of the line so far starts the next one.
  const lines = [];
  for (const glyph of glyphs) {
    const line = lines[lines.length - 1];
    if (!line || glyph.top >= line.bottom - 0.5) lines.push({glyphs: [glyph], top: glyph.top, bottom: glyph.bottom});
    else { line.glyphs.push(glyph); line.bottom = Math.max(line.bottom, glyph.bottom); }
  }
  // A line limit clips the lines after it, which still have boxes below the text's; a line that does not wrap runs past
  // its right edge. The glyphs tell, not the element's scroll size: the renderer's canvas inside it may be bigger.
  const cut = window.getComputedStyle(element);
  const clipped = cut.overflow !== 'visible';
  // Right-to-left text starts at the right edge and runs past the left one.
  const rtl = cut.direction === 'rtl';
  const truncated = clipped && (elided.length > 0 || glyphs.some(glyph => glyph.top >= element.clientHeight - 0.5 || glyph.x + glyph.width > element.clientWidth + 1 || glyph.x < -1));
  const hidden = [];
  if (truncated) for (let index = lines.length - 1; index >= 0; index--) if (lines[index].top >= element.clientHeight - 0.5) hidden.unshift(...lines.splice(index, 1)[0].glyphs);
  // The browser draws an ellipsis where it cuts the text (a line limit, or a single line that does not fit): the last visible line
  // is the glyphs that fit before it and the ellipsis. The glyphs it replaces stay with the hidden ones, for sizing.
  // The glyphs the browser left out follow the last visible one, in reading order.
  if (truncated && elided.length) {
    const end = glyphs[glyphs.length - 1];
    let x = end ? (rtl ? end.x : end.x + end.width) : 0;
    for (const glyph of elided) {
      if (rtl) x -= glyph.width;
      hidden.push({...glyph, x, top: end?.top ?? 0, bottom: end?.bottom ?? 0});
      if (!rtl) x += glyph.width;
    }
  }
  if (truncated && lines.length && (cut.textOverflow === 'ellipsis' || (cut.webkitLineClamp && cut.webkitLineClamp !== 'none'))) {
    const last = lines[lines.length - 1];
    const sample = last.glyphs[last.glyphs.length - 1];
    const context = (metricsOf.context ??= document.createElement('canvas').getContext('2d'));
    context.font = sample.font;
    const mark = context.measureText('\u2026').width;
    // The browser cuts the line where the paragraph ends: at the right edge in left-to-right text, at the left one in right-to-left
    // text, whatever the order of the glyphs in it (a right-to-left run in a left-to-right paragraph has its start on the right). The
    // glyphs past that edge, less the room of the ellipsis, are the ones it replaces; those that stay keep their reading order.
    const outside = glyph => rtl ? glyph.x < mark - 0.5 : glyph.x + glyph.width > element.clientWidth - mark + 0.5;
    const kept = [], removed = [];
    for (const glyph of last.glyphs) (outside(glyph) ? removed : kept).push(glyph);
    // Where not even the first glyph fits beside the ellipsis, the ellipsis stands alone where the line starts: every glyph is
    // replaced, and `sample` only lends it its line and font.
    const edge = !kept.length ? (rtl ? Math.max(...removed.map(glyph => glyph.x + glyph.width)) - mark : Math.min(...removed.map(glyph => glyph.x)))
      : rtl ? Math.min(...kept.map(glyph => glyph.x)) - mark : Math.max(...kept.map(glyph => glyph.x + glyph.width));
    const next = removed[0] ?? hidden[0];
    const before = kept[kept.length - 1] ?? sample;
    last.glyphs = kept;
    kept.push({...before, x: edge, width: mark, text: '\u2026', synthetic: true, character: next ? next.character : before.character + 1});
    hidden.unshift(...removed);
  }
  let payload = box(0, 0, origin.width, origin.height) + ',' + (truncated ? 1 : 0);
  for (const line of lines) {
    const runs = [];
    for (const glyph of line.glyphs) {
      const last = runs[runs.length - 1];
      if (last && last.run === glyph.run && last.parent === glyph.parent) last.glyphs.push(glyph);
      else runs.push({run: glyph.run, parent: glyph.parent, style: glyph.style, font: glyph.font, metrics: glyph.metrics, decoration: glyph.decoration, paint: glyph.paint, baseline: glyph.baseline, glyphs: [glyph]});
    }
    // The line's baseline is its first run's; its ascent and descent reach every run's.
    const baseline = runs[0].baseline;
    let left = Infinity, right = -Infinity, ascent = 0, descent = 0;
    for (const run of runs) {
      for (const glyph of run.glyphs) { left = Math.min(left, glyph.x); right = Math.max(right, glyph.x + glyph.width); }
      ascent = Math.max(ascent, baseline - (run.baseline - run.metrics.ascent));
      descent = Math.max(descent, run.baseline + run.metrics.descent - baseline);
    }
    const lineHeight = pixels(runs[0].style.lineHeight);
    const leading = lineHeight > 0 ? Math.max(0, lineHeight - ascent - descent) : 0;
    payload += RS + 'L' + US + [left, baseline, right - left, ascent, descent, leading].map(round).join(',');
    for (const run of runs) {
      let runLeft = Infinity, runRight = -Infinity;
      for (const glyph of run.glyphs) { runLeft = Math.min(runLeft, glyph.x); runRight = Math.max(runRight, glyph.x + glyph.width); }
      const rtl = run.style.direction === 'rtl' ? 1 : 0;
      payload += RS + 'R' + US + [run.run, rtl, runLeft, run.baseline, runRight - runLeft, run.metrics.ascent, run.metrics.descent, pixels(run.style.letterSpacing)].map(round).join(',')
        + US + clean(run.font) + US + clean(run.style.color) + US + clean(run.decoration) + US + clean(run.paint);
      for (const glyph of run.glyphs) payload += RS + 'G' + US + [glyph.x, glyph.width, glyph.character, ...(glyph.synthetic ? [1] : [])].map(round).join(',') + US + clean(glyph.text);
    }
  }
  for (const gap of gaps) payload += RS + 'S' + US + [gap.character, round(gap.width), gap.newline ? 1 : 0].join(',');
  // The glyphs of the lines a line limit hides: not drawn, but part of the text `TextProxy` lays out again.
  for (const glyph of hidden) payload += RS + 'H' + US + [glyph.x, glyph.width, glyph.character].map(round).join(',') + US + clean(glyph.text);
  return payload;
}

export class GeometryHost {
  constructor(root, {dispatch, eventIdAttribute, eventsAttribute, batch = run => run()}) {
    this.root = root; this.document = root.ownerDocument; this.window = this.document.defaultView;
    this.dispatch = dispatch; this.eventId = eventIdAttribute; this.events = eventsAttribute; this.batch = batch;
    this.observed = new Set(); this.sent = new WeakMap();
    this.scrolled = new Set(); this.frame = 0; this.fullFrame = false;
    this.trace = {measurements: 0, dispatches: 0, scrollFrames: 0};
    this.window.__geometryTrace = this.trace;
    this.abort = new this.window.AbortController();
    const options = {passive: true, capture: true, signal: this.abort.signal};
    // Scroll does not bubble; one capturing listener sees every scroller.
    this.document.addEventListener('scroll', event => this.schedule(event.target), options);
    this.window.addEventListener('resize', () => this.schedule(null), {passive: true, signal: this.abort.signal});
    // A web font that finishes loading changes the glyphs of the texts a TextRenderer draws, not always their boxes.
    this.document.fonts?.addEventListener?.('loadingdone', () => this.batch(() => { fontMetrics.clear(); this.textKeys = new WeakMap(); for (const element of this.observed) if (element.hasAttribute('data-text-layout')) this.measure(element); }), {signal: this.abort.signal});
  }
  selector() { return `[data-geometry-reader][${this.eventId}],[data-geometry-change][${this.eventId}],[data-text-layout][${this.eventId}]`; }
  schedule(target) {
    if (target === null || target === this.document || target === this.document.documentElement) this.fullFrame = true;
    else if (target?.nodeType === 1) this.scrolled.add(target);
    if (!this.frame) this.frame = this.window.requestAnimationFrame(() => this.flushPositions());
  }
  /** Re-measures position readers under the scrolled ancestors. */
  flushPositions() {
    this.frame = 0; this.trace.scrollFrames++;
    const full = this.fullFrame, scrolled = [...this.scrolled];
    this.fullFrame = false; this.scrolled.clear();
    for (const element of this.observed) {
      if (!element.isConnected || !this.tracksPosition(element)) continue;
      if (full || scrolled.some(host => host.contains(element) && host !== element)) this.measure(element);
    }
  }
  tracksPosition(element) {
    return element.getAttribute('data-geometry-position') === 'true' || element.getAttribute('data-geometry-change-position') === 'true';
  }
  /** Sends each geometry event whose observable value changed. Size-only
   * consumers are deduplicated by size so moving them costs nothing. */
  measure(element) {
    if (!element?.isConnected) return;
    // A view without a layout box (an inactive tab panel, a collapsed
    // disclosure) has no geometry to report: keep the last measurement so
    // hiding and re-showing it does not re-render its whole subtree twice.
    if (element.getClientRects().length === 0) return;
    const id = element.getAttribute(this.eventId); if (!id) return;
    const names = (element.getAttribute(this.events) || '').split(',');
    const payload = measurementPayload(element, this.root);
    this.trace.measurements++;
    let sent = this.sent.get(element); if (!sent) { sent = {}; this.sent.set(element, sent); }
    const send = (name, position) => {
      if (!names.includes(name)) return;
      const key = id + '|' + (position ? payload : payloadSize(payload));
      if (sent[name] === key) return;
      sent[name] = key; this.trace.dispatches++;
      this.trace.log?.push([name, payload.split(RS, 1)[0], element.tagName + '.' + String(element.className).slice(0, 60), element.closest('[role=tabpanel]')?.id || '']);
      this.dispatch(element, name, payload);
    };
    if (element.hasAttribute('data-geometry-reader')) send('geometry', element.getAttribute('data-geometry-position') === 'true');
    if (element.hasAttribute('data-geometry-change')) send('geometryChange', element.getAttribute('data-geometry-change-position') === 'true');
    if (element.hasAttribute('data-text-layout') && names.includes('textLayout')) {
      // Measuring every grapheme is the costly part: it runs again only when the text, its size or its style changed.
      const rect = element.getBoundingClientRect();
      let styles = element.getAttribute('style') || '';
      for (const run of element.querySelectorAll('[style]:not(canvas)')) styles += '|' + run.getAttribute('style');
      const key = id + '|' + rect.width + ',' + rect.height + '|' + element.textContent + '|' + styles + '|' + paintKey(element);
      this.textKeys ||= new WeakMap();
      if (this.textKeys.get(element) !== key) {
        this.textKeys.set(element, key);
        const layout = textLayoutPayload(element);
        if (sent.textLayout !== layout) { sent.textLayout = layout; this.trace.dispatches++; this.dispatch(element, 'textLayout', layout); }
      }
    }
  }
  /** Whether `sync` can change anything after a commit with these changes. With no view observed, it observes what the patch
   * adds or changes to match the selector (a stopped match, an attribute removed from a view that was observed, is covered by
   * the changed attributes: the view no longer matches). With a view observed, every commit syncs: `sync` re-measures every view
   * after the next layout (`measureAfterLayout`), since a patch can move a view without changing its size or any attribute
   * of its own, and no observer reports a move. */
  needsSync(changes) {
    if (changes.everything || this.observed.size) return true;
    return changes.touches(this.selector()) || changes.changedAttribute(['data-geometry-reader', 'data-geometry-change', 'data-text-layout', this.eventId]);
  }
  /** After a commit or settled layout: observe new views, forget removed
   * ones and re-measure everything (positions may have moved) once the
   * browser has laid the page out.
   *
   * Measuring here, in the middle of the commit, made the browser recalculate
   * style and lay out right away for what the patch and the layout pass had
   * just written (the largest forced recalculation of a commit: 774 elements
   * on a navigation in a large app), and the frame's own rendering did it again
   * for what came after. A ResizeObserver notification arrives after the
   * frame's layout and before its paint, so the same reads cost nothing and
   * the values reach Swift in the same frame as before. */
  sync() {
    this.resizeObserver ||= new this.window.ResizeObserver(entries => this.batch(() => { for (const entry of entries) this.measure(entry.target); }));
    const added = [];
    for (const element of this.root.querySelectorAll(this.selector())) {
      if (!this.observed.has(element)) { this.observed.add(element); this.resizeObserver.observe(element); added.push(element); }
    }
    for (const element of this.observed) {
      if (!this.root.contains(element) || !element.matches(this.selector())) { this.resizeObserver.unobserve(element); this.observed.delete(element); }
    }
    if (this.observed.size) this.measureAfterLayout();
    // The views measured for the first time, whose layout may change once Swift has their size (`data-measuring`).
    return added;
  }
  /** Re-measures every observed view in the next ResizeObserver delivery: observing an element (again) always reports
   * it once, after the next layout. The reports of one delivery reach Swift as one batch. */
  measureAfterLayout() {
    if (this.measurePending) return;
    this.measurePending = true;
    this.probe ||= new this.window.ResizeObserver(() => {
      if (!this.measurePending) return;
      this.measurePending = false; this.probe.unobserve(this.root);
      this.batch(() => { for (const element of this.observed) this.measure(element); });
    });
    this.probe.observe(this.root);
  }
  /** Measures `elements` now, in one batch (the commit that inserted them, which this lays out right away). */
  measureNow(elements) { this.batch(() => { for (const element of elements) this.measure(element); }); }
  dispose() {
    this.abort.abort(); this.resizeObserver?.disconnect(); this.probe?.disconnect(); this.measurePending = false; this.observed.clear();
    if (this.frame) this.window.cancelAnimationFrame(this.frame);
  }
}
