# Binary patches

Instead of HTML that the page parses and diffs into the live DOM, the worker sends a binary stream: records for the
elements that changed, and instructions that build new subtrees with `createElement`. No publication is parsed as HTML in the browser: not updates, not new screens, not the first publication.
Static rendering (`SwiftUIWebHTML` for server-side rendering and previews) still produces HTML.

## Goals

- No HTML parse in the browser runtime, for any publication.
- The DOM a binary publication leaves is the DOM the tree describes. A verification mode proves it (see "Verification").
- The page keeps its host-owned rules: host-owned attributes and styles, focus and selection, IME, typed values,
  secure fields, lazy collections, WebMount, icons, style animations, and the `publish_full` recovery.
- A publication stays complete relative to the epoch the page acknowledged, so the page may still drop intermediate
  publications and commit only the newest.
- No public API changes. The HTML serializer stays for static rendering and for tests.

## Format

The stream travels in the HTML slot (`html_pointer`, `html_length`, and the `html` field of the worker's `publish`
message). Its first byte is 0, which HTML never contains. All words are little-endian `u32`, as in BrowserIO. The format
version is 5 (`_BinaryFormat.version`).

```
header   u8 0, "SWB", u16 version, u16 flags, u32 atoms hash,
         u32 word count, u32 string count, u32 string bytes
words    the records, in tree order
strings  UTF-8, separated by NUL
atoms    only with flag 4: u32 byte count, then the atoms in index order, UTF-8, separated by NUL
ref      only with flag 1 (the verification mode): a complete publication of the same tree, to the end
```

**Flags.** Bit 1 (`1`) is the verification reference above. Bit 2 (`2`) is set when a record writes an element with a
`view-transition-name` style (a matched view, see `ViewTransitionNameModifier`): the page may start a view transition for
that publication and no other. Bit 3 (`4`) says the atoms follow the strings (see "Strings"). Old readers ignore unknown
bits 1 and 2, so adding them kept the version; the atoms section moves the reference, so it came with version 4.

**Strings.** Indices below `ATOM_COUNT` name **atoms**: tags, attribute names and the framework's frequent values
(`true`, `intrinsic`, `text`, `vstack`, the layout and control class names...). Atoms are generated at build time from
one list (`Tools/binary-atoms.json`) into Swift and JavaScript by `swiftuiweb-tools`, as BrowserIO's protocol is. The
header carries the hash of the list, so a page and a worker from different builds refuse each other instead of
misreading. The page's runtime does not ship the list: the wasm has it already, so every publication carries it (flag 4)
until the host acknowledges one, and the page keeps the first copy it reads for the rest
of the session (`installAtoms` in `Tools/binary-publication.js`). A publication that arrives before the atoms, which a page
that acknowledged nothing never sees, is refused. `BINARY_ATOMS` in `Tools/binary-atoms.generated.js` is for the tests and
tools; the bundle drops it. Higher indices name this publication's own strings, which are decoded once per publication. Swift interns
values up to 64 bytes in a per-publication table (class lists and style texts repeat a lot) and appends longer ones as
they come. The values that belong to one element (its node id, its event token) are appended without a lookup.

**Handles.** An element the page holds is named by its fiber's structural id, two words (index plus one, generation); the
index word 0 names the page's own list of children. The page keeps `Handles.elements[index]` and checks the generation
(`Handles.generations[index]`). It does not check that the element is connected: an element the page removed stays in the
table until its index is built again, and a record may name it (Swift only names an element it believes the page holds,
and the page's copy is what Swift sent, wherever it is). A failed check makes the page skip the acknowledgement and ask
for `publish_full` (`keepFailure` in `Tools/embedded-dom.js`).
`data-embedded-node-id` stays an attribute, because the layout host, focus, the WebMount snapshot and the tests read it.
The handle saves the page from parsing it. A fiber whose descriptor changed counts as a new element (a new id string).

**Records** (top level):

| Record | Words | Meaning |
|---|---|---|
| `ROOT` (1) | count, node\* | the app root's children, built from scratch: the first publication, `publish_full`, and the first publication after a migration to the main thread |
| `ATTRS` (2) | handle×2, count, (name, value)\* | an element's whole own state: every attribute, `style` and `class` included |
| `CHILDREN` (3) | handle×2, node\*, `END` | an element's children, in order (handle 0: the page's own list) |

A publication the records cannot describe is sent whole, as a `ROOT`. That whole-tree publication is the escape hatch;
see "Placement" under "Swift side".

**Nodes** (inside `ROOT` and `CHILDREN`):

