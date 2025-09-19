/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Testing
@testable import Lexical

struct FenwickTreeTests {

  // MARK: - Basic Operations

  @Test
  func initialization() {
    let tree = FenwickTree(capacity: 10)

    // All queries should return 0 for empty tree
    #expect(tree.query(upTo: 0) == 0)
    #expect(tree.query(upTo: 5) == 0)
    #expect(tree.query(upTo: 9) == 0)
  }

  @Test
  func singleUpdate() {
    let tree = FenwickTree(capacity: 10)

    tree.update(at: 3, delta: 5)

    #expect(tree.query(upTo: 2) == 0, "Values before index 3 should be 0")
    #expect(tree.query(upTo: 3) == 5, "Query up to index 3 should include the value")
    #expect(tree.query(upTo: 9) == 5, "All queries after index 3 should include the value")
  }

  @Test
  func multipleUpdates() {
    let tree = FenwickTree(capacity: 10)

    tree.update(at: 1, delta: 3)
    tree.update(at: 4, delta: 7)
    tree.update(at: 7, delta: 2)

    #expect(tree.query(upTo: 0) == 0)
    #expect(tree.query(upTo: 1) == 3)
    #expect(tree.query(upTo: 3) == 3)
    #expect(tree.query(upTo: 4) == 10)
    #expect(tree.query(upTo: 6) == 10)
    #expect(tree.query(upTo: 7) == 12)
    #expect(tree.query(upTo: 9) == 12)
  }

  @Test
  func negativeDeltas() {
    let tree = FenwickTree(capacity: 10)

    tree.update(at: 2, delta: 10)
    tree.update(at: 5, delta: 8)

    #expect(tree.query(upTo: 9) == 18, "Initial sum")

    tree.update(at: 2, delta: -3)
    #expect(tree.query(upTo: 9) == 15, "After reducing index 2")

    tree.update(at: 5, delta: -8)
    #expect(tree.query(upTo: 9) == 7, "After reducing index 5")
  }

  @Test
  func rangeQueries() {
    let tree = FenwickTree(capacity: 10)

    // Set up values: [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
    for i in 0..<10 {
      tree.update(at: i, delta: i * 2)
    }

    #expect(tree.queryRange(from: 0, to: 0) == 0, "Single element at index 0")
    #expect(tree.queryRange(from: 1, to: 1) == 2, "Single element at index 1")
    #expect(tree.queryRange(from: 0, to: 2) == 6, "Sum of 0+2+4")
    #expect(tree.queryRange(from: 2, to: 4) == 18, "Sum of 4+6+8")
    #expect(tree.queryRange(from: 5, to: 7) == 36, "Sum of 10+12+14")
    #expect(tree.queryRange(from: 0, to: 9) == 90, "Sum of all elements")
  }

  @Test
  func setOperation() {
    let tree = FenwickTree(capacity: 10)

    // Initially set some values
    tree.set(at: 2, value: 5)
    tree.set(at: 4, value: 10)
    tree.set(at: 6, value: 3)

    #expect(tree.queryRange(from: 2, to: 2) == 5)
    #expect(tree.queryRange(from: 4, to: 4) == 10)
    #expect(tree.queryRange(from: 6, to: 6) == 3)
    #expect(tree.query(upTo: 9) == 18)

    // Update existing values
    tree.set(at: 2, value: 8)
    #expect(tree.queryRange(from: 2, to: 2) == 8, "Value at index 2 should be updated")
    #expect(tree.query(upTo: 9) == 21, "Total sum should reflect the change")

    tree.set(at: 4, value: 0)
    #expect(tree.queryRange(from: 4, to: 4) == 0, "Value at index 4 should be 0")
    #expect(tree.query(upTo: 9) == 11, "Total sum should reflect removal")
  }

  @Test
  func reset() {
    let tree = FenwickTree(capacity: 10)

    // Add some values
    for i in 0..<10 {
      tree.update(at: i, delta: i + 1)
    }

    #expect(tree.query(upTo: 9) == 55, "Sum before reset")

    tree.reset()

    #expect(tree.query(upTo: 0) == 0, "After reset")
    #expect(tree.query(upTo: 5) == 0, "After reset")
    #expect(tree.query(upTo: 9) == 0, "After reset")
  }

  // MARK: - Edge Cases

  @Test
  func boundaryIndices() {
    let tree = FenwickTree(capacity: 5)

    // Test first index
    tree.update(at: 0, delta: 7)
    #expect(tree.query(upTo: 0) == 7)

    // Test last index
    tree.update(at: 4, delta: 11)
    #expect(tree.query(upTo: 4) == 18)
    #expect(tree.queryRange(from: 4, to: 4) == 11)
  }

  @Test
  func outOfBoundsOperations() {
    let tree = FenwickTree(capacity: 5)

    // Updates out of bounds should be ignored
    tree.update(at: -1, delta: 10)
    tree.update(at: 5, delta: 10)
    tree.update(at: 100, delta: 10)

    #expect(tree.query(upTo: 4) == 0, "Out of bounds updates should be ignored")

    // Queries out of bounds
    #expect(tree.query(upTo: -1) == 0, "Query with negative index")
    #expect(tree.query(upTo: 100) == 0, "Query beyond capacity")
  }

