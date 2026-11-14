/// Staged rendering: a view tree of any depth renders on a shallow call stack.
///
/// Rendering is a plain recursion (`_render` calls the children's `_render`), about ten WebAssembly frames per view
/// level, and WebKit gives a Worker's WebAssembly a fixed, small stack. Staging keeps the recursion short without
/// changing what it computes, in the manner of React Fiber's work loop: once the render has descended
/// `_RenderStaging.budget` levels, a container that is about to render its children stops, keeps the children as a
/// *deferred job* and returns. The job renders later from the loop that drives the whole pass, on a call stack that
/// is shallow again, and the pass publishes nothing until the loop has run dry.
///
/// A deferred job is invisible to everything that reads the tree:
/// - the container's `_RenderNode.children` is a lazy value. Reading it (or cloning the node deeply, or any other
///   inspection) runs the job on the spot, exactly where plain recursion would have run it, so a consumer can never
///   see a half-built tree. Only code that passes the node along (a modifier handing it to its wrapper, an owner
///   recording its token) leaves the job pending, and it is the loop that runs it;
/// - the job captures what its render reads from the dynamic extent of the call: the render context (environment,
///   identity path, state store, preference store, owner registry and token, layout proposal), and the thread state
///   (the installed environment, the state scope, the animation transaction). It resumes with identical identity,
///   so `@State`, `onAppear`, tasks, focus and the diff cannot tell a staged render from a plain one;
/// - preferences are an append-only sequence per key that `onPreferenceChange` and friends reduce in write order.
///   A job writes later than plain recursion would have, so writes carry an order tag that places a job's writes
///   where its container stood, and reading a preference first runs every pending job, because plain recursion has
///   rendered everything before the reader by then;
/// - `EquatableView` runs the jobs its content left pending before it decides whether the content read any state.
///
/// The cut sites are the places where a container renders children it only collects (the layout container of the
/// stacks and grids). Chains with no such place (a long run of modifiers or conditionals) still recurse.
package enum _RenderStaging {
  /// How many scoped view levels the render may descend before a cut site defers its children. Zero or less turns
  /// staging off. The deepest real screen measured in the smallest Worker stack (WebKit on iOS) needs about 250
  /// probe frames of the ~550 that fit, and one scoped level costs about 5 of them, so a job of this many levels
  /// stays far inside the stack that is left after the host has dispatched the render.
  ///
  /// Only the Embedded renderer, which tracks state reads itself, stages by default. A native build tracks
  /// `@Observable` reads with Swift's Observation, which records them in the dynamic extent of the owner that is
  /// rendering, and a deferred job runs after that extent has ended; tests turn staging on to exercise it.
  #if hasFeature(Embedded)
  nonisolated(unsafe) package static var budget = 12
  #else
  nonisolated(unsafe) package static var budget = 0
  #endif

  /// The staging state of the thread that is rendering (render state is per thread, see `_RenderThreadState`).
  @inline(__always) static var state: _RenderStagingState { _RenderThreadState.current.staging }

  /// Jobs created and run on this thread since it started, for tests and diagnostics.
  package static var jobsCreated: Int { state.jobsCreated }
  package static var jobsRunFromLoop: Int { state.jobsRunFromLoop }
  package static var jobsRunInline: Int { state.jobsRunInline }
  package static var nodeJobsCreated: Int { state.nodeJobsCreated }
  package static var nodeJobsForced: Int { state.nodeJobsForced }

  /// Whether a cut site should defer its children now.
  @inline(__always) package static var wantsDeferral: Bool { budget > 0 && state.depth >= budget }

  /// Whether jobs are waiting.
  @inline(__always) static var hasPending: Bool { state.hasPending }

  /// The order tag of the next preference write.
  static func nextWriteTag() -> _OrderTag {
    let state = self.state
    defer { state.orderCounter &+= 1 }
    return state.orderPrefix.appending(state.orderCounter)
  }

  /// Whether preference writes carry an order tag (a job has been created on this thread).
  static var tagging: Bool { state.tagging }

  /// Keeps the rendering of `content` as a job and returns it.
  @MainActor package static func defer_<Content: View>(
    _ content: Content, context: _RenderContext, shape: _DeferredShape = .flattened
  ) -> _DeferredChildren {
    enqueue(_DeferredContent(content, context: context, shape: shape))
  }

  /// Keeps the building of a container's child list as a job, for a container that does more with its content than
  /// collect it (it wraps it, or decides from it what else to add) and has the whole list built when the job runs.
  @MainActor package static func defer_(building build: @escaping @MainActor () -> [_RenderNode], after source: _RenderNode? = nil) -> _DeferredChildren {
    enqueue(_DeferredBuilt(source: source, build))
  }

  @MainActor private static func enqueue(_ job: _DeferredChildren) -> _DeferredChildren {
    let state = self.state
    state.tagging = true
    state.jobSequence &+= 1
    state.jobsCreated &+= 1
    job.orderPrefix = state.orderPrefix.appending(state.orderCounter &- 1).appending(state.jobSequence)
    state.queue.append(job)
    return job
  }

  /// Runs the jobs the pass left, from the loop that drives it. Called when the outermost scoped level ends; each
  /// job starts at depth zero, because the loop's own call stack is as shallow as the pass's first level was.
  @inline(never)
  @MainActor static func drive() {
    let state = self.state
    guard !state.driving else { return }
    state.driving = true
    // A job that waits for a render under way (`isReady`) is kept for the loop that is above that render.
    var waiting: [_DeferredChildren] = []
    while true {
      while state.queueHead < state.queue.count {
        let job = state.queue[state.queueHead]
        state.queueHead += 1
        if !job.finished {
          if !job.isReady { waiting.append(job); continue }
          state.jobsRunFromLoop &+= 1
          job.run(freshStack: true)
        }
      }
      // The queue is dry: the innermost container that is waiting for it goes on. What it renders next queues
      // jobs, and the loop runs them before the next stage.
      guard let entry = state.takeDeepestStage(deeperThan: -1) else { break }
      entry.job.runStage(freshStack: true)
    }
    state.queue = waiting
    state.queueHead = 0
    // Everything has rendered: the attributes that depend on the children can be looked up now.
    var next = 0
    while next < state.finalizers.count {
      state.finalizers[next].finish()
      next += 1
    }
    state.finalizers.removeAll(keepingCapacity: true)
    runOrderedEffects(state)
    state.driving = false
  }

  /// Runs the ordered effects of the pass in the order plain recursion would have run them. An effect may queue
  /// another, which runs after the ones already due.
  @MainActor private static func runOrderedEffects(_ state: _RenderStagingState) {
    while !state.orderedEffects.isEmpty {
      var batch = state.orderedEffects
      state.orderedEffects.removeAll(keepingCapacity: true)
      _sortByOrderTag(&batch)
      for effect in batch { effect.run(effect.tag) }
    }
  }

  /// Runs `effect` where plain recursion would have run it: at once while nothing has been deferred, otherwise when
  /// the loop that drives the pass has run dry, in the order of the positions the effects were requested at. For
  /// callbacks the application observes in render order (`onChange`, `onPreferenceChange`, a presentation's
  /// `onDismiss`): a deferred part of the tree requests its effects later than plain recursion would have, and
  /// running them as they come would reorder them. `effect` receives the position it was requested at, or `nil` when it
  /// runs at once (the order tag of a preference read, see `_PreferenceStore.value(for:before:)`).
  @MainActor package static func ordered(_ effect: @escaping @MainActor (_OrderTag?) -> Void) {
    let state = self.state
    // Outside a scoped render nothing will drive the loop again, so the effect cannot wait for it.
    guard state.tagging, state.depth > 0 || state.driving else {
      effect(nil)
      return
    }
    state.orderedEffects.append(_OrderedEffect(tag: nextWriteTag(), order: state.orderedEffects.count, run: effect))
  }

  /// Runs every pending job where the caller stands. For code that needs the whole tree rendered so far: a
  /// preference reader, the end of an `EquatableView`, a navigation stack collecting its toolbars. The jobs keep the
  /// depth of the caller, which is how far down the stack it is, so a job stages again at the first opportunity
  /// and the loop here, not the recursion, carries the rest.
  @inline(never)
  @MainActor static func flush() {
    let state = self.state
    var index = state.queueHead
    while index < state.queue.count {
      let job = state.queue[index]
      index += 1
      if !job.finished { job.run(freshStack: false) }
    }
    state.skipFinished()
  }

  /// Runs the jobs queued from `index` on, including those they queue, from where the caller stands.
  @MainActor static func finish(from index: Int) {
    let state = self.state
    var next = index
    while next < state.queue.count {
      let job = state.queue[next]
      next += 1
      if !job.finished { job.run(freshStack: false) }
    }
    state.skipFinished()
  }

  /// `flush()` for callers that are not isolated to the main actor (the render is, whatever calls it).
  static func flushFromAnywhere() {
    guard hasPending else { return }
    _assumeMainActor { flush() }
  }
}

