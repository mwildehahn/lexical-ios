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

    // Process each affected node
    for (nodeKey, nodeDeltas) in deltasByNode {
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

    // Apply each delta to update the range cache item
    for delta in deltas {
      switch delta.type {
      case .textUpdate(let key, let newText, _):
        if key == nodeKey {
          // Update text length directly to the new text length
          // Note: range.length is the length being replaced, not the total text length
          updatedItem.textLength = newText.lengthAsNSString()
        }

      case .nodeInsertion(let key, let insertionData, _):
        if key == nodeKey {
          // This is a new node insertion
          updatedItem.preambleLength = insertionData.preamble.length
          updatedItem.textLength = insertionData.content.length
          updatedItem.postambleLength = insertionData.postamble.length
        }

      case .nodeDeletion(let key, _):
        if key == nodeKey {
          // Node is being deleted, remove from cache
          rangeCache.removeValue(forKey: nodeKey)
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
    newItem.childrenLength = 0 // New nodes start with no calculated children length

    // Assign a node index for the Fenwick tree
    // For now, we'll use a simple mapping based on the insertion order
    // This could be improved with a more sophisticated indexing scheme
    if let fenwickIndex = getFenwickIndexForNode(nodeKey, rangeCache: rangeCache) {
      newItem.nodeIndex = fenwickIndex
    } else {
      // For new nodes, find the next available index
      newItem.nodeIndex = rangeCache.count
    }

    rangeCache[nodeKey] = newItem
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
}

// MARK: - Error Types

private enum IncrementalUpdateError: Error {
  case nodeNotFound(NodeKey)
  case nodeNotInCache(NodeKey)
  case invalidRangeCache(String)
  case fenwickTreeUpdateFailed(String)
}
