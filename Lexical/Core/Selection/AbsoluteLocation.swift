/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@MainActor
internal func absoluteNodeStartLocation(
  _ key: NodeKey,
  rangeCache: [NodeKey: RangeCacheItem],
  useOptimized: Bool,
  fenwickTree: FenwickTree
) -> Int {
  if key == kRootNodeKey { return 0 }
  guard let node = getNodeByKey(key: key) else {
    // Fallback to what we know from cache when node has been GC'd or missing
    if useOptimized, let item = rangeCache[key] { return item.locationFromFenwick(using: fenwickTree) }
    return rangeCache[key]?.location ?? 0
  }
  // If no parent, fall back to cache-provided location
  guard let parentKey = node.parent,
        let parentItem = rangeCache[parentKey],
        let parent = getNodeByKey(key: parentKey) as? ElementNode else {
    if useOptimized, let item = rangeCache[key] { return item.locationFromFenwick(using: fenwickTree) }
    return rangeCache[key]?.location ?? 0
  }

  // Recurse to parent's absolute start
  let parentStart = absoluteNodeStartLocation(parentKey, rangeCache: rangeCache, useOptimized: useOptimized, fenwickTree: fenwickTree)
  var acc = parentStart + parentItem.preambleLength

  // Sum contributions of siblings that come before this node within the parent
  for childKey in parent.getChildrenKeys(fromLatest: false) {
    if childKey == key { break }
    if let s = rangeCache[childKey] {
      acc += s.preambleLength + s.childrenLength + s.textLength + s.postambleLength
    }
  }
  return acc
}