/// What staging tracks for one rendering thread.
final class _RenderStagingState: @unchecked Sendable {
  /// Scoped view levels entered and not yet left, counted from the start of the pass or of the job being run.
  var depth = 0
  /// True while the loop that drives the pass is running its jobs.
  var driving = false
  var queue: [_DeferredChildren] = []
  var queueHead = 0
  /// Jobs whose owner derives an attribute from the children, once the loop has run dry (`completeOwner`).
  var finalizers: [_OwnerCompletion] = []
  var hasPending: Bool { queueHead < queue.count }
  /// The stage that waits for the pass to settle and is nested deepest, when it is deeper than `depth`; the first one
  /// registered among equals.
  func takeDeepestStage(deeperThan depth: Int) -> _StageEntry? {
    var best = -1
    var index = 0
    while index < stages.count {
      let entry = stages[index]
      if entry.job.isWaiting(generation: entry.generation) {
        if entry.depth > depth, best < 0 || entry.depth > stages[best].depth { best = index }
      } else {
        stages.remove(at: index)
        if best >= index { best -= 1 }
        continue
      }
      index += 1
    }
    return best >= 0 ? stages.remove(at: best) : nil
  }
  /// Moves the head of the queue past the jobs that have run, so a reader does not look at them again.
  func skipFinished() {
    while queueHead < queue.count, queue[queueHead].finished { queueHead += 1 }
  }
  /// Side effects that plain recursion would have run at their position in the render, kept with that position until
  /// the loop has run dry (see `_RenderStaging.ordered`).
  var orderedEffects: [_OrderedEffect] = []
  var jobsCreated = 0
  var nodeJobsCreated = 0
  var nodeJobsForced = 0
  var jobsRunFromLoop = 0
  var jobsRunInline = 0
  // Preference write order (see `_PreferenceStore`).
  /// True once a job has been created; before that the writes are in plain order and need no tag.
  var tagging = false
  var orderPrefix = _OrderTag()
  var orderCounter = 0
  var jobSequence = 0
  var opSequence = 0
  /// How many staged containers (see `_StagedRender`) the render is inside of: a container gathers what its content
  /// leaves behind once the containers inside it have, so it waits for the stages that are deeper than its own.
  var stageDepth = 0
  /// The stages waiting for the pass to have rendered what is queued (see `_StagedRender`).
  var stages: [_StageEntry] = []
  var stageSequence = 0
}

/// A stage waiting for the pass to settle.
struct _StageEntry {
  let depth: Int
  let order: Int
  let generation: Int
  let job: _StagedRender
}

