// Run: bun test ./Tools/test-patch-browser-index.mjs
// Covers patch-browser-index.mjs: every occurrence is replaced, the showcase bootstrap check
// refuses to write, and CRLF input is written back with LF newlines.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { embeddedBootstrap, showcaseHost } from "./patch-browser-index.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "patch-browser-index.mjs");
const BOOTSTRAP = 'const { init } = await import(new URL("./index.js", document.baseURI).href);';
const EMBEDDED = 'const { instantiate: init } = await import(new URL("./index.js", document.baseURI).href);';
const INIT = "await init(undefined, { performanceDiagnostics })";

test("embedded-bootstrap rewrites every bootstrap import and leaves the rest of the bytes alone", () => {
  const text = `<script>\n${BOOTSTRAP}\n${BOOTSTRAP}\n</script>\n`;
  assert.equal(embeddedBootstrap(text), `<script>\n${EMBEDDED}\n${EMBEDDED}\n</script>\n`);
  assert.equal(embeddedBootstrap("no bootstrap here\r\n"), "no bootstrap here\r\n");
});

test("showcase-host inserts both links before every </head> and mounts the documentation host", () => {
  const text = `<head></head>\n${INIT}\n<head>x</head>\n`;
  const patched = showcaseHost(text);
  assert.equal(patched.split('href="./showcase.css"').length - 1, 2);
  assert.ok(patched.includes(`plugins: [(await import("./showcase-host.js")).mountShowcaseHost] })`));
  assert.ok(!patched.includes(`${INIT}\n`));
});

test("showcase-host refuses a changed bootstrap with the launcher's message", () => {
  assert.throws(() => showcaseHost("<head></head>\nawait init()\n"), (error) => {
    assert.equal(error.message, "Showcase bootstrap changed: cannot mount the documentation host");
    return true;
  });
});

test("the command edits the file in place and leaves it untouched when the bootstrap check fails", () => {
  const directory = mkdtempSync(join(tmpdir(), "swui-index-"));
  try {
    const good = join(directory, "good.html");
    writeFileSync(good, `<html><head>\n</head>${BOOTSTRAP}\n</html>\r\n`);
    const ok = spawnSync(process.execPath, [SCRIPT, "embedded-bootstrap", good], { encoding: "utf8" });
    assert.equal(ok.status, 0, ok.stderr);
    assert.equal(readFileSync(good, "utf8"), `<html><head>\n</head>${EMBEDDED}\n</html>\n`);

    const bad = join(directory, "bad.html");
    const original = "<head></head>\nno init here\n";
    writeFileSync(bad, original);
    const refused = spawnSync(process.execPath, [SCRIPT, "showcase-host", bad], { encoding: "utf8" });
    assert.equal(refused.status, 1);
    assert.equal(refused.stderr, "Showcase bootstrap changed: cannot mount the documentation host\n");
    assert.equal(readFileSync(bad, "utf8"), original);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("an unknown subcommand is a usage error", () => {
  const result = spawnSync(process.execPath, [SCRIPT, "nope", "x.html"], { encoding: "utf8" });
  assert.equal(result.status, 2);
});
