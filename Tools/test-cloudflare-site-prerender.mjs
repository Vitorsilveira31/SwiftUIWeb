// Run: bun test ./Tools/test-cloudflare-site-stage.mjs
// Covers stage.mjs: the prerendered copy of every route (its <head>, its <noscript>, its scripts kept byte for byte), the
// 404 page, robots.txt, sitemap.xml, _redirects and favicon.svg. The pages, tab names and descriptions are read from the
// app's own sources, and the routes from the real recipes; the bundle is a tiny fake with the shape of index.html.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { catalogEntries, prerender, siteStrings, stage } from "./cloudflare-site/stage.mjs";

// A small runner, so the file runs the same under `bun Tools/test-...mjs` and `bun test`: each test is checked when it is
// declared, and the process exits 1 when one fails.
let failed = 0;
let passed = 0;
const describe = (_name, body) => body();
const test = (name, body) => {
  try {
    body();
    passed += 1;
  } catch (error) {
    failed += 1;
    console.error(`not ok - ${name}\n${error.message}`);
  }
};

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ORIGIN = "https://example.test";
const SCRIPTS = /<script\b[\s\S]*?<\/script\s*>/gi;
const SITE = "SwiftUIWeb";

// The script text carries a "<title>" of its own, which the copies must keep and the title reader must not take.
const INDEX = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>SwiftUIWeb</title><meta name="description" content="generic"><meta http-equiv="Content-Security-Policy" content="script-src 'sha256-test'"><script>window.first = "<title>not a title</title>";</script><link rel="stylesheet" href="app.css"></head><body><div id="app"></div><script type="module">import "./app.js";</script></body></html>
`;

const strings = siteStrings(ROOT);
const tab = (slug, lang) => strings.pages.find((page) => page.slug === slug).tab[lang];
const entries = catalogEntries();

let bundle;
let assets;
let copied;
const read = (path) => readFileSync(join(assets, path), "utf8");
const head = (html) => html.replace(SCRIPTS, "");
const titleOf = (html) => /<title>([\s\S]*?)<\/title>/.exec(head(html))?.[1];
const metaOf = (html, name) => new RegExp(`<meta\\s+name="${name}"\\s+content="([^"]*)"`).exec(head(html))?.[1];

function setup() {
  const root = mkdtempSync(join(tmpdir(), "swiftuiweb-stage-"));
  bundle = join(root, "bundle");
  assets = join(root, "public");
  mkdirSync(join(bundle, "assets"), { recursive: true });
  writeFileSync(join(bundle, "index.html"), INDEX);
  writeFileSync(join(bundle, "app.wasm"), Buffer.from([0, 97, 115, 109]));
  writeFileSync(join(bundle, "app.css"), "body{}");
  writeFileSync(join(bundle, "assets", "app.js"), "export {};");
  writeFileSync(join(bundle, "app.wasm.br"), "compressed");
  writeFileSync(join(bundle, "build.log"), "log");
  copied = [...stage(bundle, assets), ...prerender(assets, { origin: ORIGIN })];
}
setup();
process.on("exit", () => rmSync(dirname(bundle), { recursive: true, force: true }));

describe("routes", () => {
  test("the English purpose page has its own title, language, locale and canonical link", () => {
    const html = read("en/purpose/index.html");
    assert.equal(titleOf(html), `${tab("purpose", "en")} · ${SITE}`);
    assert.match(html, /<html lang="en"/);
    assert.equal(metaOf(html, "description"), strings.description.en);
    assert.match(html, /<link rel="canonical" href="https:\/\/example\.test\/en\/purpose">/);
    assert.match(html, /<meta property="og:url" content="https:\/\/example\.test\/en\/purpose">/);
    assert.match(html, /<meta property="og:locale" content="en_US">/);
    assert.match(html, /<meta property="og:type" content="website">/);
    assert.match(html, /<link rel="alternate" hreflang="pt" href="https:\/\/example\.test\/pt\/purpose">/);
  });

  test("the Portuguese pages say pt, use the app's Portuguese titles and link the English copy", () => {
    const html = read("pt/purpose/index.html");
    assert.equal(titleOf(html), `${tab("purpose", "pt")} · ${SITE}`);
    assert.match(html, /<html lang="pt"/);
    assert.match(html, /<meta property="og:locale" content="pt_BR">/);
    assert.match(html, /<link rel="alternate" hreflang="en" href="https:\/\/example\.test\/en\/purpose">/);
    for (const page of strings.pages) {
      assert.equal(titleOf(read(`pt/${page.slug}/index.html`)), `${page.tab.pt} · ${SITE}`, page.slug);
      assert.equal(titleOf(read(`en/${page.slug}/index.html`)), `${page.tab.en} · ${SITE}`, page.slug);
    }
  });

  test("a catalog entry is titled with its name, its page and the site, and links its own address", () => {
    const html = read("pt/components/slider/index.html");
    assert.equal(titleOf(html), `Slider · ${tab("components", "pt")} · ${SITE}`);
    assert.match(html, /<link rel="canonical" href="https:\/\/example\.test\/pt\/components\/slider">/);
    assert.match(html, new RegExp(`<h1>Slider · ${tab("components", "pt")} · SwiftUIWeb<\\/h1>`));
  });

  test("every route is written, and each copy has one title and one canonical", () => {
    assert.ok(entries.length > 0, "the recipes were not found");
    for (const lang of ["pt", "en"]) {
      for (const page of strings.pages) assert.ok(existsSync(join(assets, lang, page.slug, "index.html")), `${lang}/${page.slug}`);
      for (const entry of entries) {
        const path = `${lang}/components/${entry.id}/index.html`;
        assert.ok(existsSync(join(assets, path)), path);
        const html = read(path);
        assert.equal(head(html).match(/<title>/g).length, 1, `${path} has more than one title`);
        assert.equal(head(html).match(/rel="canonical"/g).length, 1, `${path} has more than one canonical`);
      }
    }
  });

  test("a catalog entry's description is its own summary in the page's language", () => {
    const slider = read("pt/components/slider/index.html");
    assert.equal(metaOf(slider, "description"), entries.find((entry) => entry.id === "slider").summary.pt);
  });
});