/// The children of a container, rendered later. See `_RenderStaging`.
package class _DeferredChildren {
  fileprivate(set) var nodes: [_RenderNode] = []
  fileprivate(set) var finished = false
  fileprivate var running = false
  fileprivate var environment: EnvironmentValues?
  fileprivate var scope: StateScope?
  fileprivate var animation: Animation?
  fileprivate var animationActive = false
  fileprivate var readRecorder: _EnvironmentReadRecorder?
  fileprivate var stageDepth = 0
  fileprivate var orderPrefix = _OrderTag()
  /// What the node that owns these children derives from them once they have rendered.
  var ownerCompletion: _OwnerCompletion?

  @MainActor init() {
    let thread = _RenderThreadState.current
    environment = thread.environment
    scope = thread.stateScope
    animation = thread.animation
    animationActive = thread.animationActive
    readRecorder = EnvironmentValues._readRecorder
    stageDepth = thread.staging.stageDepth
  }

  deinit {
    // The rendered nodes may be the last reference to a deep tree (see `_RenderNode.deinit`).
    if !nodes.isEmpty { _RenderThreadState.current.nodeGraveyard.bury(&nodes) }
  }

  /// Renders the children. Overridden by the generic job.
  @MainActor func render() -> [_RenderNode] { [] }
  /// Whether the job can run now. A job that waits for the result of another one cannot run while that one is under
  /// way (code that runs every pending job, a navigation stack or a tab view collecting what it holds, would reach it
  /// from inside the render it waits for): it stays in the queue, and the loop that drives the pass gets to it.
  @MainActor var isReady: Bool { true }
  /// Renders the job, and everything it needs, here and now: the reader of its node needs it complete. Whoever reads
  /// the children of a node runs this; a job built in stages (`_StagedRender`) also runs its stages.
  @MainActor func forceCompletion() {
    let first = _RenderStaging.state.queue.count
    run(freshStack: false)
    _RenderStaging.finish(from: first)
  }
  /// Renders the job where the caller stands, for the reader of the node that stands in for it (`_RenderStaging.force`).
  @MainActor func forceRun() { run(freshStack: false) }
  /// Hands the owner's completion the children that have rendered (see `_OwnerCompletion.postpone`).
  @MainActor fileprivate func completeOwner() {
    guard let record = ownerCompletion else { return }
    ownerCompletion = nil
    record.child = nodes.first
    record.postpone()
  }

  /// Lets go of what the job captured once it has run.
  @MainActor func release() {}
  /// Called once the job has run and the thread state is back as the caller left it.
  @MainActor func didFinish() {}

  /// Runs the job unless it has run, installing what it captured and putting back what was there.
  @MainActor final func run(freshStack: Bool) {
    guard !finished, !running, isReady else { return }
    running = true
    let thread = _RenderThreadState.current
    let savedEnvironment = thread.environment
    let savedScope = thread.stateScope
    let savedAnimation = thread.animation
    let savedActive = thread.animationActive
    let state = _RenderStaging.state
    let savedDepth = state.depth
    let savedPrefix = state.orderPrefix
    let savedCounter = state.orderCounter
    let savedRecorder = EnvironmentValues._readRecorder
    let savedStageDepth = state.stageDepth
    thread.environment = environment
    thread.stateScope = scope
    thread.animation = animation
    thread.animationActive = animationActive
    EnvironmentValues._readRecorder = readRecorder
    state.stageDepth = stageDepth
    if freshStack { state.depth = 0 }
    state.orderPrefix = orderPrefix
    state.orderCounter = 0
    if !freshStack { state.jobsRunInline &+= 1 }
    nodes = render()
    thread.environment = savedEnvironment
    thread.stateScope = savedScope
    thread.animation = savedAnimation
    thread.animationActive = savedActive
    EnvironmentValues._readRecorder = savedRecorder
    state.stageDepth = savedStageDepth
    state.depth = savedDepth
    state.orderPrefix = savedPrefix
    state.orderCounter = savedCounter
    release()
    finished = true
    running = false
    completeOwner()
    didFinish()
    // A job run where the loop is not (a node read after the pass, with nothing driving) may have queued jobs
    // of its own; with no loop above it they run now.
    if savedDepth == 0, !state.driving, state.hasPending || !state.orderedEffects.isEmpty || !state.stages.isEmpty { _RenderStaging.drive() }
  }
}

/// What a container derives from the child it renders and keeps as an attribute: the work is done once the pass has
/// rendered everything, so that looking through the child (which can reach deferred parts of the tree) happens
/// from the loop that drives the pass and not from the middle of the recursion, and a reader that cannot wait does
/// it where it stands.
final class _OwnerCompletion {
  let kind: _ChildrenCompletion
  var owner: _RenderNode?
  var child: _RenderNode?
  /// The job that renders the child, while it has not.
  var job: _DeferredChildren?
  init(kind: _ChildrenCompletion, owner: _RenderNode, child: _RenderNode?, job: _DeferredChildren?) {
    self.kind = kind; self.owner = owner; self.child = child; self.job = job
  }

  /// Waits for the end of the pass when it is running, otherwise (or if nothing is deferred) does the work now.
  @MainActor func postpone() {
    let staging = _RenderStaging.state
    if staging.driving || staging.hasPending || !staging.stages.isEmpty { staging.finalizers.append(self) } else { finish() }
  }

  @MainActor func finish() {
    guard let owner else { return }
    self.owner = nil
    owner._attributeJob = nil
    job = nil
    defer { child = nil }
    switch kind {
    case .none: break
    case .flexibleWidth:
      if let child, _hasFlexibleSpacer(in: child) { owner._sAttributes["data-flexible-width"] = "true" }
    case .lazyCollection:
      if let child, _containsLazyCollection(in: child) { owner._sAttributes["data-lazy"] = "vertical" }
    }
  }
}

/// An attribute a container derives from its children, once they have rendered.
package enum _ChildrenCompletion {
  case none
  /// An `HStack` is flexible in width when a `Spacer` is among its children.
  case flexibleWidth
  /// A `List` is lazy when a lazy collection is among its children.
  case lazyCollection
}

/// How a container turns the node its content renders into its child list.
package enum _DeferredShape {
  /// Fragments are flattened and empty nodes dropped (a layout container's children).
  case flattened
  /// The node itself, or nothing when it is empty (a stack's one child).
  case single
}

/// A job that renders one view into a child list.
private final class _DeferredContent<Content: View>: _DeferredChildren {
  private var content: Content?
  private var context: _RenderContext?
  private let shape: _DeferredShape

  @MainActor init(_ content: Content, context: _RenderContext, shape: _DeferredShape) {
    self.content = content
    self.context = context
    self.shape = shape
    super.init()
  }

  @MainActor override func render() -> [_RenderNode] {
    guard let content, let context else { return [] }
    let rendered = content._render(in: context)
    switch shape {
    case .flattened: return _flattenLayoutChildren(rendered)
    case .single: return rendered.isEmpty ? [] : [rendered]
    }
  }

