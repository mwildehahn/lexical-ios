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
    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 RANGE CACHE UPDATER: applying deltas for \(deltasByNode.keys.count) nodes")
      print("🔥 RANGE CACHE UPDATER: cache keys before=\(Array(rangeCache.keys).sorted())")
    }

    // Establish a document-order pass for newly inserted nodes based on their insertion locations
    // Also collect affected parents so we can deterministically recompute childrenLength post-pass.
    // 1) collect insertions with locations
    var insertionOrder: [(NodeKey, Int)] = []
    var insertionMeta: [(NodeKey, Int /*loc*/, Int /*contentLen*/)] = []
    var parentsToRecompute: Set<NodeKey> = []
    for deltas in deltasByNode.values {
      for d in deltas {
        if case let .nodeInsertion(nodeKey: key, insertionData: ins, location: loc) = d.type {
          insertionOrder.append((key, loc))
          insertionMeta.append((key, loc, ins.content.length))
          if let parent = getNodeByKey(key: key)?.getParent() {
            parentsToRecompute.insert(parent.getKey())
          }
        }
      }
    }
    // 2) sort insertions by ascending location to approximate document order in the backing string
    insertionOrder.sort { $0.1 < $1.1 }
    var visited: Set<NodeKey> = []

    // Build fallback assumed text lengths based on insertion locations
    var assumedTextLengths: [NodeKey: Int] = [:]
    do {
      let sorted = insertionMeta.sorted { $0.1 < $1.1 }
      for i in 0..<sorted.count {
        let (k, loc, contentLen) = sorted[i]
        let nextLoc = (i + 1 < sorted.count) ? sorted[i + 1].1 : nil
        if let next = nextLoc {
          assumedTextLengths[k] = max(0, next - loc)
        } else {
          assumedTextLengths[k] = contentLen
        }
      }
    }

    // First, process insertions in string order (assigns stable Fenwick indices in order of appearance)
    for (key, _) in insertionOrder {
      if visited.contains(key) { continue }
      if let nodeDeltas = deltasByNode[key] {
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 RANGE CACHE UPDATER: insertion-first node=\(key) deltas=\(nodeDeltas.map{ String(describing: $0.type) })")
        }
        let createdSet = Set(insertionOrder.map { $0.0 })
        try updateNodeInRangeCache(&rangeCache, nodeKey: key, deltas: nodeDeltas, createdThisBatch: createdSet, assumedTextLengths: assumedTextLengths)
        visited.insert(key)
      }
    }

    // Then process any remaining nodes (updates/attributes/deletions)
    for (nodeKey, nodeDeltas) in deltasByNode where !visited.contains(nodeKey) {
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 RANGE CACHE UPDATER: remaining node=\(nodeKey) deltas=\(nodeDeltas.map{ String(describing: $0.type) })")
      }
      let createdSet = Set(insertionOrder.map { $0.0 })
      try updateNodeInRangeCache(&rangeCache, nodeKey: nodeKey, deltas: nodeDeltas, createdThisBatch: createdSet, assumedTextLengths: assumedTextLengths)
    }

    // Note: do not coerce leaf textLength from editor state here; callers may
    // pass a detached cache snapshot for diagnostic/idempotence checks.

    // Deterministic parent recompute: only when structure changed (insert/delete)
    if !insertionOrder.isEmpty {
      let state = getActiveEditorState() ?? editor.getEditorState()
      // Compute a simple depth to process deepest elements first
      func depth(of key: NodeKey) -> Int {
        var d = 0
        var cur: NodeKey? = key
        while let k = cur, k != kRootNodeKey, let n = state.nodeMap[k] { d += 1; cur = n.parent }
        return d
      }
      // Recompute directly on parents of inserted nodes and their ancestors
      var targets: Set<NodeKey> = parentsToRecompute
      var queue = Array(parentsToRecompute)
      while let k = queue.popLast() {
        if let parent = state.nodeMap[k]?.parent, parent != kRootNodeKey, !targets.contains(parent) {
          targets.insert(parent); queue.append(parent)
        }
      }
      let elementKeys = targets.map { ($0, depth(of: $0)) }.sorted { $0.1 > $1.1 }.map { $0.0 }
      for p in elementKeys {
        guard var parentItem = rangeCache[p], let parentNode = state.nodeMap[p] as? ElementNode else { continue }
        var sum = 0
        for ck in parentNode.getChildrenKeys(fromLatest: false) {
          if var c = rangeCache[ck], let childNode = state.nodeMap[ck] {
            // Refresh pre/post from pending state to capture boundary changes (e.g., paragraph newlines)
            let newPre = childNode.getPreamble().lengthAsNSString()
            let newPost = childNode.getPostamble().lengthAsNSString()
            if c.preambleLength != newPre || c.postambleLength != newPost {
              if editor.featureFlags.diagnostics.verboseLogs {
                print("🔥 RANGE CACHE UPDATER: child pre/post normalize key=\(ck) pre \(c.preambleLength)->\(newPre) post \(c.postambleLength)->\(newPost)")
              }
              c.preambleLength = newPre
              c.postambleLength = newPost
              rangeCache[ck] = c
            }
            sum += c.preambleLength + c.childrenLength + c.textLength + c.postambleLength
          }
        }
        if sum != parentItem.childrenLength {
          parentItem.childrenLength = sum
          rangeCache[p] = parentItem
          if editor.featureFlags.diagnostics.verboseLogs {
            print("🔥 RANGE CACHE UPDATER: parent=\(p) recompute childrenLength=\(sum)")
          }
        }
      }
    }

    // (optional) debug dump of leaf lengths — comment out to keep logs quiet
    // var dump: [String] = []
    // for (k, item) in rangeCache { if let _ = getNodeByKey(key: k) as? TextNode { dump.append("\(k):tx=\(item.textLength)") } }
    // if !dump.isEmpty { print("🔥 RANGE CACHE UPDATER: leaf lengths => \(dump.sorted().joined(separator: ", "))") }
  }

  /// Update a specific node in the range cache
  private func updateNodeInRangeCache(
    _ rangeCache: inout [NodeKey: RangeCacheItem],
    nodeKey: NodeKey,
    deltas: [ReconcilerDelta],
    createdThisBatch: Set<NodeKey> = [],
    assumedTextLengths: [NodeKey: Int] = [:]
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
          insertionLocation: location,
          assumedTextLengths: assumedTextLengths
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
          // Idempotence guard: if this node was created earlier in this batch,
          // skip re-applying insertion lengths here to avoid double counting.
          let inCreated = createdThisBatch.contains(nodeKey)
          print("🔥 RANGE CACHE UPDATER: nodeInsertion key=\(nodeKey) inCreated=\(inCreated) currentItemExists=true contentLen=\(insertionData.content.length)")
          if inCreated {
            // If we already created the cache item earlier in this batch but a subsequent
            // insertion delta carries a more specific (often shorter) leaf content length,
            // treat it as authoritative and adjust downward/upward accordingly.
            let newLen = insertionData.content.length
            let delta = newLen - updatedItem.textLength
            if delta != 0 {
              updatedItem.textLength = newLen
              childrenDeltaAccumulator += delta
            }
            break
          }
          // Otherwise, treat as insertion into an existing cache item (edge case)
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
    insertionLocation: Int?,
    assumedTextLengths: [NodeKey: Int]
  ) throws {

    var newItem = RangeCacheItem()
    newItem.nodeKey = nodeKey

    // Use insertion data directly for newly inserted nodes. For TextNodes, prefer a
    // length inferred from insertion locations (assumedTextLengths) to avoid merged
    // state inflating per-leaf lengths in synthetic updater tests.
    newItem.preambleLength = insertionData.preamble.length
    newItem.postambleLength = insertionData.postamble.length
    // Prefer the actual content length for text nodes on creation to avoid
    // under/over-estimating lengths from inferred insertion gaps.
    newItem.textLength = insertionData.content.length
    newItem.childrenLength = 0
    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 CACHE INSERT: NEW node=\(nodeKey) textLen=\(newItem.textLength) pre=\(newItem.preambleLength) post=\(newItem.postambleLength)")
    }

    // Assign a stable node index for the Fenwick tree
    newItem.nodeIndex = getOrAssignFenwickIndex(for: nodeKey)
    // Ensure capacity in Fenwick tree for this index
    _ = fenwickTree.ensureCapacity(for: newItem.nodeIndex)

    rangeCache[nodeKey] = newItem
    if editor.featureFlags.diagnostics.verboseLogs {
      if let tn = editor.getEditorState().nodeMap[nodeKey] as? TextNode {
        print("🔥 CACHE INSERT TEXT: key=\(nodeKey) text='\(tn.getText_dangerousPropertyAccess())' len=\(tn.getText_dangerousPropertyAccess().lengthAsNSString()) insLen=\(insertionData.content.length)")
      }
    }

    // Bump ancestors' childrenLength by the full contribution of this node
    let totalContribution = newItem.preambleLength + newItem.childrenLength + newItem.textLength + newItem.postambleLength
    if totalContribution != 0 {
      adjustAncestorsChildrenLength(&rangeCache, nodeKey: nodeKey, delta: totalContribution)
    }

    // Post-insert sibling normalization: if this node has a previous sibling element,
    // its postamble may depend on the presence of a next sibling (e.g., paragraph newline).
    // Recompute and propagate any delta so absolute starts remain consistent.
    if let node = getNodeByKey(key: nodeKey),
       let parent = node.getParent(),
       let prevSibling = node.getPreviousSibling() {
      if var prevItem = rangeCache[prevSibling.getKey()] {
        let newPostamble = prevSibling.getPostamble().lengthAsNSString()
        if newPostamble != prevItem.postambleLength {
          let delta = newPostamble - prevItem.postambleLength
          prevItem.postambleLength = newPostamble
          rangeCache[prevSibling.getKey()] = prevItem
          if delta != 0 {
            adjustAncestorsChildrenLength(&rangeCache, nodeKey: prevSibling.getKey(), delta: delta)
          }
          if editor.featureFlags.diagnostics.verboseLogs {
            print("🔥 RANGE CACHE UPDATER: prevSibling postamble normalize key=\(prevSibling.getKey()) Δ=\(delta)")
          }
        }
      }
      _ = parent // silence unused variable warning in some toolchains
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
    guard delta != 0 else { return }
    // Use state maps directly to avoid requiring an active EditorContext (no getLatest())
    let state = getActiveEditorState() ?? editor.getEditorState()
    var currentParentKey = state.nodeMap[nodeKey]?.parent
    while let p = currentParentKey {
      if var item = rangeCache[p] {
        let before = item.childrenLength
        item.childrenLength = max(0, item.childrenLength + delta)
        let after = item.childrenLength
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 RANGE CACHE UPDATER: parent=\(p) childrenLength: \(before) -> \(after) (delta=\(delta))")
        }
        rangeCache[p] = item
      }
      currentParentKey = state.nodeMap[p]?.parent
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
