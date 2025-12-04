/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import LexicalCore

/// Concrete implementation of NodeContext that bridges the Lexical target's
/// global functions and editor context to the protocol defined in LexicalCore.
/// This allows Node.swift (when moved to LexicalCore) to use dependency injection
/// rather than directly calling global functions with UIKit dependencies.
@MainActor
final class NodeContextImpl: NodeContext {

  // MARK: - Node Map Operations

  func getNodeByKey<N: NodeProtocol>(_ key: NodeKey) -> N? {
    guard let editorState = getActiveEditorState(),
          let node = editorState.nodeMap[key] else {
      return nil
    }
    return node as? N
  }

  func setNode(_ node: any NodeProtocol, forKey key: NodeKey) {
    guard let editorState = getActiveEditorState(),
          let concreteNode = node as? Node else {
      return
    }
    editorState.nodeMap[key] = concreteNode
  }

  // MARK: - Key Generation

  func generateKey(
    for node: any NodeProtocol,
    depth: Int?,
    index: Int?,
    parentIndex: Int?
  ) throws -> NodeKey? {
    guard let concreteNode = node as? Node else {
      return nil
    }
    return try Lexical.generateKey(node: concreteNode, depth: depth, index: index, parentIndex: parentIndex)
  }

  // MARK: - Dirty Tracking

  func isNodeDirty(_ key: NodeKey) -> Bool {
    guard let editor = getActiveEditor() else {
      return false
    }
    return editor.dirtyNodes[key] != nil
  }

  func markNodeDirty(_ node: any NodeProtocol, cause: DirtyStatusCause) {
    guard let concreteNode = node as? Node else {
      return
    }
    internallyMarkNodeAsDirty(node: concreteNode, cause: cause)
  }

  func markSiblingsDirty(_ node: any NodeProtocol, status: DirtyStatusCause) {
    guard let concreteNode = node as? Node else {
      return
    }
    internallyMarkSiblingsAsDirty(node: concreteNode, status: status)
  }

  // MARK: - Clone Tracking

  func isInCloneNotNeeded(_ key: NodeKey) -> Bool {
    guard let editor = getActiveEditor() else {
      return false
    }
    return editor.cloneNotNeeded.contains(key)
  }

  func addToCloneNotNeeded(_ key: NodeKey) {
    guard let editor = getActiveEditor() else {
      return
    }
    editor.cloneNotNeeded.insert(key)
  }

  // MARK: - Read-Only State

  func isReadOnlyMode() -> Bool {
    return Lexical.isReadOnlyMode()
  }

  func errorOnReadOnly() throws {
    try Lexical.errorOnReadOnly()
  }

  // MARK: - Selection Operations

  func getSelection(allowInvalidPositions: Bool) throws -> (any BaseSelectionProtocol)? {
    // For now, return nil since the concrete types don't yet conform to protocol types.
    // This will be properly implemented when Node.swift is moved to LexicalCore and
    // the selection types are updated to conform to the Core protocols.
    // The infrastructure is in place for future migration.
    _ = try Lexical.getSelection(allowInvalidPositions: allowInvalidPositions)
    return nil
  }

  func moveSelectionPointToSibling(
    point: any PointProtocol,
    node: any NodeProtocol,
    parent: any ElementNodeProtocol
  ) {
    guard let concretePoint = point as? Point,
          let concreteNode = node as? Node,
          let concreteParent = parent as? ElementNode else {
      return
    }
    Lexical.moveSelectionPointToSibling(point: concretePoint, node: concreteNode, parent: concreteParent)
  }

  func moveSelectionPointToEnd(point: any PointProtocol, node: any NodeProtocol) {
    guard let concretePoint = point as? Point,
          let concreteNode = node as? Node else {
      return
    }
    Lexical.moveSelectionPointToEnd(point: concretePoint, node: concreteNode)
  }

  func maybeMoveChildrenSelectionToParent(parentNode: any NodeProtocol) throws -> (any BaseSelectionProtocol)? {
    // For now, return nil since the concrete types don't yet conform to protocol types.
    // This will be properly implemented when Node.swift is moved to LexicalCore.
    guard let concreteNode = parentNode as? Node else {
      return nil
    }
    _ = try Lexical.maybeMoveChildrenSelectionToParent(parentNode: concreteNode)
    return nil
  }

  func updateElementSelectionOnCreateDeleteNode(
    selection: any RangeSelectionProtocol,
    parentNode: any NodeProtocol,
    nodeOffset: Int,
    times: Int
  ) throws {
    guard let concreteSelection = selection as? RangeSelection,
          let concreteNode = parentNode as? Node else {
      return
    }
    try Lexical.updateElementSelectionOnCreateDeleteNode(
      selection: concreteSelection,
      parentNode: concreteNode,
      nodeOffset: nodeOffset,
      times: times
    )
  }

  func removeFromParent(node: any NodeProtocol) throws {
    guard let concreteNode = node as? Node else {
      return
    }
    try Lexical.removeFromParent(node: concreteNode)
  }
}

// MARK: - Shared Instance

@MainActor
private var sharedNodeContext: NodeContextImpl?

@MainActor
func getSharedNodeContext() -> NodeContextImpl {
  if let existing = sharedNodeContext {
    return existing
  }
  let context = NodeContextImpl()
  sharedNodeContext = context
  return context
}