  @MainActor override func release() {
    content = nil
    context = nil
  }
}

/// A job that builds a child list.
private final class _DeferredBuilt: _DeferredChildren {
  private var build: (@MainActor () -> [_RenderNode])?
  /// A node whose render this job's list is built from, when it stands in for one that has not run.
  private let source: _RenderNode?

  @MainActor init(source: _RenderNode? = nil, _ build: @escaping @MainActor () -> [_RenderNode]) {
    self.build = build
    self.source = source
    super.init()
  }

  @MainActor override var isReady: Bool { !_RenderStaging.isUnderWay(source) }

  @MainActor override func render() -> [_RenderNode] { build?() ?? [] }
  @MainActor override func release() { build = nil }
}

/// `_deferStackChild` for a container whose child list is built from what the content renders (a wrapper around it,
/// siblings that depend on it): `build` renders the content, in the order plain recursion would have, and returns the
/// list.
@inline(never)
@MainActor func _deferBuiltChildren(of node: _RenderNode, after source: _RenderNode? = nil, _ build: @escaping @MainActor () -> [_RenderNode]) {
  node._deferChildren(_RenderStaging.defer_(building: build, after: source))
}

extension _RenderNode {
  /// Makes `job`'s nodes this node's children, to be rendered later (see `_RenderStaging`).
  @MainActor package func _deferChildren(_ job: _DeferredChildren) {
    _children = []
    _deferredChildren = job
  }

  /// Renders what the attributes of this node wait for, then those themselves.
  @inline(never)
  func _resolveAttributes() {
    if _selfPending != nil { _resolveSelf() }
    guard let record = _attributeJob else { return }
    if _deferredChildren != nil { _materializeChildren() }
    if let job = record.job {
      nonisolated(unsafe) let pending = job
      // SAFETY: rendering, and so every deferred job, runs on the main actor.
      _assumeMainActor { pending.run(freshStack: false) }
    }
    nonisolated(unsafe) let completion = record
    // SAFETY: as above.
    _assumeMainActor { completion.finish() }
  }

  @inline(never)
  func _forgetAttributeJob() {
    _attributeJob?.owner = nil
    _attributeJob = nil
  }

  /// Runs the deferred children now and keeps them.
  @inline(never)
  func _materializeChildren() {
    guard let pending = _deferredChildren else { return }
    nonisolated(unsafe) let job = pending
    // SAFETY: rendering, and so every deferred job, runs on the main actor; a node read from anywhere else is
    // read after the pass that built it has finished and run its jobs.
    _assumeMainActor {
      // The job and every job it queues, one after another from here: whoever reads this node is about to read
      // what is below it too, and a job run from the middle of that read would sit on top of its frames.
      job.forceCompletion()
    }
    // A job that waits for a render under way (`isReady`) is still pending: the reader is inside that render.
    guard job.finished else { return }
    _children = job.nodes
    _deferredChildren = nil
  }
}

/// The inline form of `_deferChild`: the child has rendered but may still hold renders that wait in the loop.
@inline(never)
@MainActor func _postponeCompletion(_ completion: _ChildrenCompletion, of node: _RenderNode, child: _RenderNode) {
  let record = _OwnerCompletion(kind: completion, owner: node, child: child, job: nil)
  node._attributeJob = record
  record.postpone()
}

/// `_deferStackChild` for a container whose attribute `completion` depends on the child it renders: the attribute is
/// set when the child has rendered, and reading the node's attributes before that renders it.
@inline(never)
@MainActor func _deferChild<Content: View>(
  _ content: Content, context: _RenderContext, to node: _RenderNode, completion: _ChildrenCompletion
) {
  let job = _RenderStaging.defer_(content, context: context, shape: .single)
  let record = _OwnerCompletion(kind: completion, owner: node, child: nil, job: job)
  job.ownerCompletion = record
  node._deferChildren(job)
  node._attributeJob = record
}

/// The deferred form of a stack's `node.children = child.isEmpty ? [] : [child]`. Out of line, like the rest of the
/// stack's work around the recursion.
@inline(never)
@MainActor func _deferStackChild<Content: View>(_ content: Content, context: _RenderContext, to node: _RenderNode) {
  node._deferChildren(_RenderStaging.defer_(content, context: context, shape: .single))
}

/// Test container for staged rendering that also exists off Embedded, where the stacks lay out through nodes and
/// cannot defer: a `div` whose children are `content`'s, deferred when the render is deep.
package struct _StagedContainer<Content: View>: View {
  package typealias Body = Never
  private let content: Content
  package init(_ content: Content) { self.content = content }

  @MainActor package func _render(in context: _RenderContext) -> _RenderNode {
    let wrapper = _RenderNode.element("div")
    let childContext = context.child(_FiberKey("staged-content"))
    if _RenderStaging.wantsDeferral {
      wrapper._deferChildren(_RenderStaging.defer_(content, context: childContext))
    } else {
      wrapper.children = _flattenLayoutChildren(content._render(in: childContext))
    }
    return wrapper
  }
}

// MARK: - Staged containers

/// A container that has to wait for its content before it can build its node: a navigation stack gathers the toolbars
/// and destinations its content registered, a tab view the tabs, a picker the options. Plain recursion gathers right
/// after the content has rendered; the content may have deferred parts, so the container used to run them on the spot
/// (`flush`), and a container inside that content did the same from inside that call, one frame stack per level of
/// nesting.
///
/// A staged container builds its node in *stages*. When its content left nothing behind it builds the node at once,
/// as before. Otherwise it returns a node that stands in for it (`_PendingRender`, which is what makes everything the
/// parent does to the node wait for it, in order) and goes on when the pass has rendered everything that is queued:
/// that stage runs from the loop that drives the pass, where the depth is shallow again, and a stage that renders more
/// content (a destination) waits for that in turn (`whenSettled`). Containers inside one another settle from the inside
/// out, which is the order plain recursion finished them in: a stage waits for the stages that are nested deeper than
/// its own (`stageDepth`, entered by `enterStage` around the content). Reading the stand-in before then runs the stages
/// on the spot (`forceCompletion`), where plain recursion would have.
final class _StagedRender: _DeferredNodeJob {
  fileprivate var next: (@MainActor (_StagedRender) -> Void)?
  fileprivate var generation = 0
  private var completed = false
  let depth: Int

