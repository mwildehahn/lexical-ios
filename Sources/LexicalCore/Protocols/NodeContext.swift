/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// Note: SelectionType is defined in LexicalCore/CoreTypes.swift

// MARK: - NodeContext Protocol

/// Protocol defining the execution context operations that Node needs.
/// This abstracts away the concrete Editor/EditorState types so that
/// Node can be compiled in LexicalCore without UIKit dependencies.
@MainActor
public protocol NodeContext: AnyObject {
  // MARK: - Node Map Operations

  /// Get a node by its key from the current editor state
  func getNodeByKey<N: NodeProtocol>(_ key: NodeKey) -> N?

  /// Set a node in the current editor state's node map
  func setNode(_ node: any NodeProtocol, forKey key: NodeKey)

  // MARK: - Key Generation

  /// Generate a unique key for a new node
  func generateKey(
    for node: any NodeProtocol,
    depth: Int?,
    index: Int?,
    parentIndex: Int?
  ) throws -> NodeKey?

  // MARK: - Dirty Tracking

  /// Check if a node is dirty in the current update cycle
  func isNodeDirty(_ key: NodeKey) -> Bool

  /// Mark a node as dirty
  func markNodeDirty(_ node: any NodeProtocol, cause: DirtyStatusCause)

  /// Mark a node's siblings as dirty
  func markSiblingsDirty(_ node: any NodeProtocol, status: DirtyStatusCause)

  // MARK: - Clone Tracking

  /// Check if a node key is in the clone-not-needed set
  func isInCloneNotNeeded(_ key: NodeKey) -> Bool

  /// Add a key to the clone-not-needed set
  func addToCloneNotNeeded(_ key: NodeKey)

  // MARK: - Read-Only State

  /// Check if currently in read-only mode
  func isReadOnlyMode() -> Bool

  /// Throw an error if in read-only mode
  func errorOnReadOnly() throws

  // MARK: - Selection Operations

  /// Get the current selection
  func getSelection(allowInvalidPositions: Bool) throws -> (any BaseSelectionProtocol)?

  /// Move selection point to a sibling node
  func moveSelectionPointToSibling(
    point: any PointProtocol,
    node: any NodeProtocol,
    parent: any ElementNodeProtocol
  )

  /// Move selection point to the end of a node
  func moveSelectionPointToEnd(point: any PointProtocol, node: any NodeProtocol)

  /// Maybe move children selection to parent
  func maybeMoveChildrenSelectionToParent(parentNode: any NodeProtocol) throws -> (any BaseSelectionProtocol)?

  /// Update element selection on node create/delete
  func updateElementSelectionOnCreateDeleteNode(
    selection: any RangeSelectionProtocol,
    parentNode: any NodeProtocol,
    nodeOffset: Int,
    times: Int
  ) throws

  /// Remove a node from its parent
  func removeFromParent(node: any NodeProtocol) throws
}

// MARK: - Node Protocol

/// Protocol that all Node types conform to.
/// This allows LexicalCore to reference nodes without depending on the concrete Node class.
@MainActor
public protocol NodeProtocol: AnyObject, Hashable {
  var key: NodeKey { get set }
  var parent: NodeKey? { get set }
  var version: Int { get set }
  var type: NodeType { get }

  func getLatest() -> Self
  func clone() -> Self
  func isInline() -> Bool
  func getPreamble() -> String
  func getPostamble() -> String
  func getTextPart(fromLatest: Bool) -> String
  func getTextPartSize(fromLatest: Bool) -> Int
  func getTextContent(includeInert: Bool, includeDirectionless: Bool, maxLength: Int?) -> String
  func getTextContentSize(includeInert: Bool, includeDirectionless: Bool) -> Int
  func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any]
  func getBlockLevelAttributes(theme: Theme) -> BlockLevelAttributes?

  // Tree navigation
  func getParent() -> (any ElementNodeProtocol)?
  func getParentOrThrow() throws -> any ElementNodeProtocol
  func getPreviousSibling() -> (any NodeProtocol)?
  func getNextSibling() -> (any NodeProtocol)?
  func getIndexWithinParent() -> Int?
  func isAttached() -> Bool

  // Comparison
  func isSameKey(_ object: (any NodeProtocol)?) -> Bool
  func getKey() -> NodeKey
}

// MARK: - Element Node Protocol

/// Protocol for element nodes (nodes that can have children)
@MainActor
public protocol ElementNodeProtocol: NodeProtocol {
  var children: [NodeKey] { get set }
  var direction: Direction? { get set }

