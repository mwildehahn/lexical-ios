/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Computes LIS (Longest Increasing Subsequence) indices over an array of Int.
/// Returns the indices (into the input array) that form an increasing subsequence with max length.
internal func longestIncreasingSubsequenceIndices(_ arr: [Int]) -> [Int] {
  let n = arr.count
  if n == 0 { return [] }
  var parent = Array(repeating: -1, count: n)
  var tails = [Int]()
  var tailsIdx = [Int]()

  func lowerBound(_ value: Int) -> Int {
    var l = 0, r = tails.count
    while l < r {
      let m = (l + r) / 2
      if tails[m] < value { l = m + 1 } else { r = m }
    }
    return l
  }

  for i in 0..<n {
    let x = arr[i]
    let pos = lowerBound(x)
    if pos == tails.count {
      tails.append(x)
      tailsIdx.append(i)
    } else {
      tails[pos] = x
      tailsIdx[pos] = i
    }
    parent[i] = (pos > 0) ? tailsIdx[pos - 1] : -1
  }

  var lisIdx = [Int]()
  var k = tailsIdx.last!
  while k >= 0 {
    lisIdx.append(k)
    k = parent[k]
  }
  return lisIdx.reversed()
}

/// Given prev and next child key arrays that contain the same keys, compute the set of keys
/// that can stay in place (LIS by prev positions in next order).
internal func computeStableChildKeys(prev: [NodeKey], next: [NodeKey]) -> Set<NodeKey> {
  let indexInPrev: [NodeKey: Int] = Dictionary(uniqueKeysWithValues: prev.enumerated().map { ($1, $0) })
  let mapped: [Int] = next.compactMap { indexInPrev[$0] }
  let lisIdx = longestIncreasingSubsequenceIndices(mapped)
  let stable = lisIdx.map { next[$0] }
  return Set(stable)
}