  @MainActor init() {
    depth = _RenderStaging.state.stageDepth
    super.init(nil)
  }

  /// Whether every stage has run and the node is known.
  var isComplete: Bool { completed && next == nil }

  func isWaiting(generation: Int) -> Bool { next != nil && generation == self.generation }

  /// Gives the node the container ends with. The last stage calls it.
  func complete(_ node: _RenderNode) {
    nodes = [node]
    completed = true
  }

  /// Goes on with `body` when the pass has rendered what is queued and the stages nested in this one have run. At
  /// once when there is nothing to wait for.
  @MainActor func whenSettled(_ body: @escaping @MainActor (_StagedRender) -> Void) {
    let state = _RenderStaging.state
    if !state.hasPending && state.stages.isEmpty {
      _RenderStaging.stageProbe?()
      body(self)
      return
    }
    generation &+= 1
    next = body
    state.stageSequence &+= 1
    state.stages.append(_StageEntry(depth: depth, order: state.stageSequence, generation: generation, job: self))
  }

  /// Runs `first` where the container stands, as the first stage.
  @MainActor func begin(_ first: @escaping @MainActor (_StagedRender) -> Void) {
    running = true
    first(self)
    running = false
    if isComplete { finished = true }
  }

  /// Runs the stage that waits, with what the job captured installed, and settles the node when it was the last.
  @MainActor func runStage(freshStack: Bool) {
    guard let body = next, !running, !finished else { return }
    next = nil
    running = true
    let thread = _RenderThreadState.current
    let savedEnvironment = thread.environment
    let savedScope = thread.stateScope
    let savedAnimation = thread.animation
    let savedActive = thread.animationActive
    let state = _RenderStaging.state
    let savedDepth = state.depth
    let savedPrefix = state.orderPrefix
    let savedCounter = state.orderCounter
    let savedRecorder = EnvironmentValues._readRecorder
    let savedStageDepth = state.stageDepth
    thread.environment = environment
    thread.stateScope = scope
    thread.animation = animation
    thread.animationActive = animationActive
    EnvironmentValues._readRecorder = readRecorder
    state.stageDepth = stageDepth
    if freshStack { state.depth = 0 }
    state.orderPrefix = orderPrefix
    state.orderCounter = 0
    _RenderStaging.stageProbe?()
    body(self)
    thread.environment = savedEnvironment
    thread.stateScope = savedScope
    thread.animation = savedAnimation
    thread.animationActive = savedActive
    EnvironmentValues._readRecorder = savedRecorder
    state.stageDepth = savedStageDepth
    state.depth = savedDepth
    state.orderPrefix = savedPrefix
    state.orderCounter = savedCounter
    running = false
    if isComplete {
      release()
      finished = true
      didFinish()
    }
  }

  @MainActor override func forceRun() { forceCompletion() }

  @MainActor override func forceCompletion() {
    let state = _RenderStaging.state
    while !finished, !running {
      _RenderStaging.flush()
      // Containers nested in this one finish first, as they do in plain recursion.
      while let entry = state.takeDeepestStage(deeperThan: depth) {
        entry.job.runStage(freshStack: false)
        _RenderStaging.flush()
      }
      guard next != nil else { return }
      runStage(freshStack: false)
    }
  }

  @MainActor override func release() { next = nil }
}

extension _RenderStaging {
  /// Marks the start and the end of the content of a staged container: the containers rendered in between (and the
  /// jobs created in between) are nested in it, and settle before it.
  @MainActor static func enterStage() { state.stageDepth &+= 1 }

  /// Counts the renders handed to the loop that drives the pass: a render during which it did not move left nothing
  /// behind, so what it read is all there when it returns.
  @MainActor static var deferrals: Int { state.jobSequence }

  /// Called where a stage runs, for tests that measure how deep the call stack is there.
  nonisolated(unsafe) package static var stageProbe: (() -> Void)?
  @MainActor static func exitStage() { state.stageDepth &-= 1 }

  /// The node of a container that builds it in stages: `first` runs now, and calls `whenSettled` to continue when the
  /// pass has rendered what the container's content left behind, and `complete` with the node from the last stage.
  /// When nothing is left behind the node comes back as it always did; otherwise a node that stands in for it does.
  @MainActor static func stagedNode(_ first: @escaping @MainActor (_StagedRender) -> Void) -> _RenderNode {
    let job = _StagedRender()
    job.begin(first)
    if job.isComplete { return job.nodes.first ?? _RenderNode.empty() }
    let state = self.state
    let node = _RenderNode(kind: .empty)
    job.node = node
    node._selfPending = _PendingRender(job: job)
    state.tagging = true
    state.jobSequence &+= 1
    state.jobsCreated &+= 1
    state.nodeJobsCreated &+= 1
    job.orderPrefix = state.orderPrefix.appending(state.orderCounter &- 1).appending(state.jobSequence)
    return node
  }

  /// Runs `body` when the pass has rendered what is queued, from the loop that drives it (at once when nothing is).
  /// Hands `take` a copy of what `node` stands for as it is now (`_RenderNode._reuseSnapshot`): at once, or, for a node
  /// that stands in for a render that has not run, once that render has run with the operations kept for it so far
  /// (those that wrap it later are not part of it).
  @MainActor static func snapshot(of node: _RenderNode, _ take: @escaping @MainActor (_RenderNode?) -> Void) {
    guard let pending = node._selfPending else { return take(node._reuseSnapshot()) }
    pending.snapshots.append((pending.ops.count, take))
  }

  @MainActor static func settled(_ body: @escaping @MainActor () -> Void) {
    let job = _StagedRender()
    job.begin { stage in
      stage.whenSettled { stage in
        body()
        stage.complete(_RenderNode.empty())
      }
    }
  }
}

// MARK: - Deferred nodes

