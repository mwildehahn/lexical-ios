/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Fenwick Tree (Binary Indexed Tree) for prefix sums of Int deltas.
/// 1-based indexing.
public struct FenwickTree {
  private var tree: [Int]

  public init(_ n: Int) {
    precondition(n >= 0, "FenwickTree size must be non-negative")
    // store n+1, index 0 unused
    self.tree = Array(repeating: 0, count: n + 1)
  }

  public var size: Int { max(0, tree.count - 1) }

  public mutating func add(_ index: Int, _ delta: Int) {
    precondition(index >= 1 && index <= size, "Index out of bounds")
    var i = index
    while i <= size {
      tree[i] &+= delta
      i += (i & -i)
    }
  }

  /// Returns sum from 1...index
  public func prefixSum(_ index: Int) -> Int {
    if index <= 0 { return 0 }
    precondition(index <= size, "Index out of bounds")
    var i = index
    var res = 0
    while i > 0 {
      res &+= tree[i]
      i -= (i & -i)
    }
    return res
  }

  /// Returns sum in [l, r]
  public func rangeSum(_ l: Int, _ r: Int) -> Int {
    precondition(l <= r, "Invalid range")
    return prefixSum(r) - prefixSum(l - 1)
  }
}
