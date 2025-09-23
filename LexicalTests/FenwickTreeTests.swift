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

  // MARK: - Dynamic Resizing Tests

  func testDynamicResizing() throws {
    let tree = FenwickTree(size: 10)

    // Update at index 5 (within initial capacity)
    tree.update(index: 5, delta: 10)
    XCTAssertEqual(tree.query(index: 5), 10)

    // Update at index 15 (beyond initial capacity)
    tree.update(index: 15, delta: 20)
    XCTAssertEqual(tree.query(index: 15), 30)  // 10 + 20

    // Verify original values are preserved
    XCTAssertEqual(tree.rangeQuery(left: 5, right: 5), 10)

    // Update at index 100 (much beyond initial capacity)
    tree.update(index: 100, delta: 50)
    XCTAssertEqual(tree.query(index: 100), 80)  // 10 + 20 + 50

    // Verify all values are preserved
    XCTAssertEqual(tree.rangeQuery(left: 5, right: 5), 10)
    XCTAssertEqual(tree.rangeQuery(left: 15, right: 15), 20)
    XCTAssertEqual(tree.rangeQuery(left: 100, right: 100), 50)
  }

  func testResizingPreservesValues() throws {
    let tree = FenwickTree(size: 5)

    // Set initial values
    tree.set(index: 0, value: 1)
    tree.set(index: 1, value: 2)
    tree.set(index: 2, value: 3)
    tree.set(index: 3, value: 4)
    tree.set(index: 4, value: 5)

    // Verify initial sum
    XCTAssertEqual(tree.totalSum, 15)

    // Trigger resize by updating beyond capacity
    tree.set(index: 10, value: 10)

    // Verify all original values are preserved
    XCTAssertEqual(tree.rangeQuery(left: 0, right: 0), 1)
    XCTAssertEqual(tree.rangeQuery(left: 1, right: 1), 2)
    XCTAssertEqual(tree.rangeQuery(left: 2, right: 2), 3)
    XCTAssertEqual(tree.rangeQuery(left: 3, right: 3), 4)
    XCTAssertEqual(tree.rangeQuery(left: 4, right: 4), 5)
    XCTAssertEqual(tree.rangeQuery(left: 10, right: 10), 10)

    // Verify cumulative queries still work
    XCTAssertEqual(tree.query(index: 4), 15)
    XCTAssertEqual(tree.query(index: 10), 25)
  }

  func testLargeIndexResizing() throws {
    let tree = FenwickTree(size: 1)

    // Update at very large index
    tree.update(index: 10000, delta: 42)
    XCTAssertEqual(tree.rangeQuery(left: 10000, right: 10000), 42)

    // Tree should have resized to accommodate
    XCTAssertGreaterThanOrEqual(tree.treeSize, 10000)

    // Update at another large index
    tree.update(index: 20000, delta: 100)
    XCTAssertEqual(tree.rangeQuery(left: 20000, right: 20000), 100)

    // Verify both values
    XCTAssertEqual(tree.query(index: 20000), 142)
  }

  func testNodeLengthUpdateWithResize() throws {
    let tree = FenwickTree.createForReconciler(nodeCount: 5)

    // Update nodes within initial capacity
    tree.updateNodeLength(nodeIndex: 0, oldLength: 0, newLength: 10)
    tree.updateNodeLength(nodeIndex: 1, oldLength: 0, newLength: 20)

    // Update node beyond initial capacity
    tree.updateNodeLength(nodeIndex: 100, oldLength: 0, newLength: 50)

    // Verify offsets
    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 0), 0)
    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 1), 10)
    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 2), 30)  // 10 + 20
    XCTAssertEqual(tree.getNodeOffset(nodeIndex: 101), 80)  // 10 + 20 + 50
  }

  func testResizingPerformance() throws {
    let tree = FenwickTree(size: 10)

    measure {
      // This should trigger multiple resizes
      for i in 0..<1000 {
        tree.update(index: i, delta: i)
      }

      // Verify sum
      XCTAssertEqual(tree.query(index: 999), (999 * 1000) / 2)

      tree.reset()
    }
  }

  func testEnsureCapacityReturnValue() throws {
    let tree = FenwickTree(size: 10)

    // Should not resize for index within capacity
    XCTAssertFalse(tree.ensureCapacity(for: 5))
    XCTAssertFalse(tree.ensureCapacity(for: 9))

    // Should resize for index beyond capacity
    XCTAssertTrue(tree.ensureCapacity(for: 10))

    // After resizing for index 10, size should be max(10*2, 10+100) = 110
    // So index 100 should not trigger another resize
    XCTAssertFalse(tree.ensureCapacity(for: 100))

    // Should not resize again if already large enough
    XCTAssertFalse(tree.ensureCapacity(for: 50))

    // Should resize for index beyond new capacity
    XCTAssertTrue(tree.ensureCapacity(for: 200))
  }
}