/// What a node that stands in for a render that has not run yet carries (`_RenderNode._selfPending`).
///
/// Beyond the budget, an erased view boundary does not render its content: it returns an empty node that holds the
/// render as a job, and every read or write of that node runs the job first. A parent that only passes the node along
/// (a container putting it among its children, a conditional, a modifier that wraps) never runs it, and the loop that
/// drives the pass does, from a shallow stack. What a parent would do to the node it got back (set its key, apply a
/// modifier) cannot be done to a node that is not there yet, so those effects are kept as *post operations* and run,
/// in order, on the result when the job has finished, which is where plain recursion would have run them.
///
/// A job whose result is another such node waits for it, and nodes settle from the innermost out. That is a chain of
/// links, not a call chain: the stack does not grow with the length of the chain.
final class _PendingRender {
  let job: _DeferredNodeJob
  var ops: [_PostOp] = []
  /// The pending node the job returned, when the job finished with one.
  var result: _RenderNode?
  /// Nodes whose jobs returned this one: they settle when it does.
  var waiters: [_RenderNode] = []
  /// For a node that stands in for a fragment whose children have not all settled (`_pendingTarget`): the fragment, and
  /// how many of its children it still waits for.
  var fragment: _RenderNode?
  var unsettledChildren = 0
  /// The stand-ins of the fragments that wait for this node.
  var joins: [_RenderNode] = []
  /// What wants a copy of the node after the first `after` operations (`_RenderStaging.snapshot`).
  var snapshots: [(after: Int, take: @MainActor (_RenderNode?) -> Void)] = []
  init(job: _DeferredNodeJob) { self.job = job }
}

/// A job that renders one node.
class _DeferredNodeJob: _DeferredChildren {
  private var body: (@MainActor () -> _RenderNode)?
  /// The node that stands in for this render.
  var node: _RenderNode?

  @MainActor init(_ body: (@MainActor () -> _RenderNode)?) {
    self.body = body
    super.init()
  }

  @MainActor override func render() -> [_RenderNode] {
    guard let body else { return [] }
    return [body()]
  }

  @MainActor override func release() { body = nil }

  @MainActor override func didFinish() {
    guard let node, let pending = node._selfPending else { return }
    let rendered = nodes.first ?? _RenderNode.empty()
    if let inner = rendered._selfPending {
      // The result is not rendered either: this node settles when that one does.
      pending.result = rendered
      inner.waiters.append(node)
    } else if !pending.ops.isEmpty, _RenderStaging.waitForChildren(of: rendered, node: node) {
      // The result is a fragment with children that have not rendered, and what is kept for this node applies to each
      // of them: it settles when the last of them has.
    } else {
      _RenderStaging.settle(node, with: rendered)
    }
  }
}

/// The thread state a post operation needs when it runs later: what the handlers it creates capture, and where its
/// preference writes belong in the order of plain recursion.
struct _CapturedThreadState {
  let environment: EnvironmentValues?
  let scope: StateScope?
  let animation: Animation?
  let animationActive: Bool
  let readRecorder: _EnvironmentReadRecorder?
  let stageDepth: Int
  let orderPrefix: _OrderTag

  /// The state now. The writes of an operation kept now sort after everything the node it waits for writes (that is
  /// a window of `[prefix, counter - 1, job, ...]` tags) and before the next write of the container, and in the order
  /// of the passes: the job sequence is the newest job's (so it sorts after that window, and before any job created
  /// later, in this pass or in a later one), the `Int.max` after everything inside the window, and the last number
  /// keeps operations kept one after the other in the order they were kept.
  @MainActor static func capture() -> _CapturedThreadState {
    let thread = _RenderThreadState.current
    let staging = thread.staging
    staging.opSequence &+= 1
    return _CapturedThreadState(
      environment: thread.environment, scope: thread.stateScope, animation: thread.animation,
      animationActive: thread.animationActive,
      readRecorder: EnvironmentValues._readRecorder, stageDepth: staging.stageDepth,
      orderPrefix: staging.orderPrefix.appending(staging.orderCounter &- 1).appending(staging.jobSequence).appending(Int.max).appending(staging.opSequence))
  }

  /// Runs `body` with this state installed and puts back what was there.
  @MainActor func perform(_ body: () -> Void) {
    let thread = _RenderThreadState.current
    let staging = thread.staging
    let savedEnvironment = thread.environment
    let savedScope = thread.stateScope
    let savedAnimation = thread.animation
    let savedActive = thread.animationActive
    let savedPrefix = staging.orderPrefix
    let savedCounter = staging.orderCounter
    let savedRecorder = EnvironmentValues._readRecorder
    let savedStageDepth = staging.stageDepth
    thread.environment = environment
    thread.stateScope = scope
    thread.animation = animation
    thread.animationActive = animationActive
    EnvironmentValues._readRecorder = readRecorder
    staging.stageDepth = stageDepth
    staging.orderPrefix = orderPrefix
    staging.orderCounter = 0
    body()
    EnvironmentValues._readRecorder = savedRecorder
    staging.stageDepth = savedStageDepth
    thread.environment = savedEnvironment
    thread.stateScope = savedScope
    thread.animation = savedAnimation
    thread.animationActive = savedActive
    staging.orderPrefix = savedPrefix
    staging.orderCounter = savedCounter
  }
}

/// Something done to the node an erased boundary returned, kept for when the node exists.
enum _PostOp {
  case descriptor(String)
  case builderKey(_BuilderKey)
  case key(_FiberKey, overriding: Bool)
  /// `_finishEmbeddedOwner`: the node now belongs to the owner `token`.
  case owner(token: UInt64, path: _FiberPath, registry: _RenderOwnerRegistry)
  case stateScopePath(_FiberPath)
  /// `ModifiedContent`'s `_modifierTarget`: a one-child fragment stands for its child.
  case modifierTarget
  /// A modifier's `_apply`, with the state its handlers capture.
  case apply(_CapturedThreadState, @MainActor (_RenderNode) -> Void)

  /// Runs the operation on `node` and returns the node the next one works on.
  @MainActor func run(on node: _RenderNode) -> _RenderNode {
    switch self {
    case .descriptor(let tag):
      node.descriptor = tag
    case .builderKey(let key):
      key.apply(to: node)
    case .key(let key, let overriding):
      if overriding || node.key == nil { node.key = key }
    case .owner(let token, let path, let registry):
      _finishOwner(node, token: token, path: path, registry: registry)
    case .stateScopePath(let path):
      _recordStateScopePath(node, path: path)
    case .modifierTarget:
      return _modifierTarget(node)
    case .apply(let state, let body):
      state.perform { body(node) }
    }
    return node
  }
}

