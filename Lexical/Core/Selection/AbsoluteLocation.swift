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
  fenwickTree: FenwickTree,
  leadingShift: Bool = false
) -> Int {
  if key == kRootNodeKey { return 0 }
  guard let node = getNodeByKey(key: key) else {
    // Fallback to what we know from cache when node has been GC'd or missing
    if useOptimized, let item = rangeCache[key] {
      // Important: do not call back into RangeCacheItem.locationFromFenwick here,
      // as that path may in turn call absoluteNodeStartLocation for elements and
      // create mutual recursion. Use the Fenwick tree directly for a safe
      // best‑effort absolute base.
      return fenwickTree.getNodeOffset(nodeIndex: item.nodeIndex)
    }
    return rangeCache[key]?.location ?? 0
  }
  // If no parent, fall back to cache-provided location
  guard let parentKey = node.parent,
        let parentItem = rangeCache[parentKey],
        let parent = getNodeByKey(key: parentKey) as? ElementNode else {
    if useOptimized, let item = rangeCache[key] {
      // Avoid mutual recursion with locationFromFenwick (see note above).
      return fenwickTree.getNodeOffset(nodeIndex: item.nodeIndex)
    }
    return rangeCache[key]?.location ?? 0
  }

  // Recurse to parent's absolute start
  let parentStart = absoluteNodeStartLocation(parentKey, rangeCache: rangeCache, useOptimized: useOptimized, fenwickTree: fenwickTree, leadingShift: leadingShift)
  var acc = parentStart + parentItem.preambleLength
  if leadingShift, parentKey == kRootNodeKey {
    acc += 1
  }
  if let editor = getActiveEditor(), editor.featureFlags.selectionParityDebug {
    print("🔥 ABS-START: key=\(key) parent=\(parentKey) parentStart=\(parentStart) parent.pre=\(parentItem.preambleLength) parent.ch=\(parentItem.childrenLength) parent.tx=\(parentItem.textLength) parent.post=\(parentItem.postambleLength)")
  }

  // Sum contributions of siblings that come before this node within the parent
  for childKey in parent.getChildrenKeys(fromLatest: false) {
    if childKey == key { break }
    if let s = rangeCache[childKey] {
      let add = s.preambleLength + s.childrenLength + s.textLength + s.postambleLength
      acc += add
      if let editor = getActiveEditor(), editor.featureFlags.selectionParityDebug {
        print("  🔹 ABS sib=\(childKey) add=\(add) pre=\(s.preambleLength) ch=\(s.childrenLength) tx=\(s.textLength) post=\(s.postambleLength)")
      }
    }
  }
  return acc
}
