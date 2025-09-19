/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A Fenwick Tree (Binary Indexed Tree) for efficient range sum queries and updates
/// This enables O(log n) offset updates when node sizes change
internal final class FenwickTree {
  private var tree: [Int]
  private let capacity: Int

  init(capacity: Int) {
    self.capacity = capacity
    self.tree = Array(repeating: 0, count: capacity + 1)
  }

  /// Update the value at index by adding delta
  /// Time complexity: O(log n)
  func update(at index: Int, delta: Int) {
    guard index >= 0 && index < capacity else { return }

    var i = index + 1  // Fenwick tree is 1-indexed
    while i <= capacity {
      tree[i] += delta
      i += (i & -i)  // Move to parent using bit manipulation
    }
  }

  /// Get the cumulative sum from 0 to index (inclusive)
  /// Time complexity: O(log n)
  func query(upTo index: Int) -> Int {
    guard index >= 0 else { return 0 }

    var sum = 0
    var i = min(index + 1, capacity)  // Fenwick tree is 1-indexed

    while i > 0 {
      sum += tree[i]
      i -= (i & -i)  // Move to predecessor using bit manipulation
    }

    return sum
  }

  /// Get the cumulative sum for a range [from, to] (inclusive)
  /// Time complexity: O(log n)
  func queryRange(from: Int, to: Int) -> Int {
    guard from <= to else { return 0 }

    if from == 0 {
      return query(upTo: to)
    } else {
      return query(upTo: to) - query(upTo: from - 1)
    }
  }

  /// Reset the tree to all zeros
  func reset() {
    tree = Array(repeating: 0, count: capacity + 1)
  }

  /// Set the value at index (replaces current value)
  /// Time complexity: O(log n)
  func set(at index: Int, value: Int) {
    let currentValue = queryRange(from: index, to: index)
    let delta = value - currentValue
    update(at: index, delta: delta)
  }
}