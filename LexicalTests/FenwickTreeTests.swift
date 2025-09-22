/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class FenwickTreeTests: XCTestCase {

  // MARK: - Basic Operations Tests

  func testInitialization() throws {
    let tree = FenwickTree(size: 10)
    XCTAssertEqual(tree.totalSum, 0)
    XCTAssertEqual(tree.query(index: 5), 0)
  }

  func testSingleUpdate() throws {
    let tree = FenwickTree(size: 10)
    tree.update(index: 3, delta: 5)

    XCTAssertEqual(tree.query(index: 2), 0)
    XCTAssertEqual(tree.query(index: 3), 5)
    XCTAssertEqual(tree.query(index: 4), 5)
    XCTAssertEqual(tree.totalSum, 5)
  }

  func testMultipleUpdates() throws {
    let tree = FenwickTree(size: 10)
    tree.update(index: 1, delta: 3)
    tree.update(index: 3, delta: 5)
    tree.update(index: 5, delta: 2)

    XCTAssertEqual(tree.query(index: 0), 0)
    XCTAssertEqual(tree.query(index: 1), 3)
    XCTAssertEqual(tree.query(index: 3), 8)
    XCTAssertEqual(tree.query(index: 5), 10)
    XCTAssertEqual(tree.totalSum, 10)
  }

  func testRangeQuery() throws {
    let tree = FenwickTree(size: 10)
    tree.update(index: 1, delta: 3)
    tree.update(index: 3, delta: 5)
    tree.update(index: 5, delta: 2)

    XCTAssertEqual(tree.rangeQuery(left: 0, right: 0), 0)
    XCTAssertEqual(tree.rangeQuery(left: 1, right: 1), 3)
    XCTAssertEqual(tree.rangeQuery(left: 3, right: 3), 5)
    XCTAssertEqual(tree.rangeQuery(left: 1, right: 3), 8)
    XCTAssertEqual(tree.rangeQuery(left: 3, right: 5), 7)
    XCTAssertEqual(tree.rangeQuery(left: 0, right: 9), 10)
  }

  func testSetOperation() throws {
    let tree = FenwickTree(size: 10)
    tree.set(index: 2, value: 10)
    XCTAssertEqual(tree.rangeQuery(left: 2, right: 2), 10)

    tree.set(index: 2, value: 5)
    XCTAssertEqual(tree.rangeQuery(left: 2, right: 2), 5)

    tree.set(index: 2, value: 15)
    XCTAssertEqual(tree.rangeQuery(left: 2, right: 2), 15)
  }

  func testBuildFromArray() throws {
    let tree = FenwickTree(size: 10)
    let values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    tree.build(from: values)

    XCTAssertEqual(tree.query(index: 0), 1)
    XCTAssertEqual(tree.query(index: 4), 15)
    XCTAssertEqual(tree.query(index: 9), 55)
    XCTAssertEqual(tree.totalSum, 55)
  }

  // MARK: - Binary Search Tests

  func testFindFirstIndex() throws {
    let tree = FenwickTree(size: 10)
    tree.build(from: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

    XCTAssertEqual(tree.findFirstIndex(where: 1), 0)
    XCTAssertEqual(tree.findFirstIndex(where: 3), 1)
    XCTAssertEqual(tree.findFirstIndex(where: 6), 2)
    XCTAssertEqual(tree.findFirstIndex(where: 10), 3)
    XCTAssertEqual(tree.findFirstIndex(where: 15), 4)
    XCTAssertEqual(tree.findFirstIndex(where: 55), 9)
    XCTAssertNil(tree.findFirstIndex(where: 56))
  }

  // MARK: - Edge Cases

  func testEmptyTree() throws {
    let tree = FenwickTree(size: 0)
    XCTAssertEqual(tree.totalSum, 0)
  }

  func testSingleElementTree() throws {
    let tree = FenwickTree(size: 1)
    tree.update(index: 0, delta: 42)
    XCTAssertEqual(tree.query(index: 0), 42)
    XCTAssertEqual(tree.rangeQuery(left: 0, right: 0), 42)
    XCTAssertEqual(tree.totalSum, 42)
  }

  func testNegativeDeltas() throws {
    let tree = FenwickTree(size: 10)
    tree.update(index: 3, delta: 10)
    tree.update(index: 3, delta: -5)

    XCTAssertEqual(tree.rangeQuery(left: 3, right: 3), 5)
    XCTAssertEqual(tree.totalSum, 5)
  }

  func testReset() throws {
    let tree = FenwickTree(size: 10)
    tree.build(from: [1, 2, 3, 4, 5])
    XCTAssertEqual(tree.totalSum, 15)

    tree.reset()
    XCTAssertEqual(tree.totalSum, 0)
    XCTAssertEqual(tree.query(index: 4), 0)
  }

  func testDebugValues() throws {
    let tree = FenwickTree(size: 5)
    tree.build(from: [1, 2, 3, 4, 5])

    let debugValues = tree.debugValues
    XCTAssertEqual(debugValues, [1, 2, 3, 4, 5])
  }

  // MARK: - Reconciler Integration Tests

  func testNodeOffsetTracking() throws {
    let tree = FenwickTree.createForReconciler(nodeCount: 100)

    // Simulate node text lengths
    tree.updateNodeLength(nodeIndex: 0, oldLength: 0, newLength: 10)
    tree.updateNodeLength(nodeIndex: 1, oldLength: 0, newLength: 20)
    tree.updateNodeLength(nodeIndex: 2, oldLength: 0, newLength: 15)

    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 0), 0)
    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 1), 10)
    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 2), 30)
    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 3), 45)
  }

  func testNodeLengthUpdate() throws {
    let tree = FenwickTree.createForReconciler(nodeCount: 10)

    tree.updateNodeLength(nodeIndex: 0, oldLength: 0, newLength: 10)
    tree.updateNodeLength(nodeIndex: 1, oldLength: 0, newLength: 20)

    // Update node 0's length
    tree.updateNodeLength(nodeIndex: 0, oldLength: 10, newLength: 15)

    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 1), 15)
    XCTAssertEqual(tree.totalSum, 35)
  }

  func testFindNodeContainingOffset() throws {
    let tree = FenwickTree.createForReconciler(nodeCount: 10)

    tree.updateNodeLength(nodeIndex: 0, oldLength: 0, newLength: 10)
    tree.updateNodeLength(nodeIndex: 1, oldLength: 0, newLength: 20)
    tree.updateNodeLength(nodeIndex: 2, oldLength: 0, newLength: 15)

    // Text offset 5 is in node 0 (0-9)
    XCTAssertEqual(tree.findNodeContainingOffset(5), 0)

    // Text offset 10 is in node 1 (10-29)
    XCTAssertEqual(tree.findNodeContainingOffset(10), 1)

    // Text offset 25 is in node 1 (10-29)
    XCTAssertEqual(tree.findNodeContainingOffset(25), 1)

    // Text offset 30 is in node 2 (30-44)
    XCTAssertEqual(tree.findNodeContainingOffset(30), 2)

    // Text offset 44 is in node 2 (30-44)
    XCTAssertEqual(tree.findNodeContainingOffset(44), 2)

    // Text offset 45 is beyond the last node
    XCTAssertNil(tree.findNodeContainingOffset(45))
  }

  // MARK: - Performance Tests

  func testLargeTreePerformance() throws {
    let size = 10000
    let tree = FenwickTree(size: size)

    measure {
      // Build tree with values 1 to size
      tree.build(from: Array(1...size))

      // Perform 1000 updates
      for i in 0..<1000 {
        tree.update(index: i % size, delta: 1)
      }

      // Perform 1000 queries
      for i in 0..<1000 {
        _ = tree.query(index: i % size)
      }

      // Perform 1000 range queries
      for i in 0..<1000 {
        let left = i % (size / 2)
        let right = left + (size / 4)
        _ = tree.rangeQuery(left: left, right: min(right, size - 1))
      }

      tree.reset()
    }
  }

  func testUpdateComplexity() throws {
    let tree = FenwickTree(size: 100000)

    // Measure time for updates - should be O(log n)
    measure {
      for i in 0..<10000 {
        tree.update(index: i % 100000, delta: i)
      }
      tree.reset()
    }
  }

  func testQueryComplexity() throws {
    let tree = FenwickTree(size: 100000)
    tree.build(from: Array(repeating: 1, count: 100000))

    // Measure time for queries - should be O(log n)
    measure {
      for i in 0..<10000 {
        _ = tree.query(index: i % 100000)
      }
    }
  }
}