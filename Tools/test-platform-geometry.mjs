#!/usr/bin/env bun
// Compiles and runs the actual Geometry.swift in isolation, including Embedded.
//
// This is NOT a full SwiftUIWeb link or browser test. The module deliberately contains only the framework's geometry
// sources (CG types plus the host measurement / coordinate-space resolver) so no WASI SDK is required. The real
// browser path is covered by Tools/test-geometry-browser.mjs.
//
// usage: bun Tools/test-platform-geometry.mjs [--swiftc SWIFTC] [--output PATH]
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { jsonDumps, ROOT } from "./audit-support.mjs";

const CHECKS = String.raw`
func near(_ a: Double, _ b: Double) {
  precondition(abs(a - b) < 0.00000001)
}
func geometryChecks() {
  let p = CGPoint(x: 3, y: 7)
  let s = CGSize(width: 11, height: 13)
  let r = CGRect(origin: p, size: s)
  precondition(r.origin.x == 3 && r.size.height == 13)
  let negative = CGRect(x: 10, y: 20, width: -4, height: -6)
  precondition(negative.minX == 6 && negative.maxX == 10 && negative.width == 4)
  precondition(negative.minY == 14 && negative.maxY == 20 && negative.height == 6)
  let translated = CGAffineTransform.identity.scaledBy(x: 2, y: 3).translatedBy(x: 4, y: 5)
  near(Double(translated.tx), 8); near(Double(translated.ty), 15)
  let rotated = CGAffineTransform.identity.rotated(by: .pi / 2)
  near(Double(rotated.a), 0); near(Double(rotated.b), 1)
  near(Double(rotated.c), -1); near(Double(rotated.d), 0)
  let backwards = CGAffineTransform.identity.rotated(by: -.pi / 2)
  near(Double(backwards.b), -1); near(Double(backwards.c), 1)
  let inverse = translated.inverted()
  near(Double(inverse.a), 0.5); near(Double(inverse.d), 1.0 / 3)
  near(Double(inverse.tx), -4); near(Double(inverse.ty), -5)
  for k in -20...20 {
    let t = CGAffineTransform.identity.rotated(by: Double(k) * .pi / 10)
    near(Double(t.a * t.a + t.b * t.b), 1)
  }
}
`;
// The measurement types are `package` (the feature module reads them), so the sources compile under the package's name.
const MEASUREMENT_SOURCES = ["-package-name", "swiftuiweb", join(ROOT, "Sources/SwiftUIWebCore/Geometry.swift"), join(ROOT, "Sources/SwiftUIWebCore/GeometryMeasurement.swift")];
const MEASUREMENT_CHECKS = String.raw`
func rectEquals(_ r: CGRect?, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
  guard let r else { preconditionFailure("missing rect") }
  near(Double(r.origin.x), x); near(Double(r.origin.y), y)
  near(Double(r.size.width), w); near(Double(r.size.height), h)
}
func measurementChecks() {
  let raw = "100,250,80,40\u{1E}n\u{1F}stage\u{1F}20,50,300,500\u{1E}s\u{1F}vertical\u{1F}10,30,320,400\u{1E}n\u{1F}stage\u{1F}0,0,1,1"
  guard let m = _GeometryMeasurement(decoding: raw) else { preconditionFailure("decode") }
  precondition(m.spaces.count == 3)
  rectEquals(m.frame(in: .local), 0, 0, 80, 40)
  rectEquals(m.frame(in: .global), 100, 250, 80, 40)
  rectEquals(m.frame(in: .named("stage")), 80, 200, 80, 40)
  rectEquals(m.frame(in: .named("missing")), 100, 250, 80, 40)
  rectEquals(m.frame(in: .scrollView(horizontal: false, vertical: false)), 90, 220, 80, 40)
  rectEquals(m.frame(in: .scrollView(horizontal: false, vertical: true)), 90, 220, 80, 40)
  rectEquals(m.frame(in: .scrollView(horizontal: true, vertical: false)), 100, 250, 80, 40)
  rectEquals(m.bounds(of: .named("stage")), -80, -200, 300, 500)
  precondition(m.bounds(of: .named("missing")) == nil)
  precondition(_GeometrySpaceKeys.space(forNamedKey: _GeometrySpaceKeys.scrollViewVertical) == .scrollView(horizontal: false, vertical: true))
  guard let legacy = _GeometryMeasurement(decoding: "320.5,180.25") else { preconditionFailure("legacy") }
  rectEquals(legacy.frame(in: .global), 0, 0, 320.5, 180.25)
  precondition(_GeometryMeasurement(decoding: "bad") == nil)
  precondition(_GeometryMeasurement(decoding: "1,2,3") == nil)
  precondition(_GeometryMeasurement(decoding: "1,2,nan,4") == nil)
  guard let skipped = _GeometryMeasurement(decoding: "0,0,1,1\u{1E}x\u{1F}a\u{1F}0,0,1,1\u{1E}n\u{1F}b") else { preconditionFailure("records") }
  precondition(skipped.spaces.isEmpty)
}
`;

