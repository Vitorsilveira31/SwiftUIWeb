import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { stage } from "./cloudflare-site/stage.mjs";

function bundle(files) {
  const root = mkdtempSync(join(tmpdir(), "cloudflare-site-"));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(join(root, "bundle", path, ".."), { recursive: true });
    writeFileSync(join(root, "bundle", path), text);
  }
  return root;
}

describe("Cloudflare site staging", () => {
  test("copies the bundle with the brotli copies worker.js serves, without other compressed copies, logs or dotfiles, and adds _headers", () => {
    const root = bundle({
      "index.html": "<!doctype html>",
      "index.html.br": "br",
      "app.0123abcd.wasm": "wasm",
      "app.0123abcd.wasm.br": "br",
      "app.0123abcd.wasm.gz": "gz",
      [`app.0123abcd.wasm.${"a".repeat(64)}.dcb`]: "a difference file of a staged module",
      [`app.99999999.wasm.${"b".repeat(64)}.dcb`]: "a difference file whose module is not in the bundle",
      "index.0123abcd.js": "js",
      "index.0123abcd.js.br": "br",
      "index.0123abcd.js.gz": "gz",
      "style.0123abcd.css.br": "a copy without its file",
      "swift-build.log": "log",
      ".bundle-inputs": "fingerprint",
      "fonts/icons.0123abcd.woff2": "font",
    });
    const copied = stage(join(root, "bundle"), join(root, "public"));
    expect(copied).toEqual(["app.0123abcd.wasm", `app.0123abcd.wasm.${"a".repeat(64)}.dcb`, "app.0123abcd.wasm.br","fonts/icons.0123abcd.woff2", "index.0123abcd.js", "index.0123abcd.js.br", "index.html"]);
    expect(readFileSync(join(root, "public", "app.0123abcd.wasm.br"), "utf8")).toBe("br");
    expect(existsSync(join(root, "public", `app.99999999.wasm.${"b".repeat(64)}.dcb`))).toBe(false);
    expect(existsSync(join(root, "public", "index.html.br"))).toBe(false);
    expect(existsSync(join(root, "public", "style.0123abcd.css.br"))).toBe(false);
    expect(existsSync(join(root, "public", "swift-build.log"))).toBe(false);
    expect(readFileSync(join(root, "public", "_headers"), "utf8")).toContain("frame-ancestors 'none'");
  });

  test("replaces what an earlier stage left", () => {
    const root = bundle({ "index.html": "<!doctype html>", "app.0123abcd.wasm": "wasm" });
    mkdirSync(join(root, "public"));
    writeFileSync(join(root, "public", "app.old00000.wasm"), "old");
    stage(join(root, "bundle"), join(root, "public"));
    expect(existsSync(join(root, "public", "app.old00000.wasm"))).toBe(false);
  });

  test("refuses a folder that is not a built bundle", () => {
    const root = bundle({ "index.html": "<!doctype html>" });
    expect(() => stage(join(root, "bundle"), join(root, "public"))).toThrow("no .wasm");
    expect(() => stage(join(root, "missing"), join(root, "public"))).toThrow("no index.html");
  });
});
