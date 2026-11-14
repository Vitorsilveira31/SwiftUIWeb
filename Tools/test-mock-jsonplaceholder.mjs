// Run with: bun test ./Tools/test-mock-jsonplaceholder.mjs
import { describe, expect, test } from "bun:test";
import { createMockApi } from "./mock-api/server.mjs";

const call = async (api, path, init) => {
  const response = await api(new Request(`http://mock.test${path}`, init));
  const type = response.headers.get("content-type") ?? "";
  return { status: response.status, headers: response.headers, body: type.includes("json") ? await response.json() : await response.text() };
};
const write = (method, body) => ({ method, headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

describe("the resources have jsonplaceholder's counts and shapes", () => {
  const api = createMockApi();
  test("counts", async () => {
    for (const [path, count] of [["/users", 10], ["/posts", 100], ["/comments", 500], ["/albums", 100], ["/photos", 5000], ["/todos", 200]]) {
      expect((await call(api, path)).headers.get("x-total-count")).toBe(String(count));
    }
  });
  test("a user, a post and a photo have the real fields", async () => {
    const user = (await call(api, "/users/1")).body;
    expect(Object.keys(user)).toEqual(["id", "name", "username", "email", "address", "phone", "website", "company"]);
    expect(Object.keys(user.address)).toEqual(["street", "suite", "city", "zipcode", "geo"]);
    expect(Object.keys((await call(api, "/posts/1")).body)).toEqual(["userId", "id", "title", "body"]);
    expect(Object.keys((await call(api, "/photos/1")).body)).toEqual(["albumId", "id", "title", "url", "thumbnailUrl"]);
  });
  test("the same seed makes the same data", async () => {
    expect((await call(createMockApi(), "/posts/7")).body).toEqual((await call(createMockApi(), "/posts/7")).body);
  });
  test("hostile resource names and _like patterns are answered, not thrown", async () => {
    const api = createMockApi();
    expect((await call(api, "/constructor")).status).toBe(404);
    expect((await call(api, "/__proto__/1")).status).toBe(404);
    expect((await call(api, "/users/1/constructor")).status).toBe(404);
    expect((await call(api, "/users?name_like=(a+)+$")).status).toBe(200);
  });
});


describe("routes and queries", () => {
  const api = createMockApi();
  test("nested routes", async () => {
    const comments = (await call(api, "/posts/3/comments")).body;
    expect(comments).toHaveLength(5);
    expect(comments.every((comment) => comment.postId === 3)).toBe(true);
    expect((await call(api, "/users/2/albums")).body).toHaveLength(10);
    expect((await call(api, "/albums/4/photos")).body).toHaveLength(50);
  });
  test("filters, repeated keys, paging and sorting", async () => {
    expect((await call(api, "/posts?userId=2")).body).toHaveLength(10);
    expect((await call(api, "/posts?id=1&id=5")).body.map((post) => post.id)).toEqual([1, 5]);
    const page = await call(api, "/posts?_page=3&_limit=10");
    expect(page.body.map((post) => post.id)).toEqual([21, 22, 23, 24, 25, 26, 27, 28, 29, 30]);
    expect(page.headers.get("x-total-count")).toBe("100");
    expect((await call(api, "/posts?_sort=id&_order=desc&_limit=2")).body.map((post) => post.id)).toEqual([100, 99]);
    expect((await call(api, "/todos?userId=1&completed=true")).body.every((todo) => todo.completed)).toBe(true);
    expect((await call(api, "/posts?id_gte=98")).body).toHaveLength(3);
    expect((await call(api, "/posts?_start=2&_end=4")).body.map((post) => post.id)).toEqual([3, 4]);
  });
  test("full-text search, embed and expand", async () => {
    const hits = (await call(api, "/posts?q=lighthouse")).body;
    expect(hits.length).toBeGreaterThan(0);
    expect(hits.every((post) => JSON.stringify(post).toLowerCase().includes("lighthouse"))).toBe(true);
    expect((await call(api, "/posts?id=1&_embed=comments")).body[0].comments).toHaveLength(5);
    expect((await call(api, "/posts?id=1&_expand=user")).body[0].user.id).toBe(1);
  });
  test("unknown routes are 404", async () => {
    expect((await call(api, "/nothing")).status).toBe(404);
    expect((await call(api, "/posts/9999")).status).toBe(404);
    expect((await call(api, "/posts/abc")).status).toBe(404);
    expect((await call(api, "/posts/1/likes")).status).toBe(404);
  });
  test("every answer allows cross-origin reads, and OPTIONS is answered", async () => {
    expect((await call(api, "/posts/1")).headers.get("access-control-allow-origin")).toBe("*");
    expect((await call(api, "/posts", { method: "OPTIONS" })).status).toBe(204);
  });
});

describe("writes", () => {
  test("by default they are answered and forgotten, as on the real service", async () => {
    const api = createMockApi();
    const created = await call(api, "/comments", write("POST", { body: "hi", postId: 1 }));
    expect(created.status).toBe(201);
    expect(created.body).toEqual({ body: "hi", postId: 1, id: 501 });
    expect((await call(api, "/comments")).headers.get("x-total-count")).toBe("500");
    expect((await call(api, "/posts/1", write("PATCH", { title: "x" }))).body.title).toBe("x");
    expect((await call(api, "/posts/1")).body.title).not.toBe("x");
  });
  test("with persist they change the data until the process ends", async () => {
    const api = createMockApi({ persist: true });
    expect((await call(api, "/comments", write("POST", { body: "hi", postId: 1 }))).body.id).toBe(501);
    expect((await call(api, "/comments")).headers.get("x-total-count")).toBe("501");
    expect((await call(api, "/comments", write("POST", { body: "again", postId: 1 }))).body.id).toBe(502);
    expect((await call(api, "/posts/1", write("PUT", { title: "only" }))).body).toEqual({ title: "only", id: 1 });
    expect((await call(api, "/posts/1")).body).toEqual({ title: "only", id: 1 });
    expect((await call(api, "/posts/1", { method: "DELETE" })).status).toBe(200);
    expect((await call(api, "/posts/1")).status).toBe(404);
  });
});

describe("pictures", () => {
  const api = createMockApi();
  test("a photo, a thumbnail, a cover and an avatar are SVG, the same each time", async () => {
    for (const path of ["/images/photo/12.svg", "/images/thumb/12.svg", "/images/cover/3.svg?w=1200&h=400", "/images/avatar/5.svg?size=64"]) {
      const first = await call(api, path);
      expect(first.status).toBe(200);
      expect(first.headers.get("content-type")).toBe("image/svg+xml");
      expect(first.body.startsWith("<svg")).toBe(true);
      expect((await call(api, path)).body).toBe(first.body);
    }
    expect((await call(api, "/images/photo/1.svg")).body).not.toBe((await call(api, "/images/photo/2.svg")).body);
    expect((await call(api, "/images/photo/abc.svg")).status).toBe(404);
  });
  test("a photo's url points at a picture the mock serves", async () => {
    const photo = (await call(api, "/photos/9")).body;
    expect((await call(api, photo.url)).status).toBe(200);
    expect((await call(api, photo.thumbnailUrl)).status).toBe(200);
  });
});

describe("--upstream", () => {
  test("data routes go to the upstream, pictures stay local", async () => {
    const seen = [];
    const original = globalThis.fetch;
    globalThis.fetch = async (url, init) => { seen.push(String(url)); return new Response(JSON.stringify([{ id: 1 }]), { headers: { "content-type": "application/json", "x-total-count": "1" } }); };
    try {
      const api = createMockApi({ upstream: "https://upstream.test" });
      const posts = await call(api, "/posts?userId=1");
      expect(posts.body).toEqual([{ id: 1 }]);
      expect(seen).toEqual(["https://upstream.test/posts?userId=1"]);
      expect((await call(api, "/images/avatar/1.svg")).status).toBe(200);
      expect(seen).toHaveLength(1);
    } finally { globalThis.fetch = original; }
  });
});

describe("through the dev server's /api proxy", () => {
  test("an app reads the data and the pictures on its own origin", async () => {
    const { mkdtempSync, writeFileSync } = await import("node:fs");
    const { tmpdir } = await import("node:os");
    const { join } = await import("node:path");
    const root = mkdtempSync(join(tmpdir(), "mock-proxy-"));
    writeFileSync(join(root, "index.html"), "<!doctype html><title>app</title>");
    const mock = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: createMockApi({ persist: true }) });
    const probe = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: () => new Response("") });
    const port = probe.port;
    probe.stop(true);
    const server = Bun.spawn(["bun", join(import.meta.dir, "bun-server.ts"), root, String(port)], {
      env: { ...process.env, PORT: String(port), SWIFTUIWEB_API_ORIGIN: `http://127.0.0.1:${mock.port}`, SWIFTUIWEB_API_PATH: "/api" },
      stdout: "ignore", stderr: "ignore",
    });
    try {
      let up = false;
      for (let attempt = 0; attempt < 50 && !up; attempt += 1) {
        up = await fetch(`http://127.0.0.1:${port}/`).then((response) => response.ok, () => false);
        if (!up) await new Promise((resolve) => setTimeout(resolve, 100));
      }
      expect(up).toBe(true);
      const posts = await (await fetch(`http://127.0.0.1:${port}/api/posts?_limit=2`)).json();
      expect(posts.map((post) => post.id)).toEqual([1, 2]);
      const picture = await fetch(`http://127.0.0.1:${port}/api/images/photo/4.svg`);
      expect(picture.headers.get("content-type")).toBe("image/svg+xml");
      const created = await fetch(`http://127.0.0.1:${port}/api/comments`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ postId: 1, body: "hello" }) });
      expect(created.status).toBe(201);
    } finally {
      server.kill();
      mock.stop(true);
    }
  });
});