| Node | Words | Meaning |
|---|---|---|
| `HELD` (16) | handle×2 | an element the page holds, kept or moved here with its subtree untouched |
| `ELEMENT` (17) | handle×2, descriptor, tag, count, (name, value)\*, node\*, `END` | a new HTML element; the index word is 0 for an element without a fiber of its own. The element's `data-embedded-node-id` is not among the attributes: the page makes it from the handle and the descriptor (`index:generation:descriptor`) |
| `ELEMENT_NS` (18) | handle×2, descriptor, ns, tag, count, (name, value)\*, node\*, `END` | the same for SVG and MathML |
| `TEXT` (19) | value | a text node |
| `END` (22) | | closes an `ELEMENT`, and a `CHILDREN` record |

`ATTRS` and `CHILDREN` are idempotent: each gives the whole current state of one thing. The page compares them with
the live DOM using its usual rules, so drift on a recorded element is still repaired.

## Swift side

The snapshot (`_embeddedBrowserSnapshot`) is the source of every decoration: event routes, secure fields, WebMount
tokens, CSS layout classes, lazy attributes and the root annotations. `BinaryFiberEncoder`
(`Sources/SwiftUIWebHTML/BinaryEncoder.swift`) writes the publication in the browser runtime, and the HTML serializer does
not run for it: not for records, not for a whole tree. The bookkeeping lives in `BinaryHeldState`.

- **Attributes are assembled once.** A shared assembler writes either HTML bytes (static rendering) or (name, value)
  strings, so the names, values and order cannot drift between the two. It sorts names, joins classes (with
  `passthrough`), joins style declarations and adds event attributes.
