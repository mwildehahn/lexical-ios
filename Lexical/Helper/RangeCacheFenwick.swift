/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Rebuilds rangeCache locations using a Fenwick tree of per-node entireRange deltas.
/// - Parameters:
///   - prev: previous range cache (with up-to-date lengths for changed nodes)
///   - deltas: per-node total delta (entireRange length difference). Positive for growth, negative for shrink.
/// - Returns: next map with updated `location` fields; other fields preserved from `prev`.
@MainActor
internal func rebuildLocationsWithFenwick(
  prev: [NodeKey: RangeCacheItem], deltas: [NodeKey: Int]
) -> [NodeKey: RangeCacheItem] {
  let keys = prev.map { $0 }.sorted { a, b in
    if a.value.location != b.value.location { return a.value.location < b.value.location }
    return a.value.range.length > b.value.range.length
  }.map { $0.key }
  var indexOf: [NodeKey: Int] = [:]
  for (i, k) in keys.enumerated() { indexOf[k] = i + 1 }
  var bit = FenwickTree(keys.count)
  for (k, d) in deltas {
    if let idx = indexOf[k], d != 0 { bit.add(idx, d) }
  }
  var next = prev
  for (i, k) in keys.enumerated() {
    let shift = bit.prefixSum(i)
    if var item = next[k] {
      item.location = max(0, prev[k]!.location + shift)
      next[k] = item
    }
  }
  return next
}

