// Pictures made on the spot for the mock API, so the example apps need no image host: `/images/photo/12.svg` is a landscape of
// layered hills, a sun and a sky, and `/images/avatar/3.svg` a gradient with a soft shape. The same number always draws the same picture.
import { random } from "./data.mjs";

const hsl = (h, s, l) => `hsl(${Math.round(h)} ${Math.round(s)}% ${Math.round(l)}%)`;

function palette(rand) {
  const hue = rand() * 360;
  return { hue, sky: [hsl(hue, 70, 78), hsl(hue + 40, 75, 66)], hills: [hsl(hue + 160, 35, 38), hsl(hue + 190, 40, 30), hsl(hue + 220, 45, 22)], sun: hsl(hue + 25, 95, 88) };
}

/** A landscape of `width` by `height`. */
export function photo(id, width = 900, height = 900) {
  const rand = random(id * 7919);
  const colors = palette(rand);
  const hills = colors.hills.map((fill, layer) => {
    const base = height * (0.55 + layer * 0.15), amplitude = height * (0.12 - layer * 0.02), phase = rand() * Math.PI * 2;
    const points = Array.from({ length: 13 }, (_, step) => `${(width / 12) * step},${(base + Math.sin(phase + step * (0.7 + layer * 0.2)) * amplitude).toFixed(1)}`);
    return `<polygon points="0,${height} ${points.join(" ")} ${width},${height}" fill="${fill}"/>`;
  });
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img">
<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${colors.sky[0]}"/><stop offset="1" stop-color="${colors.sky[1]}"/></linearGradient></defs>
<rect width="${width}" height="${height}" fill="url(#sky)"/>
<circle cx="${(width * (0.2 + rand() * 0.6)).toFixed(0)}" cy="${(height * (0.2 + rand() * 0.2)).toFixed(0)}" r="${(Math.min(width, height) * (0.07 + rand() * 0.06)).toFixed(0)}" fill="${colors.sun}"/>
${hills.join("\n")}
</svg>`;
}

/** A round-friendly square: a gradient with two soft shapes. */
export function avatar(id, size = 128) {
  const rand = random(id * 104729);
  const colors = palette(rand);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" role="img">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${colors.sky[0]}"/><stop offset="1" stop-color="${colors.hills[0]}"/></linearGradient></defs>
<rect width="${size}" height="${size}" fill="url(#g)"/>
<circle cx="${size * 0.5}" cy="${size * 0.4}" r="${size * 0.2}" fill="${colors.sun}" opacity="0.9"/>
<ellipse cx="${size * 0.5}" cy="${size * 0.92}" rx="${size * 0.36}" ry="${size * 0.3}" fill="${colors.sun}" opacity="0.85"/>
</svg>`;
}

/** Routes under `/images/`: `photo`, `thumb`, `cover` (wide) and `avatar`, each `<kind>/<number>.svg`. Null when the path is not one. */
export function image(pathname, params) {
  const match = /^\/images\/(photo|thumb|cover|avatar)\/(\d+)\.svg$/.exec(pathname);
  if (!match) return null;
  const [, kind, number] = match, id = Number(number);
  const size = (name, fallback) => Math.min(2400, Math.max(16, Number(params.get(name)) || fallback));
  const body = kind === "photo" ? photo(id, size("w", 900), size("h", 900))
    : kind === "thumb" ? photo(id, 150, 150)
    : kind === "cover" ? photo(id, size("w", 1500), size("h", 500))
    : avatar(id, size("size", 128));
  return new Response(body, { headers: { "content-type": "image/svg+xml", "cache-control": "public, max-age=86400" } });
}
