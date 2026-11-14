import Foundation
import Testing
@testable import SwiftUIWebTransferable
@_spi(Renderer) import SwiftUIWebTransferable

private enum CoverageDataError: Error, Equatable {
  case boom
}

private struct CoverageText: Transferable, Equatable {
  let text: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation<CoverageText>(importedContentType: .plainText) { data in
      CoverageText(text: String(decoding: data, as: UTF8.self))
    }
  }
}

private func parse(_ text: String) throws -> _EmbeddedJSONValue {
  try _EmbeddedJSONCodec._parse(Data(Array(text.utf8)))
}

private func parseIsInvalid(_ bytes: [UInt8]) -> Bool {
  do {
    _ = try _EmbeddedJSONCodec._parse(Data(bytes))
    return false
  } catch let error as _EmbeddedCodableError {
    if case .invalidJSON = error { return true }
    return false
  } catch {
    return false
  }
}

private func encoded(_ value: _EmbeddedJSONValue) throws -> String {
  String(decoding: try _EmbeddedJSONCodec._encode(value), as: UTF8.self)
}

private func string(_ value: _EmbeddedJSONValue?) -> String? {
  if case .string(let text)? = value { return text }
  return nil
}

private func number(_ value: _EmbeddedJSONValue?) -> Double? {
  if case .number(let number)? = value { return number }
  return nil
}

private func fileSystemFailure(_ body: () throws -> Void) -> FileSystemError? {
  do {
    try body()
    return nil
  } catch let error as FileSystemError {
    return error
  } catch {
    return nil
  }
}

@Suite(.serialized)
struct TransferableCoverageTests {
  // MARK: Embedded JSON value and codec

  @Test func objectSubscriptReturnsTheValueForAKeyOnly() {
    let object: _EmbeddedJSONValue = .object(["flag": .bool(true)])
    if case .bool(let flag)? = object["flag"] {
      #expect(flag)
    } else {
      Issue.record("The object subscript should return the stored value")
    }
    #expect(object["missing"] == nil)

    let array: _EmbeddedJSONValue = .array([.bool(true)])
    #expect(array["flag"] == nil)
  }