- **What the page holds.** Each fiber records `publishedOwnHash` / `ownHashSince`, `publishedChildrenHash` /
  `childrenHashSince` (the handles of its DOM children, fragments flattened and empty nodes left out, or the text of a
  text-only parent), `firstPublishedEpoch` and `publishedIDHash` (its whole `data-embedded-node-id`, its tag and its
  namespace). An element is held when `firstPublishedEpoch` is set and at or before the acknowledged epoch, and its id
  hash did not change. Its own state is held when `ownHashSince` is at or before it, and its children when
  `childrenHashSince` is. The own hash is computed by the shared assembler writing into a hashing sink, so no bytes are
  written for it. What the page holds of the list of its own children is one more record, kept apart from the fibers'
  (the root fiber's element is one of that list).
- **A re-sent element keeps its epochs.** The three epochs mean "since the first publication that carried the element
  (or its state) unchanged". An element that a publication builds again, with the same id hash and the same state, keeps
  them: the page holds it if it acknowledged any publication since. Without this a page that acknowledges late is sent the
  whole tree by every publication, because each new root resets the epoch the next acknowledgement has to reach.
- **Visited until acknowledged.** A fiber that a publication visits gets `publishedEpoch = covered`, and a fiber with a
  `publishedEpoch` above the acknowledged epoch is visited again (`BinaryHeldState.holds`). This is what makes a publication
  the page dropped good: whatever it carried is carried again until the page acknowledges one that did.
- **The walk.** Over the visited copies, in tree order:
  - a held element whose own state is not held gets `ATTRS`; so does one whose state the host owns (form controls, tab
    views, lazy containers, popovers: the `~` of the host-owned set), when the publication has anything else to say (the
    markup of a publication that says nothing new is not applied either, so there is nothing to put the host's state back
    against). The annotations of a publication (hover rules, layout rules, the animation transaction) are attributes of the
    first element of the tree, so it changes with them and gets `ATTRS` like any other; the snapshot never replaces that
    element by a placeholder;
  - a held element whose children are not held gets `CHILDREN`: held children as `HELD`, new ones built inline;
  - a fiber unchanged since the acknowledged epoch is `HELD` wherever it sits. Held elements are not subject to the
    parser's placeholder rules: there is no minimum size and no blocked tags (`table`, `select`, `svg`...). Fewer fibers are
    visited, which also saves worker time. A fiber is still visited when it, or anything below it, holds state the host
    keeps (`Fiber.publishedHostOwned`, filled from the records) or is volatile, except the content of a tab panel the tab
    view hides, which is left as it was, lazy attributes included. The parser checks that decide whether a placeholder may
    sit where it does (a `div` in a `p`, a `td` outside a row) look at the elements on the way down from the root, not
    inside what is held.
- **Placement: a tree the parser would restructure is written as one it keeps.** Where the parser would move, drop or
  turn an element into another (`BinaryParserFacts`), the encoder writes what the parser keeps instead
  (`BinaryFiberEncoder`'s `Placement`), so the DOM is what Swift's tree says and a page that serializes it gets it back:
  - table parts the parser would add are written around the element, as elements no record names: a `tr` in a `table` gets
    a `tbody`, a `td` outside a row a `table`, `tbody` and `tr`, a block or a text in a row a `td`;
  - an element the parser would close or move is written as a neutral one with the role it stood for: a link in a link as
    a `span` (`role="link"`), a form in a form and a `p` holding a block as a `div` (`role="form"`, `role="paragraph"`), a
    heading in a heading as a `div` (`role="heading"`, `aria-level`), an `li`, `dd` or `dt` the parser would close as a
    `div`, a child of a `select` or `optgroup` that is not an option as an `option`, HTML in SVG or MathML as a group
    (`g`, `mrow`) or, for a text, `tspan` / `mtext`;
  - an element in an `option` is written as its text.
  An element the page holds that would now be written as another one (a link held, then put inside a link) cannot be
  named by a record: the encoder gives up on the publication and the publisher sends the whole tree as a `ROOT`, which
  holds no placeholder and which the page reconciles with the DOM it has. The `ROOT` fallback is also the only way such a
  change reaches the page.
- **New subtrees** are written as `ELEMENT` ... `END`. The nesting limit of 510 levels below the host's root
  (`_embeddedMaxNestedElements`) and the nested-button rule apply, so the DOM matches what the parser builds. A repeated
  subtree is written in full each time: cloning a cached template of it changed no metric of the Board benchmark
  (`Tools/compare-react.mjs`, 16 interleaved rounds) and cost about 22 KB of wasm before `wasm-opt`, so the format has no
  templates. Ops 20 and 21 are unassigned.

## Page side

`commit()` runs the sequence and identical-publication checks, captures and restores focus and selection around the patch,
hydrates secure fields, sends the acknowledgement, and runs the post-patch phases. A buffer whose first byte is 0 is read
as a binary publication (`Tools/binary-publication.js`). An update with no record (and no markup to verify against), or the
same bytes as the publication the page committed last, is treated as markup equal to the markup the page holds:
acknowledged and nothing else.

1. Check the header. A wrong version or atoms hash means the page asks for `publish_full`.
2. Decode the strings with one `TextDecoder.decode` and one `split('\0')`.
3. Read the annotations (`data-hover-rules`, `data-animation-transaction`) before applying anything.
   `scanRecords` splits the stream into records and collects those attributes from `ATTRS` records and from the elements a
   `CHILDREN` record builds; the page puts them on an element of their own and reads them from it. The hover rules are
   never written to an element.
4. Apply the records in order, inside the scope `patchChildren` opens (`deferredRemovals`, `styleAnimationQueue`):
   - **`ATTRS`**: the record's attributes are written into a scratch element of the live element's tag and namespace
     (`createElement` and one `setAttribute` each), then `patchAttributes(live, scratch)` runs. `patchStyle` reads the
     next style from the scratch element's `CSSStyleDeclaration`, so the skip predicates, `layout.captureStyles`, the
     animation arming and the icon checks stay single. Only recorded elements pay for a scratch element, and they are few
     (the ones whose own state changed). Form controls and a controlled `details` run `patchControlState(live, scratch)`
     after every record is applied. A `select`'s value is the last option it marks `selected` and a `textarea`'s is its own
     text, read from the live element: the scratch has no children.
   - **`CHILDREN`**: the list is built from the record and then reconciled (`reconcileChildren`): held elements are the live
     elements themselves, new ones are built nodes, texts are text nodes. Reconciling is keyed matching, the longest stable
     run, the cursor, and removals deferred to the end of the publication. A held element that moved under another parent
     is a `HELD` in its new parent's list. It is skipped for the element being composed, for `*children` host content, and
     for an icon whose symbol did not change. The children of an icon the adapter realized are not applied, and are not
     sent again for being new to the host.
   - **Building** (`ELEMENT`, `ELEMENT_NS`, `TEXT`): into the new parent while it is detached. Icons are realized while
     detached. Elements held and moved into a built element pass through the inert document the builder builds in, and a
     `HELD` inside a built subtree is appended to it as it is read. A built element whose handle the page already holds
     (its acknowledgement was on its way when Swift wrote this publication) is merged into the held element with the
     DOM-to-DOM `patchNode(held, built)`, so it keeps its state, and the handle names the held one from then on.
   - **`ROOT`**: build a fragment. Insert it into an empty root. Into a root that already has content (`publish_full`,
     migration), reconcile it with `patchChildren(root, fragment)`, which compares DOM with DOM.
5. The layout host and the CSS mapper keep learning from the mutation records. The same DOM calls produce them.

The page leads Swift on a tab selection until a publication names it (`data-selected-tab`): the page applies a click to the
tab buttons and panels first (`applyClientTabSelection`, `syncClientTabSelections`).

## Verification

- **`window.__binaryVerify`**: after a binary commit, the page compares the live DOM with a reference DOM of the whole current
  tree. Swift attaches the reference to the publication: the tree (a second, full snapshot when the publication is an update)
  encoded again as a complete binary publication, by a fresh encoder that holds nothing (no held state, no root
  record), so the page builds it as it builds the first publication. The reference follows the strings of the publication
  (flag 1 in the header, see the layout above). The page reads it with `readPublication`, builds it in the inert document with
  its own handles, and compares the two. The comparison covers element by element, attributes, text and order,
  and ignores what the skip predicates say the host owns. Every difference is reported, as `window.__layoutVerify` does for
  CSS layout. The reference shares the encoder and the builder with the publication, so the check covers the records against
  the whole tree, not the builder against the HTML parser: that parity is checked by the fixtures of
  `Tools/test-binary-publication-browser.mjs`, which parse the markup beside each fixture.
- **Verification exceptions.** The mode skips `aria-selected`, `tabindex`, `aria-hidden` and `data-tab-hidden` of tabs and
  panels while the page leads a tab selection, the lazy windows of a panel the page revealed, `data-keep-lazy-*` inside a
  hidden panel, the sheet detent while the person drags it, and `data-scroll-position-animated`. A harness that writes an
  attribute the publication does not carry declares it with `window.__binaryVerifyDeclare(element, names)`; the declaration
  covers those names of that element only.
- **Lagging acknowledgement.** `Tools/test-publication-browser.mjs` has a lagging-ack mode (`window.__acknowledgeLag = 2`,
  with changes that arrive faster than the page commits, so that it drops publications) that exercises the held epochs.
- **Swift tests**: the encoder's output over fixtures that the JavaScript reader builds and compares with the parser
  (`BinaryEncoderTests`, `Tools/test-binary-publication-browser.mjs`), the records of hand-built trees, and a model of the
  page (it applies only the newest publication, acknowledges late, and must end in the tree Swift has) driven by real
  fibers over random sequences of changes (it also asks for a publication in full now and then). The atoms carried until
  acknowledged have a test of their own.
- **Diagnostics.** `window.__binaryFailures` names why the page asked for a publication in full.

## Page writes into elements Swift renders

Why it matters: a record patches an element only when its own state changed, or the host keeps state in it. An ancestor
whose own state did not change is not compared, so a write by a host script that nothing re-asserts would stay. The patch
is the page's DOM-to-DOM patch (`patchAttributes`, `patchStyle`, `reconcileChildren`, `patchControlState`): an element is
patched by a record under a subset of the conditions the patch applies to any element. Records do not cover elements
inside a rich Text run, inside an icon or `*children` content, or the root element, whose attributes are always written.
The writers below are classified by how they stay correct.

H = skipped by the patch (a skip predicate; the verification mode skips the same). R = written again by its owner after
every commit or on the event that needs it. O = state with a lifecycle the owner completes (set and cleared by the same
host code). N = the element is the host's own (not rendered by Swift). None is "neither".

| Writer | What it writes, where | Class |
|---|---|---|
| `tab-shell.js` `sync()` | `data-tab-layout`, `data-tab-sidebar-expanded`, `data-tab-mobile-open`, `data-tab-mobile-bar` on the tab view; `role`, `aria-modal`, `inert`, `aria-hidden`, `aria-label` on the sidebar; `aria-expanded`, `aria-label` on toggle and button; `title`, `aria-label` on sidebar tabs; `hidden` of the backdrop | H (`tabShellOwns`: tab view, sidebar, toggles, sidebar tabs) and R (`setIfChanged` after every commit and resize); the backdrop's `hidden` is R |
| `tab-shell.js` tooltip | its own `role=tooltip` element, `hidden`, `left`, `top` | N |
| `embedded-dom.js` `applyClientTabSelection` / `syncClientTabSelections` | `aria-selected`, `tabindex` of tabs; `data-tab-hidden`, `aria-hidden` of panels | R after every commit; tabs (`role=tab`) and panels (`data-tab-panel`) are host-owned in Swift's sense, so a record always rewrites them first |
| `embedded-dom.js` `activateTab` | removes and restores `inert` around a click | O |
| `embedded-dom.js` arming (`armTransition`, `startStyleAnimations`) | `transition` style of an element whose `.animation(value:)` changed; restored to the authored one when the animation ends | O; armed by the record that changes `data-animation-value` |
| `embedded-dom.js` `patchControlState` / `applyControlState` | `value`, `checked`, `indeterminate`, `open` properties of controls | the patch itself; controls are host-owned, so every publication that visits them carries them |
| `embedded-dom.js` secure fields | `value` of a SecureField from a private buffer | R every publication (volatile fibers are always visited) |
| `embedded-dom.js` `syncDateTexts`, `syncInternationalization` | text of `[data-text-date-epoch]`, `lang` of date pickers | R after every commit |
| `embedded-dom.js` `syncImagePaints` | `width`/`height` of a pattern and its image, `background-*` of painted elements | R after every commit; H in the verification mode (`data-image-paint`) |
| `embedded-dom.js` `syncImagePipeline`, `fallbackAsyncImageLoading` | `loading`, `fetchpriority`, `decoding`, `sizes`, `width`, `height`, `data-image-ready`, `data-image-error`, `aspect-ratio` on images, `data-image-ratio` on their wrapper | H (`PIPELINE_IMAGE_HINTS`, `__managedWidth`/`Height`); R by the pipeline on each sync |
| icon adapter (`realizeIcons`, `data-lucide`) | the SVG inside an icon, `data-lucide`, `data-lucide-fallback` | H (`isIcon`, `keptIcon`); children of an icon are not kept by the page |
| `embedded-dom.js` hover (`setHoverGroup`) | `data-hover-group-active` on group members | O (set on enter, cleared on leave) |
| `embedded-dom.js` pressed state (`setPressed`) | `data-pressed` style hooks | O |
| `embedded-dom.js` IME | `data-ime-composing`, `data-composition-length` on the composing element | O; the composing element is skipped by the patch |
| `embedded-dom.js` context menu | `data-open`, `left`, `top` of a `popover` panel | popovers are host-owned: every publication that visits them carries them |
| `embedded-dom.js` menu `toggle` | `aria-expanded` of a `summary` | O (set by the `toggle` event that changes it) |
| `embedded-dom.js` split view | `data-compact-detail` of `.navigation-split-view` | H (`canvasOwns`) |
| `embedded-dom.js` gestures | `translate` style of the dragged element while it moves | O (restored at the end of the gesture) |
| `mesh-gradient.js` | `width` and `height` of the canvas of a mesh gradient | H (`canvasOwns`) |
| `embedded-dom.js` head, probes, importers, share output, color probe | `<head>` elements, off-screen probes, `<input type=file>`, `<a download>` | N |
| `layout-host.js` | `data-resizing` on the document element | N |
| `css-layout.js` mapper | `data-cl`, `data-cl-*`, `data-fit-selected`, `data-layout-hidden`, `display` of a hidden candidate, `--sl-*`, `--cl-*`; `data-fit-probe` and a saved/restored `style` during a fit pass | H (`ownsLayoutAttribute`, `ownsLayoutStyle`); the probe restores what it saved |
| `presentation-host.js` presentations | `data-presentation-id`, `data-presentation-phase`, `role`, `aria-modal`, `tabindex`, sheet detent attributes and `--presentation-detent-height` on a presentation; `inert` and `aria-hidden` on the siblings of its ancestors | R (`sync()` restores the saved state of the siblings and applies it again after every commit; the id is written every time); H in the verification mode |
| `transfer-host.js` file mover | an `<a download>` | N |
| `media-host.js` controls | `aria-valuenow`, `aria-valuetext`, `aria-disabled`, `title`, `aria-label`, widths of `.avkit-played`/`.avkit-loaded`, `left` of the thumb, texts of the time labels, `tabindex` of menu items | H (`data-host-managed` names and `*children`); menu item `tabindex` is O (set when the menu opens) |
| `media-host.js` players | `src` of an adaptive element, `data-media-start` of a view | H (`mediaHostOwns`); `data-media-start` is O |
| `media-host.js` headless players | their own elements and container | N |
| `showcase-host.js` drawer | `inert`, `role`, `aria-modal`, `aria-label` of the docs sidebar, `aria-expanded` of its toggle, `inert` of main and toc | R (`drawer()` after every commit) for `aria-expanded` and `inert`; `role`/`aria-modal`/`aria-label` are set when it opens and removed when it closes (O); H in the verification mode |
| `remote-dom-host.js` | attributes and values of elements an application's remote DOM operations name | the application's own elements; it writes what it is told |
| `feature-loader.js` | `<link>` elements in the head | N |

The verification mode is the check for writers that no record repairs: a difference it reports is either a writer missing
from this table or an element whose state a record should have sent.
