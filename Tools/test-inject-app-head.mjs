#!/usr/bin/env bun
// Tests for Tools/inject-app-head.mjs.
// Run: bun test ./Tools/test-inject-app-head.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import * as mod from "./inject-app-head.mjs";

const SCRIPT = fileURLToPath(new URL("./inject-app-head.mjs", import.meta.url));

function withBundle(run) {
  const dir = mkdtempSync(join(tmpdir(), "inject-app-head-test-"));
  try {
    return run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const TEMPLATE = '<!doctype html>\n<head>\n  <link rel="stylesheet" href="./styles.css">\n</head>\n';

function writeIndex(bundle, html = TEMPLATE) {
  writeFileSync(join(bundle, "index.html"), html);
}

function readIndex(bundle) {
  return readFileSync(join(bundle, "index.html"), "utf8");
}

describe("inject-app-head", () => {
  test("an application's Content-Security-Policy replaces the template's", () => {
    withBundle((bundle) => {
      writeIndex(bundle, '<!doctype html>\n<head>\n  <meta http-equiv="Content-Security-Policy" content="script-src \'self\' __INLINE_SCRIPT_HASHES__">\n  <link rel="stylesheet" href="./styles.css">\n</head>\n');
      writeFileSync(join(bundle, "head.html"), '<meta http-equiv="Content-Security-Policy" content="default-src \'self\'; script-src \'self\' https://cdn.example">\n');
      assert.equal(mod.inject(bundle), true);
      const html = readIndex(bundle);
      assert.equal((html.match(/Content-Security-Policy/g) ?? []).length, 1, html);
      assert.ok(html.includes("https://cdn.example") && !html.includes("__INLINE_SCRIPT_HASHES__"), html);
    });
  });

  test("a commented-out Content-Security-Policy keeps the template's", () => {
    withBundle((bundle) => {
      writeIndex(bundle, '<!doctype html>\n<head>\n  <meta http-equiv="Content-Security-Policy" content="script-src \'self\' __INLINE_SCRIPT_HASHES__">\n  <link rel="stylesheet" href="./styles.css">\n</head>\n');
      writeFileSync(join(bundle, "head.html"), '<!-- <meta http-equiv="Content-Security-Policy" content="default-src *"> -->\n<!-- <title>Old</title>\n');
      assert.equal(mod.inject(bundle), true);
      const html = readIndex(bundle);
      assert.ok(html.includes("__INLINE_SCRIPT_HASHES__"), html);
      assert.equal((html.match(/http-equiv="Content-Security-Policy"/g) ?? []).length, 2, html);
    });
  });

  test("injects the whole hook after styles.css with the exact layout", () => {
    withBundle((bundle) => {
      writeIndex(bundle);
      writeFileSync(join(bundle, "head.html"), '<title>App</title>\n<meta name="theme-color" content="#123456">\n');
      writeFileSync(join(bundle, "catalog-assets.css"), ":root {}\n");
      writeFileSync(join(bundle, "app.css"), "body {}\n");
      writeFileSync(
        join(bundle, "runtime-environment"),
        "SWIFTUIWEB_LANGUAGE=pt\nSWIFTUIWEB_IMAGE_ASSETS=A&B=\"<c>\"'s=catalog-assets/a.svg\n",
      );
      assert.equal(mod.inject(bundle), true);
      assert.equal(
        readIndex(bundle),
        '<!doctype html>\n<head>\n  <link rel="stylesheet" href="./styles.css">\n' +
          "  <!-- app-head -->\n" +
          "  <title>App</title>\n" +
          '  <meta name="theme-color" content="#123456">\n' +
          '  <link rel="stylesheet" href="./catalog-assets.css">\n' +
          '  <meta name="runtime-environment" content="SWIFTUIWEB_LANGUAGE=pt">\n' +
          '  <meta name="runtime-environment" content="SWIFTUIWEB_IMAGE_ASSETS=A&amp;B=&quot;&lt;c&gt;&quot;&#x27;s=catalog-assets/a.svg">\n' +
          '  <link rel="stylesheet" href="./app.css">\n' +
          "  <!-- /app-head -->\n" +
          "</head>\n",
      );
    });
  });

  test("running twice is idempotent and leaves one copy of each hook", () => {
    withBundle((bundle) => {
      writeIndex(bundle);
      writeFileSync(join(bundle, "app.css"), "body {}\n");
      mod.inject(bundle);
      const once = readIndex(bundle);
      assert.equal(mod.inject(bundle), true);
      assert.equal(readIndex(bundle), once);
      assert.equal(once.split("<!-- app-head -->").length - 1, 1);
      assert.equal(once.split('href="./app.css"').length - 1, 1);
    });
  });

  test("template title and theme-color are replaced by the fragment's", () => {
    withBundle((bundle) => {
      writeIndex(
        bundle,
        '<!doctype html>\n<head>\n  <title>Template</title>\n  <meta name="theme-color" content="#000000">\n' +
          '  <link rel="stylesheet" href="./styles.css">\n</head>\n',
      );
      writeFileSync(join(bundle, "head.html"), '<title>App</title>\n<meta name="theme-color" content="#ffffff">\n');
      mod.inject(bundle);
      const html = readIndex(bundle);
      assert.equal(html.includes("Template"), false, "the template title is removed");
      assert.equal(html.includes("#000000"), false, "the template theme-color is removed");
      assert.equal(html.includes("<title>App</title>"), true);
      assert.equal(html.includes('content="#ffffff"'), true);
    });
  });

  test("template theme-color is kept when the fragment does not declare one", () => {
    withBundle((bundle) => {
      writeIndex(
        bundle,
        '<!doctype html>\n<head>\n  <title>Template</title>\n  <meta name="theme-color" content="#000000">\n' +
          '  <link rel="stylesheet" href="./styles.css">\n</head>\n',
      );
      writeFileSync(join(bundle, "app.css"), "");
      mod.inject(bundle);
      const html = readIndex(bundle);
      assert.equal(html.includes("<title>Template</title>"), true);
      assert.equal(html.includes('content="#000000"'), true);
    });
  });

  test("catalog-assets.css is linked before app.css and the environment metas sit between them", () => {
    withBundle((bundle) => {
      writeIndex(bundle);
      writeFileSync(join(bundle, "catalog-assets.css"), ":root {}\n");
      writeFileSync(join(bundle, "app.css"), "");
      writeFileSync(join(bundle, "runtime-environment"), "SWIFTUIWEB_IMAGE_ASSETS=Dot=catalog-assets/dot.png\n");
      mod.inject(bundle);
      const html = readIndex(bundle);
      const assets = html.indexOf('href="./catalog-assets.css"');
      const meta = html.indexOf('<meta name="runtime-environment"');
      const app = html.indexOf('href="./app.css"');
      assert.ok(assets > 0 && assets < meta && meta < app, "catalog-assets, runtime metas, app.css in order");
    });
  });

  test("environment metas are HTML-escaped and only lines with '=' are kept", () => {
    withBundle((bundle) => {
      writeIndex(bundle);
      writeFileSync(
        join(bundle, "runtime-environment"),
        "\n  no equals here  \nKEY=<a>&'\"</a>\n",
      );
      writeFileSync(join(bundle, "app.css"), "");
      mod.inject(bundle);
      const html = readIndex(bundle);
      assert.ok(html.includes('content="KEY=&lt;a&gt;&amp;&#x27;&quot;&lt;/a&gt;"'));
      assert.equal(html.includes("no equals here"), false);
      assert.equal(html.split('name="runtime-environment"').length - 1, 1);
    });
  });

  test("a fragment without <title> or theme-color leaves the template's untouched", () => {
    withBundle((bundle) => {
      writeIndex(bundle, '<!doctype html>\n<head>\n  <title>Keep</title>\n  <link rel="stylesheet" href="./styles.css">\n</head>\n');
      writeFileSync(join(bundle, "head.html"), '<link rel="icon" href="./icon.svg">\n');
      mod.inject(bundle);
      assert.equal(readIndex(bundle).includes("<title>Keep</title>"), true);
    });
  });

  test("without styles.css the block goes right before </head>", () => {
    withBundle((bundle) => {
      writeIndex(bundle, "<!doctype html>\n<head>\n</head>\n");
      writeFileSync(join(bundle, "app.css"), "");
      mod.inject(bundle);
      assert.equal(
        readIndex(bundle),
        '<!doctype html>\n<head>\n  <!-- app-head -->\n  <link rel="stylesheet" href="./app.css">\n  <!-- /app-head -->\n</head>\n',
      );
    });
  });

  test("CRLF index is read with universal newlines", () => {
    withBundle((bundle) => {
      writeIndex(bundle, '<head>\r\n  <link rel="stylesheet" href="./styles.css">\r\n</head>\r\n');
      writeFileSync(join(bundle, "app.css"), "");
      mod.inject(bundle);
      assert.equal(readIndex(bundle).includes("\r"), false);
    });
  });

  test("no-op when there is nothing to inject", () => {
    withBundle((bundle) => {
      writeIndex(bundle);
      assert.equal(mod.inject(bundle), false);
      assert.equal(readIndex(bundle), TEMPLATE);
    });
  });

  test("no-op without an index.html", () => {
    withBundle((bundle) => {
      writeFileSync(join(bundle, "app.css"), "");
      assert.equal(mod.inject(bundle), false);
    });
  });

  test("usage error exits with code 2", () => {
    const none = spawnSync(process.execPath, [SCRIPT], { encoding: "utf8" });
    assert.equal(none.status, 2);
    assert.equal(none.stderr, "usage: inject-app-head.mjs <bundle-directory>\n");
    assert.equal(none.stdout, "");
    const extra = spawnSync(process.execPath, [SCRIPT, "a", "b"], { encoding: "utf8" });
    assert.equal(extra.status, 2);
  });

  test("the CLI reports the injection on stdout", () => {
    withBundle((bundle) => {
      writeIndex(bundle);
      writeFileSync(join(bundle, "app.css"), "");
      const run = spawnSync(process.execPath, [SCRIPT, bundle], { encoding: "utf8" });
      assert.equal(run.status, 0);
      assert.equal(run.stdout, "Injected application document head hook\n");
      const again = spawnSync(process.execPath, [SCRIPT, bundle], { encoding: "utf8" });
      assert.equal(again.status, 0);
      assert.equal(again.stdout, "Injected application document head hook\n");
    });
  });
});