describe("the bundle's head and scripts", () => {
  test("the scripts are byte-identical, so the CSP hashes still match", () => {
    const html = read("en/purpose/index.html");
    assert.deepEqual(html.match(SCRIPTS), INDEX.match(SCRIPTS));
    assert.match(html, /<meta http-equiv="Content-Security-Policy" content="script-src 'sha256-test'">/);
    assert.match(html, /<link rel="stylesheet" href="app\.css">/);
    assert.match(html, /<div id="app"><\/div>/);
  });

  test("a noscript with the page's heading and description follows <body>", () => {
    const html = read("pt/purpose/index.html");
    assert.match(html, new RegExp(`<body>\\n {2}<noscript><h1>${tab("purpose", "pt")} · SwiftUIWeb</h1><p>SwiftUIWeb: o SwiftUI na web\\.`));
  });

  test("the bundle has no icon, so the SVG icon is linked and written", () => {
    assert.equal(existsSync(join(assets, "favicon.svg")), true);
    assert.match(read("en/purpose/index.html"), /<link rel="icon" type="image\/svg\+xml" href="\/favicon\.svg">/);
  });
});

describe("the files around the routes", () => {
  test("404.html is noindex, says the page is not found and links both languages", () => {
    const html = read("404.html");
    assert.equal(titleOf(html), "404 · SwiftUIWeb");
    assert.match(html, /<meta name="robots" content="noindex">/);
    assert.match(html, /<h1>Page not found<\/h1>/);
    assert.match(html, /<a href="\/en\/purpose">/);
    assert.match(html, /<a href="\/pt\/purpose">/);
    assert.deepEqual(html.match(SCRIPTS), INDEX.match(SCRIPTS));
  });

  test("robots.txt points at the sitemap", () => {
    assert.equal(read("robots.txt"), `User-agent: *\nAllow: /\nSitemap: ${ORIGIN}/sitemap.xml\n`);
  });

  test("sitemap.xml lists every route with both alternates, and not the root or the language roots", () => {
    const sitemap = read("sitemap.xml");
    assert.match(sitemap, /<loc>https:\/\/example\.test\/pt\/components\/slider<\/loc>/);
    assert.match(sitemap, /<xhtml:link rel="alternate" hreflang="en" href="https:\/\/example\.test\/en\/components\/slider"\/>/);
    assert.equal(sitemap.match(/<loc>/g).length, 2 * (strings.pages.length + entries.length));
    assert.doesNotMatch(sitemap, /<loc>https:\/\/example\.test\/?<\/loc>/);
    assert.doesNotMatch(sitemap, /<loc>https:\/\/example\.test\/(en|pt)<\/loc>/);
  });

  test("an address without a language is a page of its own, canonical to the English one", () => {
    for (const suffix of ["benefits", "performance", "components", "components/slider"]) {
      const html = read(`${suffix}/index.html`);
      assert.match(html, new RegExp(`<link rel="canonical" href="https://example\\.test/en/${suffix.replace("/", "\\/")}">`), suffix);
      assert.doesNotMatch(html, /rel="alternate"/, suffix);
    }
    assert.doesNotMatch(read("sitemap.xml"), /<loc>https:\/\/example\.test\/benefits<\/loc>/);
  });

  test("_redirects keeps the old addresses working", () => {
    assert.equal(
      read("_redirects"),
      "# Addresses of the site that were used before every route had a file of its own.\n/en /en/purpose 301\n/pt /pt/purpose 301\n"
    );
  });

  test("the staged files keep the bundle's files and drop the compressed copies and logs", () => {
    assert.ok(copied.includes("app.wasm"));
    assert.ok(copied.includes("assets/app.js"));
    assert.ok(existsSync(join(assets, "_headers")));
    assert.equal(existsSync(join(assets, "app.wasm.br")), false);
    assert.equal(existsSync(join(assets, "build.log")), false);
  });
});

describe("the copy agrees with the app", () => {
  test("the pages are the SitePage cases, each with a tab name in both languages", () => {
    assert.ok(strings.pages.length >= 4);
    for (const page of strings.pages) {
      assert.ok(page.tab.pt && page.tab.en, page.slug);
      assert.ok(existsSync(join(assets, "pt", page.slug, "index.html")), page.slug);
    }
  });

  test("the description is the one ShellStrings.swift has, in both languages", () => {
    const shell = readFileSync(join(ROOT, "Examples/ShowcaseSite/Features/Shell/Presentation/ShellStrings.swift"), "utf8");
    assert.ok(shell.includes(strings.description.pt), "pt description is not in ShellStrings.swift");
    assert.ok(shell.includes(strings.description.en), "en description is not in ShellStrings.swift");
  });
});

console.log(`${passed} passed, ${failed} failed`);
// A throw, not an exit code: `bun test` runs this file without a test of its own, and it exits 0 on a failure of that kind.
if (failed) throw new Error(`${failed} check(s) failed`);