const isFile = (path) => existsSync(path) && statSync(path).isFile();

/** The executable `name` on PATH (or the path itself when it names a file), like `shutil.which`. */
function which(name) {
  if (name.includes("/")) return isFile(name) ? name : null;
  for (const directory of (process.env.PATH ?? "").split(delimiter)) {
    const candidate = join(directory, name);
    if (directory && isFile(candidate)) return candidate;
  }
  return null;
}

/**
 * String equality in Embedded Swift needs the Unicode data tables, which the browser build links explicitly (see
 * Package.swift). Link the host copy for the native Embedded executable probe.
 */
function embeddedUnicodeLinkFlags(compiler) {
  const info = spawnSync(compiler, ["-print-target-info"], { encoding: "utf8" });
  let resources;
  try {
    resources = join(JSON.parse(info.stdout).paths.runtimeResourcePath, "embedded");
  } catch {
    return [];
  }
  const machine = process.arch === "arm64" ? "arm64" : "x86_64";
  const darwin = process.platform === "darwin";
  const wanted = darwin ? [(name) => name === `${machine}-apple-macos`] : [(name) => name.startsWith(`${machine}-`) && name.includes("linux"), (name) => name.includes("linux")];
  if (!existsSync(resources)) return [];
  const directories = readdirSync(resources).sort();
  for (const matches of wanted) {
    for (const name of directories.filter(matches)) {
      const directory = join(resources, name);
      if (isFile(join(directory, "libswiftUnicodeDataTables.a"))) return ["-L", directory, "-lswiftUnicodeDataTables"];
    }
  }
  return [];
}

