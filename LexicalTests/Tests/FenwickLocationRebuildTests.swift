import XCTest
@testable import Lexical

@MainActor
final class FenwickLocationRebuildTests: XCTestCase {

  func testRebuildLocationsMultipleDeltas() throws {
    // Keys in DFS/text order: A, B, C
    let A = "A"; let B = "B"; let C = "C"
    var prev: [NodeKey: RangeCacheItem] = [:]
    var a = RangeCacheItem(); a.location = 0; a.preambleLength = 0; a.childrenLength = 0; a.textLength = 10; a.postambleLength = 0; prev[A] = a
    var b = RangeCacheItem(); b.location = 10; b.textLength = 5; prev[B] = b
    var c = RangeCacheItem(); c.location = 15; c.textLength = 7; prev[C] = c

    // Deltas: A grows by +2, C shrinks by -1
    let deltas: [NodeKey: Int] = [A: 2, C: -1]
    let next = rebuildLocationsWithFenwick(prev: prev, deltas: deltas)

    // Expected: A stays at 0; B shifts by +2; C shifts by +2 (its own delta does not move itself)
    XCTAssertEqual(next[A]?.location, 0)
    XCTAssertEqual(next[B]?.location, 12)
    XCTAssertEqual(next[C]?.location, 17)
  }
}

