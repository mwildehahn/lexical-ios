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

    // Update location offsets for all nodes based on cumulative changes
    try updateLocationOffsets(&rangeCache, basedOn: deltas)
  }

  /// Update a specific node in the range cache
  private func updateNodeInRangeCache(
    _ rangeCache: inout [NodeKey: RangeCacheItem],
    nodeKey: NodeKey,
    deltas: [ReconcilerDelta]
  ) throws {

    guard let currentItem = rangeCache[nodeKey] else {
      // Node might be newly inserted, calculate from scratch
      try calculateNewNodeRangeCacheItem(&rangeCache, nodeKey: nodeKey)
      return
    }

    var updatedItem = currentItem

    // Apply each delta to update the range cache item
    for delta in deltas {
      switch delta.type {
      case .textUpdate(let key, let newText, let range):
        if key == nodeKey {
          // Update text length
          let newTextLength = newText.lengthAsNSString()
          let oldTextLength = range.length
          let lengthDelta = newTextLength - oldTextLength
          updatedItem.textLength += lengthDelta
        }

      case .nodeInsertion(let key, let insertionData, _):
        if key == nodeKey {
          // This is a new node insertion
          updatedItem.preambleLength = insertionData.preamble.length
          updatedItem.textLength = insertionData.content.length
          updatedItem.postambleLength = insertionData.postamble.length

          // Include anchor lengths if enabled
          if editor.featureFlags.anchorBasedReconciliation {
            updatedItem.preambleLength += 1 // preamble anchor
            updatedItem.postambleLength += 1 // postamble anchor
          }
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

      case .anchorUpdate(let key, _, _):
        if key == nodeKey {
          // Anchor updates might affect preamble/postamble lengths
          try recalculateAnchorLengths(&updatedItem, nodeKey: nodeKey)
        }
      }
    }

    rangeCache[nodeKey] = updatedItem
  }

  /// Update location offsets for all nodes based on cumulative length changes
  private func updateLocationOffsets(
    _ rangeCache: inout [NodeKey: RangeCacheItem],
    basedOn deltas: [ReconcilerDelta]
  ) throws {

    // Calculate cumulative length changes by location
    let locationChanges = calculateLocationChanges(from: deltas)

    // Update each range cache item's location
    for (nodeKey, var item) in rangeCache {
      let adjustedLocation = calculateAdjustedLocation(
        originalLocation: item.location,
        locationChanges: locationChanges
      )
      item.location = adjustedLocation
      rangeCache[nodeKey] = item
    }
  }

  /// Calculate new range cache item for a newly inserted node
  private func calculateNewNodeRangeCacheItem(
    _ rangeCache: inout [NodeKey: RangeCacheItem],
    nodeKey: NodeKey
  ) throws {

    guard let node = getNodeByKey(key: nodeKey) else {
      throw IncrementalUpdateError.nodeNotFound(nodeKey)
    }

    var newItem = RangeCacheItem()

    // Calculate lengths based on node content
    newItem.preambleLength = node.getPreamble().lengthAsNSString()
    newItem.postambleLength = node.getPostamble().lengthAsNSString()

    if let textNode = node as? TextNode {
      newItem.textLength = textNode.getTextContent().lengthAsNSString()
    } else if let elementNode = node as? ElementNode {
      newItem.childrenLength = calculateChildrenLength(elementNode, rangeCache: rangeCache)
    }

    // Add anchor lengths if enabled
    if editor.featureFlags.anchorBasedReconciliation {
      newItem.preambleLength += 1 // preamble anchor
      newItem.postambleLength += 1 // postamble anchor
    }

    // Calculate location using FenwickTree
    if let fenwickIndex = getFenwickIndexForNode(nodeKey) {
      newItem.location = fenwickTree.query(index: fenwickIndex)
    }

    rangeCache[nodeKey] = newItem
  }

  /// Recalculate anchor-related lengths in a range cache item
  private func recalculateAnchorLengths(
    _ item: inout RangeCacheItem,
    nodeKey: NodeKey
  ) throws {

    guard editor.featureFlags.anchorBasedReconciliation else { return }

    // Reset special character lengths to account for anchors
    item.preambleSpecialCharacterLength = 1 // for anchor
    // Note: Postamble special characters would be handled similarly if needed
  }

  /// Calculate children length for an element node
  private func calculateChildrenLength(
    _ elementNode: ElementNode,
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> Int {

    var totalLength = 0

    for child in elementNode.getChildren() {
      if let childItem = rangeCache[child.key] {
        totalLength += childItem.range.length
      } else {
        // Child not in cache yet, calculate its length
        totalLength += calculateNodeLength(child)
      }
    }

    return totalLength
  }

  /// Calculate the total length of a node
  private func calculateNodeLength(_ node: Node) -> Int {
    var length = node.getPreamble().lengthAsNSString()
    length += node.getPostamble().lengthAsNSString()

    if let textNode = node as? TextNode {
      length += textNode.getTextContent().lengthAsNSString()
    } else if let elementNode = node as? ElementNode {
      for child in elementNode.getChildren() {
        length += calculateNodeLength(child)
      }
    }

    // Add anchor lengths if enabled
    if editor.featureFlags.anchorBasedReconciliation {
      length += 2 // preamble + postamble anchors
    }

    return length
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
    case .anchorUpdate(let nodeKey, _, _):
      return nodeKey
    }
  }

  private func calculateLocationChanges(from deltas: [ReconcilerDelta]) -> [(location: Int, lengthDelta: Int)] {
    var changes: [(location: Int, lengthDelta: Int)] = []

    for delta in deltas {
      switch delta.type {
      case .textUpdate(_, let newText, let range):
        let lengthDelta = newText.lengthAsNSString() - range.length
        if lengthDelta != 0 {
          changes.append((location: range.location, lengthDelta: lengthDelta))
        }

      case .nodeInsertion(_, let insertionData, let location):
        let totalLength = insertionData.preamble.length + insertionData.content.length + insertionData.postamble.length
        var insertionLength = totalLength

        // Add anchor lengths if enabled
        if editor.featureFlags.anchorBasedReconciliation {
          insertionLength += 2 // preamble + postamble anchors
        }

        changes.append((location: location, lengthDelta: insertionLength))

      case .nodeDeletion(_, let range):
        changes.append((location: range.location, lengthDelta: -range.length))

      case .attributeChange, .anchorUpdate:
        // These don't change text length
        break
      }
    }

    // Sort by location (reverse order for correct offset calculation)
    return changes.sorted { $0.location > $1.location }
  }

  private func calculateAdjustedLocation(
    originalLocation: Int,
    locationChanges: [(location: Int, lengthDelta: Int)]
  ) -> Int {

    var adjustedLocation = originalLocation

    for change in locationChanges {
      if change.location <= originalLocation {
        adjustedLocation += change.lengthDelta
      }
    }

    return max(0, adjustedLocation)
  }

  private func getFenwickIndexForNode(_ nodeKey: NodeKey) -> Int? {
    // TODO: Implement mapping from NodeKey to FenwickTree index
    // This would depend on how nodes are indexed in the FenwickTree
    return nil
  }
}

// MARK: - Error Types

private enum IncrementalUpdateError: Error {
  case nodeNotFound(NodeKey)
  case invalidRangeCache(String)
  case fenwickTreeUpdateFailed(String)
}