// The codec copy (EmbeddedCodable.swift, a symlink compiled with EMBEDDED_JSON_TESTS) names `Data` without importing it,
// as its own module declares it. Re-exporting Foundation (WebFoundation, through the module alias) gives every file here
// the framework's own `Data`, `Date` and calendar types.
@_exported import Foundation
