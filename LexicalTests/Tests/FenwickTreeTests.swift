import XCTest
@testable import Lexical
@testable import LexicalUIKit

final class FenwickTreeTests: XCTestCase {
  func testPrefixAndRangeSums() {
    var bit = FenwickTree(8)
    bit.add(1, 5)
    bit.add(2, -2)
    bit.add(3, 7)
    bit.add(8, 4)

    XCTAssertEqual(bit.prefixSum(1), 5)
    XCTAssertEqual(bit.prefixSum(2), 3)
    XCTAssertEqual(bit.prefixSum(3), 10)
    XCTAssertEqual(bit.prefixSum(8), 14)

    XCTAssertEqual(bit.rangeSum(1, 1), 5)
    XCTAssertEqual(bit.rangeSum(2, 3), 5) // -2 + 7
    XCTAssertEqual(bit.rangeSum(4, 8), 4)
  }

  func testMultipleAddsSameIndex() {
    var bit = FenwickTree(5)
    bit.add(3, 2)
    bit.add(3, 3)
    bit.add(3, -1)
    XCTAssertEqual(bit.prefixSum(3), 4)
    XCTAssertEqual(bit.rangeSum(3, 3), 4)
  }

  func testBounds() {
    var bit = FenwickTree(1)
    bit.add(1, 1)
    XCTAssertEqual(bit.prefixSum(1), 1)
  }
}

