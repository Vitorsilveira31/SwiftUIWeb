// The page's side of the binary publication (Documentation/Architecture/BINARY_PATCHES.md): reads the stream Swift's
// `BinaryFiberEncoder` writes into the HTML slot and builds the DOM it describes, where the HTML transport would parse
// markup. The DOM it builds is the DOM the parser builds from the same tree's HTML, quirks included (`buildFragment`),
// and `compareDom` is how the verification mode (`window.__binaryVerify`) proves it, against a reference publication of the same
// tree that Swift attaches to each publication in that mode.
import { BINARY_VERSION, BINARY_ATOMS_HASH, BINARY_OPS, BINARY_NAMESPACES } from './binary-atoms.generated.js';

const SVG_NS = 'http://www.w3.org/2000/svg';
const MATHML_NS = 'http://www.w3.org/1998/Math/MathML';
const XLINK_NS = 'http://www.w3.org/1999/xlink';
const XML_NS = 'http://www.w3.org/XML/1998/namespace';
const XMLNS_NS = 'http://www.w3.org/2000/xmlns/';
const HEADER_BYTES = 28;
// Flag 1: a reference publication of the same tree follows the strings (the verification mode).
const FLAG_REFERENCE = 1;
// Flag 2: a record names an element for a view transition, so the page may start one for this publication (see `commit`).
const FLAG_TRANSITION = 2;
// Flag 4: the atoms follow the strings (a u32 byte count, then the atoms separated by NUL). Swift sends them until the page
// acknowledges a publication; the page keeps them for the rest of the session and ships no copy of its own.
const FLAG_ATOMS = 4;
const { ROOT, ATTRS, CHILDREN, HELD, ELEMENT, ELEMENT_NS, TEXT, SHAPE, DEFINE, END } = BINARY_OPS;
const NODE_ID = 'data-embedded-node-id';
// The attributes a publication puts on the first element of the tree to ask something of the page. The page reads them before it
// patches anything, and the hover rules are never written to an element: they are applied to a style sheet.
// Their indices are known once the atoms are (`installAtoms`).
let ANNOTATION_TRANSACTION = -1, ANNOTATION_HOVER_RULES = -1;
/** The atoms, in index order: from the first publication that carried them, or from `installAtoms`. */
let atoms = null;

/** Makes `list` the atoms of the publications read from now on. The runtime takes them from the first publication; a test
 * that builds publications without Swift passes `BINARY_ATOMS` of Tools/binary-atoms.generated.js. */
export function installAtoms(list) {
  atoms = Object.freeze([...list]);
  ANNOTATION_TRANSACTION = atoms.indexOf('data-animation-transaction');
  ANNOTATION_HOVER_RULES = atoms.indexOf('data-hover-rules');
}

/** A publication the page cannot read: from another build (its version or atoms differ), or damaged. */
export class BinaryFormatError extends Error {}

/** The bytes of a binary publication, as `html()` returns them in place of markup. */
export class BinaryBuffer {
  constructor(bytes) { this.bytes = bytes; this.length = bytes.length; }
}

/** Whether `bytes` start a binary publication: markup never starts with a NUL. */
export const isBinary = bytes => bytes.length > 0 && bytes[0] === 0;

/** Whether two publications are the same bytes: what Swift sends again until the page acknowledges it. */
export function sameBinary(a, b) {
  if (!(a instanceof BinaryBuffer) || !(b instanceof BinaryBuffer) || a.length !== b.length) return false;
  const x = a.bytes, y = b.bytes;
  for (let index = 0; index < x.length; index++) if (x[index] !== y[index]) return false;
  return true;
}

/** Whether a publication holds no record and no markup to verify against: nothing to apply. */
export function isEmptyUpdate(bytes) {
  if (bytes.length < HEADER_BYTES) return false;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  // Before the atoms arrived nothing is "nothing to apply": the page has not committed a publication yet.
  return view.getUint32(16, true) === 0 && atoms !== null && (view.getUint16(6, true) & FLAG_REFERENCE) === 0 && view.getUint16(4, true) === BINARY_VERSION && view.getUint32(8, true) === BINARY_ATOMS_HASH;
}

const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});

