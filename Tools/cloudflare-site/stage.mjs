#!/usr/bin/env bun
// Copies a release bundle into the assets directory of the Cloudflare site (Tools/cloudflare-site/public), with the
// _headers file next to it. Cloudflare compresses on its own, so the .br/.gz copies stay behind, and so do build logs
// and the build's own dotfiles (.bundle-inputs, the fingerprint that lets suites reuse a bundle).
//
// It also writes what a crawler and a browser without JavaScript need, because every route is a real file now: a
// prerendered copy of index.html for each address of the site (its own title, description and canonical link, and a
// <noscript> with the page's heading), 404.html for an address that names no file, robots.txt, sitemap.xml and the
// _redirects of the site's old addresses. The app still boots from every copy; the copies only change the <head>.
//
//   bun Tools/cloudflare-site/stage.mjs <bundle> [<assets directory>]
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../..");
const RECIPES = join(ROOT, "Examples/ShowcaseSite/Features/Components/Recipes");
const LEFT_OUT = /^\.|\.(br|gz|log)$/;
const DEFAULT_ORIGIN = "https://swiftuiweb.vitorsilveira31.workers.dev";

// The site's own words come from the same source tree as the bundle, so a <title> cannot drift from the app's: the pages
// (SitePage.swift, in order), their tab names and the description (ShellStrings.swift) are read from there.
const SITE_NAME = "SwiftUIWeb";
const LANGUAGES = ["pt", "en"];
const LOCALE = { pt: "pt_BR", en: "en_US" };
const SITE_PAGES = "Examples/ShowcaseSite/Data/Domain/SitePage.swift";
const SHELL_STRINGS = "Examples/ShowcaseSite/Features/Shell/Presentation/ShellStrings.swift";

