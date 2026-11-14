import Foundation
import LoweringCore

// The Swift source lowerer: the command line, files and exit codes the build relies on (see Documentation/EMBEDDED_SOURCE_LOWERING.md).
// A failure is printed as plain `path:line:column: [code] message` lines and ends the run with status 1.

func printError(_ text: String) {
  FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// `--literal-diff OLD NEW RELATIVE`. When the two sources differ only in the values of the literals the
/// `live-literals` pass wraps, prints one `id<TAB>kind<TAB>value` line per changed literal and returns 0; returns 3 when
/// they differ in anything else (the save needs a build).
func literalDiff(_ values: [String]) -> Int32 {
  guard values.count == 3, let old = try? String(contentsOfFile: values[0], encoding: .utf8), let new = try? String(contentsOfFile: values[1], encoding: .utf8) else {
    printError("usage: swiftuiweb-lowering --literal-diff OLD NEW RELATIVE")
    return 1
  }
  guard let lines = try? LiveLiteralSites.replacements(old: old, new: new, relativePath: values[2]) else { return 3 }
  print(lines.joined(separator: "\n"))
  return 0
}

func run() -> Int32 {
  if CommandLine.arguments.dropFirst().first == "--literal-diff" { return literalDiff(Array(CommandLine.arguments.dropFirst(2))) }
  let arguments: LoweringArguments
  do {
    arguments = try LoweringArguments.parse(Array(CommandLine.arguments.dropFirst()))
  } catch {
    printError(LoweringArguments.usage)
    printError("\(error)")
    return 1
  }
  if arguments.listPasses {
    print(LoweringPipeline.passNames.joined(separator: "\n"))
    return 0
  }
  if arguments.help {
    printError(LoweringArguments.usage)
    return 0
  }
  do {
    switch arguments.mode {
    case .restore:
      try WorkspaceRestore.run(arguments: arguments)
    case .apply:
      var pipeline = LoweringPipeline.standard
      if let rules = arguments.rules {
        guard let selected = pipeline.selecting(rules) else {
          throw LoweringArguments.Failure.message("unknown pass in --rules; ported passes: \(LoweringPipeline.passNames.joined(separator: ", "))")
        }
        pipeline = selected
      }
      let aliases = ProcessInfo.processInfo.environment["SWIFTUIWEB_MODULE_ALIASES"] == "1"
      let summary = try WorkspaceLowering(arguments: arguments, pipeline: pipeline, moduleAliases: aliases).run()
      print(summary.output)
    }
    return 0
  } catch {
    printError("\(error)")
    return 1
  }
}

exit(run())