/** The header, the words and the string table of a publication. `bytes` is a Uint8Array of its own (the words are read
 * in place when it is aligned). `reference` is the bytes of the publication of the same tree, a whole tree for a host that
 * holds nothing, when Swift attached it (the verification mode); read it with `readPublication` again. */
export function readPublication(bytes) {
  if (bytes.length < HEADER_BYTES || bytes[0] !== 0 || bytes[1] !== 0x53 || bytes[2] !== 0x57 || bytes[3] !== 0x42) throw new BinaryFormatError('SwiftUIWeb binary publication has no header');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const version = view.getUint16(4, true), flags = view.getUint16(6, true), atomsHash = view.getUint32(8, true);
  const generation = view.getUint32(12, true), wordCount = view.getUint32(16, true), stringCount = view.getUint32(20, true), stringBytes = view.getUint32(24, true);
  // A page and a worker from different builds refuse each other instead of misreading.
  if (version !== BINARY_VERSION) throw new BinaryFormatError(`SwiftUIWeb binary publication version ${version}, expected ${BINARY_VERSION}`);
  if (atomsHash !== BINARY_ATOMS_HASH) throw new BinaryFormatError('SwiftUIWeb binary publication atoms differ from the page\'s');
  const stringsStart = HEADER_BYTES + wordCount * 4, end = stringsStart + stringBytes;
  if (end > bytes.length) throw new BinaryFormatError('SwiftUIWeb binary publication is shorter than its header says');
  const words = (bytes.byteOffset + HEADER_BYTES) % 4 === 0
    ? new Uint32Array(bytes.buffer, bytes.byteOffset + HEADER_BYTES, wordCount)
    : new Uint32Array(bytes.slice(HEADER_BYTES, stringsStart).buffer);
  // One decode and one split for every string of the publication. Markup would have been normalized by the parser's input
  // stream: a carriage return, alone or before a line feed, reads as a line feed.
  let text = stringBytes ? decoder.decode(bytes.subarray(stringsStart, end)) : '';
  if (text.includes('\r')) text = text.replace(/\r\n?/g, '\n');
  const own = stringCount ? text.split('\0') : [];
  if (own.length !== stringCount) throw new BinaryFormatError('SwiftUIWeb binary publication string table is damaged');
  let next = end;
  if (flags & FLAG_ATOMS) {
    if (next + 4 > bytes.length) throw new BinaryFormatError('SwiftUIWeb binary publication is shorter than its header says');
    const atomBytes = view.getUint32(next, true);
    if (next + 4 + atomBytes > bytes.length) throw new BinaryFormatError('SwiftUIWeb binary publication atoms are cut short');
    if (atoms === null) installAtoms(decoder.decode(bytes.subarray(next + 4, next + 4 + atomBytes)).split('\0'));
    next += 4 + atomBytes;
  }
  if (atoms === null) throw new BinaryFormatError('SwiftUIWeb binary publication arrived before the atoms');
  const reference = flags & FLAG_REFERENCE ? bytes.subarray(next) : null;
  return {words, strings: atoms.concat(own), reference, generation, transition: (flags & FLAG_TRANSITION) !== 0};
}

// What the HTML parser does to names inside SVG and MathML: it lowercases every name, then restores the case of the ones
// it knows. `createElementNS` and `setAttribute` keep what they are given, so the builder does the same.
const SVG_TAGS = new Map('altGlyph altGlyphDef altGlyphItem animateColor animateMotion animateTransform clipPath feBlend feColorMatrix feComponentTransfer feComposite feConvolveMatrix feDiffuseLighting feDisplacementMap feDistantLight feDropShadow feFlood feFuncA feFuncB feFuncG feFuncR feGaussianBlur feImage feMerge feMergeNode feMorphology feOffset fePointLight feSpecularLighting feSpotLight feTile feTurbulence foreignObject glyphRef linearGradient radialGradient textPath'.split(' ').map(name => [name.toLowerCase(), name]));
const SVG_ATTRIBUTES = new Map('attributeName attributeType baseFrequency baseProfile calcMode clipPathUnits diffuseConstant edgeMode filterUnits glyphRef gradientTransform gradientUnits kernelMatrix kernelUnitLength keyPoints keySplines keyTimes lengthAdjust limitingConeAngle markerHeight markerUnits markerWidth maskContentUnits maskUnits numOctaves pathLength patternContentUnits patternTransform patternUnits pointsAtX pointsAtY pointsAtZ preserveAlpha preserveAspectRatio primitiveUnits refX refY repeatCount repeatDur requiredExtensions requiredFeatures specularConstant specularExponent spreadMethod startOffset stdDeviation stitchTiles surfaceScale systemLanguage tableValues targetX targetY textLength viewBox viewTarget xChannelSelector yChannelSelector zoomAndPan'.split(' ').map(name => [name.toLowerCase(), name]));
// Attributes the parser puts in a namespace of their own on foreign elements.
const FOREIGN_ATTRIBUTES = new Map([
  ['xlink:actuate', XLINK_NS], ['xlink:arcrole', XLINK_NS], ['xlink:href', XLINK_NS], ['xlink:role', XLINK_NS], ['xlink:show', XLINK_NS],
  ['xlink:title', XLINK_NS], ['xlink:type', XLINK_NS], ['xml:lang', XML_NS], ['xml:space', XML_NS], ['xmlns', XMLNS_NS], ['xmlns:xlink', XMLNS_NS]
]);

