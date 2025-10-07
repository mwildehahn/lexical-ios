import XCTest
@testable import Lexical
@testable import LexicalUIKit

final class KeyedDiffTests: XCTestCase {
  func testLISBasic() {
    let arr = [3, 1, 2, 5, 4]
    let idx = longestIncreasingSubsequenceIndices(arr)
    // One valid LIS is 1,2,5 or 1,2,4 by value; indices should be increasing
    XCTAssertFalse(idx.isEmpty)
    var last = -1
    for i in idx {
      XCTAssertGreaterThan(i, last)
      last = i
    }
  }

  func testStableChildKeys() {
    let prev = ["a","b","c","d","e"]
    let next = ["b","a","c","e","d"]
    let stable = computeStableChildKeys(prev: prev, next: next)
    // "c" is obviously stable; depending on LIS, either "b" or "a" may be included as well
    XCTAssertTrue(stable.contains("c"))
    XCTAssertTrue(stable.isSubset(of: Set(next)))
  }
}

