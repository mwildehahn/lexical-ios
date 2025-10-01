import XCTest
@testable import Lexical

final class DfsIndexTests: XCTestCase {
  func testSortedNodeKeysByLocation() {
    var cache: [NodeKey: RangeCacheItem] = [:]
    // Simulate simple tree with overlapping ranges at same location
    // Root at 0..30, child at 0..10, sibling at 10..20
    var root = RangeCacheItem()
    root.location = 0
    root.preambleLength = 0
    root.childrenLength = 30
    cache["root"] = root

    var a = RangeCacheItem()
    a.location = 0
    a.childrenLength = 10
    cache["a"] = a

    var b = RangeCacheItem()
    b.location = 10
    b.childrenLength = 20
    cache["b"] = b

    let sorted = sortedNodeKeysByLocation(rangeCache: cache)
    // For same location, longer range (root) should come before child (a)
    XCTAssertEqual(sorted.first, "root")
    XCTAssertTrue(sorted.contains("a"))
    XCTAssertTrue(sorted.contains("b"))
    // Ensure order by location groups a (0) before b (10)
    let idxA = sorted.firstIndex(of: "a")!
    let idxB = sorted.firstIndex(of: "b")!
    XCTAssertLessThan(idxA, idxB)
  }
}

