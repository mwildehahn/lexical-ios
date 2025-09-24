/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Updates RangeCache incrementally based on delta changes rather than full rebuilds
@MainActor
internal class IncrementalRangeCacheUpdater {

  private let editor: Editor
  private let fenwickTree: FenwickTree

  // MARK: - Initialization

  init(editor: Editor, fenwickTree: FenwickTree) {
    self.editor = editor
    self.fenwickTree = fenwickTree
  }

  // MARK: - Incremental Updates

  /// Update range cache based on applied deltas
  func updateRangeCache(
    _ rangeCache: inout [NodeKey: RangeCacheItem],
    basedOn deltas: [ReconcilerDelta]
  ) throws {

    // Group deltas by node for efficient processing
    let deltasByNode = groupDeltasByNode(deltas)
    print("🔥 RANGE CACHE UPDATER: applying deltas for \(deltasByNode.keys.count) nodes")

    // Establish a document-order pass for newly inserted nodes based on their insertion locations
    // 1) collect insertions with locations
    var insertionOrder: [(NodeKey, Int)] = []
    for deltas in deltasByNode.values {
      for d in deltas {
        if case let .nodeInsertion(nodeKey: key, insertionData: _, location: loc) = d.type {
          insertionOrder.append((key, loc))
        }
      }
    }
    // 2) sort insertions by ascending location to approximate document order in the backing string
    insertionOrder.sort { $0.1 < $1.1 }
    var visited: Set<NodeKey> = []

    // First, process insertions in string order (assigns stable Fenwick indices in order of appearance)
    for (key, _) in insertionOrder {
      if visited.contains(key) { continue }
      if let nodeDeltas = deltasByNode[key] {
        print("🔥 RANGE CACHE UPDATER: insertion-first node=\(key) deltas=\(nodeDeltas.map{ String(describing: $0.type) })")
        try updateNodeInRangeCache(&rangeCache, nodeKey: key, deltas: nodeDeltas)
        visited.insert(key)
      }
    }

    // Then process any remaining nodes (updates/attributes/deletions)
    for (nodeKey, nodeDeltas) in deltasByNode where !visited.contains(nodeKey) {
      print("🔥 RANGE CACHE UPDATER: remaining node=\(nodeKey) deltas=\(nodeDeltas.map{ String(describing: $0.type) })")
      try updateNodeInRangeCache(&rangeCache, nodeKey: nodeKey, deltas: nodeDeltas)
    }
  }

  /// Update a specific node in the range cache
  private func updateNodeInRangeCache(
    _ rangeCache: inout [NodeKey: RangeCacheItem],
    nodeKey: NodeKey,
    deltas: [ReconcilerDelta]
  ) throws {

    guard let currentItem = rangeCache[nodeKey] else {
      // Node might be newly inserted, check if we have insertion data
      let insertionDetails = deltas.compactMap { delta -> (NodeInsertionData, Int)? in
        if case .nodeInsertion(let key, let insertionData, let location) = delta.type, key == nodeKey {
          return (insertionData, location)
        }
        return nil
      }.first

      if let (insertionData, location) = insertionDetails {
        try calculateNewNodeRangeCacheItem(
          &rangeCache,
          nodeKey: nodeKey,
          insertionData: insertionData,
          insertionLocation: location
        )
      } else {
        // This is an error - we're trying to update a node that's not in cache
        // and we don't have insertion data for it
        throw IncrementalUpdateError.nodeNotInCache(nodeKey)
      }
      return
    }

    var updatedItem = currentItem
    var childrenDeltaAccumulator = 0

    // Apply each delta to update the range cache item
    for delta in deltas {
      switch delta.type {
      case .textUpdate(let key, let newText, _):
        if key == nodeKey {
          // Update text length directly to the new text length
          // Note: range.length is the length being replaced, not the total text length
          let old = updatedItem.textLength
          let newLen = newText.lengthAsNSString()
          updatedItem.textLength = newLen
          childrenDeltaAccumulator += (newLen - old)
        }

      case .nodeInsertion(let key, let insertionData, _):
        if key == nodeKey {
          // This is a new node insertion
          updatedItem.preambleLength = insertionData.preamble.length
          let old = updatedItem.textLength + updatedItem.preambleLength + updatedItem.postambleLength + updatedItem.childrenLength
          updatedItem.textLength = insertionData.content.length
          updatedItem.postambleLength = insertionData.postamble.length
          let newTotal = updatedItem.preambleLength + updatedItem.textLength + updatedItem.postambleLength + updatedItem.childrenLength
          childrenDeltaAccumulator += (newTotal - old)
        }

      case .nodeDeletion(let key, _):
        if key == nodeKey {
          // Node is being deleted, remove from cache
          let total = updatedItem.preambleLength + updatedItem.textLength + updatedItem.postambleLength + updatedItem.childrenLength
          childrenDeltaAccumulator -= total
          rangeCache.removeValue(forKey: nodeKey)
          // adjust ancestors then return
          adjustAncestorsChildrenLength(&rangeCache, nodeKey: nodeKey, delta: childrenDeltaAccumulator)
          return
        }

      case .attributeChange(let key, _, _):
        if key == nodeKey {
          // Attribute changes don't affect range cache lengths
          // But might affect special character lengths in some cases
          // For now, we'll recalculate if needed
        }
      }
    }

    rangeCache[nodeKey] = updatedItem
    if childrenDeltaAccumulator != 0 {
      print("🔥 RANGE CACHE UPDATER: bumping ancestors of \(nodeKey) by \(childrenDeltaAccumulator)")
      adjustAncestorsChildrenLength(&rangeCache, nodeKey: nodeKey, delta: childrenDeltaAccumulator)
    }
  }