  func getChildrenSize() -> Int
  func getChildrenKeys() -> [NodeKey]
  func getChildAtIndex<T: NodeProtocol>(index: Int) -> T?
  func getFirstChild<T: NodeProtocol>() -> T?
  func getLastChild<T: NodeProtocol>() -> T?
  func getLastDescendant<T: NodeProtocol>() -> T?
  func getChildren() -> [any NodeProtocol]
  func canBeEmpty() -> Bool
  func excludeFromCopy() -> Bool
  func select(anchorOffset: Int?, focusOffset: Int?) throws -> any RangeSelectionProtocol
  func append(_ nodesToAppend: [any NodeProtocol]) throws
}

// MARK: - Text Node Protocol

/// Protocol for text nodes
@MainActor
public protocol TextNodeProtocol: NodeProtocol {
  var format: TextFormat { get set }
  var mode: Mode { get set }

  func getText_dangerousPropertyAccess() -> String
  func setText_dangerousPropertyAccess(_ text: String)
  func isToken() -> Bool
  func isInert() -> Bool
  func isSegmented() -> Bool
  func select(anchorOffset: Int?, focusOffset: Int?) throws -> any RangeSelectionProtocol
}

// MARK: - Decorator Node Protocol

/// Protocol for decorator nodes
@MainActor
public protocol DecoratorNodeProtocol: NodeProtocol {
  func selectStart() throws -> any RangeSelectionProtocol
  func selectEnd() throws -> any RangeSelectionProtocol
}

// MARK: - Root Node Protocol

/// Protocol for the root node
@MainActor
public protocol RootNodeProtocol: ElementNodeProtocol {}

// MARK: - Type Checking Helpers

/// Check if a node is an element node using protocol conformance
@MainActor
public func isElementNode(_ node: (any NodeProtocol)?) -> Bool {
  node is (any ElementNodeProtocol)
}

/// Check if a node is a text node using protocol conformance
@MainActor
public func isTextNode(_ node: (any NodeProtocol)?) -> Bool {
  node is (any TextNodeProtocol)
}

/// Check if a node is the root node using protocol conformance
@MainActor
public func isRootNode(_ node: (any NodeProtocol)?) -> Bool {
  node is (any RootNodeProtocol)
}

/// Check if a node is a decorator node using protocol conformance
@MainActor
public func isDecoratorNode(_ node: (any NodeProtocol)?) -> Bool {
  node is (any DecoratorNodeProtocol)
}

// MARK: - Selection Protocols

/// Protocol for base selection
@MainActor
public protocol BaseSelectionProtocol: AnyObject {
  var dirty: Bool { get set }

  func clone() -> any BaseSelectionProtocol
  func getNodes() throws -> [any NodeProtocol]
  func isSelection(_ selection: any BaseSelectionProtocol) -> Bool
}

/// Protocol for range selection
@MainActor
public protocol RangeSelectionProtocol: BaseSelectionProtocol {
  var anchor: any PointProtocol { get }
  var focus: any PointProtocol { get }

  func isBackward() throws -> Bool
  func getCharacterOffsets(selection: any RangeSelectionProtocol) -> (Int, Int)
}

/// Protocol for selection points
@MainActor
public protocol PointProtocol: AnyObject {
  var key: NodeKey { get set }
  var offset: Int { get set }
  var type: SelectionType { get set }

  func getNode() throws -> any NodeProtocol
  func getCharacterOffset() -> Int
  func isBefore(point: any PointProtocol) throws -> Bool
  func updatePoint(key: NodeKey, offset: Int, type: SelectionType)
}

// Note: TextFormat is defined in LexicalCore/TextFormat.swift

// MARK: - NodeContext Access

/// Global accessor for the current NodeContext.
/// This is set by the Lexical target when entering an update/read block.
@MainActor
public enum NodeContextProvider {
  private static var _current: (any NodeContext)?

  public static var current: (any NodeContext)? {
    get { _current }
    set { _current = newValue }
  }

  /// Execute a closure with a specific NodeContext
  public static func withContext<T>(_ context: (any NodeContext)?, operation: () throws -> T) rethrows -> T {
    let previous = _current
    _current = context
    defer { _current = previous }
    return try operation()
  }
}

// Note: Convenience functions like getNodeByKey(), isReadOnlyMode(), errorOnReadOnly(), getSelection()
// are defined in the Lexical target (Updates.swift, Utils.swift, SelectionUtils.swift).
// When Node.swift is moved to LexicalCore, these functions will be provided via the NodeContext protocol.