const unquote = (text) => text.replace(/\\(["\\])/g, "$1");

// The pages, their tab names and the site's description, as the app has them. Throws when the sources do not parse: a
// stage without them would write titles the app does not use.
export function siteStrings(root = ROOT) {
  const enumBlock = /enum SitePage[\s\S]*?\n\}/.exec(readFileSync(join(root, SITE_PAGES), "utf8"))?.[0];
  const shell = readFileSync(join(root, SHELL_STRINGS), "utf8");
  const tabBlock = /static func tab\([\s\S]*?\n {2}\}/.exec(shell)?.[0];
  const descriptionBlock = /static func description[\s\S]*?\n {2}\}/.exec(shell)?.[0];
  if (!enumBlock || !tabBlock || !descriptionBlock) throw new Error("ShellStrings.swift or SitePage.swift changed shape: update stage.mjs");
  const tabs = {};
  for (const [, slug, pt, en] of tabBlock.matchAll(/case \.(\w+): return language\.pick\(pt: "((?:[^"\\]|\\.)*)", en: "((?:[^"\\]|\\.)*)"\)/g)) {
    tabs[slug] = { pt: unquote(pt), en: unquote(en) };
  }
  const slugs = [...enumBlock.matchAll(/^ {2}case (\w+)$/gm)].map((match) => match[1]);
  const pages = slugs.map((slug) => {
    if (!tabs[slug]) throw new Error(`ShellStrings.swift has no tab for ${slug}`);
    return { slug, tab: tabs[slug] };
  });
  const text = /pt: "((?:[^"\\]|\\.)*)",\s*en: "((?:[^"\\]|\\.)*)"/.exec(descriptionBlock);
  return { pages, description: { pt: unquote(text[1]), en: unquote(text[2]) } };
}

// The tags the prerendered copies own. They are removed from the bundle's head and written again, so one copy has one of each.
const MANAGED = [
  /<title>[\s\S]*?<\/title>/gi,
  /<meta\s+name=["']description["'][^>]*>/gi,
  /<meta\s+name=["']robots["'][^>]*>/gi,
  /<link\s+rel=["']canonical["'][^>]*>/gi,
  /<link\s+rel=["']alternate["'][^>]*>/gi,
  /<meta\s+property=["']og:[^"']*["'][^>]*>/gi,
];
const ICON_LINK = /<link\b[^>]*\brel=["']?(?:shortcut\s+)?icon["'\s>]/i;

// Cloudflare reads this file next to the assets. The root address has no rule: index.html answers it, and the app picks the
// language (the browser's, or the one the reader chose) and writes the address, which a redirect to /en/... would decide first.
const REDIRECTS = `# Addresses of the site that were used before every route had a file of its own.
/en /en/purpose 301
/pt /pt/purpose 301
`;

// A plain mark for the tab, used when the bundle brings no icon of its own.
const FAVICON = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#0a84ff"/><text x="32" y="43" font-family="-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif" font-size="28" font-weight="700" text-anchor="middle" fill="#ffffff">SW</text></svg>
`;

const escape = (text) =>
  String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const unswift = (text) => text.replace(/\\(["\\])/g, "$1");

// The catalog entries, read from the recipes the way Tools/test-showcase-site-browser.mjs reads their names: the id is the
// entry's address, the name is its title, and the summary is the copy under the title. Without the repository there are
// no entries, and their addresses are not written. An entry without a summary falls back to the page's description.
export function catalogEntries(recipes = RECIPES) {
  if (!existsSync(recipes)) return [];
  return readdirSync(recipes)
    .filter((file) => file.endsWith("CatalogRecipe.swift"))
    .sort()
    .map((file) => {
      const source = readFileSync(join(recipes, file), "utf8");
      const id = /CatalogRecipe\(\s*id: "([^"]+)"/.exec(source)?.[1];
      const name = /\bname: "((?:[^"\\]|\\.)*)"/.exec(source)?.[1];
      if (!id || !name) throw new Error(`${file}: no id and name in its CatalogRecipe`);
      const summary = /summary: CatalogText\(\s*pt: "((?:[^"\\]|\\.)*)",\s*en: "((?:[^"\\]|\\.)*)"/.exec(source);
      return { id, name: unswift(name), summary: summary && { pt: unswift(summary[1]), en: unswift(summary[2]) } };
    });
}

// Every address of the site with the head it needs. `suffix` is the address after the language: the page, or the
// Components page and the entry's id, which is what the other language's copy of the same route is called.
export function siteRoutes(entries, strings) {
  const routes = [];
  for (const lang of LANGUAGES) {
    for (const page of strings.pages) {
      const tab = page.tab[lang];
      routes.push({ lang, suffix: page.slug, title: `${tab} · ${SITE_NAME}`, description: strings.description[lang], heading: `${tab} · ${SITE_NAME}` });
      if (page.slug !== "components") continue;
      for (const entry of entries) {
        const title = `${entry.name} · ${tab} · ${SITE_NAME}`;
        const description = entry.summary?.[lang] ?? strings.description[lang];
        routes.push({ lang, suffix: `components/${entry.id}`, title, description, heading: title });
      }
    }
  }
  return routes.map((route) => ({ ...route, path: `/${route.lang}/${route.suffix}` }));
}

// The addresses written without a language (`/benefits`, `/components/slider`): the app accepts them and picks the reader's language,
// so each is served as a page of its own (a redirect to `/en/...` would take Portuguese readers' language away), and its
// canonical link names the English address so the two are not counted as different pages.
export function languageLessRoutes(routes) {
  return routes
    .filter((route) => route.lang === "en")
    .map((route) => ({ ...route, path: `/${route.suffix}`, canonical: route.path, alternates: false }));
}

function headTags(route, origin) {
  const url = origin + (route.canonical ?? route.path);
  const other = LANGUAGES.find((lang) => lang !== route.lang);
  return [
    `<title>${escape(route.title)}</title>`,
    `<meta name="description" content="${escape(route.description)}">`,
    `<link rel="canonical" href="${escape(url)}">`,
    `<meta property="og:title" content="${escape(route.title)}">`,
    `<meta property="og:description" content="${escape(route.description)}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:url" content="${escape(url)}">`,
    `<meta property="og:locale" content="${LOCALE[route.lang]}">`,
    ...(route.alternates === false ? [] : [`<link rel="alternate" hreflang="${other}" href="${escape(origin + `/${other}/${route.suffix}`)}">`]),
  ];
}

// Writes one copy of the bundle's index.html. Only the head's non-script text and the <html> and <body> tags change; the
// <script> elements are kept byte for byte, since the CSP allows them by hash.
function render(template, { lang, tags, noscript, icon }) {
  const headEnd = template.search(/<\/head>/i);
  const bodyStart = template.search(/<body\b/i);
  if (headEnd < 0 || bodyStart < headEnd) throw new Error("index.html has no <head> and <body> to prerender into");
  const head = template.slice(0, headEnd);
  const rest = template.slice(headEnd);
  // split() with a capture group puts the <script> elements at the odd indexes.
  const cleaned = head
    .split(/(<script\b[\s\S]*?<\/script\s*>)/i)
    .map((part, index) => (index % 2 ? part : MANAGED.reduce((text, pattern) => text.replace(pattern, ""), part)))
    .join("");
  const all = [...tags, ...(icon ? [] : [`<link rel="icon" type="image/svg+xml" href="/favicon.svg">`])];
  const newHead = cleaned + all.map((tag) => `  ${tag}\n`).join("");
  const newRest = rest.replace(/<body\b[^>]*>/i, (open) => `${open}\n  ${noscript}`);
  return (newHead + newRest).replace(/<html\b([^>]*)>/i, (_, attributes) => `<html lang="${lang}"${attributes.replace(/\s+lang=["'][^"']*["']/i, "")}>`);
}

const noscriptFor = (route) => `<noscript><h1>${escape(route.heading)}</h1><p>${escape(route.description)}</p></noscript>`;

export function stage(bundle, assets) {
  if (!existsSync(join(bundle, "index.html"))) throw new Error(`${bundle} has no index.html: build the bundle first`);
  rmSync(assets, { recursive: true, force: true });
  const copied = [];
  const walk = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const source = join(directory, name);
      const path = relative(bundle, source);
      if (statSync(source).isDirectory()) walk(source);
      else if (!LEFT_OUT.test(name)) {
        mkdirSync(dirname(join(assets, path)), { recursive: true });
        copyFileSync(source, join(assets, path));
        copied.push(path);
      }
    }
  };
  walk(bundle);
  if (!copied.some((path) => path.endsWith(".wasm"))) throw new Error(`${bundle} has no .wasm file`);
  copyFileSync(join(HERE, "_headers"), join(assets, "_headers"));
  return copied;
}

/** Writes the prerendered routes, the 404 page, robots.txt, sitemap.xml and _redirects next to the staged bundle. Reads the
 *  staged index.html as the template, so it runs after `stage`. Returns the paths written. */
export function prerender(assets, { origin = process.env.SITE_ORIGIN || DEFAULT_ORIGIN, recipes = RECIPES, root = ROOT } = {}) {
  const base = origin.replace(/\/+$/, "");
  const template = readFileSync(join(assets, "index.html"), "utf8");
  const icon = ICON_LINK.test(template.slice(0, template.search(/<\/head>/i)));
  const written = [];
  const write = (path, text) => {
    mkdirSync(dirname(join(assets, path)), { recursive: true });
    writeFileSync(join(assets, path), text);
    written.push(path);
  };

  const strings = siteStrings(root);
  const routes = siteRoutes(catalogEntries(recipes), strings);
  for (const route of [...routes, ...languageLessRoutes(routes)]) {
    write(`${route.path.slice(1)}/index.html`, render(template, { lang: route.lang, tags: headTags(route, base), noscript: noscriptFor(route), icon }));
  }

  // The app shows Purpose for an address it does not know, so the 404 copy still boots it. The 404 status comes from the
  // Worker (notFoundHandling "404-page"), so the page only says what happened to a reader without JavaScript.
  write(
    "404.html",
    render(template, {
      lang: "en",
      tags: [`<title>404 · ${SITE_NAME}</title>`, `<meta name="description" content="${escape(strings.description.en)}">`, `<meta name="robots" content="noindex">`],
      noscript: `<noscript><h1>Page not found</h1><p><a href="/en/purpose">English</a> · <a href="/pt/purpose">Português</a></p></noscript>`,
      icon,
    })
  );

  write("robots.txt", `User-agent: *\nAllow: /\nSitemap: ${base}/sitemap.xml\n`);
  const urls = routes.map((route) => {
    const alternates = LANGUAGES.map((lang) => `    <xhtml:link rel="alternate" hreflang="${lang}" href="${escape(`${base}/${lang}/${route.suffix}`)}"/>\n`).join("");
    return `  <url>\n    <loc>${escape(base + route.path)}</loc>\n${alternates}  </url>\n`;
  });
  write("sitemap.xml", `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls.join("")}</urlset>\n`);
  write("_redirects", REDIRECTS);
  if (!existsSync(join(assets, "favicon.svg"))) write("favicon.svg", FAVICON);

  return written;
}

if (import.meta.main) {
  const [bundle, assets = join(HERE, "public")] = process.argv.slice(2);
  if (!bundle) {
    console.error("usage: bun Tools/cloudflare-site/stage.mjs <bundle> [<assets directory>]");
    process.exit(2);
  }
  try {
    const copied = stage(resolve(bundle), resolve(assets));
    const written = prerender(resolve(assets));
    console.log(`Staged ${copied.length} files, the _headers and ${written.length} prerendered files into ${relative(process.cwd(), resolve(assets)) || "."}`);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