// Text of an element the parser reads as raw text (no entity is decoded: the `&amp;` the serializer wrote for an
// ampersand stays what it is) or as RCDATA, and the elements whose first line feed it drops.
// `noscript` is not one of them: a template's content has no scripting, so its `noscript` is read as an element.
const RAW_TEXT = new Set(['style', 'xmp', 'iframe', 'noembed', 'noframes', 'plaintext']);
const LEADING_LINE_FEED = new Set(['textarea', 'pre', 'listing']);
const escapeMarkup = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

// How the text of the element being built is read.
const TEXT_PLAIN = 0, TEXT_RAW = 1, TEXT_LEADING_LINE_FEED = 2;

// What the builder decides from a tag name, worked out once per distinct name: the name as the parser makes it in each
// namespace, whether the element is a script (never built) or a template (its children go in its content), and how the text
// directly inside it is read.
const TAGS = new Map();
function tagInfo(name) {
  let info = TAGS.get(name);
  if (info === undefined) {
    const lower = name.toLowerCase();
    // The parser reads `<image>` as `<img>`.
    info = {html: lower === 'image' ? 'img' : lower, svg: SVG_TAGS.get(lower) || lower, foreign: lower, script: lower === 'script', template: lower === 'template',
      text: RAW_TEXT.has(lower) ? TEXT_RAW : LEADING_LINE_FEED.has(lower) ? TEXT_LEADING_LINE_FEED : TEXT_PLAIN};
    if (TAGS.size > 4096) TAGS.clear();
    TAGS.set(name, info);
  }
  return info;
}

/** Refuses a count of words that runs past the publication: a damaged count (0xffffffff attribute pairs) would otherwise
 * keep a loop going for billions of turns, past the end of the words. */
function within(words, position, length) {
  if (!(length >= 0) || position + length > words.length) throw new BinaryFormatError('SwiftUIWeb binary publication has a count that runs past its end');
}

/** The templates of the shapes the page holds, by id (`DEFINE`), for the generation of the shape table that defined them. */
export class Templates {
  constructor() { this.map = new Map(); this.generation = 0; }
  /** The templates are Swift's to keep: a new generation of its table means none of these is any longer. */
  adopt(generation) { if (generation !== this.generation) { this.map.clear(); this.generation = generation; } }
}

/** The elements a publication built, by the handle Swift gave them (the index and generation of the fiber's structural id).
 * A record names an element this way. An element of a handle that was built again, or whose generation differs, is not the
 * one the record means: the lookup fails and the page asks Swift for a publication in full. */
export class Handles {
  /** `recover(index, generation)` finds the element in the page when the one the table holds has left it: something other
   * than a publication replaced it (a host script, a test) and the page holds a copy under the same id. */
  constructor(recover = null) { this.elements = []; this.generations = []; this.size = 0; this.recover = recover; }
  register(element, index, generation) {
    if (this.elements[index] === undefined) this.size++;
    this.elements[index] = element; this.generations[index] = generation;
    // The page reads a built element's handle when it merges the element into one it holds.
    element.__swi = index; element.__swg = generation;
  }
  lookup(index, generation) {
    const element = this.elements[index];
    if (element === undefined || this.generations[index] !== generation) return null;
    if (this.recover !== null && !element.isConnected) {
      const found = this.recover(index, generation);
      if (found !== null) { this.register(found, index, generation); return found; }
    }
    return element;
  }
  clear() { if (this.size > 0) { this.elements = []; this.generations = []; this.size = 0; } }
}

