#!/usr/bin/env bun
// A jsonplaceholder-compatible API on this machine, for the example apps (Tools/mock-api/). The launcher starts it and the dev server
// forwards `/api` to it, so an app calls `/api/posts` on its own origin.
//
//   bun Tools/mock-jsonplaceholder.mjs [--port 8090] [--persist] [--delay 150] [--upstream https://jsonplaceholder.typicode.com]
//
// Resources: /posts /comments /albums /photos /todos /users, nested routes (/posts/1/comments), json-server queries (_page, _limit, _sort,
// _order, _embed, _expand, q, field filters), writes, and pictures under /images/ (photo, thumb, cover, avatar). With --upstream the data
// routes are answered by that service and only the pictures are local.
import { parseArgs } from "node:util";
import { createMockApi } from "./mock-api/server.mjs";

if (import.meta.main) {
  const { values } = parseArgs({ options: { port: { type: "string", default: "8090" }, persist: { type: "boolean", default: false }, delay: { type: "string", default: "0" }, upstream: { type: "string", default: "" }, seed: { type: "string" } } });
  const handle = createMockApi({ seed: values.seed ? Number(values.seed) : undefined, persist: values.persist, delay: Number(values.delay), upstream: values.upstream });
  const server = Bun.serve({ port: Number(values.port), hostname: "127.0.0.1", fetch: handle });
  console.log(`Mock API on http://127.0.0.1:${server.port}${values.upstream ? ` (data from ${values.upstream})` : ""}${values.persist ? ", writes kept in memory" : ""}`);
}
