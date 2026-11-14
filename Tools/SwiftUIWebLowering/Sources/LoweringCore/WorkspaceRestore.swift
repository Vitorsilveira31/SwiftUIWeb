import Foundation

/// `swiftuiweb-lowering --restore`: puts back the original of every file a lowering rewrote in place and removes what the
/// lowering recorded. Nothing to do (and no error) when there is no state, so a cleanup trap can run it unconditionally.
public enum WorkspaceRestore {
  public static func run(arguments: LoweringArguments) throws {
    let root = try FileSystem.canonical(arguments.rootPath)
    let statePath = FileSystem.join(root, arguments.statePath)
    guard FileSystem.exists(statePath) else { return }

    let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
    guard let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      throw LoweringArguments.Failure.message("\(statePath) is not a lowering state file")
    }
    guard let stateDirectory = FileSystem.parent(of: statePath) else { throw LoweringArguments.Failure.message("state has no parent") }
    // A state written before each state had its own backup folder has no `backup` entry and used the shared `backup`.
    let backupName = (state["backup"] as? String) ?? "backup"
    guard !backupName.isEmpty, !backupName.contains("/"), backupName != "..", backupName != "." else {
      throw LoweringArguments.Failure.message("state names a backup folder outside the state folder: \(backupName)")
    }
    let backup = FileSystem.join(stateDirectory, backupName)
    let hashes = state["hashes"] as? [String: Any] ?? [:]
    var kept: [String] = []
    for file in (state["files"] as? [Any])?.compactMap({ $0 as? String }) ?? [] {
      // The state is written by the lowerer, but a restore must never write outside the root it was asked to restore.
      guard !file.hasPrefix("/"), !file.split(separator: "/").contains("..") else {
        throw LoweringArguments.Failure.message("state names a file outside the restored root: \(file)")
      }
      let source = FileSystem.join(backup, file)
      let destination = FileSystem.join(root, file)
      guard FileSystem.exists(source) else { continue }
      // A file the user has edited since the lowering keeps its edits: it is restored only while it still holds the text the
      // lowering wrote, and a path through a symbolic link is refused.
      let recorded = (hashes[file] as? [String: Any])?["generated"] as? String
      let current = try? FileSystem.readString(destination)
      // A file that already holds its original text (restored by an earlier run that kept another file) is done.
      if let current, let original = try? FileSystem.readString(source), current == original { continue }
      guard let recorded, !FileSystem.hasSymbolicLinkComponent(root: root, relative: file),
        let current, SourceMap.stableHash(current) == recorded
      else {
        kept.append(file)
        continue
      }
      try FileSystem.createDirectories(FileSystem.parent(of: destination) ?? root)
      try FileSystem.copy(from: source, to: destination)
    }
    if !kept.isEmpty {
      // The originals of the skipped files stay in the backup, and the state stays with them, so nothing is lost.
      for file in kept {
        FileHandle.standardError.write(Data("restore: skipped \(file): it changed since the lowering, or its path has a symbolic link\n".utf8))
      }
      return
    }
    if FileSystem.exists(backup) { try remove(backup) }
    try remove(statePath)

    // State paths are configurable. Never recursively remove their parent: it can be the package root (or hold the
    // generated report). Remove only an empty state directory that is safely inside the restored root.
    if let canonicalParent = try? FileSystem.canonical(stateDirectory), canonicalParent != root,
      canonicalParent.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    {
      if rmdir(stateDirectory) != 0, errno != ENOENT, errno != ENOTEMPTY {
        throw LoweringArguments.Failure.message(FileSystem.osError())
      }
    }
  }

  private static func remove(_ path: String) throws {
    do {
      try FileManager.default.removeItem(atPath: path)
    } catch {
      throw LoweringArguments.Failure.message(FileSystem.describe(error))
    }
  }
}