/** Where the values of a template are: for each, the element that holds it (by its place among the template's elements), and
 * the attribute it is, or the child that is the text. A shape names a value by its place in this list. */
function planOf(words, strings, begin, end) {
  const plan = [], open = [];
  let ordinal = -1, position = begin;
  while (position < end) {
    const word = words[position];
    if (word === ELEMENT || word === ELEMENT_NS) {
      const namespace = word === ELEMENT_NS ? words[position + 4] : 0, countAt = position + (word === ELEMENT_NS ? 6 : 5), pairs = words[countAt];
      // The element is a child of the one open, and a text after it is the next.
      if (open.length) open[open.length - 1].children++;
      ordinal++;
      open.push({ordinal, children: 0});
      within(words, countAt + 1, pairs * 2);
      for (let pair = 0; pair < pairs; pair++) plan.push({element: ordinal, child: -1, namespace, name: strings[words[countAt + 1 + pair * 2]]});
      position = countAt + 1 + pairs * 2;
    } else if (word === TEXT) {
      const parent = open[open.length - 1];
      plan.push({element: parent.ordinal, child: parent.children++, namespace: 0, name: null});
      position += 2;
    } else if (word === END) { open.pop(); position++; }
    else throw new BinaryFormatError(`SwiftUIWeb binary publication has an unknown op ${word} in a template`);
  }
  return plan;
}

/** What a list of nodes is read as: the text mode of the element the list is the children of. */
export function textModeOf(element) {
  return element.namespaceURI === 'http://www.w3.org/1999/xhtml' ? tagInfo(element.localName).text : TEXT_PLAIN;
}

/** Builds the nodes a publication describes in `document`, which should be inert so that nothing loads before the nodes are
 * inserted into the page's own, as the nodes of a parsed template do not. A script is not built: the commit strips the
 * scripts of every template it parses. */
export class Builder {
  constructor(publication, document, handles, templates = new Templates()) {
    this.words = publication.words; this.strings = publication.strings; this.document = document; this.handles = handles; this.templates = templates;
    this.attributeNames = new Map();
    this.missing = false;
  }

