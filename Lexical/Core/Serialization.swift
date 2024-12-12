/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - Datatypes
enum PartialCodingKeys: String, CodingKey {
  case type
}

public struct SerializedEditorState: Codable {
  enum RootCodingKeys: String, CodingKey {
    case root
    case version
  }

  public var rootNode: RootNode?
  public var version: Int

  public init(rootNode: RootNode, version: Int = 1) {
    self.rootNode = rootNode
    self.version = version
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: RootCodingKeys.self)
    self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    self.rootNode = try container.decode(RootNode.self, forKey: .root)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: RootCodingKeys.self)
    // Only encode version if it's not the default
    if version != 1 {
      try container.encode(version, forKey: .version)
    }

    try container.encode(rootNode, forKey: .root)
  }
}

public struct SerializedNodeArray: Decodable {
  enum PartialCodingKeys: String, CodingKey {
    case type
  }

  public var nodeArray: [Node]

  public init(nodeArray: [Node]) {
    self.nodeArray = nodeArray
  }

  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var nodeArray = [Node]()

    self.nodeArray = nodeArray

    guard let editor = getActiveEditor() else { return }

    let deserializationMap = editor.registeredNodes

    while !container.isAtEnd {
      var containerCopy = container
      let unprocessedContainer = try container.nestedContainer(keyedBy: PartialCodingKeys.self)
      let type = try NodeType(rawValue: unprocessedContainer.decode(String.self, forKey: .type))
      let klass = deserializationMap[type] ?? UnknownNode.self

      do {
        let decoder = try containerCopy.superDecoder()
        let decodedNode = try klass.init(from: decoder)
        nodeArray.append(decodedNode)
      } catch {
        print(error)
      }
    }

    self.nodeArray = nodeArray
  }
}

public typealias DeserializationConstructor = (Decoder) throws -> Node
typealias DeserializationMapping = [NodeType: DeserializationConstructor]

// MARK: - Utilities

// NB: We are assuming JSON serialization here initially
let sharedDecoder = JSONDecoder()

let defaultDeserializationMapping: DeserializationMapping = [
  NodeType.root: { decoder in try RootNode(from: decoder) },
  NodeType.text: { decoder in try TextNode(from: decoder) },
  NodeType.element: { decoder in try ElementNode(from: decoder) },
  NodeType.heading: { decoder in try HeadingNode(from: decoder) },
  NodeType.paragraph: { decoder in try ParagraphNode(from: decoder) },
  NodeType.quote: { decoder in try QuoteNode(from: decoder) },
]

func makeDeserializationMap() -> DeserializationMapping {
  return defaultDeserializationMapping
}
