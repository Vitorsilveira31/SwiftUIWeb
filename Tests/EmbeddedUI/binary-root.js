// Test-only encoder: the binary ROOT publication (Tools/binary-publication.js) of the tree a markup string describes. The
// fixture serves these bytes where Swift serves its publication, so the page builds the tree the markup describes without
// parsing anything itself. The markup is parsed into an inert template, and its nodes are written as the words `Builder`
// reads back: ELEMENT or ELEMENT_NS with END, and TEXT, under a ROOT.
import { BINARY_VERSION, BINARY_ATOMS_HASH, BINARY_OPS, BINARY_NAMESPACES, BINARY_ATOMS } from '../../Tools/binary-atoms.generated.js';

const { ROOT, ELEMENT, ELEMENT_NS, TEXT, END } = BINARY_OPS;
const HEADER_BYTES = 24;
const HTML_NS = 'http://www.w3.org/1999/xhtml';
const SVG_NS = 'http://www.w3.org/2000/svg';
const MATHML_NS = 'http://www.w3.org/1998/Math/MathML';
const NODE_ID = 'data-embedded-node-id';
// `<index>:<generation>:<descriptor>`: the id of an element that has a handle. Any other id is an ordinary attribute.
const HANDLE = /^(\d+):(\d+):([\s\S]*)$/;
const ATOM_INDEX = new Map(BINARY_ATOMS.map((value, index) => [value, index]));

// How the text directly inside an element is read: as the parser reads it, plain, raw (`style`), or with the first line
// feed dropped (`textarea`). Mirrors the sets in `Tools/binary-publication.js`, which does not export them.
const PLAIN = 0, RAW = 1, LEADING_LINE_FEED = 2;
const RAW_TEXT = new Set(['style', 'xmp', 'iframe', 'noembed', 'noframes', 'plaintext']);
const LINE_FEED_FIRST = new Set(['textarea', 'pre', 'listing']);

const escapeMarkup = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
const unescapeMarkup = text => text.replace(/&(amp|lt|gt|quot|#39);/g, (_, name) => ({amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'"})[name]);

/** The bytes of a binary ROOT publication of the children of `markup`, parsed into `document`'s inert template. */
export function binaryRoot(markup, document = globalThis.document) {
  const template = document.createElement('template');
  template.innerHTML = markup;
  const words = [ROOT, 0];
  const own = [], ownIndex = new Map();
  // An atom is named by its index in the list; any other string is this publication's own, appended once.
  const stringIndex = value => {
    const atom = ATOM_INDEX.get(value);
    if (atom !== undefined) return atom;
    let index = ownIndex.get(value);
    if (index === undefined) { index = BINARY_ATOMS.length + own.length; ownIndex.set(value, index); own.push(value); }
    return index;
  };
  const modeOf = element => element.namespaceURI !== HTML_NS ? PLAIN : RAW_TEXT.has(element.localName) ? RAW : LINE_FEED_FIRST.has(element.localName) ? LEADING_LINE_FEED : PLAIN;
  // The builder escapes the text of a raw element itself, so the text it is given is the one the markup would hold unescaped.
  const rawText = value => {
    const text = unescapeMarkup(value);
    if (escapeMarkup(text) !== value) throw new Error(`binary-root: raw text ${JSON.stringify(value)} is not markup the builder reads back`);
    return text;
  };

  // The nodes of a list, as the builder reads them: `mode` is the text mode of the element they are the children of. Returns
  // how many it wrote, which a ROOT holds as its count.
  const emitList = (nodes, mode) => {
    let written = 0, first = true;
    for (const node of nodes) {
      // The format has no comment: a comment is not part of the tree a publication describes.
      if (node.nodeType === 8) continue;
      if (node.nodeType === 3) {
        let value = mode === RAW ? rawText(node.nodeValue) : node.nodeValue;
        // The builder drops a line feed that starts the first child, as the parser drops the one after the start tag. A text
        // that starts with one keeps it through one more.
        if (mode === LEADING_LINE_FEED && first && value.startsWith('\n')) value = '\n' + value;
        if (value === '') continue;
        words.push(TEXT, stringIndex(value));
      } else if (node.nodeType === 1) emitElement(node);
      else throw new Error(`binary-root: a node of type ${node.nodeType} has no binary form`);
      written++; first = false;
    }
    return written;
  };

  const emitElement = element => {
    const html = element.namespaceURI === HTML_NS;
    const namespace = html ? 0 : element.namespaceURI === SVG_NS ? BINARY_NAMESPACES.svg : element.namespaceURI === MATHML_NS ? BINARY_NAMESPACES.mathml : -1;
    if (namespace < 0) throw new Error(`binary-root: <${element.localName}> is in no namespace the builder knows`);
    const handle = HANDLE.exec(element.getAttribute(NODE_ID) ?? '');
    // The handle is the index plus one and the generation; the descriptor is what the page restores the id from. A handle
    // element has no id attribute of its own: the builder writes it back from the handle.
    words.push(html ? ELEMENT : ELEMENT_NS, handle ? Number(handle[1]) + 1 : 0, handle ? Number(handle[2]) : 0, handle ? stringIndex(handle[3]) : 0);
    if (!html) words.push(namespace);
    words.push(stringIndex(element.localName));
    const attributes = [...element.attributes].filter(attribute => !(handle && attribute.name === NODE_ID));
    words.push(attributes.length);
    for (const attribute of attributes) words.push(stringIndex(attribute.name), stringIndex(attribute.value));
    // A template's children are in its content, which the builder fills.
    const children = html && element.localName === 'template' ? element.content.childNodes : element.childNodes;
    emitList(children, modeOf(element));
    // Every element ends with END, void ones included: the builder reads an element as a container either way.
    words.push(END);
  };

  words[1] = emitList(template.content.childNodes, PLAIN);

  const table = new TextEncoder().encode(own.join('\0'));
  // A first publication carries the atoms after its strings (flag 4), as Swift's does until the page acknowledges one.
  const atoms = new TextEncoder().encode(BINARY_ATOMS.join('\0'));
  const bytes = new Uint8Array(HEADER_BYTES + words.length * 4 + table.length + 4 + atoms.length);
  const view = new DataView(bytes.buffer);
  // The header: 0 and "SWB", the version, flags (4: the atoms follow), the atoms hash, then the counts.
  bytes.set([0, 0x53, 0x57, 0x42], 0);
  view.setUint16(4, BINARY_VERSION, true);
  view.setUint16(6, 4, true);
  view.setUint32(8, BINARY_ATOMS_HASH, true);
  view.setUint32(12, words.length, true);
  view.setUint32(16, own.length, true);
  view.setUint32(20, table.length, true);
  words.forEach((word, index) => view.setUint32(HEADER_BYTES + index * 4, word, true));
  bytes.set(table, HEADER_BYTES + words.length * 4);
  view.setUint32(HEADER_BYTES + words.length * 4 + table.length, atoms.length, true);
  bytes.set(atoms, HEADER_BYTES + words.length * 4 + table.length + 4);
  return bytes;
}