  /** The nodes of a list read from `position`: `count` top-level nodes (a ROOT), or the ones before the END that closes the
   * record (CHILDREN; `count` is -1). `parent` is the live element the list is the children of, which says how its text
   * is read. `held` holds the top-level nodes that were already in the page, named by a HELD; a missing one sets `missing`. */
  readList(position, count, parent) {
    const {words, strings, document, handles} = this;
    const nodes = [], held = new Set();
    const containers = [], textModes = [];
    let current = null, textMode = parent === null ? TEXT_PLAIN : textModeOf(parent), topLevel = 0, lastText = null;
    // Whether the next text would be the first child of the element being built, and how many levels of a script are
    // being skipped.
    let firstChild = true, skipping = 0;
    while (count < 0 || topLevel < count || containers.length > 0) {
      const word = words[position++];
      if (word === ELEMENT || word === ELEMENT_NS) {
        const index = words[position++] - 1, generation = words[position++], descriptor = strings[words[position++]];
        const namespace = word === ELEMENT_NS ? words[position++] : 0;
        const name = strings[words[position++]], pairs = words[position++];
        within(words, position, pairs * 2);
        if (containers.length === 0) topLevel++;
        if (skipping > 0) { position += pairs * 2; skipping++; continue; }
        const info = tagInfo(name);
        if (info.script) { position += pairs * 2; skipping = 1; continue; }
        const element = namespace === 0 ? document.createElement(info.html)
          : namespace === BINARY_NAMESPACES.svg ? document.createElementNS(SVG_NS, info.svg) : document.createElementNS(MATHML_NS, info.foreign);
        for (const end = position + pairs * 2; position < end; position += 2) {
          if (words[position] === ANNOTATION_HOVER_RULES) continue;
          const attribute = strings[words[position]], value = strings[words[position + 1]];
          try {
            if (namespace === 0) element.setAttribute(attribute, value);
            else setForeignAttribute(element, namespace, attribute, value, this.attributeNames);
          } catch { /* a name the parser would take and the DOM refuses: the verification mode reports the difference */ }
        }
        // An element Swift gave no handle (it is not a fiber's) is built and never named again; the others carry their id.
        if (index >= 0) { handles.register(element, index, generation); element.setAttribute(NODE_ID, index + ':' + generation + ':' + descriptor); }
        if (current === null) { nodes.push(element); lastText = null; } else current.appendChild(element);
        containers.push(current = namespace === 0 && info.template ? element.content : element);
        textModes.push(textMode = namespace === 0 ? info.text : TEXT_PLAIN);
        firstChild = true;
      } else if (word === END) {
        if (skipping > 0) { skipping--; continue; }
        if (containers.length === 0) break;
        containers.pop(); textModes.pop();
        current = containers.length > 0 ? containers[containers.length - 1] : null;
        textMode = containers.length > 0 ? textModes[textModes.length - 1] : parent === null ? TEXT_PLAIN : textModeOf(parent);
        firstChild = false;
      } else if (word === TEXT) {
        let text = strings[words[position++]];
        if (containers.length === 0) topLevel++;
        if (skipping > 0) continue;
        if (textMode !== TEXT_PLAIN) {
          if (textMode === TEXT_RAW) text = escapeMarkup(text);
          else if (firstChild && text.charCodeAt(0) === 10) text = text.slice(1);
        }
        firstChild = false;
        if (text === '') continue;
        // Adjacent texts are one text node, as the parser makes them.
        if (current === null) {
          if (lastText !== null) lastText.appendData(text); else nodes.push(lastText = document.createTextNode(text));
        } else {
          const last = current.lastChild;
          if (last !== null && last.nodeType === 3) last.appendData(text); else current.appendChild(document.createTextNode(text));
        }
      } else if (word === DEFINE) {
        position = this.define(position);
      } else if (word === SHAPE) {
        const id = words[position++], elements = words[position++], handlesAt = position;
        within(words, position, elements * 3);
        position += elements * 3;
        const fills = words[position++], fillsAt = position;
        within(words, position, fills * 2);
        position += fills * 2;
        if (containers.length === 0) topLevel++;
        if (skipping > 0) continue;
        const template = this.templates.map.get(id);
        if (template === undefined) { this.missing = true; continue; }
        const clone = template.root.cloneNode(true);
        const built = [clone, ...clone.querySelectorAll('*')];
        if (built.length !== elements) throw new BinaryFormatError('SwiftUIWeb binary publication has a shape of another size than its template');
        for (let at = 0; at < elements; at++) {
          const index = words[handlesAt + at * 3] - 1;
          if (index < 0) continue;
          const generation = words[handlesAt + at * 3 + 1];
          handles.register(built[at], index, generation);
          built[at].setAttribute(NODE_ID, index + ':' + generation + ':' + strings[words[handlesAt + at * 3 + 2]]);
        }
        for (let at = 0; at < fills; at++) {
          const slot = template.plan[words[fillsAt + at * 2]], value = strings[words[fillsAt + at * 2 + 1]];
          if (slot === undefined) throw new BinaryFormatError('SwiftUIWeb binary publication fills a place its shape does not have');
          const target = built[slot.element];
          if (slot.child >= 0) target.childNodes[slot.child].nodeValue = value;
          else {
            try {
              if (slot.namespace === 0) target.setAttribute(slot.name, value);
              else setForeignAttribute(target, slot.namespace, slot.name, value, this.attributeNames);
            } catch { /* see above */ }
          }
        }
        if (current === null) { nodes.push(clone); lastText = null; } else current.appendChild(clone);
        firstChild = false;
      } else if (word === HELD) {
        const index = words[position++] - 1, generation = words[position++];
        if (containers.length === 0) topLevel++;
        if (skipping > 0) continue;
        const element = handles.lookup(index, generation);
        if (element === null) { this.missing = true; continue; }
        if (current === null) { nodes.push(element); held.add(element); lastText = null; } else current.appendChild(element);
        firstChild = false;
      } else throw new BinaryFormatError(`SwiftUIWeb binary publication has an unknown op ${word}`);
    }
    return {nodes, held, position};
  }

