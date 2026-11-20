#!/usr/bin/env bun
// Tests for Tools/compile-assets.mjs.
// Run: bun test ./Tools/test-compile-assets.mjs
import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  existsSync,
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import * as mod from "./compile-assets.mjs";

function withTemp(run) {
  const dir = mkdtempSync(join(tmpdir(), "compile-assets-test-"));
  try {
    return run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function writeJson(path, value) {
  writeFileSync(path, JSON.stringify(value));
}

function colorset(root, name, colors) {
  const folder = join(root, "App.xcassets", `${name}.colorset`);
  mkdirSync(folder, { recursive: true });
  writeJson(join(folder, "Contents.json"), { colors });
}

function srgb(r, g, b, a = "1.000", space = "srgb") {
  return { "color-space": space, components: { red: r, green: g, blue: b, alpha: a } };
}

const DARK = [{ appearance: "luminosity", value: "dark" }];

// Maps are compared as plain objects; the key order itself is covered by the golden comparison.
const plain = (map) => Object.fromEntries(map);

describe("CompileAssets", () => {
  test("light and dark become light-dark", () => {
    withTemp((root) => {
      colorset(root, "Ink", [
        { color: srgb("0x1C", "0x1A", "0x26"), idiom: "universal" },
        { appearances: DARK, color: srgb("0.929", "0.922", "0.957"), idiom: "universal" },
      ]);
      assert.deepEqual(plain(mod.compileAssets(root)), { Ink: "light-dark(#1C1A26, #EDEBF4)" });
    });
  });

  test("single appearance and equal dark are plain", () => {
    withTemp((root) => {
      colorset(root, "Fixed", [{ color: srgb("0x2A", "0x26", "0x38") }]);
      colorset(root, "Same", [
        { color: srgb("0xFF", "0xFF", "0xFF") },
        { appearances: DARK, color: srgb("0xFF", "0xFF", "0xFF") },
      ]);
      assert.deepEqual(plain(mod.compileAssets(root)), { Fixed: "#2A2638", Same: "#FFFFFF" });
    });
  });

  test("alpha and display-p3", () => {
    withTemp((root) => {
      colorset(root, "Scrim", [
        { color: srgb("0x12", "0x10", "0x1C", "0.420") },
        { appearances: DARK, color: srgb("0x06", "0x05", "0x0A", "0.600") },
      ]);
      colorset(root, "Wide", [{ color: srgb("1.0", "0.5", "0.0", "1.000", "display-p3") }]);
      const values = mod.compileAssets(root);
      assert.equal(values.get("Scrim"), "light-dark(rgb(18 16 28 / 0.42), rgb(6 5 10 / 0.6))");
      assert.equal(values.get("Wide"), "color(display-p3 1 0.5 0)");
    });
  });

  test("image sets are copied and listed in the environment", () => {
    withTemp((root) => {
      const bundle = join(root, "bundle");
      mkdirSync(bundle);
      const brand = join(root, "App.xcassets", "AppBrand.imageset");
      mkdirSync(brand, { recursive: true });
      writeFileSync(join(brand, "logo.svg"), "<svg/>");
      writeJson(join(brand, "Contents.json"), { images: [{ filename: "logo.svg", idiom: "universal" }] });
      const poster = join(root, "App.xcassets", "Poster.imageset");
      mkdirSync(poster);
      writeFileSync(join(poster, "poster@2x.png"), Buffer.from("\x89PNG", "latin1"));
      writeFileSync(join(poster, "poster.png"), Buffer.from("\x89PNG1x", "latin1"));
      writeJson(join(poster, "Contents.json"), {
        images: [
          { filename: "poster@2x.png", idiom: "universal", scale: "2x" },
          { filename: "poster.png", idiom: "universal", scale: "1x" },
        ],
      });
      const missing = join(root, "App.xcassets", "Gone.imageset");
      mkdirSync(missing);
      writeJson(join(missing, "Contents.json"), { images: [{ filename: "gone.png", idiom: "universal" }] });
      writeFileSync(join(bundle, "runtime-environment"), "SWIFTUIWEB_LANGUAGE=pt\nSWIFTUIWEB_IMAGE_ASSETS=stale=old.png\n");
      assert.equal(mod.main(["x", root, join(root, "o.css"), bundle]), 0);
      assert.equal(readFileSync(join(bundle, "catalog-assets", "AppBrand.svg"), "utf8"), "<svg/>");
      assert.equal(
        readFileSync(join(bundle, "catalog-assets", "Poster@2x.png"), "latin1"),
        "\x89PNG",
        "the universal 2x file wins, its name keeping its density",
      );
      assert.equal(existsSync(join(bundle, "catalog-assets", "Poster.png")), false);
      assert.equal(existsSync(join(bundle, "catalog-assets", "Gone.png")), false);
      assert.deepEqual(readFileSync(join(bundle, "runtime-environment"), "utf8").split("\n").slice(0, -1), [
        "SWIFTUIWEB_LANGUAGE=pt",
        "SWIFTUIWEB_IMAGE_ASSETS=AppBrand=catalog-assets/AppBrand.svg;Poster=catalog-assets/Poster@2x.png",
      ]);
      assert.equal(existsSync(join(root, "o.css")), false, "no color sets, no stylesheet");
    });
  });

  test("build directories are skipped and empty writes nothing", () => {
    withTemp((root) => {
      const hidden = join(root, ".build", "X.xcassets", "Gone.colorset");
      mkdirSync(hidden, { recursive: true });
      writeJson(join(hidden, "Contents.json"), { colors: [{ color: srgb("0", "0", "0") }] });
      assert.equal(mod.compileAssets(root).size, 0);
      const out = join(root, "o.css");
      assert.equal(mod.main(["x", root, out]), 0);
      assert.equal(existsSync(out), false);
    });
  });
});

describe("Namespaces", () => {
  test("namespaced folders prefix names and css escapes them", () => {
    withTemp((root) => {
      const bundle = join(root, "bundle");
      mkdirSync(bundle);
      const catalog = join(root, "Kit.xcassets");
      const header = join(catalog, "header");
      mkdirSync(header, { recursive: true });
      writeJson(join(header, "Contents.json"), { properties: { "provides-namespace": true } });
      const sky = join(header, "Sky Start.colorset");
      mkdirSync(sky);
      writeJson(join(sky, "Contents.json"), { colors: [{ color: srgb("0x10", "0x20", "0x30") }] });
      const plainFolder = join(catalog, "dough"); // no namespace flag: names stay bare
      mkdirSync(plainFolder);
      const thumb = join(plainFolder, "yellow.imageset");
      mkdirSync(thumb);
      writeFileSync(join(thumb, "yellow.png"), Buffer.from("\x89PNG", "latin1"));
      writeJson(join(thumb, "Contents.json"), { images: [{ filename: "yellow.png" }] });
      const values = mod.compileAssets(root);
      assert.deepEqual(plain(values), { "header/Sky Start": "#102030" });
      // Every non-identifier character is a hex escape: `/` is \2f and the space is \20, each ended by a space.
      assert.match(mod.render(values), /--asset-color-header\\2f Sky\\20 Start: #102030;/);
      const manifest = mod.installImages(mod.compileImages(root), bundle);
      assert.deepEqual(plain(manifest), { yellow: "catalog-assets/yellow.png" });
    });
  });
});

describe("Accent color", () => {
  test("a system color reference compiles to its light and dark values and AccentColor becomes the tint", () => {
    withTemp((root) => {
      const set = join(root, "Kit.xcassets", "AccentColor.colorset");
      mkdirSync(set, { recursive: true });
      writeJson(join(set, "Contents.json"), { colors: [{ color: { platform: "universal", reference: "systemIndigoColor" } }] });
      const values = mod.compileAssets(root);
      assert.deepEqual(plain(values), { AccentColor: "light-dark(#5856D6, #5E5CE6)" });
      const css = mod.render(values);
      assert.match(css, /--asset-color-AccentColor: light-dark\(#5856D6, #5E5CE6\);/);
      assert.match(css, /--tint-color: var\(--asset-color-AccentColor\);/);
    });
  });

  test("an unset AccentColor, an unknown reference and other colors leave the tint alone", () => {
    withTemp((root) => {
      const unset = join(root, "Kit.xcassets", "AccentColor.colorset");
      mkdirSync(unset, { recursive: true });
      writeJson(join(unset, "Contents.json"), { colors: [{ color: { platform: "universal" } }] });
      const odd = join(root, "Kit.xcassets", "Odd.colorset");
      mkdirSync(odd);
      writeJson(join(odd, "Contents.json"), { colors: [{ color: { reference: "systemNopeColor" } }] });
      const other = join(root, "Kit.xcassets", "Sky.colorset");
      mkdirSync(other);
      writeJson(join(other, "Contents.json"), { colors: [{ color: srgb("0x10", "0x20", "0x30") }] });
      const values = mod.compileAssets(root);
      assert.deepEqual(plain(values), { Sky: "#102030" });
      assert.doesNotMatch(mod.render(values), /--tint-color/);
    });
  });
});

describe("Containment", () => {
  const SECRET = "SECRET-OUTSIDE-PACKAGE";

  function outsideFile(root, relative, text = SECRET) {
    const path = join(root, "outside", relative);
    mkdirSync(join(root, "outside"), { recursive: true });
    writeFileSync(path, text);
    return path;
  }

  function imageset(pkg, name, images) {
    const folder = join(pkg, "App.xcassets", `${name}.imageset`);
    mkdirSync(folder, { recursive: true });
    writeJson(join(folder, "Contents.json"), { images });
    return folder;
  }

  // Text of every file the compile step copied into the bundle's catalog-assets folder.
  function copiedText(bundle) {
    const folder = join(bundle, "catalog-assets");
    return existsSync(folder) ? readdirSync(folder).map((name) => readFileSync(join(folder, name), "latin1")) : [];
  }

  // Runs the compile step and returns its result with the warnings it printed to stderr.
  function quietly(run) {
    const warnings = [];
    const original = console.error;
    console.error = (...args) => warnings.push(args.join(" "));
    try {
      return { result: run(), warnings };
    } finally {
      console.error = original;
    }
  }

  test("filenames that leave the image set are skipped with a warning", () => {
    withTemp((root) => {
      const pkg = join(root, "pkg");
      const bundle = join(root, "bundle");
      mkdirSync(pkg);
      mkdirSync(bundle);
      outsideFile(root, "secret.png");
      imageset(pkg, "Parent", [{ filename: "../../../outside/secret.png", idiom: "universal" }]);
      imageset(pkg, "Absolute", [{ filename: join(root, "outside", "secret.png"), idiom: "universal" }]);
      imageset(pkg, "Nested", [{ filename: "sub/secret.png", idiom: "universal" }]);
      mkdirSync(join(pkg, "App.xcassets", "Nested.imageset", "sub"), { recursive: true });
      writeFileSync(join(pkg, "App.xcassets", "Nested.imageset", "sub", "secret.png"), SECRET);
      const { result, warnings } = quietly(() => mod.main(["x", pkg, join(root, "o.css"), bundle]));
      assert.equal(result, 0);
      assert.deepEqual(copiedText(bundle).filter((text) => text.includes(SECRET)), []);
      assert.equal(existsSync(join(bundle, "runtime-environment")), false);
      assert.equal(warnings.length, 3, warnings.join("\n"));
    });
  });

  test("symbolic links are not followed out of the package", () => {
    withTemp((root) => {
      const pkg = join(root, "pkg");
      const bundle = join(root, "bundle");
      mkdirSync(pkg);
      mkdirSync(bundle);
      const secret = outsideFile(root, "secret.png");
      const leak = imageset(pkg, "Leak", [{ filename: "leak.png", idiom: "universal" }]);
      symlinkSync(secret, join(leak, "leak.png"));
      const linked = join(root, "outside", "linked.imageset");
      mkdirSync(linked, { recursive: true });
      writeJson(join(linked, "Contents.json"), { images: [{ filename: "shot.png", idiom: "universal" }] });
      writeFileSync(join(linked, "shot.png"), SECRET);
      symlinkSync(linked, join(pkg, "App.xcassets", "Linked.imageset"));
      const { result, warnings } = quietly(() => mod.main(["x", pkg, join(root, "o.css"), bundle]));
      assert.equal(result, 0);
      assert.deepEqual(copiedText(bundle).filter((text) => text.includes(SECRET)), []);
      assert.ok(warnings.length >= 2, warnings.join("\n"));
    });
  });

  test("normal catalogs compile through a symlinked package root and in-folder links", () => {
    withTemp((root) => {
      const pkg = join(root, "pkg");
      const bundle = join(root, "bundle");
      mkdirSync(pkg);
      mkdirSync(bundle);
      const set = imageset(pkg, "Ok", [{ filename: "ok.png", idiom: "universal" }]);
      writeFileSync(join(set, "ok.png"), "OK-BYTES");
      const alias = imageset(pkg, "Alias", [{ filename: "alias.png", idiom: "universal" }]);
      writeFileSync(join(alias, "real.png"), "OK-BYTES");
      symlinkSync(join(alias, "real.png"), join(alias, "alias.png"));
      const link = join(root, "pkg-link");
      symlinkSync(pkg, link);
      const { result, warnings } = quietly(() => mod.main(["x", link, join(root, "o.css"), bundle]));
      assert.equal(result, 0);
      assert.deepEqual(warnings, []);
      assert.equal(readFileSync(join(bundle, "catalog-assets", "Ok.png"), "utf8"), "OK-BYTES");
      assert.equal(readFileSync(join(bundle, "catalog-assets", "Alias.png"), "utf8"), "OK-BYTES");
    });
  });
});

describe("Symbols", () => {
  test("custom symbol template becomes a tintable svg", () => {
    withTemp((root) => {
      const bundle = join(root, "bundle");
      mkdirSync(bundle);
      const sym = join(root, "Kit.xcassets", "donut.symbolset");
      mkdirSync(sym, { recursive: true });
      writeFileSync(
        join(sym, "donut.svg"),
        '<svg><line id="left-margin-Regular-M" x1="100" y1="0"/><line id="right-margin-Regular-M" x1="160" y1="0"/>' +
          '<g id="Regular-M" transform="matrix(1 0 0 1 100 200)"><path class="hierarchical-0:secondary" d="M0-10L20-30L40-10Z"/>' +
          '<path class="hierarchical-1:primary" d="M0 0L40 0L20 5Z"/></g></svg>',
      );
      writeJson(join(sym, "Contents.json"), { symbols: [{ filename: "donut.svg", idiom: "universal" }] });
      const manifest = mod.installImages(mod.compileImages(root), bundle);
      assert.deepEqual(plain(manifest), { donut: "catalog-assets/donut.symbol.svg" });
      const svg = readFileSync(join(bundle, "catalog-assets", "donut.symbol.svg"), "utf8");
      assert.ok(svg.includes('viewBox="100 170 60 35"'));
      assert.ok(svg.includes('fill="currentColor" fill-opacity="0.5"'));
    });
  });

  test("older template with unsuffixed margins and classless paths", () => {
    withTemp((root) => {
      const bundle = join(root, "bundle");
      mkdirSync(bundle);
      const sym = join(root, "Kit.xcassets", "salty.symbolset");
      mkdirSync(sym, { recursive: true });
      writeFileSync(
        join(sym, "salty.svg"),
        '<svg><line id="left-margin" x1="100" y1="0"/><line id="right-margin" x1="160" y1="0"/>' +
          '<g id="Regular-M" transform="matrix(1 0 0 1 100 200)"><path d="M0-10L20-30L40-10Z"/></g></svg>',
      );
      writeJson(join(sym, "Contents.json"), { symbols: [{ filename: "salty.svg", idiom: "universal" }] });
      const manifest = mod.installImages(mod.compileImages(root), bundle);
      assert.deepEqual(plain(manifest), { salty: "catalog-assets/salty.symbol.svg" });
      assert.ok(
        readFileSync(join(bundle, "catalog-assets", "salty.symbol.svg"), "utf8").includes(
          'fill="currentColor" fill-opacity="1"',
        ),
      );
    });
  });

  test("small-only template saved by an editor is framed by its guides", () => {
    withTemp((root) => {
      const bundle = join(root, "bundle");
      mkdirSync(bundle);
      const sym = join(root, "Kit.xcassets", "rocket.symbolset");
      mkdirSync(sym, { recursive: true });
      writeFileSync(
        join(sym, "rocket.svg"),
        '<svg><line\n id="Capline-S"\n x1="0" y1="600"/><line\n id="Baseline-S"\n x1="0" y1="700"/>' +
          '<line\n id="left-margin-Regular-S"\n style="x"\n x1="1400" y1="0"/>' +
          '<line\n id="right-margin-Regular-S"\n style="x"\n x1="1500" y1="0"/>' +
          '<g\n id="Regular-S">\n<path\n d="m 1450,650 c 1,-2 3,-4 5,-6 z"/></g></svg>',
      );
      writeJson(join(sym, "Contents.json"), { symbols: [{ filename: "rocket.svg", idiom: "universal" }] });
      const manifest = mod.installImages(mod.compileImages(root), bundle);
      assert.deepEqual(plain(manifest), { rocket: "catalog-assets/rocket.symbol.svg" });
      assert.ok(
        readFileSync(join(bundle, "catalog-assets", "rocket.symbol.svg"), "utf8").includes(
          'viewBox="1400 600 100 100"',
        ),
      );
    });
  });
});
