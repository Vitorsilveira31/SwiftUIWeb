#!/usr/bin/env bun
// The direct build of the development profile `fast` (Documentation/Performance/BUILD_TIME.md, "The direct build").
//
// `swift build` spends about 1.3 s finding out what a save changed before it compiles anything. In the development loop the
// launcher already knows the lowered tree and the last build, so this tool does the compiling itself: it replays the
// compiler commands that a verbose `swift build` printed, for the modules whose sources changed, and links.
//
//   record  after a successful `swift build -v`: reads its log and keeps, per module, the driver command, the copies that
//           publish the module's interface and the link command (`<cache>/direct-build-plan.json`). Logs add up: a build
//           that compiled one module adds that module.
//   build   compiles the modules whose sources are newer than the last build, then the modules that import a module
//           whose interface changed, and links.
//
// What the lowering changed in the tree is given as a count (`--tree-changes`, a framework product: every one of those files
// must be a Swift source found changed) or as the list the tree sync printed (`--changed-files`, a staged package: each
// file must be a module's Swift source, or a Swift file no module compiles).
//
// Exit status of `build`: 0 built; 3 this save is not one the direct build knows how to do (a new or removed file, a
// manifest change, a module whose commands were never seen, a source that is not Swift), so the caller runs `swift build`;
// 1 the compiler or the linker failed, with their output printed.
//
// Hot swap (`--hot`, Documentation/Performance/BUILD_TIME.md, "Hot swap"): the product is linked as two modules instead
// of one. The main module holds the framework and the standard library and exports every symbol; the application module
// is compiled position independent and linked as a side module (`wasm-ld --shared`) that imports what it uses from the
// main module. A save that changes only the application then links the side module alone, and the page loads it into the
// module it is already running (Tools/side-module.js) instead of reloading.
//
// Nothing here decides what the commands are: they are the build system's own, so a flag the launcher adds reaches the
// direct build through the next `swift build -v`. The plan is dropped when the launcher's fingerprint of the build changes.
import { spawn } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, sep } from "node:path";
import { parseArgs } from "node:util";

const PLAN = "direct-build-plan.json";
const NOT_DIRECT = 3;

const real = (path) => { try { return realpathSync(path); } catch { return path; } };

/** Splits a command line as the build log prints it: spaces separate arguments, a backslash escapes the next character. */
export function splitCommand(text) {
  const out = [];
  let current = "", has = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === "\\" && i + 1 < text.length) { current += text[++i]; has = true; }
    else if (c === " " || c === "\n") { if (has) out.push(current); current = ""; has = false; }
    else { current += c; has = true; }
  }
  if (has) out.push(current);
  return out;
}

/** The commands of one verbose build log: `{ modules: { name: { cwd, argv } }, copies: [{ from, to }], link }`. */
export function parseLog(log) {
  const lines = log.split("\n");
  const modules = {}, copies = [];
  let link = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const cwd = (lines[i - 1] ?? "").trim().replace(/^cd /, "");
    if (line.startsWith("builtin-SwiftDriver -- ")) {
      const argv = splitCommand(line.slice("builtin-SwiftDriver -- ".length));
      const name = argv[argv.indexOf("-module-name") + 1];
      if (name && argv.includes("-output-file-map")) modules[name] = { cwd, argv };
    } else if (line.startsWith("builtin-copy ") && line.includes(" -rename ")) {
      const argv = splitCommand(line);
      copies.push({ from: argv[argv.length - 2], to: argv[argv.length - 1] });
    } else if (/(^|\/)swiftc /.test(line) && line.includes(" -emit-executable ") && line.includes(" -o ")) {
      // The link is a compiler driver call; `-rdynamic` reaches clang, which only warns, but the driver refuses it outside
      // the build system.
      const all = splitCommand(line);
      const argv = all.filter((argument, index) => !(argument === "-rdynamic" || (argument === "-Xclang-linker" && all[index + 1] === "-rdynamic")));
      // Output printed on the same line as the command (a warning of the linker) is not part of it.
      const output = argv.indexOf("-o");
      link = { cwd, argv: argv.slice(0, output + 2) };
    }
  }
  return { modules, copies, link };
}

