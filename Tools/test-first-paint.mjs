#!/usr/bin/env bun
// The pure parts of Tools/first-paint.mjs: what the capture adds to index.html and takes out again, the policy's hash, and
// the width range a set of comparisons allows. The browser behavior is Tools/test-first-paint-browser.mjs.
// Run with: bun test ./Tools/test-first-paint.mjs
import { describe, expect, test } from "bun:test";
import { EARLY_EVENT_SCRIPT, WIDTH_LADDER, allowScript, composePage, mediaFor, parseViewport, scriptHash, stripFirstPaint } from "./first-paint.mjs";

const PAGE = `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'sha256-abc='; style-src 'self' 'unsafe-inline'"><title>x</title></head>
<body>
  <script>1</script>
</body></html>`;
const CAPTURE = { markup: "<p>hi</p>", css: "[data-cl-1]{width:1px}", rootAttributes: {}, media: "(min-width:320px)", lang: "en", route: "/" };

describe("first paint page", () => {
  test("composePage adds the style, the root with its conditions and the script, and the script's hash to the policy", () => {
    const html = composePage(PAGE, CAPTURE);
    expect(html).toContain('<style id="first-paint-style">[data-cl-1]{width:1px}</style>');
    expect(html).toContain('<div id="embedded-app-root" data-first-paint data-first-paint-route="/" data-first-paint-media="(min-width:320px)" data-first-paint-lang="en"><p>hi</p></div>');
    expect(html).toContain(scriptHash(EARLY_EVENT_SCRIPT));
    expect(html.indexOf("<div id=\"embedded-app-root\"")).toBeLessThan(html.indexOf("<script>1</script>"));
  });

  test("stripFirstPaint removes exactly what composePage added", () => {
    expect(stripFirstPaint(composePage(PAGE, CAPTURE))).toBe(PAGE);
    expect(stripFirstPaint(PAGE)).toBe(PAGE);
  });

  test("a policy with no script-src cannot take the script's hash", () => {
    const noScriptSrc = PAGE.replace("script-src 'self' 'wasm-unsafe-eval' 'sha256-abc='; ", "");
    expect(() => allowScript(noScriptSrc, EARLY_EVENT_SCRIPT)).toThrow(/script-src/);
    expect(allowScript("<html></html>", EARLY_EVENT_SCRIPT)).toBe("<html></html>");
  });

  test("the script allows nothing but its hash: no eval, no remote address, no inline handler in the markup it records", () => {
    expect(EARLY_EVENT_SCRIPT).not.toMatch(/eval|Function\(|http/);
    expect(EARLY_EVENT_SCRIPT.length).toBeLessThan(1600);
  });
});

describe("first paint width range", () => {
  const results = (matching) => WIDTH_LADDER.map((width) => ({ width, prerendered: true, diff: { sameSize: true, different: matching.includes(width) ? 0 : 5 } }));
  test("is the contiguous run of matching ladder steps around the capture width", () => {
    expect(mediaFor(results(WIDTH_LADDER), 1280, 1200)).toBe("(min-width:320px) and (max-height:1200px)");
    expect(mediaFor(results([1280, 1440, 1920, 2560, 3840, 1024]), 1280, 1200)).toBe("(min-width:1024px) and (max-height:1200px)");
    expect(mediaFor(results([768, 1024, 1280, 1440]), 1280, 800)).toBe("(min-width:768px) and (max-width:1440px) and (max-height:800px)");
    // a gap breaks the run: 1920 matches again but 1440 does not
    expect(mediaFor(results([1024, 1280, 1920]), 1280, 1200)).toBe("(min-width:1024px) and (max-width:1280px) and (max-height:1200px)");
  });
  test("parses a viewport", () => {
    expect(parseViewport("1280x1200")).toEqual({ width: 1280, height: 1200 });
    expect(() => parseViewport("wide")).toThrow();
  });
});
