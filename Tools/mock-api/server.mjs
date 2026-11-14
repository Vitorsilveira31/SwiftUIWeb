// The mock API: a jsonplaceholder-compatible service that runs on this machine. `createMockApi` returns a `fetch` handler (what the tests
// call and `Bun.serve` serves); `Tools/mock-jsonplaceholder.mjs` is the command line.
import { makeData, NESTED } from "./data.mjs";
import { image } from "./images.mjs";
import { query } from "./query.mjs";

const CORS = { "access-control-allow-origin": "*", "access-control-allow-methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS", "access-control-allow-headers": "*", "access-control-expose-headers": "X-Total-Count,Link" };
const json = (value, init = {}) => new Response(JSON.stringify(value), { ...init, headers: { "content-type": "application/json; charset=utf-8", ...CORS, ...init.headers } });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
// The nested-resource key for `parent/child`, or undefined; own keys only, so a path such as `constructor` finds nothing.
const nestedKey = (parent, child) => (Object.hasOwn(NESTED, parent) && Object.hasOwn(NESTED[parent], child) ? NESTED[parent][child] : undefined);

/**
 * @param {{ seed?: number, persist?: boolean, delay?: number, upstream?: string }} options
 *   persist: writes (POST, PUT, PATCH, DELETE) change the data in memory until the process ends; the real service accepts them and forgets.
 *   upstream: a base URL (https://jsonplaceholder.typicode.com) that answers the data routes, while the pictures stay local.
 */
export function createMockApi({ seed, persist = false, delay = 0, upstream = "" } = {}) {
  const data = makeData(seed);
  const nextId = Object.fromEntries(Object.entries(data).map(([name, items]) => [name, items.length + 1]));

  async function proxy(request, url) {
    const target = new URL(url.pathname + url.search, upstream);
    const response = await fetch(target, { method: request.method, headers: { "content-type": request.headers.get("content-type") ?? "application/json" }, body: ["GET", "HEAD"].includes(request.method) ? undefined : await request.text() });
    return new Response(response.body, { status: response.status, headers: { "content-type": response.headers.get("content-type") ?? "application/json", "x-total-count": response.headers.get("x-total-count") ?? "", ...CORS } });
  }

  function listing(name, url, scope) {
    const params = new URLSearchParams(url.searchParams);
    for (const [field, value] of Object.entries(scope)) params.set(field, value);
    let { items, total } = query(data[name], params);
    const embed = params.getAll("_embed"), expand = params.getAll("_expand");
    if (embed.length || expand.length) {
      items = items.map((item) => {
        const copy = { ...item };
        for (const child of embed) { const key = nestedKey(name, child); if (key) copy[child] = data[child].filter((other) => other[key] === item.id); }
        for (const parent of expand) { const owner = Object.hasOwn(data, `${parent}s`) ? data[`${parent}s`].find((other) => other.id === item[`${parent}Id`]) : undefined; if (owner) copy[parent] = owner; }
        return copy;
      });
    }
    return json(items, { headers: { "x-total-count": String(total) } });
  }

  async function write(request, name, id) {
    const body = request.method === "DELETE" ? {} : await request.json().catch(() => ({}));
    const collection = data[name];
    const index = id === null ? -1 : collection.findIndex((item) => item.id === id);
    if (request.method === "POST") {
      const created = { ...body, id: nextId[name] };
      if (persist) { collection.push(created); nextId[name] += 1; }
      return json(created, { status: 201 });
    }
    if (index < 0) return json({}, { status: 404 });
    if (request.method === "DELETE") { if (persist) collection.splice(index, 1); return json({}); }
    const updated = request.method === "PUT" ? { ...body, id } : { ...collection[index], ...body, id };
    if (persist) collection[index] = updated;
    return json(updated);
  }

  return async function handle(request) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (delay > 0) await sleep(delay);
    const picture = request.method === "GET" ? image(url.pathname, url.searchParams) : null;
    if (picture) { for (const [key, value] of Object.entries(CORS)) picture.headers.set(key, value); return picture; }
    const segments = url.pathname.split("/").filter(Boolean);
    const [name, rawId, child] = segments;
    if (!name) return json({ resources: Object.fromEntries(Object.entries(data).map(([resource, items]) => [resource, `/${resource} (${items.length})`])), images: ["/images/photo/:n.svg", "/images/thumb/:n.svg", "/images/cover/:n.svg", "/images/avatar/:n.svg"] });
    // Own keys only: `constructor` or `__proto__` in the path must not reach Object.prototype.
    if (!Object.hasOwn(data, name) || segments.length > 3) return json({}, { status: 404 });
    if (upstream) return proxy(request, url);
    const id = rawId === undefined ? null : Number(rawId);
    if (rawId !== undefined && !Number.isInteger(id)) return json({}, { status: 404 });
    if (request.method !== "GET") return segments.length > 2 ? json({}, { status: 404 }) : write(request, name, id);
    if (child) {
      const key = nestedKey(name, child);
      return key ? listing(child, url, { [key]: String(id) }) : json({}, { status: 404 });
    }
    if (id === null) return listing(name, url, {});
    const found = data[name].find((item) => item.id === id);
    return found ? json(found) : json({}, { status: 404 });
  };
}