  /** A template for a shape (the words after a DEFINE): built like any subtree, kept, and not put in the page. Returns where the
   * definition ends. */
  define(position) {
    const id = this.words[position++], begin = position;
    const built = this.readList(position, 1, null);
    this.templates.map.set(id, {root: built.nodes[0], plan: planOf(this.words, this.strings, begin, built.position)});
    return built.position;
  }

  /** The fragment of the children of the root a ROOT record holds. */
  buildRoot() {
    const fragment = this.document.createDocumentFragment();
    if (this.words[0] !== ROOT) throw new BinaryFormatError('SwiftUIWeb binary publication does not start with a root');
    for (const node of this.readList(2, this.words[1], null).nodes) fragment.appendChild(node);
    return fragment;
  }

  /** An element with the attributes of the ATTRS record at `position` (the word of their count), of the namespace and name
   * of `live`: the page patches the element it holds from it as it patches one from the markup it parsed. */
  buildAttributes(position, live) {
    const {words, strings, document} = this;
    const namespace = live.namespaceURI === SVG_NS ? BINARY_NAMESPACES.svg : live.namespaceURI === MATHML_NS ? BINARY_NAMESPACES.mathml : 0;
    const element = namespace === 0 ? document.createElement(live.localName) : document.createElementNS(live.namespaceURI, live.localName);
    const pairs = words[position++];
    within(words, position, pairs * 2);
    for (const end = position + pairs * 2; position < end; position += 2) {
      if (words[position] === ANNOTATION_HOVER_RULES) continue;
      const attribute = strings[words[position]], value = strings[words[position + 1]];
      try {
        if (namespace === 0) element.setAttribute(attribute, value);
        else setForeignAttribute(element, namespace, attribute, value, this.attributeNames);
      } catch { /* see readList */ }
    }
    // The id belongs to the element's handle, which does not change: it is not in the record.
    const id = live.getAttribute(NODE_ID);
    if (id !== null) element.setAttribute(NODE_ID, id);
    return element;
  }
}

/** Where the element that starts at `position` ends: after its END. */
function skipNode(words, position) {
  let depth = 0;
  for (;;) {
    if (position >= words.length) throw new BinaryFormatError('SwiftUIWeb binary publication has a record that does not end');
    const word = words[position];
    if (word === ELEMENT) { position += 6 + words[position + 5] * 2; depth++; }
    else if (word === ELEMENT_NS) { position += 7 + words[position + 6] * 2; depth++; }
    else if (word === TEXT) position += 2;
    else if (word === END) { position++; if (--depth === 0) return position; }
    else throw new BinaryFormatError(`SwiftUIWeb binary publication has an unknown op ${word} in a template`);
  }
}

/** Splits an update into its records, as `{op, position, index, generation}`: `position` is where the record's body starts (the
 * count of an ATTRS record's pairs, the first node of a CHILDREN record's list) and `index` is -1 for the page's own list of
 * children. `annotations` are the `[name, value]` pairs of what the publication asks of the page (a transaction, hover rules,
 * layout rules) on whatever element carries them, whether the record has it by ATTRS or builds it. */
