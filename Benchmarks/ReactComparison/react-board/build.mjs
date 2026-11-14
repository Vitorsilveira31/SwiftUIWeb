// Builds the React board for production into dist/: one minified bundle, the stylesheet and index.html. Then it does what a
// SwiftUIWeb release bundle gets (Tools/hash-release-bundle.mjs, Tools/precompress-bundle.mjs): the scripts and styles get
// content-hashed names, so the server caches them for a year, and precompressed copies, so both sides send the same bytes.
import { cpSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

rmSync("dist", { recursive: true, force: true });
mkdirSync("dist", { recursive: true });
const result = await Bun.build({
  entrypoints: ["src/main.jsx"],
  outdir: "dist",
  minify: true,
  target: "browser",
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
});
if (!result.success) {
  for (const log of result.logs) console.error(log);
  process.exit(1);
}
cpSync("src/style.css", "dist/style.css");
writeFileSync(
  "dist/index.html",
  `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n<title>Works board (React)</title>\n<link rel="stylesheet" href="./style.css">\n</head>\n<body>\n<div id="root"></div>\n<script type="module" src="./main.js"></script>\n</body>\n</html>\n`,
);
const tools = new URL("../../../Tools/", import.meta.url);
const bundle = new URL("dist/", import.meta.url).pathname;
for (const tool of ["hash-release-bundle.mjs", "precompress-bundle.mjs"]) {
  const step = spawnSync("bun", [new URL(tool, tools).pathname, bundle], { stdio: "inherit" });
  if (step.status !== 0) process.exit(step.status ?? 1);
}
console.log("React board built into dist/");
