/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit

/// A base class that combines DecoratorBlockNode's custom view rendering
/// with ElementNode's child management capabilities
open class DecoratorContainerNode: DecoratorBlockNode {

  // Child management properties (similar to ElementNode)
  var children: [NodeKey] = []
  var direction: Direction?

  enum ContainerCodingKeys: String, CodingKey {
    case children
    case direction
  }

  override public init() {
    super.init()
  }

  public required init(_ key: NodeKey?) {
    super.init(key)
  }

  public required init(
    from decoder: Decoder,
    depth: Int? = nil,
    index: Int? = nil,
    parentIndex: Int? = nil
  ) throws {
    let container = try decoder.container(keyedBy: ContainerCodingKeys.self)
    self.children = []
    var childNodes: [Node] = []

    guard let editor = getActiveEditor() else {
      throw LexicalError.internal("Could not get active editor")
    }

    do {
      let deserializationMap = editor.registeredNodes
      var childrenUnkeyedContainer = try container.nestedUnkeyedContainer(forKey: .children)
      var childIndex = 0

      while !childrenUnkeyedContainer.isAtEnd {
        var containerCopy = childrenUnkeyedContainer
        let unprocessedContainer = try childrenUnkeyedContainer.nestedContainer(
          keyedBy: PartialCodingKeys.self)
        let type = try NodeType(rawValue: unprocessedContainer.decode(String.self, forKey: .type))

        let klass = deserializationMap[type] ?? UnknownNode.self

        do {
          let decoder = try containerCopy.superDecoder()
          let childDepth = depth != nil ? (depth ?? 0) + 1 : nil
          let decodedNode = try klass.init(
            from: decoder, depth: childDepth, index: childIndex, parentIndex: index)
          childNodes.append(decodedNode)
          self.children.append(decodedNode.key)
        } catch {
          print(error)
        }

        childIndex += 1
      }
    } catch {
      print(error)
    }

    self.direction = try container.decodeIfPresent(Direction.self, forKey: .direction)
    try super.init(from: decoder, depth: depth, index: index, parentIndex: parentIndex)

    for node in childNodes {
      node.parent = self.key
    }
  }

  override public func encode(to encoder: Encoder) throws {
    try super.encode(to: encoder)
    var container = encoder.container(keyedBy: ContainerCodingKeys.self)
    try container.encode(self.getChildren(), forKey: .children)
    try container.encode(self.direction, forKey: .direction)
  }

  // MARK: - Direction

  open func getDirection() -> Direction? {
    return direction
  }

  @discardableResult
  open func setDirection(direction: Direction?) throws -> DecoratorContainerNode {
    try errorOnReadOnly()
    let node = try getWritable() as DecoratorContainerNode
    node.direction = direction
    return node
  }

  // MARK: - Child Management Methods (from ElementNode)

  public func getFirstChild<T: Node>() -> T? {
    let children = getLatest().children

    if children.count == 0 {
      return nil
    }

    guard let firstChild = children.first else { return nil }

    return getNodeByKey(key: firstChild)
  }

  public func getLastChild() -> Node? {
    let children = getLatest().children

    if children.count == 0 {
      return nil
    }

    return getNodeByKey(key: children[children.count - 1])
  }

  public func getChildrenSize() -> Int {
    let latest = getLatest() as DecoratorContainerNode
    return latest.children.count
  }

  public func getChildAtIndex(index: Int) -> Node? {
    let children = self.children
    if index >= 0 && index < children.count {
      let key = children[index]
      return getNodeByKey(key: key)
    } else {
      return nil
    }
  }

  public func getDescendantByIndex(index: Int) -> Node? {
    let children = getChildren()

    if index >= children.count {
      if let resolvedNode = children.last as? ElementNode,
        let lastDescendant = resolvedNode.getLastDescendant()
      {
        return lastDescendant
      }

      return children.last
    }

    if let node = children[index] as? ElementNode, let firstDescendant = node.getFirstDescendant() {
      return firstDescendant
    }

    return children[index]
  }

  public func getFirstDescendant() -> Node? {
    var node: Node? = self.getFirstChild()
    while let unwrappedNode = node {
      if let child = (unwrappedNode as? ElementNode)?.getFirstChild() {
        node = child
      } else {
        break
      }
    }

    return node
  }

  public func getLastDescendant() -> Node? {
    var node = self.getLastChild()
    while let unwrappedNode = node {
      if let child = (unwrappedNode as? ElementNode)?.getLastChild() {
        node = child
      } else {
        break
      }
    }

    return node
  }

  public func getChildren() -> [Node] {
    return getLatest().children.compactMap { nodeKey in
      getNodeByKey(key: nodeKey)
    }
  }

  public func getChildrenKeys(fromLatest: Bool = true) -> [NodeKey] {
    if fromLatest {
      let latest: DecoratorContainerNode = getLatest()
      return latest.children
    }

    return children
  }

  @discardableResult
  func clear() throws -> DecoratorContainerNode {
    try errorOnReadOnly()

    let writableSelf = try getWritable()

    let children = writableSelf.getChildren()
    _ = try children.map({ try $0.remove() })

    return writableSelf
  }

  // MARK: - State Methods

  open func isEmpty() -> Bool {
    return getChildrenSize() == 0
  }
}
