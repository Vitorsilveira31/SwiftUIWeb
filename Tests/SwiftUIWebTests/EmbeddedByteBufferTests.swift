import Testing
@testable import SwiftUIWebBrowser

@MainActor
@Suite struct EmbeddedByteBufferTests {
  private func fill(_ buffer: inout _EmbeddedByteBuffer, with byte: UInt8, count: Int) {
    let pointer = buffer.reserve(count)!
    pointer.update(repeating: byte, count: count)
    buffer.commit(count)
  }

  @Test func wipeZeroesTheWrittenBytesNotTheCapacity() {
    var buffer = _EmbeddedByteBuffer()
    fill(&buffer, with: 7, count: 4)
    let pointer = buffer.pointer!
    // Bytes past what the host wrote belong to nobody; a marker there shows
    // wipe() does not walk the whole capacity.
    pointer[100] = 9
    buffer.wipe()
    #expect((0..<4).allSatisfy { pointer[$0] == 0 })
    #expect(pointer[100] == 9)
    #expect(buffer.count == 0)
  }

  @Test func aLargeValueDoesNotKeepTheCapacity() {
    var buffer = _EmbeddedByteBuffer()
    fill(&buffer, with: 1, count: 200 * 1024)
    #expect(buffer.capacity >= 200 * 1024)
    buffer.wipe()
    #expect(buffer.capacity == 0)
    #expect(buffer.pointer == nil)
    // The next keystroke starts from the small default again.
    fill(&buffer, with: 2, count: 3)
    #expect(buffer.capacity < _EmbeddedByteBuffer.retainedCapacity)
    #expect(buffer.count == 3)
  }

  @Test func smallValuesKeepTheirStorage() {
    var buffer = _EmbeddedByteBuffer()
    fill(&buffer, with: 1, count: 10)
    let pointer = buffer.pointer
    buffer.wipe()
    #expect(buffer.pointer == pointer)
    fill(&buffer, with: 1, count: 12)
    #expect(buffer.pointer == pointer)
  }

  @Test func reservingAgainErasesAnUncommittedWrite() {
    var buffer = _EmbeddedByteBuffer()
    let pointer = buffer.reserve(8)!
    pointer.update(repeating: 5, count: 8)  // host wrote, never committed
    let again = buffer.reserve(8)!
    #expect((0..<8).allSatisfy { again[$0] == 0 })
  }

  @Test func growingWipesTheOldBytesBeforeReleasingThem() {
    var buffer = _EmbeddedByteBuffer()
    fill(&buffer, with: 3, count: 256)
    #expect(buffer.reserve(4096) != nil)
    #expect(buffer.capacity >= 4096)
    #expect(buffer.count == 0)
  }

  @Test func requestsPastTheLimitAreRefused() {
    var buffer = _EmbeddedByteBuffer()
    #expect(buffer.reserve(_EmbeddedByteBuffer.limit + 1) == nil)
    #expect(buffer.reserve(-1) == nil)
  }
}
