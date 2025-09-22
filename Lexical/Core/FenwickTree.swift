/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Fenwick Tree (Binary Indexed Tree) for efficient range sum queries and updates
/// Used for O(log n) offset management in the optimized reconciler
@MainActor
internal final class FenwickTree {
  private var tree: [Int]
  private let size: Int

  /// Get the size of the Fenwick tree
  var treeSize: Int {
    return size
  }

  /// Initialize a Fenwick tree with given size
  /// - Parameter size: The maximum number of elements in the tree
  init(size: Int) {
    self.size = size
    self.tree = Array(repeating: 0, count: size + 1)
  }

  /// Update the value at index by delta
  /// - Parameters:
  ///   - index: The index to update (0-based)
  ///   - delta: The amount to add to the value at index
  /// - Complexity: O(log n)
  func update(index: Int, delta: Int) {
    var idx = index + 1 // Convert to 1-based indexing
    while idx <= size {
      tree[idx] += delta
      idx += idx & (-idx) // Add last set bit
    }
  }

  /// Query the prefix sum from index 0 to index (inclusive)
  /// - Parameter index: The end index of the range (0-based)
  /// - Returns: The sum of values from 0 to index
  /// - Complexity: O(log n)
  func query(index: Int) -> Int {
    guard index >= 0 else { return 0 }

    var sum = 0
    var idx = min(index + 1, size) // Convert to 1-based indexing
    while idx > 0 {
      sum += tree[idx]
      idx -= idx & (-idx) // Remove last set bit
    }
    return sum
  }

  /// Query the sum of values in range [left, right] (inclusive)
  /// - Parameters:
  ///   - left: The start index of the range (0-based)
  ///   - right: The end index of the range (0-based)
  /// - Returns: The sum of values in the range
  /// - Complexity: O(log n)
  func rangeQuery(left: Int, right: Int) -> Int {
    guard left <= right else { return 0 }
    guard left >= 0 else { return query(index: right) }

    return query(index: right) - (left > 0 ? query(index: left - 1) : 0)
  }

  /// Set the value at index to a specific value
  /// - Parameters:
  ///   - index: The index to set (0-based)
  ///   - value: The new value to set at index
  /// - Complexity: O(log n)
  func set(index: Int, value: Int) {
    let currentValue = rangeQuery(left: index, right: index)
    let delta = value - currentValue
    update(index: index, delta: delta)
  }

  /// Build the tree from an initial array of values
  /// - Parameter values: The initial values to populate the tree with
  /// - Complexity: O(n log n)
  func build(from values: [Int]) {
    // Reset tree
    tree = Array(repeating: 0, count: size + 1)

    // Build tree by updating each position
    for (index, value) in values.enumerated() where index < size {
      update(index: index, delta: value)
    }
  }

  /// Find the first index where the cumulative sum is greater than or equal to target
  /// Useful for binary searching on cumulative sums
  /// - Parameter target: The target cumulative sum
  /// - Returns: The first index where prefix sum >= target, or nil if not found
  /// - Complexity: O(log^2 n)
  func findFirstIndex(where prefixSum: Int) -> Int? {
    var left = 0
    var right = size - 1
    var result: Int?

    while left <= right {
      let mid = left + (right - left) / 2
      let sum = query(index: mid)

      if sum >= prefixSum {
        result = mid
        right = mid - 1
      } else {
        left = mid + 1
      }
    }

    return result
  }

  /// Reset all values in the tree to zero
  /// - Complexity: O(n)
  func reset() {
    tree = Array(repeating: 0, count: size + 1)
  }

  /// Get the total sum of all values in the tree
  /// - Returns: The sum of all values
  /// - Complexity: O(log n)
  var totalSum: Int {
    return query(index: size - 1)
  }

  /// Debug description showing the actual values at each index
  var debugValues: [Int] {
    return (0..<size).map { rangeQuery(left: $0, right: $0) }
  }
}

// MARK: - Reconciler Integration

extension FenwickTree {
  /// Create a Fenwick tree for tracking node offsets in the document
  /// - Parameter nodeCount: The maximum number of nodes to track
  /// - Returns: A configured Fenwick tree for offset tracking
  static func createForReconciler(nodeCount: Int) -> FenwickTree {
    // Add some buffer for growth
    let bufferSize = max(nodeCount * 2, 1000)
    return FenwickTree(size: bufferSize)
  }

  /// Update the text length for a node at the given index
  /// - Parameters:
  ///   - nodeIndex: The index of the node in document order
  ///   - oldLength: The previous text length of the node
  ///   - newLength: The new text length of the node
  func updateNodeLength(nodeIndex: Int, oldLength: Int, newLength: Int) {
    let delta = newLength - oldLength
    if delta != 0 {
      update(index: nodeIndex, delta: delta)
    }
  }

  /// Get the text offset for a node at the given index
  /// - Parameter nodeIndex: The index of the node in document order
  /// - Returns: The cumulative text offset up to (but not including) this node
  func getNodeOffset(nodeIndex: Int) -> Int {
    guard nodeIndex > 0 else { return 0 }
    return query(index: nodeIndex - 1)
  }

  /// Find the node index that contains the given text offset
  /// - Parameter textOffset: The text offset in the document
  /// - Returns: The node index containing this offset, or nil if not found
  func findNodeContainingOffset(_ textOffset: Int) -> Int? {
    return findFirstIndex(where: textOffset + 1)
  }
}