export function scanRecords(publication) {
  const {words, strings} = publication;
  const records = [], annotations = [];
  const annotationsAt = (at, pairs) => {
    for (const end = at + pairs * 2; at < end; at += 2) {
      const name = words[at];
      if (name === ANNOTATION_TRANSACTION || name === ANNOTATION_HOVER_RULES) annotations.push([strings[name], strings[words[at + 1]]]);
    }
  };
  let position = 0;
  while (position < words.length) {
    const op = words[position];
    if (op === ATTRS) {
      const index = words[position + 1] - 1, generation = words[position + 2], pairs = words[position + 3];
      annotationsAt(position + 4, pairs);
      records.push({op, position: position + 3, index, generation});
      position += 4 + pairs * 2;
    } else if (op === DEFINE) {
      // The definition of a shape: the element that follows is its template.
      records.push({op, position: position + 1, index: -1, generation: 0});
      position = skipNode(words, position + 2);
    } else if (op === CHILDREN) {
      const index = words[position + 1] - 1, generation = words[position + 2];
      records.push({op, position: position + 3, index, generation});
      // The nodes up to the END that closes the record.
      let depth = 0;
      position += 3;
      for (;;) {
        if (position >= words.length) throw new BinaryFormatError('SwiftUIWeb binary publication has a record that does not end');
        const word = words[position];
        if (word === ELEMENT) { annotationsAt(position + 6, words[position + 5]); position += 6 + words[position + 5] * 2; depth++; }
        else if (word === ELEMENT_NS) { annotationsAt(position + 7, words[position + 6]); position += 7 + words[position + 6] * 2; depth++; }
        else if (word === DEFINE) position += 2;
        else if (word === SHAPE) { const after = position + 3 + words[position + 2] * 3; position = after + 1 + words[after] * 2; }
        else if (word === HELD) position += 3;
        else if (word === TEXT) position += 2;
        else if (word === END) { position++; if (depth === 0) break; depth--; }
        else throw new BinaryFormatError(`SwiftUIWeb binary publication has an unknown op ${word}`);
      }
    } else throw new BinaryFormatError(`SwiftUIWeb binary publication has an unknown record ${op}`);
  }
  return {records, annotations};
}

/** The hover rules a whole tree (`ROOT`) carries, or null. The builder leaves `data-hover-rules` off the element it builds (the
 * rules go to a style sheet, not the DOM), so the page reads them from the stream. */
export function rootHoverRules(publication) {
  const {words, strings} = publication;
  let position = 2;
  while (position < words.length) {
    const word = words[position];
    if (word === ELEMENT || word === ELEMENT_NS) {
      const at = position + (word === ELEMENT ? 6 : 7), pairs = words[at - 1];
      for (let pair = at; pair < at + pairs * 2; pair += 2) if (words[pair] === ANNOTATION_HOVER_RULES) return strings[words[pair + 1]];
      position = at + pairs * 2;
    } else if (word === DEFINE) position += 2;
    else if (word === SHAPE) { const after = position + 3 + words[position + 2] * 3; position = after + 1 + words[after] * 2; }
    else if (word === HELD) position += 3;
    else if (word === TEXT) position += 2;
    else if (word === END) position++;
    else throw new BinaryFormatError(`SwiftUIWeb binary publication has an unknown op ${word}`);
  }
  return null;
}

// The attribute of a foreign element as the parser names it: lowercase, with the case it restores for the ones it knows,
// and in a namespace of its own for `xlink:*`, `xml:*` and `xmlns`.
function setForeignAttribute(element, namespace, name, value, cache) {
  let adjusted = cache.get(name);
  if (adjusted === undefined) {
    const lower = name.toLowerCase();
    adjusted = [FOREIGN_ATTRIBUTES.get(lower) || null, namespace === BINARY_NAMESPACES.svg ? SVG_ATTRIBUTES.get(lower) || lower : lower === 'definitionurl' ? 'definitionURL' : lower];
    cache.set(name, adjusted);
  }
  // The cache is shared by SVG and MathML elements; only `definitionURL` and the SVG list differ, and they do not collide.
  if (adjusted[0] !== null) element.setAttributeNS(adjusted[0], adjusted[1], value); else element.setAttribute(adjusted[1], value);
}

// --- Verification ---------------------------------------------------------------------------------------------------

/** Compares the DOM under `live` with the one under `expected` (what the parser built from the markup of the same tree),
 * element by element, and returns every difference as `{path, kind, ...}`. `options` says what the host owns and so
 * what to leave out: `attributeOwned(element, name)` and `styleOwned(element, name)` for the live element,
 * `contentOwned(element)` for an element whose children another owner writes. */
