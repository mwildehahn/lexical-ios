/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

internal let kRootNodeKey = "root"

public typealias EditorStateMigrationHandler = @Sendable (EditorState) throws -> Void

public struct EditorStateMigration: Sendable {
  let fromVersion: Int
  let toVersion: Int
  let handler: EditorStateMigrationHandler

  public init(fromVersion: Int, toVersion: Int, handler: @escaping EditorStateMigrationHandler) {
    self.fromVersion = fromVersion
    self.toVersion = toVersion
    self.handler = handler
  }
}

/// The Lexical data model.
///
/// An EditorState contains nodes and a selection. It can be serialized to and from JSON, and passed around between Lexical ``Editor`` instances.
@MainActor
public class EditorState: NSObject {

  internal var nodeMap: [NodeKey: Node] = [:]
  public var selection: BaseSelection?
  public var version: Int = 1

  override init() {
    let rootNode = RootNode()
    nodeMap[kRootNodeKey] = rootNode
  }

  convenience init(version: Int = 1) {
    self.init()
    self.version = version
  }

  init(_ editorState: EditorState) {
    nodeMap = editorState.nodeMap
    version = editorState.version
  }

  /// Returns the root node for this EditorState, if one is set.
  public func getRootNode() -> RootNode? {
    return nodeMap[kRootNodeKey] as? RootNode
  }

  /// Accessor function for the node map (i.e. the dictionary of key -> node object).
  public func getNodeMap() -> [NodeKey: Node] {
    return nodeMap
  }

  /// Allows you to interrogate the contents of this EditorState without having to attach it to an Editor.
  public func read<V>(closure: () throws -> V) throws -> V {
    return try beginRead(activeEditorState: self, closure: closure)
  }

  private func beginRead<V>(
    activeEditorState: EditorState,
    closure: () throws -> V
  ) throws -> V {
    var result: V?
    try runWithStateLexicalScopeProperties(
      activeEditor: nil, activeEditorState: activeEditorState, readOnlyMode: true,
      editorUpdateReason: nil
    ) {
      result = try closure()
    }
    guard let result else {
      throw LexicalError.internal("No result returned from expected closure")
    }
    return result
  }

  /// Copies this EditorState, optionally adding a new selection while doing so.
  public func clone(selection: RangeSelection?) -> EditorState {
    let editorState = EditorState(self)

    if let selection {
      editorState.selection = selection.clone() as? RangeSelection
    } else {
      editorState.selection = self.selection?.clone() as? RangeSelection
    }

    return editorState
  }

  public static func == (lhs: EditorState, rhs: EditorState) -> Bool {
    let isEqual = lhs.hasSameState(as: rhs)

    let selectionEqual: Bool
    if let lhsSelection = lhs.selection, let rhsSelection = rhs.selection {
      selectionEqual = lhsSelection.isSelection(rhsSelection)
    } else if lhs.selection == nil && rhs.selection == nil {
      selectionEqual = true
    } else {
      selectionEqual = false
    }

    return lhs.version == rhs.version && isEqual && selectionEqual
  }

  public func hasSameState(as rhs: EditorState) -> Bool {
    if nodeMap.count != rhs.nodeMap.count {
      return false
    }

    var isEqual = true
    for element in rhs.nodeMap {
      isEqual = nodeMap[element.key] == element.value
      if !isEqual {
        break
      }
    }

    return isEqual
  }

  static public func empty(version: Int = 1) -> EditorState {
    let editorState = EditorState()
    editorState.version = version
    return editorState
  }

  /**
   Returns a JSON string representing this EditorState.
  
   The JSON string is designed to be interoperable with Lexical JavaScript (subject to the individual node classes using matching keys).
   */
  public func toJSON(outputFormatting: JSONEncoder.OutputFormatting = []) throws -> String {
    let string: String? = try read {
      guard let rootNode = getRootNode() else {
        throw LexicalError.invariantViolation("Could not get RootNode")
      }
      let persistedEditorState = SerializedEditorState(rootNode: rootNode, version: version)
      let encoder = JSONEncoder()
      encoder.outputFormatting = outputFormatting
      let encodedData = try encoder.encode(persistedEditorState)
      guard let jsonString = String(data: encodedData, encoding: .utf8) else { return "" }
      return jsonString
    }
    if let string {
      return string
    }
    throw LexicalError.invariantViolation("Expected string")
  }

  /**
   Creates a new EditorState from a JSON string.
  
   This function requires an ``Editor`` to be passed in, so that the list of registered node classes and plugins can be used when deserializing the JSON.
   The newly created EditorState is not added to the Editor; it is expected that the API consumer will call ``Editor/setEditorState(_:)`` if that is desired.
   */
  public static func fromJSON(json: String, editor: Editor, migrations: [EditorStateMigration] = [])
    throws -> EditorState
  {
    guard let stateData = json.data(using: .utf8) else {
      throw LexicalError.internal("Could not generate data from string JSON state")
    }

    return try editor.parseEditorState(json: stateData, migrations: migrations)
  }
}