extension _RenderNode {
  /// Whether this node stands in for a render that has not run.
  @inline(__always) var _isPendingRender: Bool { _selfPending != nil }

  /// Runs the render this node stands in for, and every post operation kept for it (see `_PendingRender`).
  @inline(never)
  func _resolveSelf() {
    nonisolated(unsafe) let node = self
    // SAFETY: rendering, and so every deferred render, runs on the main actor; a node read from anywhere else is
    // read after the pass that built it has finished and settled its pending nodes.
    _assumeMainActor { _RenderStaging.force(node) }
  }

  /// Keeps `op` for when this pending node has been rendered. Only for a node that is pending.
  @inline(never)
  func _keep(_ op: _PostOp) {
    _selfPending?.ops.append(op)
  }

  /// Sets the descriptor now, or when the render this node stands in for has run.
  @inline(__always) func _postDescriptor(_ tag: String) {
    if _selfPending != nil { _keep(.descriptor(tag)) } else { _sDescriptor = tag }
  }
}

extension _RenderStaging {
  /// A node standing in for the render `body` performs, which the loop that drives the pass runs later.
  @MainActor static func deferNode(_ body: @escaping @MainActor () -> _RenderNode) -> _RenderNode {
    standIn(for: _DeferredNodeJob(body))
  }

  @MainActor private static func standIn(for job: _DeferredNodeJob) -> _RenderNode {
    let state = self.state
    let node = _RenderNode(kind: .empty)
    job.node = node
    node._selfPending = _PendingRender(job: job)
    state.tagging = true
    state.jobSequence &+= 1
    state.jobsCreated &+= 1
    state.nodeJobsCreated &+= 1
    job.orderPrefix = state.orderPrefix.appending(state.orderCounter &- 1).appending(state.jobSequence)
    state.queue.append(job)
    return node
  }

  /// Renders the pending `node` where the caller stands: its job, and the jobs it returns pending nodes of, one
  /// after another from here. Whoever reads a pending node needs the node itself, not what is below it.
  @inline(never)
  @MainActor static func force(_ node: _RenderNode) {
    state.nodeJobsForced &+= 1
    var current = node
    while let pending = current._selfPending {
      let job = pending.job
      if job.running { return }
      if !job.finished { job.forceRun() }
      // The job settled the node (and everything waiting for it), or returned a node that has to settle first.
      guard current._selfPending != nil else { break }
      if let fragment = pending.fragment {
        // A fragment waits for its children, and settles when the last of them does.
        for child in _pendingNodes(in: fragment) { force(child) }
        break
      }
      guard let next = pending.result else { break }
      current = next
    }
  }

  /// Whether the render that `node` stands in for, or one it waits for, is running: a reader that forced it from
  /// here would find it unfinished.
  @MainActor static func isUnderWay(_ node: _RenderNode?) -> Bool {
    var stack: [_RenderNode] = []
    if let node { stack.append(node) }
    while let current = stack.popLast() {
      guard let pending = current._selfPending else { continue }
      if pending.job.running { return true }
      if let result = pending.result { stack.append(result) }
      if let fragment = pending.fragment { stack.append(contentsOf: _pendingNodes(in: fragment)) }
    }
    return false
  }

  /// Makes the pending `node` wait for the children of `fragment` that are still pending, if it has any, to settle as the
  /// fragment when they have (`_PendingRender.fragment`). Whether it waits.
  @MainActor static func waitForChildren(of fragment: _RenderNode, node: _RenderNode) -> Bool {
    guard fragment.kind == .fragment, let pending = node._selfPending else { return false }
    let unsettled = _pendingNodes(in: fragment)
    guard !unsettled.isEmpty else { return false }
    pending.fragment = fragment
    pending.unsettledChildren = unsettled.count
    for child in unsettled { child._selfPending?.joins.append(node) }
    return true
  }

  /// Gives `node` the `rendered` node it stood in for, after the post operations kept for it, and settles the nodes
  /// that were waiting for `node` the same way.
  @MainActor static func settle(_ node: _RenderNode, with rendered: _RenderNode) {
    var work: [(node: _RenderNode, rendered: _RenderNode)] = [(node, rendered)]
    while let item = work.popLast() {
      guard let pending = item.node._selfPending else { continue }
      var target = item.rendered
      if pending.snapshots.isEmpty {
        for op in pending.ops { target = op.run(on: target) }
      } else {
        let snapshots = pending.snapshots
        pending.snapshots = []
        for (index, op) in pending.ops.enumerated() {
          for snapshot in snapshots where snapshot.after == index { snapshot.take(target._reuseSnapshot()) }
          target = op.run(on: target)
        }
        for snapshot in snapshots where snapshot.after == pending.ops.count { snapshot.take(target._reuseSnapshot()) }
      }
      let waiters = pending.waiters
      let joins = pending.joins
      pending.job.node = nil
      pending.waiters = []
      pending.joins = []
      pending.ops = []
      pending.result = nil
      pending.fragment = nil
      item.node._become(target)
      for waiter in waiters { work.append((waiter, item.node)) }
      for join in joins {
        guard let joined = join._selfPending, let fragment = joined.fragment else { continue }
        joined.unsettledChildren -= 1
        if joined.unsettledChildren == 0 { work.append((join, fragment)) }
      }
    }
  }
}

// MARK: - Order tags

/// A side effect kept with the position in the render at which plain recursion would have run it.
struct _OrderedEffect {
  let tag: _OrderTag
  /// The order it was requested in, for effects with equal tags.
  let order: Int
  let run: @MainActor (_OrderTag?) -> Void
}

/// Whether the position `lhs` comes before `rhs` (order tags, see `_RenderStaging.nextWriteTag`). A position that is
/// a prefix of another comes first; an empty one (written before the first deferral) comes before all.
func _orderTagLess(_ lhs: _OrderTag, _ rhs: _OrderTag) -> Bool {
  lhs.compare(to: rhs) < 0
}

