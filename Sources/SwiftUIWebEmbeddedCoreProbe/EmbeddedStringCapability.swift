/// Optional capability probe, excluded from the minimum artifact unless the
/// build script is invoked with `--string`. A literal plus UTF-8 traversal is
/// enough to show the cost of ordinary String support without pulling the
/// framework's reflection-shaped `String(describing:)` paths into the result.
#if SWIFTUIWEB_EMBEDDED_STRING_PROBE
@_cdecl("embedded_string_length")
public func swiftuiwebEmbeddedStringLength(_ value: Int32) -> Int32 {
  let literal = "SwiftUIWeb"
  return Int32(literal.utf8.count) + value
}
#endif