  @Test func parserDecodesEveryStandardEscapeInAString() throws {
    let value = try parse(#""a\nb\t\"\\\/\b\f\r""#)
    #expect(string(value) == "a\nb\t\"\\/\u{8}\u{c}\r")
  }

  @Test func parserDecodesUnicodeEscapesAndSurrogatePairs() throws {
    let pair = try parse(#""𝄞""#)
    #expect(string(pair) == "\u{1D11E}")

    let accented = try parse(#""é""#)
    #expect(string(accented) == "\u{e9}")
  }

  @Test func parserKeepsRawNonASCIIBytesBeforeAnEscape() throws {
    let value = try parse("\"\u{e9}\\n\"")
    #expect(string(value) == "\u{e9}\n")
  }

  @Test func parserRejectsMalformedStrings() {
    #expect(parseIsInvalid(Array(#""\x""#.utf8)))
    #expect(parseIsInvalid(Array(#""\uDC00""#.utf8)))
    #expect(parseIsInvalid(Array(#""\uD800x""#.utf8)))
    #expect(parseIsInvalid(Array(#""\uD800A""#.utf8)))
    #expect(parseIsInvalid(Array(#""\u12G4""#.utf8)))
    #expect(parseIsInvalid(Array(#""\u12""#.utf8)))
    #expect(parseIsInvalid(Array("\"a\u{1}\"".utf8)))
    #expect(parseIsInvalid(Array(#""abc"#.utf8)))
    #expect(parseIsInvalid([34, 0xFF, 34]))
  }

  @Test func parserReadsExponentsAndFallsBackForLongNumbers() throws {
    #expect(number(try parse("1.5e2")) == 150)
    #expect(number(try parse("1e+2")) == 100)
    #expect(number(try parse("-2.5E-1")) == -0.25)
    #expect(number(try parse("12345678901234567890")) == Double("12345678901234567890"))
    #expect(parseIsInvalid(Array("1e400".utf8)))
  }

  @Test func encoderWritesLargeNumbersInExponentForm() throws {
    #expect(try encoded(.number(1.5e30)) == "1.5e30")
  }

  @Test func encoderEscapesControlCharactersAsUnicodeEscapes() throws {
    #expect(try encoded(.string("\u{1}")) == #""\u0001""#)
    #expect(try encoded(.string("a\"b\\\n")) == #""a\"b\\\n""#)
  }

  @Test func mappingKeysRewritesEveryNestedObjectKey() throws {
    let value = try parse(#"{"user_name":{"first_name":"a"},"items":[{"item_id":1}]}"#)
    let mapped = value._mappingKeys(_EmbeddedKeyCase.camelFromSnake)

    #expect(mapped["user_name"] == nil)
    #expect(string(mapped["userName"]?["firstName"]) == "a")
    if case .array(let items)? = mapped["items"], case .object(let first) = items[0] {
      #expect(number(first["itemId"]) == 1)
    } else {
      Issue.record("Array items should be mapped element by element")
    }
  }

  @Test func mappingKeysLeavesScalarsUnchanged() {
    let scalar = _EmbeddedJSONValue.number(2)._mappingKeys { $0.uppercased() }
    #expect(number(scalar) == 2)
  }

  @Test func requiredReturnsAPresentValueAndNamesAMissingKey() {
    let present = try? _EmbeddedJSONValue.required(["name": .string("Vitor")], "name")
    #expect(string(present) == "Vitor")

    do {
      _ = try _EmbeddedJSONValue.required([:], "missing")
      Issue.record("A missing key should throw")
    } catch let error as _EmbeddedCodableError {
      if case .missingKey(let key) = error {
        #expect(key == "missing")
      } else {
        Issue.record("A missing key should throw missingKey")
      }
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }

  @Test func base64EncodesEveryPaddingShape() {
    #expect(_embeddedBase64Encode([77, 97, 110]) == "TWFu")
    #expect(_embeddedBase64Encode([77, 97]) == "TWE=")
    #expect(_embeddedBase64Encode([77]) == "TQ==")
  }

  @Test func base64DecodesEveryPaddingShapeAndRefusesMalformedInput() throws {
    #expect(try _embeddedBase64Decode("TWFu") == [77, 97, 110])
    #expect(try _embeddedBase64Decode("TWE=") == [77, 97])
    #expect(try _embeddedBase64Decode("TQ==") == [77])
    #expect(throws: (any Error).self) { try _embeddedBase64Decode("TQ=") }
    #expect(throws: (any Error).self) { try _embeddedBase64Decode("T!==") }
  }

  // MARK: Virtual file system

  @Test func fileSystemErrorKeepsItsReasonAndPath() {
    let error = FileSystemError(reason: .notADirectory, path: "/tmp/not-a-directory")
    #expect(error.reason == .notADirectory)
    #expect(error.path == "/tmp/not-a-directory")
  }

  @Test func appendToFileAddsBytesAfterTheExistingContents() throws {
    let vfs = _VirtualFileSystem.shared
    let path = "/tmp/transferable-coverage-append.bin"
    defer { try? vfs.remove(path) }

    try vfs.writeFile(Data([1, 2]), at: path)
    try vfs.appendToFile([3, 4] as [UInt8], at: path)
    #expect(vfs.file(at: path) == Data([1, 2, 3, 4]))
  }

  @Test func appendToFileCreatesAMissingFileInAnExistingDirectory() throws {
    let vfs = _VirtualFileSystem.shared
    let path = "/tmp/transferable-coverage-created.bin"
    defer { try? vfs.remove(path) }

    try vfs.appendToFile([9] as [UInt8], at: path)
    #expect(vfs.file(at: path) == Data([9]))
  }

  @Test func appendToFileNamesTheMissingParentDirectory() {
    let vfs = _VirtualFileSystem.shared
    let failure = fileSystemFailure {
      try vfs.appendToFile([1] as [UInt8], at: "/tmp/transferable-coverage-missing/file.bin")
    }
    #expect(failure?.reason == .noSuchFile)
    #expect(failure?.path == "/tmp/transferable-coverage-missing")
  }

  @Test func copyFileCopiesBytesAndRefusesBadDestinations() throws {
    let vfs = _VirtualFileSystem.shared
    let source = "/tmp/transferable-coverage-source.txt"
    let destination = "/tmp/transferable-coverage-copy.txt"
    defer {
      try? vfs.remove(source)
      try? vfs.remove(destination)
    }

    try vfs.writeFile(Data(Array("copied".utf8)), at: source)
    try vfs.copyFile(from: source, to: destination)
    #expect(vfs.file(at: destination) == Data(Array("copied".utf8)))

    let exists = fileSystemFailure { try vfs.copyFile(from: source, to: destination) }
    #expect(exists?.reason == .fileExists)
    #expect(exists?.path == destination)

    let missingSource = fileSystemFailure {
      try vfs.copyFile(from: "/tmp/transferable-coverage-absent.txt", to: "/tmp/transferable-coverage-other.txt")
    }
    #expect(missingSource?.reason == .noSuchFile)
    #expect(missingSource?.path == "/tmp/transferable-coverage-absent.txt")

    let missingParent = fileSystemFailure {
      try vfs.copyFile(from: source, to: "/tmp/transferable-coverage-nowhere/copy.txt")
    }
    #expect(missingParent?.reason == .noSuchFile)
    #expect(missingParent?.path == "/tmp/transferable-coverage-nowhere")
  }

  @Test func childrenListsOnlyDirectEntriesInSortedOrder() throws {
    let vfs = _VirtualFileSystem.shared
    let directory = "/tmp/transferable-coverage-children"
    defer { try? vfs.remove(directory) }

    try vfs.makeDirectory(directory, intermediate: false)
    try vfs.makeDirectory(directory + "/sub", intermediate: false)
    try vfs.writeFile(Data([1]), at: directory + "/b")
    try vfs.writeFile(Data([2]), at: directory + "/a")
    try vfs.writeFile(Data([3]), at: directory + "/sub/nested")

    #expect(vfs.children(of: directory) == [
      directory + "/a",
      directory + "/b",
      directory + "/sub",
    ])
  }

  @Test func fileURLPathsDecodeEscapesAndNormalize() {
    #expect(_VirtualFileSystem.path(of: URL("file:///tmp/cov%41%6a/./x%zz")) == "/tmp/covAj/x%zz")
    #expect(_VirtualFileSystem.path(of: URL("file://host/tmp/x")) == "/tmp/x")
    #expect(_VirtualFileSystem.path(of: URL("bare/../tmp//plain")) == "/tmp/plain")
    #expect(_VirtualFileSystem.normalized("/a/../b//c/.") == "/b/c")
  }

  // MARK: Data

  @Test func dataSlicesKeepTheIndicesOfTheirBase() {
    let data = Data([0, 1, 2, 3, 4, 5])
    let slice = data[2..<4]
    #expect(slice.startIndex == 2)
    #expect(slice.endIndex == 4)
    #expect(slice[2] == 2)
    #expect(slice[3] == 3)
    #expect(Array(slice) == [2, 3])
    #expect(Array(data[1...3]) == [1, 2, 3])
    #expect(data[4...].startIndex == 4)
  }

  @Test func dataSubscriptsWriteThroughToTheBytes() {
    var data = Data([0, 1, 2, 3, 4, 5])
    data[0] = 7
    data[2..<4] = Data([9, 9])
    data[4..<5] = Data([8])
    #expect(Array(data) == [7, 1, 9, 9, 8, 5])
  }

  @Test func replaceSubrangeOnASliceUsesBaseIndices() {
    var slice = Data([0, 1, 2, 3, 4, 5])[2..<4]
    slice.replaceSubrange(2..<3, with: [7, 7])
    #expect(slice.startIndex == 2)
    #expect(Array(slice) == [7, 7, 3])
  }

  @Test func dataEqualityAndHashIgnoreIndices() {
    let data = Data([0, 1, 2, 3])
    #expect(data[1..<3] == Data([1, 2]))
    #expect(data[1..<3] != Data([1, 3]))
    #expect(Set([Data([1, 2])]).contains(data[1..<3]))
  }

  @Test func withUnsafeBytesReadsTheSliceBytes() {
    let slice = Data([1, 2, 3, 4])[1..<3]
    let sum = slice.withUnsafeBytes { buffer in buffer.reduce(0) { $0 + Int($1) } }
    #expect(sum == 5)
    #expect(Data([4, 5])[0..<1].toArray() == [4])
  }

  @Test func withUnsafeMutableBytesWritesBackToTheData() {
    var data = Data([1, 2, 3])
    data.withUnsafeMutableBytes { buffer in buffer[1] = 9 }
    #expect(Array(data) == [1, 9, 3])
  }

  @Test func unsafeBufferAccessRethrowsTheBodyError() {
    let data = Data([1])
    #expect(throws: CoverageDataError.boom) {
      _ = try data.withUnsafeBytes { (_: UnsafeRawBufferPointer) throws(CoverageDataError) -> Int in throw .boom }
    }

    var mutable = Data([1])
    #expect(throws: CoverageDataError.boom) {
      try mutable.withUnsafeMutableBytes { (_: UnsafeMutableRawBufferPointer) throws(CoverageDataError) -> Void in throw .boom }
    }
  }

  // MARK: Transferable

  @Test func initializerImportsDataWithTheGivenContentType() async throws {
    let value = try await CoverageText(importing: Data(Array("hello".utf8)), contentType: .plainText)
    #expect(value == CoverageText(text: "hello"))
  }

  @Test func initializerImportsDataWithoutAContentTypeUsingTheFirstImportedType() async throws {
    let value = try await CoverageText(importing: Data(Array("bare".utf8)), contentType: nil)
    #expect(value == CoverageText(text: "bare"))
  }

  @Test func initializerImportsAFileFromTheVirtualFileSystem() async throws {
    let vfs = _VirtualFileSystem.shared
    let path = "/tmp/transferable-coverage-import.txt"
    defer { try? vfs.remove(path) }

    try vfs.writeFile(Data(Array("from file".utf8)), at: path)
    let value = try await CoverageText(importing: URL(fileURLWithPath: path), contentType: .plainText)
    #expect(value == CoverageText(text: "from file"))
  }
  @Test
  func aDataSliceReportsItsIndices() {
    let data = Data([1, 2, 3, 4])
    #expect(data.indices == 0..<4)
    #expect(data[1...2].indices == 1..<3)
  }
}