export function compareDom(live, expected, options) {
  const differences = [];
  const limit = 200;
  const describe = node => {
    const parts = [];
    for (let current = node; current && current !== live && parts.length < 8; current = current.parentNode) {
      if (current.nodeType !== 1) continue;
      const id = current.getAttribute('data-embedded-node-id');
      parts.push(current.localName + (id ? '[' + id.split(':').slice(0, 2).join(':') + ']' : ''));
    }
    return parts.reverse().join(' > ');
  };
  const report = (node, kind, detail) => {
    if (differences.length < limit) differences.push({path: describe(node), element: node.nodeType === 1 ? node.localName + (node.getAttribute('class') ? '.' + node.getAttribute('class').split(' ')[0] : '') : '#text', kind, ...detail});
  };
  const walk = (a, b) => {
    if (differences.length >= limit) return;
    if (a.nodeType !== b.nodeType) { report(a, 'nodeType', {live: a.nodeType, expected: b.nodeType}); return; }
    if (a.nodeType === 3) { if (a.nodeValue !== b.nodeValue) report(a.parentNode || a, 'text', {live: a.nodeValue, expected: b.nodeValue}); return; }
    if (a.nodeType !== 1) return;
    if (a.localName !== b.localName || a.namespaceURI !== b.namespaceURI) { report(a, 'tag', {live: a.namespaceURI + ' ' + a.localName, expected: b.namespaceURI + ' ' + b.localName}); return; }
    compareAttributes(a, b);
    if (options.contentOwned(a)) return;
    // The content of a template is not a child.
    const x = a.localName === 'template' && a.namespaceURI !== SVG_NS ? a.content : a, y = b.localName === 'template' && b.namespaceURI !== SVG_NS ? b.content : b;
    // An element playing its removal transition (transition-host.js) is not part of the publication.
    // A content-transition run (transition-host.js) stands for the text node it replaces.
    const children = [...x.childNodes].filter(node => node.nodeType !== 1 || !node.hasAttribute('data-transition-leaving'))
      .map(node => node.nodeType === 1 && node.hasAttribute('data-content-run') ? node.ownerDocument.createTextNode(node.getAttribute('data-content-run')) : node), others = y.childNodes;
    const shared = Math.min(children.length, others.length);
    if (children.length !== others.length) report(a, 'children', {live: children.length, expected: others.length});
    for (let index = 0; index < shared; index++) walk(children[index], others[index]);
  };
  const compareAttributes = (a, b) => {
    // The style of either may be empty, or hold only what the host owns: its declarations are compared, not the attribute.
    if (a.hasAttribute('style') || b.hasAttribute('style')) compareStyle(a, b);
    for (const attribute of a.attributes) {
      const {name, value} = attribute;
      if (name === 'style' || options.attributeOwned(a, name)) continue;
      const other = b.getAttributeNode(name);
      if (other === null) { report(a, 'attribute-extra', {name, live: value}); continue; }
      if (other.value !== value) report(a, 'attribute', {name, live: value, expected: other.value});
      else if (other.namespaceURI !== attribute.namespaceURI || other.prefix !== attribute.prefix) report(a, 'attribute-namespace', {name, live: attribute.namespaceURI, expected: other.namespaceURI});
    }
    for (const {name, value} of b.attributes) {
      if (name === 'style' || options.attributeOwned(a, name) || a.hasAttribute(name)) continue;
      report(a, 'attribute-missing', {name, expected: value});
    }
  };
  // Style text may be written differently (the patch writes declarations one by one); the declarations are what count.
  const compareStyle = (a, b) => {
    const declarations = element => {
      const map = new Map();
      for (const property of element.style) {
        if (!options.styleOwned(a, property)) map.set(property, element.style.getPropertyValue(property) + (element.style.getPropertyPriority(property) ? ' !important' : ''));
      }
      for (const [property, value] of options.styleText(element.getAttribute('style') || '')) if (value.includes('var(') && !property.startsWith('--') && !options.styleOwned(a, property)) map.set(property, value);
      return map;
    };
    const mine = declarations(a), theirs = declarations(b);
    for (const [property, value] of mine) if (theirs.get(property) !== value) report(a, 'style', {name: property, live: value, expected: theirs.get(property) ?? null});
    for (const [property, value] of theirs) if (!mine.has(property)) report(a, 'style', {name: property, live: null, expected: value});
  };
  const x = live, y = expected;
  const shared = Math.min(x.childNodes.length, y.childNodes.length);
  if (x.childNodes.length !== y.childNodes.length) report(x, 'children', {live: x.childNodes.length, expected: y.childNodes.length});
  for (let index = 0; index < shared; index++) walk(x.childNodes[index], y.childNodes[index]);
  return differences;
}
