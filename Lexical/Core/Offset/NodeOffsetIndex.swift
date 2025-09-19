/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Tracks node positions using a Fenwick tree for O(log n) offset updates
/// Replaces the anchor-based approach with efficient position tracking
internal final class NodeOffsetIndex {
  private struct NodeEntry {
    let key: NodeKey
    var length: Int
    var isDirty: Bool
  }

  private var nodes: [NodeEntry] = []
  private var nodeKeyToIndex: [NodeKey: Int] = [:]
  private let fenwickTree: FenwickTree

  init(capacity: Int = 1000) {
    self.fenwickTree = FenwickTree(capacity: capacity)
  }

  /// Register a node with its initial length
  func registerNode(key: NodeKey, length: Int) {
    if let existingIndex = nodeKeyToIndex[key] {
      // Update existing node
      updateNodeLength(key: key, newLength: length)
    } else {
      // Add new node
      let index = nodes.count
      nodes.append(NodeEntry(key: key, length: length, isDirty: false))
      nodeKeyToIndex[key] = index
      fenwickTree.set(at: index, value: length)
    }
  }

  /// Update a node's length (e.g., after text edit)
  /// Time complexity: O(log n)
  func updateNodeLength(key: NodeKey, newLength: Int) {
    guard let index = nodeKeyToIndex[key] else { return }

    let oldLength = nodes[index].length
    let delta = newLength - oldLength

    nodes[index].length = newLength
    fenwickTree.update(at: index, delta: delta)
  }

  /// Mark a node as dirty (needs reconciliation)
  func markDirty(key: NodeKey) {
    guard let index = nodeKeyToIndex[key] else { return }
    nodes[index].isDirty = true
  }

  /// Clear dirty flag for a node
  func clearDirty(key: NodeKey) {
    guard let index = nodeKeyToIndex[key] else { return }
    nodes[index].isDirty = false
  }

  /// Get the absolute text position of a node
  /// Time complexity: O(log n)
  func getNodePosition(key: NodeKey) -> Int? {
    guard let index = nodeKeyToIndex[key] else { return nil }

    if index == 0 {
      return 0
    }

    // Sum of all node lengths before this one
    return fenwickTree.query(upTo: index - 1)
  }

  /// Get the range (position and length) of a node
  func getNodeRange(key: NodeKey) -> NSRange? {
    guard let index = nodeKeyToIndex[key],
          let position = getNodePosition(key: key) else { return nil }

    return NSRange(location: position, length: nodes[index].length)
  }

  /// Find the node at a given text position
  /// Time complexity: O(n) - could be optimized with binary search
  func findNodeAt(position: Int) -> NodeKey? {
    var currentPos = 0

    for node in nodes {
      let nextPos = currentPos + node.length
      if position >= currentPos && position < nextPos {
        return node.key
      }
      currentPos = nextPos
    }

    return nil
  }

  /// Get all dirty nodes that need reconciliation
  func getDirtyNodes() -> Set<NodeKey> {
    var dirtyKeys = Set<NodeKey>()
    for node in nodes where node.isDirty {
      dirtyKeys.insert(node.key)
    }
    return dirtyKeys
  }

  /// Clear all dirty flags
  func clearAllDirty() {
    for i in nodes.indices {
      nodes[i].isDirty = false
    }
  }

  /// Reset the entire index
  func reset() {
    nodes.removeAll()
    nodeKeyToIndex.removeAll()
    fenwickTree.reset()
  }

  /// Remove a node from the index
  func removeNode(key: NodeKey) {
    guard let index = nodeKeyToIndex[key] else { return }

    // Set its length to 0 (effectively removing it from position calculations)
    fenwickTree.set(at: index, value: 0)
    nodes[index].length = 0

    // Note: We don't actually remove from arrays to preserve indices
    // A more sophisticated implementation could handle compaction
  }

  /// Get nodes in document order with their positions
  func getNodesInOrder() -> [(key: NodeKey, range: NSRange)] {
    var result: [(key: NodeKey, range: NSRange)] = []
    var currentPos = 0

    for node in nodes where node.length > 0 {
      let range = NSRange(location: currentPos, length: node.length)
      result.append((key: node.key, range: range))
      currentPos += node.length
    }

    return result
  }

  /// Check if we can use fast path for a single dirty node
  func canUseFastPath() -> (Bool, NodeKey?) {
    let dirtyNodes = getDirtyNodes()
    if dirtyNodes.count == 1 {
      return (true, dirtyNodes.first)
    }
    return (false, nil)
  }
}