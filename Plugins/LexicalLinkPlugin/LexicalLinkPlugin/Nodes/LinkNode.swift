/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

extension NodeType {
  public static let link = NodeType(rawValue: "link")
}

public protocol LinkNodeVisitor {
  func visitLinkNode(_ node: LinkNode) throws
}

open class LinkNode: ElementNode {
  enum CodingKeys: String, CodingKey {
    case url
  }

  public var url: String = ""

  override public init() {
    super.init()
  }

  public required init(url: String, key: NodeKey?) {
    super.init(key)
    self.url = url
  }

  public required convenience init(from decoder: Decoder) throws {
    try self.init(from: decoder, depth: nil, index: nil)
  }

  public required init(from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try super.init(from: decoder, depth: depth, index: index, parentIndex: parentIndex)

    self.url = try container.decode(String.self, forKey: .url)
  }

  override open class func getType() -> NodeType {
    return .link
  }

  override open func encode(to encoder: Encoder) throws {
    try super.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.url, forKey: .url)
  }

  public func getURL() -> String {
    let latest: LinkNode = getLatest()
    return latest.url
  }

  public func setURL(_ url: String) throws {
    try errorOnReadOnly()
    try getWritable().url = url
  }

  override public func canInsertTextBefore() -> Bool {
    return false
  }

  override public func canInsertTextAfter() -> Bool {
    return false
  }

  override public func canBeEmpty() -> Bool {
    return false
  }

  override public func isInline() -> Bool {
    return true
  }

  override open func clone() -> Self {
    Self(url: url, key: key)
  }

  override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
    if url.isEmpty {
      return [:]
    }

    var attribs: [NSAttributedString.Key: Any] = theme.link ?? [:]
    attribs[.link] = url
    return attribs
  }

  override open func insertNewAfter(selection: RangeSelection?) throws -> RangeSelection.InsertNewAfterResult {
    if let element = try getParentOrThrow().insertNewAfter(selection: selection).element as? ElementNode {
      let linkNode = LinkNode(url: url, key: nil)
      try element.append([linkNode])
      return .init(element: linkNode)
    }

    return .init()
  }

  open override func accept<V>(visitor: V) throws where V : NodeVisitor {
    if let visitor = visitor as? LinkNodeVisitor {
      try visitor.visitLinkNode(self)
    }
  }
}
