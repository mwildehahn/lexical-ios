/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Testing
@testable import Lexical

struct NodeOffsetIndexTests {

  // MARK: - Node Registration

  @Test
  func initialization() {
    let index = NodeOffsetIndex(capacity: 100)

    #expect(index.getDirtyNodes().count == 0, "Should start with no dirty nodes")
    #expect(index.getNodePosition(key: "nonexistent") == nil, "Should return nil for non-registered node")
  }

  @Test
  func registerSingleNode() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)

    #expect(index.getNodePosition(key: "node1") == 0, "First node should be at position 0")
    #expect(index.getNodeRange(key: "node1") == NSRange(location: 0, length: 100))
  }

  @Test
  func registerMultipleNodes() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    #expect(index.getNodePosition(key: "node1") == 0)
    #expect(index.getNodePosition(key: "node2") == 100)
    #expect(index.getNodePosition(key: "node3") == 150)

    #expect(index.getNodeRange(key: "node1") == NSRange(location: 0, length: 100))
    #expect(index.getNodeRange(key: "node2") == NSRange(location: 100, length: 50))
    #expect(index.getNodeRange(key: "node3") == NSRange(location: 150, length: 75))
  }

  @Test
  func reRegisterExistingNode() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)

    // Re-register node1 with different length
    index.registerNode(key: "node1", length: 150)

    #expect(index.getNodePosition(key: "node1") == 0, "Position should remain the same")
    #expect(index.getNodeRange(key: "node1")?.length == 150, "Length should be updated")
    #expect(index.getNodePosition(key: "node2") == 150, "Following node position should be updated")
  }

  // MARK: - Position Tracking and Updates

  @Test
  func updateNodeLength() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    // Increase node2's length
    index.updateNodeLength(key: "node2", newLength: 80)

    #expect(index.getNodePosition(key: "node1") == 0, "node1 position unchanged")
    #expect(index.getNodePosition(key: "node2") == 100, "node2 position unchanged")
    #expect(index.getNodePosition(key: "node3") == 180, "node3 position should shift by 30")
  }

  @Test
  func updateNodeLengthDecrease() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    // Decrease node1's length
    index.updateNodeLength(key: "node1", newLength: 60)

    #expect(index.getNodePosition(key: "node1") == 0)
    #expect(index.getNodePosition(key: "node2") == 60, "node2 should shift left by 40")
    #expect(index.getNodePosition(key: "node3") == 110, "node3 should shift left by 40")
  }

  @Test
  func updateNonExistentNode() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)

    // Should not crash when updating non-existent node
    index.updateNodeLength(key: "nonexistent", newLength: 50)

    #expect(index.getNodePosition(key: "node1") == 0, "Existing node unaffected")
  }

  @Test
  func findNodeAtPosition() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    // Test finding nodes at various positions
    #expect(index.findNodeAt(position: 0) == "node1", "Start of node1")
    #expect(index.findNodeAt(position: 50) == "node1", "Middle of node1")
    #expect(index.findNodeAt(position: 99) == "node1", "End of node1")
    #expect(index.findNodeAt(position: 100) == "node2", "Start of node2")
    #expect(index.findNodeAt(position: 125) == "node2", "Middle of node2")
    #expect(index.findNodeAt(position: 149) == "node2", "End of node2")
    #expect(index.findNodeAt(position: 150) == "node3", "Start of node3")
    #expect(index.findNodeAt(position: 200) == "node3", "Middle of node3")
    #expect(index.findNodeAt(position: 224) == "node3", "End of node3")

    // Out of bounds
    #expect(index.findNodeAt(position: 225) == nil, "Beyond last node")
    #expect(index.findNodeAt(position: 1000) == nil, "Far beyond")
  }

  @Test
  func getNodesInOrder() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    let nodes = index.getNodesInOrder()

    #expect(nodes.count == 3)
    #expect(nodes[0].key == "node1")
    #expect(nodes[0].range == NSRange(location: 0, length: 100))
    #expect(nodes[1].key == "node2")
    #expect(nodes[1].range == NSRange(location: 100, length: 50))
    #expect(nodes[2].key == "node3")
    #expect(nodes[2].range == NSRange(location: 150, length: 75))
  }

  // MARK: - Dirty Node Management

  @Test
  func markDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    #expect(index.getDirtyNodes().count == 0, "No dirty nodes initially")

    index.markDirty(key: "node2")
    let dirtyNodes = index.getDirtyNodes()
    #expect(dirtyNodes.count == 1)
    #expect(dirtyNodes.contains("node2"))
  }

  @Test
  func markMultipleDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    index.markDirty(key: "node1")
    index.markDirty(key: "node3")

    let dirtyNodes = index.getDirtyNodes()
    #expect(dirtyNodes.count == 2)
    #expect(dirtyNodes.contains("node1"))
    #expect(dirtyNodes.contains("node3"))
    #expect(!dirtyNodes.contains("node2"))
  }

  @Test
  func clearDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)

    index.markDirty(key: "node1")
    index.markDirty(key: "node2")
    #expect(index.getDirtyNodes().count == 2)

    index.clearDirty(key: "node1")
    let dirtyNodes = index.getDirtyNodes()
    #expect(dirtyNodes.count == 1)
    #expect(!dirtyNodes.contains("node1"))
    #expect(dirtyNodes.contains("node2"))
  }

  @Test
  func clearAllDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    index.markDirty(key: "node1")
    index.markDirty(key: "node2")
    index.markDirty(key: "node3")
    #expect(index.getDirtyNodes().count == 3)

    index.clearAllDirty()
    #expect(index.getDirtyNodes().count == 0, "All dirty flags should be cleared")
  }

  @Test
  func markNonExistentNodeDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)

    // Should not crash
    index.markDirty(key: "nonexistent")
    index.clearDirty(key: "nonexistent")

    #expect(index.getDirtyNodes().count == 0)
  }

  // MARK: - Node Removal

  @Test
  func removeNode() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    index.removeNode(key: "node2")

    // node2 should have 0 length
    #expect(index.getNodeRange(key: "node2")?.length == 0)

    // node3 position should adjust
    #expect(index.getNodePosition(key: "node3") == 100, "node3 should move to where node2 was")

    // getNodesInOrder should skip removed nodes
    let nodes = index.getNodesInOrder()
    #expect(nodes.count == 2, "Only non-removed nodes in order")
    #expect(nodes[0].key == "node1")
    #expect(nodes[1].key == "node3")
  }

  @Test
  func removeNonExistentNode() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)

    // Should not crash
    index.removeNode(key: "nonexistent")

    #expect(index.getNodePosition(key: "node1") == 0)
    #expect(index.getNodeRange(key: "node1")?.length == 100)
  }

  // MARK: - Fast Path Detection

  @Test
  func canUseFastPathSingleDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    index.markDirty(key: "node2")

    let (canUse, dirtyNode) = index.canUseFastPath()
    #expect(canUse, "Should be able to use fast path with single dirty node")
    #expect(dirtyNode == "node2")
  }

  @Test
  func canUseFastPathMultipleDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.registerNode(key: "node3", length: 75)

    index.markDirty(key: "node1")
    index.markDirty(key: "node3")

    let (canUse, dirtyNode) = index.canUseFastPath()
    #expect(!canUse, "Cannot use fast path with multiple dirty nodes")
    #expect(dirtyNode == nil)
  }

  @Test
  func canUseFastPathNoDirty() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)

    let (canUse, dirtyNode) = index.canUseFastPath()
    #expect(!canUse, "Cannot use fast path with no dirty nodes")
    #expect(dirtyNode == nil)
  }

  // MARK: - Reset

  @Test
  func reset() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node2", length: 50)
    index.markDirty(key: "node1")

    index.reset()

    #expect(index.getNodePosition(key: "node1") == nil, "node1 should be gone")
    #expect(index.getNodePosition(key: "node2") == nil, "node2 should be gone")
    #expect(index.getDirtyNodes().count == 0, "No dirty nodes after reset")
    #expect(index.getNodesInOrder().count == 0, "No nodes after reset")
  }

  // MARK: - Performance and Stress Tests

  @Test
  func largeDocumentSimulation() {
    let index = NodeOffsetIndex(capacity: 1000)
    let nodeCount = 500

    // Register many nodes
    for i in 0..<nodeCount {
      let length = 50 + (i % 100)  // Varying lengths
      index.registerNode(key: "node\(i)", length: length)
    }

    // Verify positions are correct
    var expectedPosition = 0
    for i in 0..<nodeCount {
      let length = 50 + (i % 100)
      #expect(index.getNodePosition(key: "node\(i)") == expectedPosition)
      expectedPosition += length
    }

    // Update some nodes
    for i in stride(from: 0, to: nodeCount, by: 10) {
      index.updateNodeLength(key: "node\(i)", newLength: 200)
    }

    // Mark some dirty
    for i in stride(from: 5, to: nodeCount, by: 20) {
      index.markDirty(key: "node\(i)")
    }

    let dirtyCount = index.getDirtyNodes().count
    #expect(dirtyCount == 25, "Should have correct number of dirty nodes")
  }

  @Test(.timeLimit(.minutes(1)))
  func rapidUpdatesPerformance() {
    let index = NodeOffsetIndex(capacity: 100)

    // Setup initial nodes
    for i in 0..<100 {
      index.registerNode(key: "node\(i)", length: 100)
    }

    // Perform many rapid updates
    for _ in 0..<1000 {
      let nodeIndex = Int.random(in: 0..<100)
      let newLength = Int.random(in: 50...200)
      index.updateNodeLength(key: "node\(nodeIndex)", newLength: newLength)
    }

    // Query positions
    for i in 0..<100 {
      _ = index.getNodePosition(key: "node\(i)")
    }
  }

  @Test
  func complexEditingSession() {
    let index = NodeOffsetIndex()

    // Initial document structure
    index.registerNode(key: "title", length: 50)
    index.registerNode(key: "paragraph1", length: 200)
    index.registerNode(key: "paragraph2", length: 150)
    index.registerNode(key: "paragraph3", length: 180)

    // User edits paragraph2
    index.markDirty(key: "paragraph2")
    index.updateNodeLength(key: "paragraph2", newLength: 175)

    #expect(index.getNodePosition(key: "paragraph3") == 50 + 200 + 175)

    // User adds content to paragraph1
    index.markDirty(key: "paragraph1")
    index.updateNodeLength(key: "paragraph1", newLength: 250)

    #expect(index.getNodePosition(key: "paragraph2") == 50 + 250)
    #expect(index.getNodePosition(key: "paragraph3") == 50 + 250 + 175)

    // Clear dirty flags after reconciliation
    index.clearAllDirty()
    #expect(index.getDirtyNodes().count == 0)

    // User deletes content from title
    index.markDirty(key: "title")
    index.updateNodeLength(key: "title", newLength: 30)

    #expect(index.getNodePosition(key: "paragraph1") == 30)
    #expect(index.getNodePosition(key: "paragraph2") == 30 + 250)
    #expect(index.getNodePosition(key: "paragraph3") == 30 + 250 + 175)
  }

  @Test
  func insertionBetweenNodes() {
    let index = NodeOffsetIndex()

    // Initial nodes
    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "node3", length: 75)

    // Insert node2 between them (simulating insertion in document order)
    index.registerNode(key: "node2", length: 50)

    // Note: Our current implementation doesn't handle insertion order
    // Nodes are added in registration order, not document order
    // This is a limitation that might need addressing

    let nodes = index.getNodesInOrder()
    #expect(nodes.count == 3)

    // The actual order depends on implementation
    // Current implementation maintains registration order
  }

  @Test
  func zeroLengthNodes() {
    let index = NodeOffsetIndex()

    index.registerNode(key: "node1", length: 100)
    index.registerNode(key: "empty", length: 0)
    index.registerNode(key: "node2", length: 50)

    #expect(index.getNodePosition(key: "node1") == 0)
    #expect(index.getNodePosition(key: "empty") == 100)
    #expect(index.getNodePosition(key: "node2") == 100, "Empty node shouldn't affect position")

    // Zero-length nodes should be excluded from getNodesInOrder
    let nodes = index.getNodesInOrder()
    #expect(nodes.count == 2, "Should exclude zero-length nodes")
  }

  @Test
  func concurrentModifications() {
    let index = NodeOffsetIndex()

    // Setup initial state
    for i in 0..<20 {
      index.registerNode(key: "node\(i)", length: 100)
    }

    // Simulate concurrent-like modifications (though not truly concurrent)
    // Mark multiple nodes dirty
    index.markDirty(key: "node5")
    index.markDirty(key: "node10")
    index.markDirty(key: "node15")

    // Update their lengths
    index.updateNodeLength(key: "node5", newLength: 150)
    index.updateNodeLength(key: "node10", newLength: 75)
    index.updateNodeLength(key: "node15", newLength: 125)

    // Verify positions are still consistent
    #expect(index.getNodePosition(key: "node5") == 500)
    #expect(index.getNodePosition(key: "node6") == 650)  // 500 + 150
    #expect(index.getNodePosition(key: "node10") == 1050)  // Adjusted for node5 change
    #expect(index.getNodePosition(key: "node11") == 1125)  // Adjusted for both changes
    #expect(index.getNodePosition(key: "node15") == 1525)
    #expect(index.getNodePosition(key: "node16") == 1650)  // All changes applied
  }
}