  /// Calculate new range cache item for a newly inserted node
  private func calculateNewNodeRangeCacheItem(
    _ rangeCache: inout [NodeKey: RangeCacheItem],
    nodeKey: NodeKey,
    insertionData: NodeInsertionData,
    insertionLocation: Int?
  ) throws {

    var newItem = RangeCacheItem()

    // Use insertion data directly for newly inserted nodes
    newItem.preambleLength = insertionData.preamble.length
    newItem.postambleLength = insertionData.postamble.length
    newItem.textLength = insertionData.content.length
    // New nodes start with no calculated children length; if the node is an element
    // and some of its children were inserted earlier in this batch, seed the
    // childrenLength from currently-known children in the cache.
    if let element: ElementNode = getNodeByKey(key: nodeKey) {
      var sum = 0
      for childKey in element.getChildrenKeys() {
        if let child = rangeCache[childKey] {
          sum += child.preambleLength + child.childrenLength + child.textLength + child.postambleLength
        }
      }
      newItem.childrenLength = sum
    } else {
      newItem.childrenLength = 0
    }

    // Assign a stable node index for the Fenwick tree
    newItem.nodeIndex = getOrAssignFenwickIndex(for: nodeKey)
    // Ensure capacity in Fenwick tree for this index
    _ = fenwickTree.ensureCapacity(for: newItem.nodeIndex)

    rangeCache[nodeKey] = newItem

    // Bump ancestors' childrenLength by the full contribution of this node
    let totalContribution = newItem.preambleLength + newItem.childrenLength + newItem.textLength + newItem.postambleLength
    if totalContribution != 0 {
      adjustAncestorsChildrenLength(&rangeCache, nodeKey: nodeKey, delta: totalContribution)
    }
  }

  // MARK: - Helper Methods

  private func groupDeltasByNode(_ deltas: [ReconcilerDelta]) -> [NodeKey: [ReconcilerDelta]] {
    var groups: [NodeKey: [ReconcilerDelta]] = [:]

    for delta in deltas {
      let nodeKey = getNodeKeyFromDelta(delta)
      if groups[nodeKey] == nil {
        groups[nodeKey] = []
      }
      groups[nodeKey]?.append(delta)
    }

    return groups
  }

  private func getNodeKeyFromDelta(_ delta: ReconcilerDelta) -> NodeKey {
    switch delta.type {
    case .textUpdate(let nodeKey, _, _):
      return nodeKey
    case .nodeInsertion(let nodeKey, _, _):
      return nodeKey
    case .nodeDeletion(let nodeKey, _):
      return nodeKey
    case .attributeChange(let nodeKey, _, _):
      return nodeKey
    }
  }


  private func getFenwickIndexForNode(_ nodeKey: NodeKey, rangeCache: [NodeKey: RangeCacheItem]) -> Int? {
    // Get the range cache item for this node
    guard let rangeCacheItem = rangeCache[nodeKey] else { return nil }

    // Return the node's index in the Fenwick tree
    return rangeCacheItem.nodeIndex
  }

  private func getOrAssignFenwickIndex(for nodeKey: NodeKey) -> Int {
    if let idx = editor.fenwickIndexMap[nodeKey] { return idx }
    let idx = editor.nextFenwickIndex
    editor.nextFenwickIndex += 1
    editor.fenwickIndexMap[nodeKey] = idx
    return idx
  }

  // Adjust ancestors' childrenLength incrementally based on delta length
  private func adjustAncestorsChildrenLength(_ rangeCache: inout [NodeKey: RangeCacheItem], nodeKey: NodeKey, delta: Int) {
    guard delta != 0, let node = getNodeByKey(key: nodeKey) else { return }
    let parents = node.getParentKeys()
    for p in parents {
      if var item = rangeCache[p] {
        let before = item.childrenLength
        item.childrenLength = max(0, item.childrenLength + delta)
        let after = item.childrenLength
        print("🔥 RANGE CACHE UPDATER: parent=\(p) childrenLength: \(before) -> \(after) (delta=\(delta))")
        rangeCache[p] = item
      }
    }
  }
}

// MARK: - Error Types

private enum IncrementalUpdateError: Error {
  case nodeNotFound(NodeKey)
  case nodeNotInCache(NodeKey)
  case invalidRangeCache(String)
  case fenwickTreeUpdateFailed(String)
}
