#!/usr/bin/env bun
// The page's side of the binary publication in a real browser: every fixture Swift's encoder wrote
// (Tests/Fixtures/BinaryPublication, rewritten by `SWIFTUIWEB_UPDATE_BINARY_FIXTURES=1 swift test --filter BinaryEncoderTests`)
// is built by Tools/binary-publication.js and compared, node by node, with the DOM the parser makes of the markup beside it:
// tags, namespaces, attributes (and their namespaces), text and order, and every element is the one its handle names.
// The records of an update (ATTRS, CHILDREN, HELD) are written by hand as the format describes them and read by the same module.
//
//   bun Tools/test-binary-publication-browser.mjs
//   SWIFTUIWEB_BROWSER_ENGINE=webkit bun Tools/test-binary-publication-browser.mjs
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { engineName, launch, runSuite, serveStatic } from "./browser-test-support.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const FIXTURES = join(ROOT, "Tests/Fixtures/BinaryPublication");

await runSuite(async () => {
  const names = readdirSync(FIXTURES).filter((file) => file.endsWith(".bin")).map((file) => file.slice(0, -4)).sort();
  assert.ok(names.length > 10, "the fixtures are missing: run the BinaryEncoderTests with SWIFTUIWEB_UPDATE_BINARY_FIXTURES=1");
  const fixtures = names.map((name) => ({ name, bytes: [...readFileSync(join(FIXTURES, `${name}.bin`))], html: readFileSync(join(FIXTURES, `${name}.html`), "utf8") }));
  const server = serveStatic(join(ROOT, "Tools"));
  const browser = await launch();
  try {
    const page = await browser.newPage();
    await page.goto(`${server.base}/binary-publication.js`);
    const results = await page.evaluate(async ({ base, fixtures }) => {
      const { readPublication, Builder, Handles, Templates, scanRecords, compareDom, BinaryFormatError } = await import(`${base}/binary-publication.js`);
      const { BINARY_ATOMS, BINARY_OPS } = await import(`${base}/binary-atoms.generated.js`);
      const out = [];
      const inert = () => document.implementation.createHTMLDocument("");
      const everything = { attributeOwned: () => false, styleOwned: () => false, styleText: () => [], contentOwned: () => false };
      for (const fixture of fixtures) {
        const problems = [];
        // What the page does with markup: parse in a template, strip the scripts.
        const template = document.createElement("template");
        template.innerHTML = fixture.html;
        for (const script of template.content.querySelectorAll("script")) script.remove();
        const handles = new Handles();
        const built = new Builder(readPublication(new Uint8Array(fixture.bytes)), inert(), handles).buildRoot();
        for (const difference of compareDom(built, template.content, everything)) problems.push(JSON.stringify(difference).slice(0, 300));
        // Every element that has an id is the one its handle names.
        for (const element of built.querySelectorAll("[data-embedded-node-id]")) {
          const [index, generation] = element.getAttribute("data-embedded-node-id").split(":");
          if (!/^\d+$/.test(index)) continue;
          if (handles.lookup(Number(index), Number(generation)) !== element) problems.push(`handle ${index}:${generation} does not name its element`);
        }
        // A script is never built.
        if (built.querySelector("script")) problems.push("a script was built");
        out.push({ name: fixture.name, problems: problems.slice(0, 6), elements: built.querySelectorAll("*").length });
      }
      // Records, written by hand as the format describes them: the page splits them, builds the lists and the attributes.
      const records = [];
      const check = (name, ok, detail = "") => records.push({ name, ok, detail });
      {
        const { ROOT, ATTRS, CHILDREN, HELD, ELEMENT, ELEMENT_NS, TEXT, SHAPE, DEFINE, END } = BINARY_OPS;
        const own = [];
        const str = (text) => { const atom = BINARY_ATOMS.indexOf(text); if (atom >= 0) return atom; let at = own.indexOf(text); if (at < 0) at = own.push(text) - 1; return BINARY_ATOMS.length + at; };
        const publication = (words) => ({ words: Uint32Array.from(words), strings: BINARY_ATOMS.concat(own), reference: null });
        const attributes = (pairs) => [pairs.length, ...pairs.flatMap(([name, value]) => [str(name), str(value)])];
        const element = (index, generation, tag, pairs, ...children) => [ELEMENT, index + 1, generation, str(""), str(tag), ...attributes(pairs), ...children.flat(), END];
        const text = (value) => [TEXT, str(value)];
        const held = (index, generation) => [HELD, index + 1, generation];
        const handles = new Handles();
        // The page holds a list: <ul 1:1><li 2:1>a</li><li 3:1>b</li></ul>, built from a root.
        const root = publication([ROOT, 1, ...element(1, 1, "ul", [["data-embedded-node-id", "1:1:"]], element(2, 1, "li", [["data-embedded-node-id", "2:1:"]], text("a")), element(3, 1, "li", [["data-embedded-node-id", "3:1:"]], text("b")))]);
        const ul = new Builder(root, inert(), handles).buildRoot().firstChild;
        const first = handles.lookup(2, 1), second = handles.lookup(3, 1);
        check("a root registers the elements it builds", ul.localName === "ul" && first.localName === "li" && handles.lookup(3, 2) === null && handles.lookup(9, 1) === null);
        // An update: the list's children are the second item, a new item and the first, and one item's attributes change.
        const update = publication([
          ATTRS, 3 + 1, 1, ...attributes([["data-embedded-node-id", "3:1:"], ["title", "t"]]),
          CHILDREN, 1 + 1, 1, ...held(3, 1), ...element(4, 1, "li", [["data-embedded-node-id", "4:1:"]], text("new "), text("text")), ...held(2, 1), END,
          CHILDREN, 0, 0, TEXT, str("root text"), END,
        ]);
        const scanned = scanRecords(update).records;
        check("an update splits into its records", scanned.length === 3 && scanned[0].op === ATTRS && scanned[0].index === 3 && scanned[1].op === CHILDREN && scanned[1].index === 1 && scanned[2].index === -1,
          JSON.stringify(scanned));
        const builder = new Builder(update, inert(), handles);
        const scratch = builder.buildAttributes(scanned[0].position, second);
        check("attributes are built on an element of the live element's name", scratch.localName === "li" && scratch.getAttribute("title") === "t" && scratch.ownerDocument !== document);
        const list = builder.readList(scanned[1].position, -1, ul);
        check("a list holds held elements as they are, and builds the others", !builder.missing && list.nodes.length === 3 && list.nodes[0] === second && list.nodes[2] === first && list.held.has(first) && list.held.has(second)
          && list.nodes[1].localName === "li" && list.nodes[1].textContent === "new text" && !list.held.has(list.nodes[1]) && handles.lookup(4, 1) === list.nodes[1]);
        check("the list of the page itself is the record of handle zero", builder.readList(scanned[2].position, -1, document.body).nodes[0].nodeValue === "root text");
        // A held element the page does not have is reported, not guessed.
        const lost = new Builder(publication([CHILDREN, 1 + 1, 1, ...held(77, 1), END]), inert(), handles);
        lost.readList(3, -1, ul);
        check("a held element the page does not have is missing", lost.missing);
        const generation = new Builder(publication([CHILDREN, 1 + 1, 1, ...held(2, 5), END]), inert(), handles);
        generation.readList(3, -1, ul);
        check("a held element of another generation is missing", generation.missing);
        // The attributes that ask something of the page mark their record.
        const annotated = scanRecords(publication([
          ATTRS, 1 + 1, 1, ...attributes([["data-hover-rules", "+a"], ["data-embedded-node-id", "1:1:"]]), ATTRS, 2 + 1, 1, ...attributes([["title", "x"]]),
          CHILDREN, 0, 0, ...element(5, 1, "div", [["data-sl-rules", ".sl1{a:b}"], ["data-animation-transaction", "t"]]), END]));
        check("what a publication asks of the page is read wherever it sits", annotated.annotations.length === 3 && annotated.annotations[0][0] === "data-hover-rules" && annotated.annotations[1][1] === ".sl1{a:b}",
          JSON.stringify(annotated.annotations));
        const hover = new Builder(publication([ATTRS, 1 + 1, 1, ...attributes([["data-hover-rules", "+a"], ["title", "x"]])]), inert(), handles).buildAttributes(3, document.createElement("div"));
        check("the hover rules are not an attribute of any element", !hover.hasAttribute("data-hover-rules") && hover.getAttribute("title") === "x");
        // A leading line feed of the children of a textarea is dropped, as the parser drops it; a list of texts is one text.
        const area = document.createElement("textarea");
        const textarea = new Builder(publication([CHILDREN, 0, 0, TEXT, str("\nfirst"), TEXT, str(" second"), END]), inert(), handles).readList(3, -1, area);
        check("the text of a textarea is read as the parser reads it", textarea.nodes.length === 1 && textarea.nodes[0].nodeValue === "first second");
        const pre = new Builder(publication([CHILDREN, 0, 0, TEXT, str("\n\nkept"), END]), inert(), handles).readList(3, -1, document.createElement("pre"));
        check("only one leading line feed goes", pre.nodes[0].nodeValue === "\nkept");
        // Records end where the format says: a truncated one is refused.
        let refused = false;
        try { scanRecords(publication([CHILDREN, 0, 0, ...element(1, 1, "p", [])])); } catch (error) { refused = error instanceof BinaryFormatError; }
        check("a record that does not end is refused", refused);
        // Elements without a handle are built and never named.
        const bare = new Builder(publication([ROOT, 1, ELEMENT, 0, 0, str(""), str("p"), 0, END]), inert(), new Handles());
        const loose = bare.buildRoot();
        check("an element without a handle is built", loose.firstChild.localName === "p");
        // SVG: attributes on a live element of that namespace.
        const svg = document.createElementNS("http://www.w3.org/2000/svg", "clipPath");
        const foreign = new Builder(publication([ATTRS, 1, 1, ...attributes([["clipPathUnits", "objectBoundingBox"], ["xlink:href", "#a"]])]), inert(), handles).buildAttributes(3, svg);
        check("attributes of an SVG element are built in its namespace", foreign.namespaceURI === "http://www.w3.org/2000/svg" && foreign.getAttribute("clipPathUnits") === "objectBoundingBox" && foreign.getAttributeNS("http://www.w3.org/1999/xlink", "href") === "#a");
      }
      {
        const { ROOT, CHILDREN, HELD, ELEMENT, TEXT, SHAPE, DEFINE, END } = BINARY_OPS;
        const own = [];
        const str = (text) => { const atom = BINARY_ATOMS.indexOf(text); if (atom >= 0) return atom; let at = own.indexOf(text); if (at < 0) at = own.push(text) - 1; return BINARY_ATOMS.length + at; };
        const publication = (words, generation = 0) => ({ words: Uint32Array.from(words), strings: BINARY_ATOMS.concat(own), reference: null, generation });
        const attributes = (pairs) => [pairs.length, ...pairs.flatMap(([name, value]) => [str(name), str(value)])];
        const anonymous = (tag, pairs, ...children) => [ELEMENT, 0, 0, str(""), str(tag), ...attributes(pairs), ...children.flat(), END];
        const text = (value) => [TEXT, str(value)];
        // A template: <li data-n="0" class="a"><span title="x">t</span><b></b></li>, three elements and two texts' worth of values.
        const definition = [DEFINE, 7, ...anonymous("li", [["class", "a"], ["data-n", "0"]], anonymous("span", [["title", "x"]], text("t")), anonymous("b", []))];
        const templates = new Templates();
        const handles = new Handles();
        const shape = (id, entries, fills) => [SHAPE, id, entries.length, ...entries.flatMap(([index, generation, descriptor]) => [index + 1, generation, str(descriptor)]), fills.length, ...fills.flatMap(([slot, value]) => [slot, str(value)])];
        // Two rows built from it: the first changes the class and the text, the second changes nothing but the handles.
        const words = [ROOT, 2, ...definition, ...shape(7, [[10, 1, "row"], [11, 1, ""], [12, 3, "x"]], [[0, "b"], [3, "other"]]), ...shape(7, [[20, 1, ""], [21, 1, ""], [22, 1, ""]], [])];
        const root = new Builder(publication(words), inert(), handles, templates).buildRoot();
        const rows = [...root.childNodes];
        check("a definition builds a template and a shape builds from it", rows.length === 2 && rows[0].localName === "li" && rows[0].getAttribute("class") === "b" && rows[0].firstChild.firstChild.nodeValue === "other"
          && rows[1].getAttribute("class") === "a" && rows[1].firstChild.firstChild.nodeValue === "t" && rows[1].getAttribute("data-n") === "0" && rows[0].children.length === 2, rows.map((row) => row.outerHTML).join(" "));
        check("a shape registers its elements and gives them their ids", rows[0].getAttribute("data-embedded-node-id") === "10:1:row" && rows[0].lastChild.getAttribute("data-embedded-node-id") === "12:3:x"
          && handles.lookup(11, 1) === rows[0].firstChild && handles.lookup(22, 1) === rows[1].lastChild && rows[1].getAttribute("data-embedded-node-id") === "20:1:");
        check("the template is not in the page and is not changed by its instances", templates.map.get(7).root.getAttribute("class") === "a" && templates.map.get(7).root.getAttribute("data-embedded-node-id") === null && templates.map.get(7).root.firstChild.firstChild.nodeValue === "t");
        // In a list of children, a definition is not a node, and a shape is one.
        const update = publication([CHILDREN, 0, 0, ...shape(7, [[30, 1, ""], [31, 1, ""], [32, 1, ""]], [[1, "9"]]), END]);
        const scanned = scanRecords(update);
        check("the records of a list that holds a shape are split", scanned.records.length === 1);
        const list = new Builder(update, inert(), handles, templates).readList(scanned.records[0].position, -1, document.body);
        check("a list builds a shape as one node", list.nodes.length === 1 && list.nodes[0].getAttribute("data-n") === "9");
        const missing = new Builder(publication([CHILDREN, 0, 0, ...shape(99, [[40, 1, ""]], []), END]), inert(), handles, templates);
        missing.readList(3, -1, document.body);
        check("a shape the page does not have is missing", missing.missing);
        templates.adopt(1);
        const forgotten = new Builder(update, inert(), handles, templates);
        forgotten.readList(3, -1, document.body);
        check("a new generation makes the page forget its templates", forgotten.missing && templates.map.size === 0);
        let wrong = false;
        templates.adopt(1);
        try { new Builder(publication([ROOT, 1, ...definition, ...shape(7, [[50, 1, ""]], [])], 1), inert(), handles, templates).buildRoot(); } catch (error) { wrong = error instanceof BinaryFormatError; }
        check("a shape of another size than its template is refused", wrong);
      }
      // A stream the page cannot read is refused, not misread.
      const refusals = [];
      const good = new Uint8Array(fixtures[0].bytes);
      const attempt = (label, bytes) => { try { readPublication(bytes); refusals.push(`${label}: accepted`); } catch (error) { if (!(error instanceof BinaryFormatError)) refusals.push(`${label}: ${error}`); } };
      const wrongAtoms = good.slice(); wrongAtoms[8] ^= 1;
      const wrongVersion = good.slice(); wrongVersion[4] = 99;
      attempt("atoms hash", wrongAtoms);
      attempt("version", wrongVersion);
      attempt("truncated", good.slice(0, good.length - 40));
      attempt("header", good.slice(0, 10));
      attempt("not binary", new TextEncoder().encode("<div></div>"));
      return { out, records, refusals, atoms: BINARY_ATOMS.length };
    }, { base: server.base, fixtures });
    let failed = 0;
    for (const result of results.out) {
      if (result.problems.length) { failed++; console.error(`FAIL ${result.name}\n  ${result.problems.join("\n  ")}`); }
      else console.log(`PASS ${result.name} (${result.elements} elements)`);
    }
    for (const record of results.records) {
      if (record.ok) console.log(`PASS ${record.name}`);
      else { failed++; console.error(`FAIL ${record.name} ${record.detail}`); }
    }
    for (const refusal of results.refusals) { failed++; console.error(`FAIL refusal ${refusal}`); }
    assert.equal(failed, 0, `${failed} binary publication checks failed on ${engineName()}`);
    console.log(`PASS binary publication parity (${results.out.length} fixtures, ${engineName()})`);
  } finally {
    await browser.close();
    await server.stop();
  }
});