  @Test
  func invalidRangeQueries() {
    let tree = FenwickTree(capacity: 10)

    for i in 0..<10 {
      tree.update(at: i, delta: 1)
    }

    // Range where from > to should return 0
    #expect(tree.queryRange(from: 5, to: 3) == 0, "Invalid range should return 0")
    #expect(tree.queryRange(from: 8, to: 2) == 0, "Invalid range should return 0")
  }

  @Test
  func largeValues() {
    let tree = FenwickTree(capacity: 10)

    let largeValue = Int.max / 20  // Avoid overflow
    tree.update(at: 3, delta: largeValue)
    tree.update(at: 7, delta: largeValue)

    #expect(tree.query(upTo: 9) == largeValue * 2, "Should handle large values")
    #expect(tree.queryRange(from: 4, to: 7) == largeValue, "Range query with large values")
  }

  @Test
  func alternatingPositiveNegative() {
    let tree = FenwickTree(capacity: 10)

    // Set alternating positive and negative values
    for i in 0..<10 {
      let value = (i % 2 == 0) ? 5 : -3
      tree.update(at: i, delta: value)
    }

    // Sum should be 5*5 + (-3)*5 = 25 - 15 = 10
    #expect(tree.query(upTo: 9) == 10, "Should handle alternating signs")

    // Range [2, 5] = 5 + (-3) + 5 + (-3) = 4
    #expect(tree.queryRange(from: 2, to: 5) == 4, "Range with alternating signs")
  }

  // MARK: - Stress Tests

  @Test
  func largeCapacity() {
    let capacity = 10000
    let tree = FenwickTree(capacity: capacity)

    // Update every 10th position
    for i in stride(from: 0, to: capacity, by: 10) {
      tree.update(at: i, delta: 1)
    }

    #expect(tree.query(upTo: capacity - 1) == 1000, "Should handle large capacity")
  }

  @Test(.timeLimit(.minutes(1)))
  func manyUpdatesPerformance() {
    let tree = FenwickTree(capacity: 1000)

    // Perform 10000 updates
    for _ in 0..<10000 {
      let index = Int.random(in: 0..<1000)
      let delta = Int.random(in: -100...100)
      tree.update(at: index, delta: delta)
    }

    // Perform 1000 queries
    for _ in 0..<1000 {
      let index = Int.random(in: 0..<1000)
      _ = tree.query(upTo: index)
    }
  }

  @Test
  func sequentialUpdatesAndQueries() {
    let tree = FenwickTree(capacity: 100)
    var expectedSum = 0

    // Simulate sequential document updates
    for i in 0..<100 {
      let value = i + 1
      tree.update(at: i, delta: value)
      expectedSum += value

      // Verify cumulative sum is correct after each update
      #expect(tree.query(upTo: i) == expectedSum, "Sum up to index \(i)")
    }
  }

  @Test
  func setVsUpdateEquivalence() {
    let tree1 = FenwickTree(capacity: 20)
    let tree2 = FenwickTree(capacity: 20)

    // Use set operations for tree1
    for i in 0..<20 {
      tree1.set(at: i, value: i * 3)
    }

    // Use update operations for tree2
    for i in 0..<20 {
      tree2.update(at: i, delta: i * 3)
    }

    // Both should give same results
    for i in 0..<20 {
      #expect(tree1.query(upTo: i) == tree2.query(upTo: i),
              "Set and update should give same results at index \(i)")
    }
  }

  @Test
  func complexDocumentSimulation() {
    let tree = FenwickTree(capacity: 50)

    // Simulate a document with nodes of varying sizes
    let nodeSizes = [100, 50, 200, 75, 150, 300, 25, 125, 80, 175]

    // Initial setup
    for (i, size) in nodeSizes.enumerated() {
      tree.set(at: i, value: size)
    }

    // Verify initial state
    var expectedTotal = nodeSizes.reduce(0, +)
    #expect(tree.query(upTo: 9) == expectedTotal)

    // Simulate text edits that change node sizes
    tree.update(at: 2, delta: 50)  // Node 2 grows by 50
    expectedTotal += 50
    #expect(tree.query(upTo: 9) == expectedTotal)

    tree.update(at: 5, delta: -100)  // Node 5 shrinks by 100
    expectedTotal -= 100
    #expect(tree.query(upTo: 9) == expectedTotal)

    // Verify position calculations
    let positionOfNode3 = tree.query(upTo: 2)  // Sum of nodes 0, 1, 2
    #expect(positionOfNode3 == 100 + 50 + 250)  // 250 because we added 50 to node 2

    let positionOfNode6 = tree.query(upTo: 5)  // Sum of nodes 0-5
    #expect(positionOfNode6 == 100 + 50 + 250 + 75 + 150 + 200)  // 200 because we subtracted 100
  }
}