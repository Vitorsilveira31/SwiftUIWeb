// The query language of json-server, which jsonplaceholder runs: equality filters (a repeated key is an OR), `_gte`, `_lte`, `_ne`
// and `_like` suffixes, `q` full-text search, `_sort`/`_order`, and paging by `_page`/`_limit` or `_start`/`_end`/`_limit`.

const SUFFIXES = ["_gte", "_lte", "_ne", "_like"];

function matches(item, key, values) {
  const suffix = SUFFIXES.find((candidate) => key.endsWith(candidate));
  const field = suffix ? key.slice(0, -suffix.length) : key;
  const actual = field.split(".").reduce((value, part) => value?.[part], item);
  if (actual === undefined) return false;
  const text = String(actual);
  switch (suffix) {
    case "_gte": return Number(actual) >= Number(values[0]);
    case "_lte": return Number(actual) <= Number(values[0]);
    case "_ne": return values.every((value) => text !== value);
    // Literal match: a user-supplied pattern must not compile to a backtracking regex (ReDoS).
    case "_like": return values.some((value) => text.toLowerCase().includes(value.toLowerCase()));
    default: return values.some((value) => text === value);
  }
}

const compare = (a, b) => (typeof a === "number" && typeof b === "number" ? a - b : String(a ?? "").localeCompare(String(b ?? "")));

/** Applies `params` (a URLSearchParams) to a collection. Returns the page and how many matched before paging. */
export function query(collection, params) {
  const control = new Set(["_page", "_limit", "_start", "_end", "_sort", "_order", "_embed", "_expand", "q"]);
  const filters = new Map();
  for (const [key, value] of params) if (!control.has(key)) filters.set(key, [...(filters.get(key) ?? []), value]);
  let items = collection.filter((item) => [...filters].every(([key, values]) => matches(item, key, values)));
  const search = params.get("q");
  if (search) {
    const needle = search.toLowerCase();
    items = items.filter((item) => JSON.stringify(item).toLowerCase().includes(needle));
  }
  const sorts = (params.get("_sort") ?? "").split(",").filter(Boolean);
  const orders = (params.get("_order") ?? "").split(",");
  if (sorts.length) {
    items = [...items].sort((a, b) => {
      for (const [index, field] of sorts.entries()) {
        const result = compare(a[field], b[field]) * (orders[index]?.toLowerCase() === "desc" ? -1 : 1);
        if (result !== 0) return result;
      }
      return 0;
    });
  }
  const total = items.length;
  const limit = params.has("_limit") ? Number(params.get("_limit")) : null;
  if (params.has("_page")) {
    const size = limit ?? 10, page = Math.max(1, Number(params.get("_page")));
    items = items.slice((page - 1) * size, page * size);
  } else if (params.has("_start") || params.has("_end")) {
    const start = Number(params.get("_start") ?? 0);
    items = items.slice(start, params.has("_end") ? Number(params.get("_end")) : limit !== null ? start + limit : undefined);
  } else if (limit !== null) {
    items = items.slice(0, limit);
  }
  return { items, total };
}
