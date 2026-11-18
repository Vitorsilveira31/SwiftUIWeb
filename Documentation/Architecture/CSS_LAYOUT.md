# CSS layout

The browser lays out the page with its own flexbox and grid. CSS is the only layout: the page works out the CSS from the
layout attributes Swift publishes, in JavaScript after each DOM patch (`Tools/css-layout.js`, driven by
`Tools/layout-host.js`). The islands are the semantic roots of the page: the application's
root view with its `.sidebarAdaptable` TabView and NavigationStacks (title bar and toolbar items included), the content of the
sidebar's slots (expanded or a collapsed rail), a presentation's content, and the layout trees that native widgets host.
Chromium and WebKit are tested; Firefox is not yet (one difference is handled: a VStack child's height cap, below).

## Switches

There is no way to turn CSS layout off. `window.__layoutVerify` (`SWIFTUIWEB_LAYOUT_VERIFY=1` with the browser suites) compares
every incremental flush with an analysis from scratch (see "Checks").

## How it works

1. **Islands.** Each layout pass first offers the mapper the semantic roots it can be given whole (`CssLayout.claimRoot`,
   `claimCssRoots` in `Tools/layout-host.js`), each with what its container proposes:
   - the application's root view: the window (the root's width and `100dvh`), centred;
   - the content of a sidebar slot: the slot's width and the content's own height, leading (centred in a collapsed rail,
     where the mapper leaves out what the browser does not display);
   - the content of a NavigationSplitView column: the column's content box (the stylesheet makes the column a flex column
     of definite height), centred;
   - a pane of an HSplitView or VSplitView: the box Swift's split layout gave its item (a one-cell grid, `data-cl-host`), the
     content centred across and at the top where it hugs (see "Split views");
   - a presentation's content (a sheet, a popover, an alert) that holds the root alone: its content box, which the mapper
     makes a one-cell grid (`data-cl-host`; a percentage height there resolves against the padding box in WebKit);
   - an alert's or a confirmation dialog's message, which shares the content with the actions (the stylesheet's flex row):
     the content's width, as tall as it needs, centred;
   - the layout tree of a table cell: nothing is proposed, so it is as large as its ideal size (`width: max-content`),
     which the browser sizes the table's columns from;
   - the views a Chart draws in an SVG `foreignObject` (annotations, custom axis labels): proposed the foreignObject's box,
     which is a flex box Swift justified and aligned for the view, so the box places the view;
   - a `Grid` a native widget hosts (a Form row, a disclosure): the width of its container, as tall as it needs, leading;
   - in a documentation page (`data-native-layout="document"`), an example's preview (`data-layout-root`): the width of
     its container and nothing along the height, centred at the top. The page's own
     chrome (the shell, the sidebar, the header) is the stylesheet's and has no root.

   The mapper styles all of a claimed root, and a window resize leaves it nothing to do. A root nobody can lay out (CSS refuses
   something in it, or its container proposes it nothing) is not laid out: the host counts it in
   `window.__embeddedSession.layoutMetrics.unlaid` (the roots of the last pass), logs it once, and leaves it to the stylesheet.
   A page that lays out with CSS alone leaves it at 0, which the fixtures suite
   (`Tools/test-css-layout-fixtures-browser.mjs`) asserts for every fixture and `Tools/test-showcase-live.mjs` for every Showcase
   route. An island that stops being expressible is released (`CssLayout.release`): its elements lose their blocks. A semantic root
   that is not CSS's inside an island keeps its mutations (`CssLayout.setForeign`).
2. **Analysis.** The mapper reads the `data-*` layout attributes Swift emits, the same the host reads, and works out per
   node and axis whether its size is fixed, takes what it is offered (`fill`), has a minimum, a maximum or a cap, or does
   not give way below its ideal size (`rigid`). A top-down pass adds whether the proposal on each axis is finite: SwiftUI
   proposes nothing along a vertical ScrollView's axis and below `fixedSize`, and there `.infinity` frames and Spacers do
   not fill.
3. **Emission.** Each node gets one declaration block for its context. The blocks are rules of constructed stylesheets,
   and a commit writes only the elements whose block changed. An element carries `data-cl-n`, which its rule
   (`[data-cl-n]`) matches, and `data-cl="n"`, which names it for diagnostics. The rules of the blocks a pass creates go
   into a stylesheet of their own, adopted after the others, and the sheets are merged into one when the page is idle:
   Chromium takes a rule inserted into an adopted stylesheet as a change of the whole sheet and restyles every element
   any of its rules matches, so each new block (a frame whose width follows the window) restyled every element the mapper
   styles, where an appended sheet restyles what its own rules match. The browser files attribute selectors by
   attribute name, so a rule per attribute name is found as directly as a class; with `[data-cl="n"]` rules every styled
   element was tested against every rule, and a full style recalculation of a large production-style screen took
   4.2 ms against 3.1 ms (2.9 ms without the rules). The Content-Security-Policy does not apply to constructed stylesheets.
4. **Incremental.** A DOM mutation inside an island marks the element and its ancestors; the next layout pass analyses
   those again and styles the nodes whose context changed. A text change costs nothing: the browser lays text out. A
   refused island is analysed from scratch at the next pass, since its mutations do not reach the mapper.

## Lengths that change

A length that follows a resize, a scroll or an animation (a frame's size, a fixed size, a minmax or fit-content track of a
frame, a position, a lazy collection's extents) is not part of a block's rule: the rule reads `var(--cl-len<i>)` and the
element carries the values as inline custom properties (`style="--cl-len0:961px"`), in the order the lengths stand in the
block (`vpx` marks them, `lengthVariables` splits them off). With the lengths inside the rule, every resize step would mint a
new rule per frame that differs only in a length, and a rule inserted into a stylesheet makes WebKit invalidate the style of
the whole document, 10 to 19 ms of style and layout on a large app's board; now a step changes one inline declaration.
Paddings, gaps, spacings and the other lengths a view authors stay in the rule: they do not follow the window. The blocks of a
collapsed rail keep their lengths in the text (an element carries one set of properties, its expanded block's). A DOM patch
leaves the `--cl-len<i>` properties alone (`ownsLayoutStyle`). `window.__layoutVerify` compares the lengths as well as the
blocks.

## The mapping

| SwiftUI | CSS |
| --- | --- |
| `VStack`/`HStack(spacing:alignment:)` | `display:flex`, `gap`, `align-self` per child; a child fills the cross axis only when the proposal there is finite |
| HStack children sharing the width | `flex: W 1 0%; min-width:0; max-width:max-content` (equal shares, each capped at its ideal size); rigid children `flex:0 0 auto` |
| VStack children sharing the height | the same, with `max-height:max-content`, written `flex: var(--sl-hug-grow,W) 1 var(--sl-hug-basis,0%)`. Firefox ignores an intrinsic `max-height` on a flex item, so `Tools/styles.css` sets the two variables for Firefox only (`@supports (-moz-appearance: none)`): there the child keeps its content's height (`flex: 0 1 auto`), and in a column too short for every child it shrinks in proportion to that height instead of taking an equal share |
| `Spacer` | `flex-grow` last in line (`1` against `1e6`); `min-width` is its minimum length |
| `layoutPriority(p)` | a `flex-grow` tier `1e6^(p+1)` (the order is right; see below). Swift writes whole and half priorities (exact: `1e6^1.5` is `1e9`); another is the page's, since `Math.pow` rounds it differently from engine to engine |
| `frame(width:height:alignment:)` | `width`/`height`; the child aligned in a one-cell grid |
| `frame(maxWidth: .infinity)` | fills (`stretch` or `flex-grow`); `minWidth` is `min-width` |
| `frame(maxWidth: 560)` | offered a width, takes it clamped to 560 (along a stack's axis it grows from nothing to 560, sharing what is left with its siblings); offered none, takes its content's, clamped (`max-width: 560px`) |
| `frame(minHeight: 300)` | offered nothing, proposes its minimum: a view in it that fills is 300 tall (one track `minmax(300px, auto)`) |
| `Canvas.frame(...)` | a Canvas keeps its element when it is framed, so the frame has no child: the drawing is a flexible leaf the analysis adds (as the host does), which takes the frame's proposal (`frame(height: 120)` is as wide as it is offered; offered nothing, 10 pt) |
| `padding` | `padding`; a negative inset is a negative margin of the children (a filling child is `calc(100% + outset)`) |
| `ZStack`, `overlay`, `background` | one-cell grid; secondary layers `position:absolute; inset:0`, aligned by margins, so they never size the stack. A layer as tall or wide as its content aligns that content at the start and makes its flexible rows `max-content` (no change where the box hugs its tracks; WebKit would measure both from the containing block) |
| `fixedSize` | `max-content` on the fixed axes |
| `GeometryReader` | a box that takes its proposal, children at the top leading corner; 10 pt when offered nothing; `contain: size`, so what it holds never sizes it |
| `ScrollView` inside a root | takes its proposal along the axes it scrolls; across them it is as large as its content, which it holds at its top leading corner, and its parent places it: a horizontal shelf in a VStack is as tall as its cards |
| `TabView` with `.sidebarAdaptable` | one-cell grid inset by the stylesheet's `--tab-sidebar-width` and `--tab-bottom-inset`; the sidebar is the stylesheet's; the selected tab's body and panel take the proposal |
| `Spacer` across its stack | as thin as its content: its flexibility and minimum length are along the stack's axis only |
| `NavigationStack` (and the legacy `NavigationView`, rendered as one: `navigation-stack navigation-view`) | a grid of two rows: the bar (the stylesheet's `::before` title, a grid item, and the toolbar items: leading, centred or trailing, centred in the title row or in a large title's top 3rem; several items on one side get a column each, 8 px apart, in the order they were declared; several principal items get a column each, touching, between two equal flexible columns, so the group is centred on the bar and starts 8 px after the leading items at the earliest; with several items on a side as well, the group is centred between the two blocks of items (one row of columns cannot centre on the bar without knowing the widths of the items), and items too wide for the bar are pushed past its end) and the screen; a pushed screen replaces the root, which the stylesheet hides and the mapper hides by the stack's depth when its `aria-hidden` is gone (a presentation's focus isolation restores that attribute), and so does a destination presented with `navigationDestination(isPresented:)`, `navigationDestination(item:)` or an active `NavigationLink`, which hides the screen below it as SwiftUI pushes it; an item with nothing to show is not shown |
| `Divider` | an `hr` a point thick (the stylesheet's border) that takes the whole length across the stack it is in: horizontal in a VStack, a ZStack, a frame and anywhere else, vertical in an HStack, also through a `frame`, a `padding`, a `fixedSize` or an `overlay` around it (`Divider().frame(height: 20)`), as SwiftUI runs it. Along a stack's cross axis it stretches (`align-self: stretch`) even where the stack is proposed no length there, so a row of no height is as tall as its other views and the rule as tall as the row. A vertical rule draws its line on its leading edge. Apple: `x-divider-*` |
| a linear `ProgressView`, a `Slider` | as wide as they are offered (a `field`: a text field, which also has no width of its own); a progress bar is 8 px tall, the track its view authors (the browser gives `appearance: none` no height), a slider as tall as its track. In an HStack they take what their neighbours leave. Apple: `x-progress-*`, `x-slider-*` (widths and positions; macOS draws a bar 20 pt tall and a slider 16) |
| a linear `Gauge` | as wide as it is offered, the label above the track with the stylesheet's 8 px gap, as wide as its text. Apple: `x-gauge-*` (widths and positions) |
| `TextEditor` | flexible both ways: the height of its frame (or what its stack leaves), where it scrolls its text; offered no height it is its two rows. Apple: `x-editor-*` |
| a leaf's own padding | kept: a native button's or a text field's stylesheet padding is part of its size |
| `aspectRatio` | `aspect-ratio` and `width:100%` where it takes the proposal; `max-width` of the height that the frames and paddings sharing its element propose to it times the ratio (`frame(maxHeight: 250)` proposes 250, `aspectCap`), so a `.fit` box is not wider than the frame is tall allows |
| `LazyVGrid`, `Grid`/`GridRow` | `display:grid` with the tracks of the columns; virtualisation extents are the grid's padding, the after-rows spacer at its end. A `Grid` sizes a row from what its cells take offered no height, then proposes each cell its row's height: a cell that fills (a card holding a chart) stretches to it |
| `Button` with a text label | gives way below its ideal width (its label truncates), as a native leaf measured at the offered width |
| `Link` | as wide as its label, which wraps where it must: the inline `a` is measured as text (an `inline-block` as tall as its lines) |
| a menu `Picker` | the width of a copy of the select that holds only its selected option, measured by the page at each pass (`sizeSelects`, `--sl-select-w`); `field-sizing: content` until then (Chromium). Along an HStack it is that wide at most and gives way down to its arrows in a row too narrow for it, as Apple's pop-up button does (`x-picker-row-tight`) |

**A run of layout modifiers on one element.** A chain of `frame`, `padding` and `fixedSize` shares one element (the
outermost modifier's, with the others in `data-layout-wrap`, see "A run of layout modifiers is one element" in
[PERFORMANCE_CONTRACTS.md](../Performance/PERFORMANCE_CONTRACTS.md)). CSS has one box for it, so `CssLayout.chainPlan` folds
the chain into a one-cell grid, per axis:

- the element's own frame is the box, and the paddings right inside it are its padding;
- the frames inside those make the grid track: a fixed, `fixedSize` or min/max frame is the track's size; the frame that
  holds it aligns the track (`justify-content`/`align-content`, `unsafe`, so a track larger than the box overflows it on both
  sides as SwiftUI centres it); the innermost frame aligns the children;
- a frame with no size on an axis takes its child's size there, so it does nothing on that axis, except as the group of
  several children (the track then hugs them: `fit-content(100%)`);
- a `.infinity` frame with a minimum around the track keeps the element at least that large, and so does a frame with a
  minimum and no maximum, which also aligns the track;
- a padding inside the innermost frame is the margin of its one child.

A chain one box cannot express is refused (two sized frames inside the paddings, a frame inside an inner padding, an inner
padding around several children, a filling minimum that overflows a fixed box): Swift does not merge such a chain
(`_SemanticLayers.isFoldable`), it keeps an element for each wrapper, and CSS lays those out one by one.
`Tools/test-css-layout-layers.mjs` lays out every chain of up to four layers (frame, padding and fixedSize variants, one and
two views) as wrapper elements and as one element and requires the same rectangles, or a refusal, and that the chains it
refuses are the ones `SemanticLayerTests` counts as unfoldable.

**Several views in a wrapper.** A frame, padding, fixedSize or aspect ratio modifier on a `Group` wraps each of its views
(as SwiftUI does), so these wrappers hold one view. The wrappers the framework builds itself (a Section's header and footer)
put several views in a vstack of their own, leading and with no spacing (`_semanticHeld`), which is what the host's `@group`
stacks them in, so CSS sees one child.

## What CSS does not match

The oracle (`bun Tools/css-layout-oracle.mjs --check`) lays out the SwiftUI trees of the layout conformance suite and 36 extra
fixtures with CSS only, and compares them with real Apple SwiftUI frames
(`Tests/LayoutConformance/apple-macos-css.json` and `apple-macos-css-extra.json`, recorded on macOS 27 with
`Tools/LayoutConformance/run-apple.sh` and `run-css-apple.sh`). Chromium and WebKit give the same results. It fails when a node
outside its list of 14 known misses misses, or a known miss passes:

- **`layoutPriority` minimum.** SwiftUI keeps a truncated `Text` at the width of its ellipsis (6.5 pt); CSS gives it 0
  (6 nodes). The order of the priorities is right.
- **Tight text boxes.** SwiftUI reports a wrapped `Text` as wide as its longest line, and a truncated one-line `Text` as
  wide as what it draws ("Resched…"); a CSS box is as wide as the offer, so the slack its siblings get differs (6 nodes,
  8 to 22 pt; a truncated label is 1 to 3 px wider than SwiftUI's).
- **Height truncation.** SwiftUI truncates a `Text` to a proposed height; CSS overflows (1 node).
- **An aspect box around a Layout that is smaller than the fit.** SwiftUI sizes a capped frame with its aspect box proposed no height
  (320 x 155 for Food Truck's hero, which the frame caps at 100), then places the box at the 200 x 100 fit, where the Layout answers 95:
  the box takes the Layout's size. CSS keeps the box at the fit, so the frame, the stack and the Layout match and the box is 5 pt taller
  (`x-aspect-hero.aspect`; the box is not drawn).

Alignment guides are out of reach as well, and refused where they occur. A `safeAreaInset`, and a TabView with its bottom tab bar (the host lays both out as an inset), is a grid of a track for
the inset, as large as its ideal size along its edge and aligned across it, and one for the content, which takes what is
left (`Tools/test-css-layout-fixtures-browser.mjs` lays the lowering app's
`EmbeddedInsetFixture` out on Chromium and WebKit and requires every semantic root to have its layout). A `.position(x:y:)` takes its proposal (10 pt where there is none, as a
GeometryReader does) and centres its content on its point: the content is absolutely positioned there (`left`, `top`,
`translate: -50% -50%`; a global `:dir(rtl)` rule measures the point from the right), offered the
whole space, so a long text wraps at its width (`EmbeddedPlacementFixture`). Among a stack's views the host offers it at
most 10 pt (its answer to an unlimited proposal, as for an aspect box: `capIdeal`); what such a 10 pt position offers its
own content, and the share its siblings get, can differ from the host's there. A `ViewThatFits` is laid out with the
page's measurements (the choice needs them). It is a ZStack of the candidate it shows,
as large as that candidate; the others keep their blocks and the stylesheet hides them. At each pass (a patch, a resize
of the window) `chooseFits` shows the first candidate whose ideal size fits what the ViewThatFits is offered on the axes
it chooses along, else the last:
- what it is offered: nothing on an axis with no proposal; where the candidate shown fills, its box; elsewhere a probe
  (`probeFits`, `[data-fit-probe]`) lays it out once as a view that takes all it is given, with no candidate shown, and
  reads its box. Along a stack's axis that is the share a flexible view of its priority gets (a Spacer keeps its
  minimum, so a Spacer is sized last); across, its whole proposal, `max-width: 100%` of what holds it, which
  content-sized ancestors give up to their own proposal;
- a candidate's ideal size: shown out of the flow, proposed nothing on those axes (`max-content`) and its proposal on
  the other, measured once and again after a change inside it.

A ViewThatFits inside a candidate of another is proposed nothing on the axes it chooses along while the candidate's ideal
size is measured, so it shows its first candidate there (`measureIdeals`); all are
chosen before any is shown, and `chooseFits` repeats (at most four passes) while a choice changes the ideal size around it.
A ViewThatFits that shares a stack with other views is probed with that stack widened to take all it is offered, and one
inside another's candidate is probed after the outer one (a probe shows no candidate).
A ViewThatFits with no candidate (`ViewThatFits { EmptyView() }`) is a ZStack of nothing, with a zero size, and `chooseFits` has nothing to select; with one, that one is shown whether it fits or not.
`EmbeddedFitFixture` covers candidates that fill, Food Truck's parking spot card (a ViewThatFits beside a Spacer in an
HStack, in three widths), candidates as wide as their content, a vertical choice, a resize of the window, and the cases
above: no candidate, one candidate, a ViewThatFits in a candidate, candidates from a `ForEach` and from an `if`, one in a
ZStack, in a horizontal ScrollView and over both axes. A `containerRelativeFrame` is a frame whose size on the axes it selects is Swift's sampled length function, piecewise linear,
written as a CSS expression (`relativeLength`: a sum of ramps, `max(0px, var(--sl-cw) - c)`, and a `clamp` step where a
container length has two samples) of its container's length; the samples are sorted, so a function that
decreases, bends or arrives unsorted is the same expression. `Tools/test-css-layout-relative.mjs` compares it with
the reference function at container lengths from 0 to 3000. The frame can carry layers (`data-layout-wrap`): it is the
outermost, fixed-size box of the chain, and `chainPlan` folds the layers inside it as it does inside a fixed frame (Swift never
writes this today: `containerRelativeFrame` is not a layer kind, so it always has an element of its own). A gap shared with
fixed frames: inside a box larger than its content, a frame with a minimum width and no maximum is laid out as the box's track
rather than as large as its content, so `test-css-layout-layers.mjs` leaves those chains out below a relative frame.
`updateContainers` reads a ScrollView's length from its box, which is its proposal only where the ScrollView fills it: a
vertical ScrollView whose content is narrower hugs that content on the CSS path, and a relative frame in it reads a width of
0 (the fixtures give such content the full width). At each pass `updateContainers` writes that length on the containers
a relative frame reads it from (a
ScrollView, a NavigationStack, a pushed screen or a tab's panel, the semantic root) as `--sl-cw`/`--sl-ch`: the box on an
axis where the container has a proposal (it fills it), else nothing, so the outer container's inherited value applies;
a semantic root's is what it is proposed (the window: its container's width and `100dvh`). Inherited
variables find the nearest container without CSS containment, which would make a ScrollView the containing block of the
fixed-position menus inside it (`EmbeddedRelativeFixture`). A `LabeledContent` row is a grid: `grid-template-columns: minmax(0,1fr) auto`, the row's spacing as its gap and its padding, both
cells centred; the value takes its ideal width and shrinks no narrower than its longest word (a text in a labeled cell keeps
its words, `min-width: min-content`), the label takes what is left and may fall to zero. The row is as wide as it is
offered; among a stack's views it is offered at most its ideal width (`max-width: max-content`, `capContent`) (`EmbeddedLabeledFixture`). A ScrollView holding several views (a `List`'s
rows) stacks them the same way, from the top, leading, with no spacing: its grid has a row for each, as tall as its view
(`grid-template-rows: none; grid-auto-rows: max-content`, so a fixed height never squeezes the rows).

A composite leaf the layout does not look into (a List row's link, a list, a table, a segmented picker; not a native
control, nor a span, which is measured as text) takes the finite width it is offered, as the host measures it under
that proposal. Along an HStack it keeps its ideal width: the host finds it as wide at a zero as at an unlimited proposal, so
it is not flexible there. The mapper calls that a soft fill (`axis.soft`): a fill on the cross axis and in a cell, rigid
along a stack's axis, which a container passes on when every view of it that fills is soft.
A NavigationSplitView is a `flexible` leaf whose columns the stylesheet's grid lays out: it keeps the stylesheet's
`display`, and the content of each column is a semantic root of its own, which the mapper lays out with CSS (a column's
content box, see "Islands").

**A user-defined `Layout`** runs in Swift (`sizeThatFits`, `placeSubviews`); CSS and the page's measurements give it what the
host's solve gives it. The wrapper (`layout-box`) is a `size` leaf of the width and height Swift wrote for the proposal it
was last told. Each subview sits in an item (`layout-item`) that is a semantic root of its own, proposed what the Layout
placed it with (`data-layout-child-proposal`: a width and a height, either left empty): it takes a finite proposal where it
fills and wraps at it otherwise (`max-content` clamped by `max-width`, with `min-width: min-content`), and is as large as its
content on an axis left empty (`max-content`). Swift writes the placed point (`left`, `top`) and the anchor as shares of the
item's own size (`--layout-anchor-x/y`), which the mapper applies as a `translate`: the size is the page's, so the Layout
can pin a centre without knowing it. After each layout pass (`reportLayouts`) the mapper tells Swift, with the events
`layoutproposal` and `layoutsizes`:
- the proposal the Layout is offered, read as a ViewThatFits's is (`probeFits`): the wrapper is laid out once as a view that
  takes all it is given, on the axes that are proposed a size when SwiftUI asks for one (`prop`: `definite` with `strict`), and
  its box is read; nothing on the others. That is nothing along the axes a hugging view above asks for an ideal size along, as
  a `fixedSize`, a ScrollView along its axis, and a Grid that is itself proposed nothing do (a Grid asks its cells with the
  proposal it has, then places them in the row it found), and it does not count a frame's minimum as a proposal (a frame passes
  a missing proposal on; the GeometryReader in it is only placed at the minimum, which `def` counts). Each Layout is probed on
  its own, the rest of the page as it is laid out: the views raised for one take what they are offered, which can take it from
  a view beside them (a header's Layout raised in the window's VStack left the TabView below it no height, and the Layout of
  the TabView's page, probed in the same layout, was offered none);
- the size each subview took at the proposal it was placed with, once every subview is a root of the mapper (else the host
  reports what it laid out), then its size at each other proposal the Layout asked it about. Swift writes those on the item
  (`data-layout-asks`, the first four: SwiftUI's `sizeThatFits` of a subview at a proposal it does not place it with, such as
  `.unspecified` for an ideal size, or the height it is offered before it places the subview at the height that answers), and
  the mapper lays the item out at each one as it lays it out at the placed proposal (`measureAsks`: the item is out of the
  flow, so nothing else moves), reads it, and puts it back.
Swift re-renders when either changes, as before: one render for a new proposal, one for the sizes it brings. Until the page has
measured a proposal, Swift answers it from its estimate; a proposal the Layout asks about first after a render is measured
after the next one.
`Tools/test-css-layout-fixtures-browser.mjs` lays
`EmbeddedLayoutFixture` out (a wrapping flow, a radial layout, ideal-width columns, Layouts inside one another and in
a ScrollView, a publication and a resize) and `EmbeddedLayoutParityFixture` (Layouts that ask a subview about
another proposal than the one they place it with, and two Layouts in one VStack, against Apple's frames) on Chromium and
WebKit, and requires that the mapper
refuses nothing in it.

A Layout that is offered no height grows its row, its card and its frame to the size it answers: Food Truck's donut lattice in a
hugging `Grid` row is 548 x 329 at a 1180 px window, as on Apple (`x-layout-grid-hug`, `x-layout-grid-tall`, `x-layout-stack-hug`
and `x-layout-scroll` of the oracle, whose harness answers the reported proposals with the Layouts' own `sizeThatFits`). Where a
parent hugs its content along an axis it is offered, the page offers the Layout what that parent is offered (`reportLayouts`
makes it take its offer while it reads). What a Layout is offered in a `Grid` row of a definite height is not modelled: the
wrapper contributes nothing to the row, so the row is as tall as the other cells.

**Split views.** An `HSplitView` or `VSplitView` is a user-defined Layout (`_SplitLayout`) whose wrapper (`layout-box split-pane`) is
treated as above: a box of the size Swift wrote, offered the proposal the page reports. Swift places each pane in an item
(`split-item`, absolute, with its box inline: the divider positions, `_SplitViewStateStore`, and the panes' minimum, ideal and
maximum extents decide the slot in Swift) and each divider beside it. The content of a pane is a
root of the mapper, proposed its slot on both axes; the item is a one-cell grid (`data-cl-host`), so the root fills it
(`maxWidth: .infinity`), takes `min(slot, maximum)` and at least its minimum (a `frame(minWidth:idealWidth:maxWidth:)`), or hugs its
content, centred across and at the top. A pane the mapper refuses is the host's alone, and the
split view around it stays CSS's. The mapper never reads the divider positions: they only change the slots Swift writes. A divider
drag (`Tools/split-view-host.js`) writes the two panes' boxes itself, which the mapper observes like any other change, and reports the
settled fractions to Swift (`split-positions`), so the next render places the slots from them.
`EmbeddedSplitFixture` (two and three panes, panes that hug and fill, frames with a minimum, an ideal and a maximum, a text that
wraps, a ScrollView and a split view in a pane, a publication and a resize) has its boxes checked against the recorded ones, and the
test requires that the mapper refuses nothing in it and that no root is left without a layout.

## Checks

| Check | What |
| --- | --- |
| `bun Tools/css-layout-oracle.mjs --check` | CSS against Apple SwiftUI, the layout conformance suite and its extra fixtures |
| `bun Tools/test-css-layout-fixtures-browser.mjs` | the lowering app's fixtures, in each step (opened, clicked, resized): no root left without a layout, no page error or block mismatch, and the boxes Apple's frames decide |
| `bun Tools/test-css-layout-layers.mjs` | a merged layer chain, with a `containerRelativeFrame` outermost too, is laid out like its wrapper elements, or refused |
| `bun Tools/test-css-layout-relative.mjs` | a `containerRelativeFrame`'s length as CSS equals the reference function through Swift's samples |
| `bun Tools/test-css-layout-incremental.mjs` | incremental styling equals styling from scratch after random edits |
| `bun Tools/test-css-layout-roots.mjs` | a window root with a `.sidebarAdaptable` TabView, NavigationStack bars (several items on each side and principal items between them) and pushed screens over a root the stylesheet shows, foreign roots, appended rule sheets, release |
| `SWIFTUIWEB_LAYOUT_VERIFY=1` with the browser suites | every flush is compared with an analysis from scratch (`CssLayout.verify`: a `css block` entry in `window.__layoutMismatch`) |

The first four run in `make integrated-check`.

