/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import LexicalCore

/// Rebuilds rangeCache locations using a Fenwick tree of per-node entireRange deltas.
/// - Parameters:
///   - prev: previous range cache (with up-to-date lengths for changed nodes)
///   - deltas: per-node total delta (entireRange length difference). Positive for growth, negative for shrink.
/// - Returns: next map with updated `location` fields; other fields preserved from `prev`.
@MainActor
internal func rebuildLocationsWithFenwick(
  prev: [NodeKey: RangeCacheItem],
  deltas: [NodeKey: Int],
  order: [NodeKey]? = nil,
  indexOf: [NodeKey: Int]? = nil
) -> [NodeKey: RangeCacheItem] {
  if deltas.isEmpty { return prev }
  let useProvided = order != nil && indexOf != nil
  let keys: [NodeKey]
  let lookup: [NodeKey: Int]
  if useProvided {
    keys = order!
    lookup = indexOf!
  } else {
    let ordered = prev.map { $0 }.sorted { a, b in
      if a.value.location != b.value.location { return a.value.location < b.value.location }
      return a.value.range.length > b.value.range.length
    }
    keys = ordered.map { $0.key }
    var map: [NodeKey: Int] = [:]
    map.reserveCapacity(keys.count)
    for (i, k) in keys.enumerated() { map[k] = i + 1 }
    lookup = map
  }
  var bit = FenwickTree(keys.count)
  for (k, d) in deltas {
    if let idx = lookup[k], d != 0 { bit.add(idx, d) }
  }
  if keys.isEmpty { return prev }
  var next = prev
  for (i, k) in keys.enumerated() {
    let shift = bit.prefixSum(i)
    if var item = next[k], let prevItem = prev[k] {
      item.location = max(0, prevItem.location + shift)
      next[k] = item
    }
  }
  return next
}

/// Rebuilds rangeCache locations by applying range-based shifts using a Fenwick tree.
/// Each range is defined as [startKey, endKeyExclusive) in the DFS/location order.
/// Passing `nil` for endKeyExclusive means the shift applies until the end.
@MainActor
internal func rebuildLocationsWithFenwickRanges(
  prev: [NodeKey: RangeCacheItem],
  ranges: [(startKey: NodeKey, endKeyExclusive: NodeKey?, delta: Int)],
  order: [NodeKey]? = nil,
  indexOf: [NodeKey: Int]? = nil
) -> [NodeKey: RangeCacheItem] {
  if ranges.isEmpty { return prev }
  let useProvided = order != nil && indexOf != nil
  let keys: [NodeKey]
  let lookup: [NodeKey: Int]
  if useProvided {
    keys = order!
    lookup = indexOf!
  } else {
    let ordered = prev.map { $0 }.sorted { a, b in
      if a.value.location != b.value.location { return a.value.location < b.value.location }
      return a.value.range.length > b.value.range.length
    }
    keys = ordered.map { $0.key }
    var map: [NodeKey: Int] = [:]
    map.reserveCapacity(keys.count)
    for (i, k) in keys.enumerated() { map[k] = i + 1 }
    lookup = map
  }
  var bit = FenwickTree(keys.count)
  for (s, e, d) in ranges {
    if d == 0 { continue }
    if let si = lookup[s] { bit.add(si, d) }
    if let e, let ei = lookup[e] { bit.add(ei, -d) }
  }
  if keys.isEmpty { return prev }
  var next = prev
  for (i, k) in keys.enumerated() {
    let shift = bit.prefixSum(i)
    if var item = next[k], let prevItem = prev[k] {
      item.location = max(0, prevItem.location + shift)
      next[k] = item
    }
  }
  return next
}

@MainActor
internal func rebuildLocationsWithRangeDiffs(
  prev: [NodeKey: RangeCacheItem],
  ranges: [(startKey: NodeKey, endKeyExclusive: NodeKey?, delta: Int)],
  order: [NodeKey]? = nil,
  indexOf: [NodeKey: Int]? = nil
) -> [NodeKey: RangeCacheItem] {
  if ranges.isEmpty { return prev }
  let useProvided = order != nil && indexOf != nil
  let keys: [NodeKey]
  let lookup: [NodeKey: Int]
  if useProvided {
    keys = order!
    lookup = indexOf!
  } else {
    let ordered = prev.map { $0 }.sorted { a, b in
      if a.value.location != b.value.location { return a.value.location < b.value.location }
      return a.value.range.length > b.value.range.length
    }
    keys = ordered.map { $0.key }
    var map: [NodeKey: Int] = [:]
    map.reserveCapacity(keys.count)
    for (i, k) in keys.enumerated() { map[k] = i + 1 }
    lookup = map
  }
  if keys.isEmpty { return prev }
  var diff = Array(repeating: 0, count: keys.count + 2)
  for (s, e, d) in ranges {
    if d == 0 { continue }
    if let si = lookup[s] { diff[si] &+= d }
    if let e, let ei = lookup[e] { diff[ei] &-= d }
  }
  var prefix = 0
  var next = prev
  for (i, k) in keys.enumerated() {
    prefix &+= diff[i + 1]
    if var item = next[k], let prevItem = prev[k] {
      item.location = max(0, prevItem.location + prefix)
      next[k] = item
    }
  }
  return next
}
