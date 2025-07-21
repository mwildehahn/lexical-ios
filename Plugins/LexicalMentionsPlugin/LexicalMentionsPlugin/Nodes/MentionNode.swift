/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Lexical
import UIKit

extension NodeType {
  static let mention = NodeType(rawValue: "mention")
}

@MainActor
protocol MentionNodeVisitor {
  func visitMentionNode(_ node: MentionNode) throws
}

public class MentionNode: TextNode {
  enum CodingKeys: String, CodingKey {
    case mention
  }

  private var mention: String = ""

  public required init(mention: String, text: String?, key: NodeKey?) {
    super.init(text: text ?? mention, key: key)
    self.mention = mention
  }

  override public class func getType() -> NodeType {
    .mention
  }

  public required init(
    from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil
  ) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try super.init(from: decoder, depth: depth, index: index, parentIndex: parentIndex)
    self.mention = try container.decode(String.self, forKey: .mention)
  }

  required init(text: String, key: NodeKey?) {
    super.init(text: text, key: key)
  }

  public func getMention() -> String {
    let node: MentionNode = getLatest()
    return node.mention
  }

  override public func encode(to encoder: Encoder) throws {
    try super.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.mention, forKey: .mention)
  }

  override public func clone() -> Self {
    Self(mention: mention, text: getText_dangerousPropertyAccess(), key: key)
  }

  override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any]
  {
    var attributeDictionary = super.getAttributedStringAttributes(theme: theme)
    attributeDictionary[.backgroundColor] = UIColor.lightGray
    return attributeDictionary
  }

  override open func accept<Visitor: NodeVisitor>(visitor: Visitor) throws -> Visitor.Result {
    if let visitor = visitor as? MentionNodeVisitor {
      try visitor.visitMentionNode(self)
    }
  }
}

public func createMentionNode(mention: String, text: String) -> TextNode {
  let result = MentionNode(mention: mention, text: text, key: nil)
  do {
    try result.setMode(mode: .segmented).toggleDirectionless()
  } catch {
    // Fail silently. It doesn't matter if a mention node is not segmented
  }
  return result
}