function loadPlan(cache) {
  try { return JSON.parse(readFileSync(join(cache, PLAN), "utf8")); } catch { return null; }
}

/** Every `<Module>.SwiftFileList` under the scratch folder: the Swift modules the build system knows, by name. */
function fileLists(scratch) {
  const found = {};
  const walk = (directory, depth) => {
    let entries;
    try { entries = readdirSync(directory, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) { if (depth < 8) walk(path, depth + 1); }
      else if (entry.name.endsWith(".SwiftFileList")) found[entry.name.slice(0, -".SwiftFileList".length)] = path;
    }
  };
  walk(join(scratch, "out", "Intermediates.noindex"), 0);
  return found;
}

/**
 * The folder each module's sources live under, derived from the sources (the plan does not record a target's path): the
 * deepest folder that holds all of them. Folders inside another one are left out; the scan of the outer one covers them.
 */
export function moduleRoots(sources) {
  const roots = [];
  for (const files of Object.values(sources)) {
    if (files.length === 0) continue;
    let common = dirname(files[0]).split(sep);
    for (const file of files) {
      const parts = dirname(file).split(sep);
      let length = 0;
      while (length < common.length && length < parts.length && common[length] === parts[length]) length++;
      common = common.slice(0, length);
    }
    roots.push(common.join(sep) || sep);
  }
  const unique = [...new Set(roots)];
  return unique.filter((root) => !unique.some((other) => other !== root && root.startsWith(other.endsWith(sep) ? other : other + sep)));
}

/** True when `file` is inside one of `roots`. */
export const isBeneath = (file, roots) => roots.some((root) => file.startsWith(root.endsWith(sep) ? root : root + sep));

/**
 * The first Swift file beneath `roots` that no module compiles, or null. SwiftPM compiles every Swift file under a target's
 * folder (a manifest could exclude some; this tool cannot see it, and a file it excludes only costs a `swift build`).
 * Only folders are listed, no file is read; hidden folders (.build, .git) are not sources.
 */
export function unknownSwiftFile(roots, owned) {
  const walk = (directory) => {
    let entries;
    try { entries = readdirSync(directory, { withFileTypes: true }); } catch { return null; }
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) {
        if (entry.name.startsWith(".")) continue;
        const found = walk(path);
        if (found) return found;
      } else if (entry.name.endsWith(".swift") && !owned.has(real(path))) return path;
    }
    return null;
  };
  for (const root of roots) { const found = walk(root); if (found) return found; }
  return null;
}

const sourcesOf = (fileList) => readFileSync(fileList, "utf8").split("\n").filter(Boolean).map((line) => real(line.replace(/\\(.)/g, "$1")));

