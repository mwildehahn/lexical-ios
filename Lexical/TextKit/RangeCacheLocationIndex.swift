/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@MainActor
internal final class RangeCacheLocationIndex {

  private var orderedKeys: [NodeKey] = []
  private var baseLocations: [Int] = []
  private var positions: [NodeKey: Int] = [:]
  private var fenwick: FenwickTree = FenwickTree(count: 0)

  internal init() {}

  var isEmpty: Bool {
    orderedKeys.isEmpty
  }

  func rebuild(rangeCache: [NodeKey: RangeCacheItem]) {
    if rangeCache.isEmpty {
      orderedKeys = []
      baseLocations = []
      positions = [:]
      fenwick = FenwickTree(count: 0)
      return
    }

    orderedKeys = rangeCache.keys.sorted { leftKey, rightKey in
      let leftRange = rangeCache[leftKey] ?? RangeCacheItem()
      let rightRange = rangeCache[rightKey] ?? RangeCacheItem()
      if leftRange.location == rightRange.location {
        return leftKey < rightKey
      }
      return leftRange.location < rightRange.location
    }

    baseLocations = orderedKeys.map { key in
      rangeCache[key]?.location ?? 0
    }

    positions.removeAll(keepingCapacity: true)
    for (index, key) in orderedKeys.enumerated() {
      positions[key] = index
    }

    fenwick = FenwickTree(count: orderedKeys.count)
  }

  func clear() {
    orderedKeys = []
    baseLocations = []
    positions = [:]
    fenwick = FenwickTree(count: 0)
  }

  func effectiveLocation(for key: NodeKey, base: Int) -> Int {
    guard let index = positions[key] else {
      return base
    }
    return base + fenwick.query(index)
  }

  func shiftNodes(startingAt location: Int, delta: Int) {
    guard delta != 0, !baseLocations.isEmpty else {
      return
    }

    let startIndex = lowerBound(baseLocations, value: location)
    guard startIndex < orderedKeys.count else {
      return
    }

    fenwick.addSuffix(from: startIndex, delta: delta)
  }

  private func lowerBound(_ array: [Int], value: Int) -> Int {
    var low = 0
    var high = array.count
    while low < high {
      let mid = (low + high) / 2
      if array[mid] < value {
        low = mid + 1
      } else {
        high = mid
      }
    }
    return low
  }

  private struct FenwickTree {
    private var tree: [Int]

    init(count: Int) {
      // 1-based indexing for Fenwick tree simplifies implementation.
      tree = Array(repeating: 0, count: count + 2)
    }

    mutating func addSuffix(from index: Int, delta: Int) {
      guard delta != 0 else { return }
      let count = tree.count - 1
      guard index < count else { return }
      var idx = index + 1
      while idx <= count {
        tree[idx] += delta
        idx += idx & -idx
      }
    }

    func query(_ index: Int) -> Int {
      if index < 0 {
        return 0
      }
      var idx = min(index + 1, tree.count - 1)
      var result = 0
      while idx > 0 {
        result += tree[idx]
        idx -= idx & -idx
      }
      return result
    }
  }
}

extension RangeCacheItem {
  @MainActor
  func resolvingLocation(using index: RangeCacheLocationIndex?, key: NodeKey) -> RangeCacheItem {
    guard let index else { return self }
    var resolved = self
    resolved.location = index.effectiveLocation(for: key, base: location)
    return resolved
  }
}