function main() {
  const { values: args } = parseArgs({
    options: {
      swiftc: { type: "string", default: process.env.SWIFTC ?? "swiftc" },
      output: { type: "string", default: join(ROOT, ".build/geometry-validation/result.json") },
    },
  });
  const compiler = which(args.swiftc);
  if (!compiler) {
    console.error("Swift compiler not found");
    return 2;
  }
  const results = [];
  const work = mkdtempSync(join(tmpdir(), "swiftuiweb-geometry-"));
  try {
    const run = (name, command) => {
      const strings = command.map(String);
      const result = spawnSync(strings[0], strings.slice(1), { encoding: "utf8", maxBuffer: 1 << 28 });
      const exitCode = result.status ?? -(result.signal ? 1 : 0);
      results.push({
        name, status: exitCode === 0 ? "PASS" : "FAIL", command: strings, exit_code: exitCode,
        stdout: result.stdout ?? "", stderr: result.stderr ?? "",
      });
      if (exitCode !== 0) {
        console.error(result.stderr);
        return false;
      }
      return true;
    };
    const extension = process.platform === "darwin" ? "dylib" : "so";
    const library = join(work, `libSwiftUIWebGeometryProbe.${extension}`);
    const ok = run("standard-source-module", [
      compiler, "-swift-version", "6", "-parse-as-library", "-emit-library", "-emit-module", "-module-name", "SwiftUIWebGeometryProbe",
      join(ROOT, "Sources/SwiftUIWebCore/Geometry.swift"), "-emit-module-path", join(work, "SwiftUIWebGeometryProbe.swiftmodule"), "-o", library,
    ]);
    if (ok) {
      // The CG types are SwiftUIWeb's own on every host (no Foundation import, as an application compiled with
      // `Foundation=WebFoundation` sees them): a client uses them from the module alone.
      ["import SwiftUIWebGeometryProbe"].forEach((imports, number) => {
        const client = join(work, `import-order-${number}.swift`);
        writeFileSync(client, imports + "\n" + CHECKS + "\ngeometryChecks()\n");
        const executable = join(work, `order-${number}`);
        if (run(`import-order-${number}-compile`, [
          compiler, "-swift-version", "6", "-I", work, "-L", work, "-lSwiftUIWebGeometryProbe", "-Xlinker", "-rpath", "-Xlinker", work, client, "-o", executable,
        ])) run(`import-order-${number}-execute`, [executable]);
      });
    }
    // Reproduce cross-file public default arguments without importing the platform module in the declaring file. This caught
    // the Swift 6.4 CoreGraphics/Foundation failure that a Geometry.swift-only probe missed.
    const defaults = join(work, "GeometryDefaultArguments.swift");
    writeFileSync(defaults, `
public struct GeometryDefaultArgumentProbe {
  public init(
    point: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint,
    size: CGSize = _SwiftUIWebGeometryDefaults.zeroSize,
    rect: CGRect = _SwiftUIWebGeometryDefaults.zeroRect
  ) {}
}
`);
    run("cross-file-default-arguments", [
      compiler, "-swift-version", "6", "-parse-as-library", "-emit-module", "-module-name", "SwiftUIWebGeometryDefaultsProbe",
      join(ROOT, "Sources/SwiftUIWebCore/Geometry.swift"), defaults, "-emit-module-path", join(work, "SwiftUIWebGeometryDefaultsProbe.swiftmodule"),
    ]);

    // Host measurement decoding and coordinate-space resolution share the standard module build; run them as one internal
    // module.
    const measurement = join(work, "MeasurementChecks.swift");
    writeFileSync(measurement, CHECKS + MEASUREMENT_CHECKS + "\n@main struct MeasurementMain { static func main() { geometryChecks(); measurementChecks() } }\n");
    let executable = join(work, "measurement-standard");
    if (run("measurement-standard-compile", [compiler, "-swift-version", "6", "-parse-as-library", ...MEASUREMENT_SOURCES, measurement, "-o", executable])) {
      run("measurement-standard-execute", [executable]);
    }
    // Same files, real Embedded compiler branch. No Foundation imports.
    const embedded = join(work, "EmbeddedChecks.swift");
    writeFileSync(embedded, CHECKS + MEASUREMENT_CHECKS + "\n@main struct GeometryMain { static func main() { geometryChecks(); measurementChecks() } }\n");
    executable = join(work, "embedded");
    if (run("embedded-native-compile", [
      compiler, "-enable-experimental-feature", "Embedded", "-wmo", "-O", "-parse-as-library", ...MEASUREMENT_SOURCES, embedded, "-o", executable,
      ...embeddedUnicodeLinkFlags(compiler), ...(process.platform.startsWith("linux") ? ["-lm"] : []),
    ])) run("embedded-native-execute", [executable]);
    // SDK-less compile probe. Linking/browser execution belongs to browser-test.
    run("embedded-wasm-object-compile", [
      compiler, "-enable-experimental-feature", "Embedded", "-wmo", "-O", "-parse-as-library", "-target", "wasm32-unknown-none-wasm", "-emit-object",
      ...MEASUREMENT_SOURCES, embedded, "-o", join(work, "geometry.wasm.o"),
    ]);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  const version = (spawnSync(compiler, ["--version"], { encoding: "utf8" }).stdout ?? "").trim();
  const report = {
    scope: "GEOMETRY_SOURCE_ONLY_NOT_FULL_FRAMEWORK", swiftc: version,
    status: results.every((item) => item.status === "PASS") ? "PASS" : "FAIL", checks: results,
  };
  const output = resolve(args.output);
  mkdirSync(join(output, ".."), { recursive: true });
  writeFileSync(output, jsonDumps(report) + "\n");
  console.log(jsonDumps({
    scope: report.scope, status: report.status, checks: results.map(({ name, status }) => ({ name, status })), report: output,
  }));
  return report.status === "PASS" ? 0 : 1;
}

process.exit(main());