const IMPORT = /^[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*(?:(?:public|package|internal|private|fileprivate)[ \t]+)?import[ \t]+(?:(?:struct|class|enum|protocol|typealias|func|var|let)[ \t]+)?(\w+)/gm;

/** The modules `sources` import, with the names the driver command aliases (`-module-alias Foundation=WebFoundation`) resolved. */
function importsOf(sources, argv) {
  const aliases = new Map();
  for (let i = 0; i < (argv?.length ?? 0); i++) if (argv[i] === "-module-alias" && argv[i + 1]?.includes("=")) { const [from, to] = argv[i + 1].split("="); aliases.set(from, to); }
  const names = new Set();
  for (const source of sources) {
    let text;
    try { text = readFileSync(source, "utf8"); } catch { continue; }
    for (const match of text.matchAll(IMPORT)) names.add(aliases.get(match[1]) ?? match[1]);
  }
  return names;
}

// --- hot swap -----------------------------------------------------------------------------------------------------

const PIC = ["-Xllvm", "-relocation-model=pic"];
/** The sections of a side module the Swift runtime must be told about (Tools/side-module.js registers them). */
export const SWIFT_SECTIONS = ["swift5_protocols", "swift5_protocol_conformances", "swift5_type_metadata"];
/** The libraries of the toolchain whose every symbol the main module carries: a side module compiled later may use any. */
const WHOLE_LIBRARIES = ["libswiftCore.a", "libswiftSwiftOnoneSupport.a", "libswift_Concurrency.a", "libswift_StringProcessing.a", "libswift_RegexParser.a", "libswiftSynchronization.a", "libswiftObservation.a"];

/** The application's module: the one whose objects the link takes directly (`<Module>.LinkFileList`). */
function applicationModule(plan) {
  const list = plan.link?.argv.find((argument) => argument.startsWith("@") && argument.endsWith(".LinkFileList"));
  const name = list ? basename(list).slice(0, -".LinkFileList".length) : null;
  return name && plan.modules[name]?.argv ? name : null;
}

const objectsOf = (module) => Object.values(JSON.parse(readFileSync(module.argv[module.argv.indexOf("-output-file-map") + 1], "utf8"))).map((entry) => entry.object).filter(Boolean);

/** The link of the main module: the product's link without the application's objects, with every symbol exported. */
function mainLink(plan, output) {
  const all = plan.link.argv, argv = [];
  for (let i = 0; i < all.length; i++) {
    const argument = all[i];
    // The exports the product asks for are the application's, and nothing may be dropped as unused: a side module
    // linked later decides what is used.
    if (argument === "-Xlinker" && (/^--export(-if-defined)?=/.test(all[i + 1] ?? "") || all[i + 1] === "--gc-sections")) { i++; continue; }
    if (argument.startsWith("@") && argument.endsWith(".LinkFileList")) continue;
    if (argument === "-o") { argv.push("-o", output); i++; continue; }
    argv.push(argument);
  }
  const resources = all[all.lastIndexOf("-resource-dir") + 1];
  const libraries = WHOLE_LIBRARIES.map((name) => join(resources, "wasi", name)).filter(existsSync);
  const linker = (...flags) => flags.flatMap((flag) => ["-Xlinker", flag]);
  // `--allow-undefined`: the framework calls entry points the application defines (browser_io_receive); the host binds
  // them to the side module. `--allow-multiple-definition`: the driver names the standard library again after these.
  argv.push(...linker("--export-all", "--export=__stack_pointer", "--export-table", "--growable-table", "--allow-undefined", "--allow-multiple-definition", "--whole-archive", ...libraries, "--no-whole-archive"));
  return { cwd: plan.link.cwd, argv };
}

/** The link of the side module: the application's objects as a shared module, with the records the loader needs. */
function sideLink(plan, application, output) {
  const linker = join(dirname(plan.modules[application].argv[0]), "wasm-ld");
  return { cwd: plan.link.cwd, argv: [linker, "--shared", "--experimental-pic", "--allow-undefined", "--emit-relocs", "--export-dynamic",
    ...SWIFT_SECTIONS.flatMap((section) => [`--export-if-defined=__start_${section}`, `--export-if-defined=__stop_${section}`]), ...objectsOf(plan.modules[application]), "-o", output] };
}

/** What the side module imports that neither the main module nor the loader provides. */
function missingSymbols(main, side) {
  const have = new Set(WebAssembly.Module.exports(new WebAssembly.Module(readFileSync(main))).map((entry) => entry.name));
  const sideModule = new WebAssembly.Module(readFileSync(side));
  const own = new Set(WebAssembly.Module.exports(sideModule).map((entry) => entry.name));
  const provided = new Set(["memory", "__indirect_function_table", "__stack_pointer", "__memory_base", "__table_base"]);
  return WebAssembly.Module.imports(sideModule).filter((wanted) => !provided.has(wanted.name) && !have.has(wanted.name) && !(wanted.module !== "env" && own.has(wanted.name))).map((wanted) => wanted.name);
}

export const hotPaths = (cache) => ({ main: join(cache, "hot", "main.wasm"), side: join(cache, "hot", "side.wasm") });

/**
 * Records that the split is not valid: the plan says so, and the two modules are deleted, so nothing that looks for them
 * can take a split that was left by an earlier build or written before a check refused it.
 */
export function markHotFailed(cache, plan, reason) {
  if (plan) { plan.hot = { ok: false, reason }; writeFileSync(join(cache, PLAN), JSON.stringify(plan)); }
  for (const path of Object.values(hotPaths(cache))) rmSync(path, { force: true });
}

/**
 * Which link is current. Every compile makes a new generation of objects, and each of the two ways to link them (the
 * ordinary executable, the two modules of a hot build) remembers the generation it linked. A build links only the one
 * its mode bundles, so after a change of mode the other is behind and is linked even when no source changed.
 */
const generationOf = (plan) => plan.generation ?? 0;
const isCurrent = (plan, mode) => plan.linked?.[mode] === generationOf(plan);
function linkedNow(plan, mode, compiled) {
  if (compiled) plan.generation = generationOf(plan) + 1;
  plan.linked = { ...plan.linked, [mode]: generationOf(plan) };
}

/**
 * `hot-status`: true only when the plan says the split is valid now (for `fingerprint`, when given), the two modules were
 * linked from the current objects, and both exist.
 */
export function hotStatus({ cache, fingerprint = null }) {
  const plan = loadPlan(cache), paths = hotPaths(cache);
  return plan?.hot?.ok === true && isCurrent(plan, "hot") && (fingerprint === null || plan.fingerprint === fingerprint) && existsSync(paths.main) && existsSync(paths.side);
}

/**
 * Links what a hot build needs: the main module when `linkMain`, the side module when `linkSide`. Resolves
 * `{ ok, output, steps, reason }`; `ok` false with a `reason` when this product cannot be split (the plan is then
 * marked, and the caller links the product as one module).
 */
async function hotLink(plan, cache, { linkMain, linkSide }) {
  const application = applicationModule(plan), paths = hotPaths(cache), steps = [];
  let output = "";
  mkdirSync(dirname(paths.main), { recursive: true });
  for (const [label, wanted, command] of [["main module", linkMain, () => mainLink(plan, paths.main)], ["side module", linkSide, () => sideLink(plan, application, paths.side)]]) {
    if (!wanted) continue;
    const began = performance.now(), { cwd, argv } = command();
    const result = await run(argv, cwd);
    steps.push([label, performance.now() - began]);
    output += result.output;
    if (result.status !== 0) return { ok: false, failed: label, output, steps };
  }
  const missing = missingSymbols(paths.main, paths.side);
  if (missing.length > 0) return { ok: false, reason: `the main module lacks ${missing.length} symbol(s) the application uses (${missing.slice(0, 3).join(", ")})`, output, steps };
  return { ok: true, output, steps };
}

/**
 * `prepare-hot`: after a `swift build` was recorded, compiles the application module position independent (its driver
 * command gets the flag from now on) and links the two modules. Resolves `{ status, output, reason }`: status 0 with the
 * modules at `hotPaths(cache)`, 3 when the product cannot be hot (the plan says so and `build` links it as before).
 */
export async function prepareHot({ cache }) {
  const plan = loadPlan(cache);
  const give = (reason, output = "") => { markHotFailed(cache, plan, reason); return { status: NOT_DIRECT, reason, output }; };
  if (!plan?.link) return give("no recorded build");
  const application = applicationModule(plan);
  if (!application) return give("the application's module was not found in the link");
  const module = plan.modules[application];
  if (!PIC.every((flag) => module.argv.includes(flag))) module.argv.push(...PIC);
  const compiled = await run(module.argv, module.cwd);
  if (compiled.status !== 0) return give(`the application did not compile position independent`, compiled.output);
  const linked = await hotLink(plan, cache, { linkMain: true, linkSide: true });
  if (!linked.ok) return give(linked.reason ?? `the ${linked.failed} did not link`, compiled.output + linked.output);
  plan.hot = { ok: true, application };
  // The application was compiled again (position independent), so the ordinary executable is behind from here.
  linkedNow(plan, "hot", true);
  writeFileSync(join(cache, PLAN), JSON.stringify(plan));
  return { status: 0, output: compiled.output + linked.output, steps: linked.steps };
}

/** `record`: merges the commands of `logPath` into the plan of `cache`. */
export function record({ cache, scratch, logPath, fingerprint, started }) {
  const parsed = parseLog(readFileSync(logPath, "utf8"));
  let plan = loadPlan(cache);
  if (!plan || plan.fingerprint !== fingerprint) plan = { fingerprint, modules: {}, link: null };
  plan.scratch = scratch;
  // A hot plan compiles its application position independent; the build system's own command for it does not say so.
  const hotApplication = plan.hot?.ok ? plan.hot.application : null;
  for (const [name, module] of Object.entries(parsed.modules)) {
    plan.modules[name] = { ...plan.modules[name], ...module };
    if (name === hotApplication && !PIC.every((flag) => module.argv.includes(flag))) plan.modules[name].argv = [...module.argv, ...PIC];
  }
  for (const copy of parsed.copies) {
    const owner = Object.keys(plan.modules).find((name) => basename(copy.from).startsWith(name + "."));
    if (!owner) continue;
    const list = (plan.modules[owner].copies ??= []);
    if (!list.some((known) => known.to === copy.to)) list.push(copy);
  }
  if (parsed.link) plan.link = parsed.link;
  // The sources of every module as of this build: a save that adds or removes one is for `swift build`.
  plan.lists = fileLists(scratch);
  plan.sources = Object.fromEntries(Object.entries(plan.lists).map(([name, list]) => [name, sourcesOf(list)]));
  // The modification time of every source this build compiled: a save is a source whose time is another one. A source
  // modified after the build started may not be what it compiled, so it has no time and counts as changed. (One time for
  // the whole build would not do: a file saved in the millisecond the build starts is on either side of it.)
  // `swift build` compiled and linked the ordinary executable.
  linkedNow(plan, "ordinary", true);
  plan.stamps = {};
  for (const source of Object.values(plan.sources).flat()) {
    let modified = 0;
    try { modified = statSync(source).mtimeMs; } catch { /* removed since: it will be missed below */ }
    plan.stamps[source] = modified < started ? modified : 0;
  }
  writeFileSync(join(cache, PLAN), JSON.stringify(plan));
  return plan;
}

function run(argv, cwd) {
  return new Promise((done) => {
    const child = spawn(argv[0], argv.slice(1), { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.on("error", (error) => done({ status: 1, output: String(error) }));
    child.on("close", (status) => done({ status, output }));
  });
}

/** The object files of a library as the link reads them: copies under `<Products>/<Module>.objlib`, named in lower case. */
function libraryObjects(module, name, products) {
  const library = join(products, name + ".objlib");
  if (!existsSync(library)) return [];
  const map = module.argv[module.argv.indexOf("-output-file-map") + 1];
  const objects = Object.values(JSON.parse(readFileSync(map, "utf8"))).map((entry) => entry.object).filter(Boolean);
  const pairs = objects.map((object) => ({ from: object, to: join(library, basename(object).toLowerCase()) }));
  if (new Set(pairs.map((pair) => pair.to)).size !== pairs.length || pairs.some((pair) => !existsSync(pair.to))) return null;
  return pairs;
}

/** Copies `from` over `to` when their bytes differ; true when it wrote. */
function publish(from, to) {
  const bytes = readFileSync(from);
  try { if (Buffer.compare(bytes, readFileSync(to)) === 0) return false; } catch { /* not there yet */ }
  writeFileSync(to, bytes);
  return true;
}

/**
 * `build`. Resolves `{ status, output, steps }`: status 0, 3 (`reason` says why the save is for `swift build`) or 1.
 * `treeChanges` is the number of files the lowering changed in the tree on this run, when the caller knows it.
 */
export async function build({ cache, fingerprint, treeChanges = null, changedFiles: listed = null, hot = false, log = () => {} }) {
  const notDirect = (reason) => ({ status: NOT_DIRECT, reason, output: "", steps: [] });
  const plan = loadPlan(cache);
  if (!plan) return notDirect("no plan yet");
  if (plan.fingerprint !== fingerprint) return notDirect("the build's flags changed");
  if (!plan.link) return notDirect("the link command was never seen");
  const products = dirname(plan.link.argv[plan.link.argv.indexOf("-o") + 1]);

  // The same modules with the same files as the last build.
  const lists = fileLists(plan.scratch);
  if (Object.keys(lists).sort().join("\n") !== Object.keys(plan.lists ?? {}).sort().join("\n")) return notDirect("the set of modules changed");
  const changed = new Map(); // module -> its changed sources
  const compiledAt = new Map(); // a changed source -> the modification time it is compiled at
  let changedFiles = 0;
  for (const [name, sources] of Object.entries(plan.sources)) {
    for (const source of sources) {
      let stat;
      try { stat = statSync(source); } catch { return notDirect(`${source} was removed`); }
      if (stat.mtimeMs !== plan.stamps?.[source]) { (changed.get(name) ?? changed.set(name, []).get(name)).push(source); compiledAt.set(source, stat.mtimeMs); changedFiles++; }
    }
  }
  // A Swift file anywhere beneath a module's folder that no module lists is a file the last build did not see.
  const owned = new Set(Object.values(plan.sources).flat());
  const roots = moduleRoots(plan.sources);
  const added = unknownSwiftFile(roots, owned);
  if (added) return notDirect(`${added} is new`);
  // A file the lowering changed that is not one of those sources (a manifest, a C source, a resource) is not ours.
  if (listed !== null) {
    // The list of a tree sync. A Swift file outside every module's folders is compiled by nobody (a staged copy of a
    // package that lives inside the framework's repository holds its sources twice); one beneath them and not a source
    // is a new file.
    for (const file of listed.map(real)) {
      if (owned.has(file)) continue;
      if (!file.endsWith(".swift") || /^Package(@swift-[\d.]+)?\.swift$/.test(basename(file)) || isBeneath(file, roots)) return notDirect(`${file} is not a Swift source of a module`);
    }
  } else {
    if (treeChanges === null) return notDirect("the lowering did not say what it changed");
    if (treeChanges > changedFiles) return notDirect("a file that is not a Swift source of a module changed");
  }
  const mode = hot && plan.hot?.ok ? "hot" : "ordinary";
  // Nothing to compile, and what this mode bundles was linked from the objects as they are.
  const behind = !isCurrent(plan, mode);
  // Modules a failed build left to compile: one whose import published a new interface before the build stopped has
  // no changed source, and the interface will not change again to say so.
  const owed = (plan.owed ?? []).filter((name) => name in plan.sources);
  if (changed.size === 0 && owed.length === 0 && !behind) return { status: 0, output: "", steps: [], nothing: true };

  // Who imports whom, from the sources as they are now.
  const names = Object.keys(plan.sources);
  const dependencies = Object.fromEntries(names.map((name) => [name, [...importsOf(plan.sources[name], plan.modules[name]?.argv)].filter((other) => other !== name && names.includes(other))]));
  const order = [], seen = new Set();
  const visit = (name) => { if (seen.has(name)) return; seen.add(name); for (const dependency of dependencies[name]) visit(dependency); order.push(name); };
  names.forEach(visit);
  // Everything a module reaches through its imports: it waits for all of it, since a module two imports away can change
  // what the ones in between publish.
  const reaches = {};
  for (const name of order) reaches[name] = new Set(dependencies[name].flatMap((dependency) => [dependency, ...reaches[dependency]]));

  const steps = [];
  let output = "";
  const dirty = new Set([...changed.keys(), ...owed]);
  const done = new Set();
  // A build that stops after compiling anything leaves every module it meant to compile owed to the next one.
  const failed = (name) => {
    plan.owed = [...dirty];
    writeFileSync(join(cache, PLAN), JSON.stringify(plan));
    return { status: 1, output, steps, failed: name };
  };
  // In dependency order, the modules that are ready together compile together.
  for (;;) {
    const ready = order.filter((name) => dirty.has(name) && !done.has(name) && [...reaches[name]].every((dependency) => !dirty.has(dependency) || done.has(dependency)));
    if (ready.length === 0) break;
    for (const name of ready) {
      const module = plan.modules[name];
      if (!module?.argv) return notDirect(`the compile command of ${name} was never seen`);
      const hasDependents = names.some((other) => dependencies[other].includes(name));
      if (hasDependents && !(module.copies ?? []).some((copy) => copy.to.endsWith(".swiftmodule"))) return notDirect(`how ${name} publishes its interface was never seen`);
      module.objects = libraryObjects(module, name, products);
      if (module.objects === null) return notDirect(`the object library of ${name} is not the one expected`);
    }
    const results = await Promise.all(ready.map(async (name) => {
      const began = performance.now();
      const result = await run(plan.modules[name].argv, plan.modules[name].cwd);
      return { name, result, ms: performance.now() - began };
    }));
    for (const { name, result, ms } of results) {
      steps.push([name, ms]);
      output += result.output;
      done.add(name);
      if (result.status !== 0) return failed(name);
      const module = plan.modules[name];
      for (const object of module.objects) {
        const from = statSync(object.from), to = statSync(object.to);
        if (to.mtimeMs < from.mtimeMs || to.size !== from.size) copyFileSync(object.from, object.to);
      }
      // The modules that import this one compile again only when what it publishes changed.
      let interfaceChanged = false;
      for (const copy of module.copies ?? []) {
        if (!existsSync(copy.from)) continue;
        const wrote = publish(copy.from, copy.to);
        if (wrote && !/\.(swiftsourceinfo|swiftdoc)$/.test(copy.to)) interfaceChanged = true;
      }
      // Every module that reaches this one, not only the ones that import it by name: a module in between can export
      // it again (`@_exported import`) and publish the same bytes itself. One that already compiled in this run compiles
      // again.
      if (interfaceChanged) for (const other of names) if (reaches[other].has(name)) { dirty.add(other); done.delete(other); }
      log(`${name} ${ms.toFixed(0)} ms${interfaceChanged ? " (interface changed)" : ""}`);
    }
  }

  // A hot plan links two modules: the side module when the application compiled, the main module when anything else did.
  // A save that compiled only the application leaves the main module, and the page that runs it, as they are.
  if (mode === "hot") {
    const compiled = new Set(steps.map(([name]) => name));
    // Both when the split is behind the objects (the last builds were ordinary ones).
    const linkSide = behind || compiled.has(plan.hot.application), linkMain = behind || [...compiled].some((name) => name !== plan.hot.application);
    const linked = await hotLink(plan, cache, { linkMain, linkSide });
    steps.push(...linked.steps);
    output += linked.output;
    if (!linked.ok) {
      // Neither module can be trusted now: the split is dropped (the launcher bundles the ordinary executable) until
      // `prepare-hot` makes one again after a `swift build`.
      if (linked.failed) plan.owed = [...dirty];
      markHotFailed(cache, plan, linked.reason ?? `the ${linked.failed} did not link`);
      return linked.failed ? { status: 1, output, steps, failed: linked.failed } : notDirect(linked.reason);
    }
    for (const [source, modified] of compiledAt) plan.stamps[source] = modified;
    delete plan.owed;
    linkedNow(plan, "hot", compiled.size > 0);
    writeFileSync(join(cache, PLAN), JSON.stringify(plan));
    return { status: 0, output, steps, hot: linkMain ? "main" : "side" };
  }
  const began = performance.now();
  const linked = await run(plan.link.argv, plan.link.cwd);
  steps.push(["link", performance.now() - began]);
  output += linked.output;
  if (linked.status !== 0) return failed("link");
  // What was compiled is each source as it was when it was found changed; one saved again since then has another time.
  for (const [source, modified] of compiledAt) plan.stamps[source] = modified;
  delete plan.owed;
  linkedNow(plan, "ordinary", steps.length > 1);
  writeFileSync(join(cache, PLAN), JSON.stringify(plan));
  return { status: 0, output, steps };
}

if (import.meta.main) {
  const { positionals, values } = parseArgs({
    allowPositionals: true,
    options: { cache: { type: "string" }, scratch: { type: "string" }, log: { type: "string" }, fingerprint: { type: "string" }, started: { type: "string" }, "tree-changes": { type: "string" }, "changed-files": { type: "string" }, hot: { type: "boolean" } },
  });
  const [command] = positionals;
  if (command === "record") {
    const plan = record({ cache: values.cache, scratch: values.scratch, logPath: values.log, fingerprint: values.fingerprint ?? "", started: Number(values.started) });
    console.log(`Direct build: the commands of ${Object.keys(plan.modules).length} of ${Object.keys(plan.lists).length} modules are known`);
  } else if (command === "build") {
    const treeChanges = /^\d+$/.test(values["tree-changes"] ?? "") ? Number(values["tree-changes"]) : null;
    // The sync's list: `  changed: <path>` lines; a removed file, or a list that cannot be read, is not a direct build.
    let changedFiles = null;
    if (values["changed-files"] !== undefined) {
      let lines = null;
      try { lines = readFileSync(values["changed-files"], "utf8").split("\n").filter((line) => line.trim() !== ""); } catch { /* unknown */ }
      if (lines === null || treeChanges === null || lines.some((line) => !line.startsWith("  changed: "))) { console.log("Direct build not used: the tree sync did not list what it changed"); process.exit(NOT_DIRECT); }
      changedFiles = lines.map((line) => line.slice("  changed: ".length));
    }
    const result = await build({ cache: values.cache, fingerprint: values.fingerprint ?? "", treeChanges, changedFiles, hot: values.hot === true });
    if (result.output) process.stdout.write(result.output.endsWith("\n") ? result.output : result.output + "\n");
    if (result.status === NOT_DIRECT) console.log(`Direct build not used: ${result.reason}`);
    else if (result.status === 0) {
      console.log(result.nothing ? "Direct build: nothing to compile" : `Direct build: ${result.steps.map(([name, ms]) => `${name} ${(ms / 1000).toFixed(2)} s`).join(", ")}`);
      // The launcher reads this line: which of the two modules of a hot build changed.
      if (result.hot) console.log(`Hot swap: the ${result.hot} module changed`);
    }
    else console.error(`error: the direct build failed in ${result.failed}`);
    process.exit(result.status);
  } else if (command === "prepare-hot") {
    const result = await prepareHot({ cache: values.cache });
    if (result.status !== 0 && result.output) process.stdout.write(result.output.endsWith("\n") ? result.output : result.output + "\n");
    console.log(result.status === 0 ? `Hot swap: the application is a side module (${result.steps.map(([name, ms]) => `${name} ${(ms / 1000).toFixed(2)} s`).join(", ")})` : `Hot swap not used: ${result.reason}`);
    process.exit(result.status);
  } else if (command === "hot-status") {
    // Exit 0 only when the split is valid now: the launcher bundles the two modules on this word alone.
    process.exit(hotStatus({ cache: values.cache, fingerprint: values.fingerprint ?? null }) ? 0 : 1);
  } else {
    console.error("usage: dev-direct-build.mjs record|build|prepare-hot|hot-status --cache DIR [--scratch DIR --log FILE --started MS] [--fingerprint TEXT] [--tree-changes N] [--changed-files FILE]");
    process.exit(2);
  }
}