/// A position in the render, as the numbers a tag is made of (see `_RenderStaging.nextWriteTag`), kept as a chain that
/// shares its prefix: a job's tag extends the tag of the position it was created at by a few numbers, and every write
/// and effect inside it extends that by one, so a tag costs the same however many jobs are nested above it. Comparing
/// two tags walks only down from the first link they do not share.
package struct _OrderTag: Equatable {
  final class Link {
    fileprivate(set) var parent: Link?
    let value: Int
    let depth: Int
    init(parent: Link?, value: Int) {
      self.parent = parent
      self.value = value
      depth = (parent?.depth ?? 0) + 1
    }

    /// Releases the chain above this link from a loop (see `_FiberPath.Link`).
    deinit {
      guard var current = parent else { return }
      parent = nil
      while isKnownUniquelyReferenced(&current), let next = current.parent {
        current.parent = nil
        current = next
      }
    }
  }

  private(set) var link: Link?

  package init() {}
  package var count: Int { link?.depth ?? 0 }
  package var isEmpty: Bool { link == nil }

  package func appending(_ value: Int) -> _OrderTag {
    var tag = _OrderTag()
    tag.link = Link(parent: link, value: value)
    return tag
  }

  /// Negative when `self` sorts before `other`, positive after, zero when they are the same position. The numbers are
  /// compared from the first: where one is a prefix of the other, the shorter one sorts first.
  package func compare(to other: _OrderTag) -> Int {
    var left = link
    var right = other.link
    if left === right { return 0 }
    let leftDepth = count, rightDepth = other.count
    while let current = left, current.depth > rightDepth { left = current.parent }
    while let current = right, current.depth > leftDepth { right = current.parent }
    // Equal depth now. The difference closest to the first number is the last one found going up, and the chains
    // are the same from the first link they share.
    var difference = 0
    while let a = left, let b = right, a !== b {
      if a.value != b.value { difference = a.value < b.value ? -1 : 1 }
      left = a.parent
      right = b.parent
    }
    if difference != 0 { return difference }
    return leftDepth == rightDepth ? 0 : (leftDepth < rightDepth ? -1 : 1)
  }

  package static func == (lhs: _OrderTag, rhs: _OrderTag) -> Bool { lhs.compare(to: rhs) == 0 }
}

/// Sorts by tag; equal tags keep the order they were requested in.
func _sortByOrderTag(_ effects: inout [_OrderedEffect]) {
  _stableSort(&effects) { _orderTagLess($0.tag, $1.tag) }
}

/// A stable sort that is linear on input that is already in order and `n log n` otherwise (a top-down merge sort that
/// merges only the runs that are out of order). An insertion sort was quadratic on a tree whose deferred parts arrive
/// in the opposite order to their positions, which is what a deep chain of containers produces.
package func _stableSort<Element>(_ items: inout [Element], by less: (Element, Element) -> Bool) {
  let count = items.count
  guard count > 1 else { return }
  var alreadySorted = true
  var probe = 1
  while probe < count {
    if less(items[probe], items[probe - 1]) { alreadySorted = false; break }
    probe += 1
  }
  if alreadySorted { return }
  var source = items
  var width = 1
  while width < count {
    var start = 0
    while start < count {
      let middle = min(start + width, count)
      let end = min(start + 2 * width, count)
      var left = start, right = middle, out = start
      while left < middle, right < end {
        // Take from the right only when it is strictly less, which keeps equal elements in their original order.
        if less(source[right], source[left]) { items[out] = source[right]; right += 1 } else { items[out] = source[left]; left += 1 }
        out += 1
      }
      while left < middle { items[out] = source[left]; left += 1; out += 1 }
      while right < end { items[out] = source[right]; right += 1; out += 1 }
      start += 2 * width
    }
    source = items
    width *= 2
  }
}

/// Values collected while the pass renders that the application reads in render order (the toolbars a navigation
/// stack gathers). A deferred part of the tree adds its values later than plain recursion would have, so each value
/// is tagged with its position and read back in position order.
struct _OrderedValues<Value> {
  private var values: [Value] = []
  private var tags: [_OrderTag] = []
  private var tagged = false

  var isEmpty: Bool { values.isEmpty }

  @MainActor mutating func append(_ value: Value) {
    if _RenderStaging.tagging {
      while tags.count < values.count { tags.append(_OrderTag()) }
      tags.append(_RenderStaging.nextWriteTag())
      tagged = true
    }
    values.append(value)
  }

  mutating func removeAll() {
    values.removeAll()
    tags.removeAll()
    tagged = false
  }

  /// The values in the order plain recursion would have collected them.
  func inOrder() -> [Value] {
    guard tagged else { return values }
    var order = Array(values.indices)
    func tag(_ index: Int) -> _OrderTag { index < tags.count ? tags[index] : _OrderTag() }
    _stableSort(&order) { _orderTagLess(tag($0), tag($1)) }
    return order.map { values[$0] }
  }
}

/// The node a modifier that waits puts its `_apply` on when the content has not all rendered: the
/// content itself when it is a pending node, or, for a `Group`/`ForEach`/tuple (a fragment) with pending children, a
/// pending node that stands for the fragment once they have settled. A modifier applies to each child of a fragment, so
/// it cannot start before the children exist; one that forced them here would make a recursive structure of groups under
/// modifiers recurse with it. `nil` when the content is complete and the modifier applies to it now.
@inline(never)
@MainActor func _pendingTarget(_ rendered: _RenderNode) -> _RenderNode? {
  if rendered._selfPending != nil { return rendered }
  guard rendered.kind == .fragment, !_pendingNodes(in: rendered, first: true).isEmpty else { return nil }
  return _RenderStaging.deferNode { rendered }
}

/// The pending nodes among the children of `fragment`, looking through the fragments nested in it (a modifier on a group
/// applies to the children of the groups inside it too). Only the first when `first`.
@MainActor func _pendingNodes(in fragment: _RenderNode, first: Bool = false) -> [_RenderNode] {
  var found: [_RenderNode] = []
  var stack = [fragment]
  while let current = stack.popLast() {
    for child in current.children {
      if child._selfPending != nil {
        found.append(child)
        if first { return found }
      } else if child.kind == .fragment {
        stack.append(child)
      }
    }
  }
  return found
}
