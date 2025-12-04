/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation
import LexicalCore

public class RootNode: ElementNode {

  public override required init() {
    super.init(kRootNodeKey)
  }

  public required convenience init(from decoder: Decoder) throws {
    try self.init(from: decoder, depth: nil, index: nil)
  }

  public required init(from decoder: Decoder, depth: Int? = nil, index: Int? = nil, parentIndex: Int? = nil) throws {
    try super.init(from: decoder, depth: depth ?? -1, index: index ?? 0, parentIndex: parentIndex)
  }

  override public func clone() -> Self {
    Self()
  }

  override public static func getType() -> NodeType {
    return .root
  }

  override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
    if let root = theme.root {
      return root
    }

    return [.font: LexicalConstants.defaultFont]
  }

  // In read-only contexts only, strip a single leading newline from the
  // document text content to match legacy parity when reading the full
  // string (pre/post spacing is still preserved within paragraphs).
  override public func getTextContent(
    includeInert: Bool = false,
    includeDirectionless: Bool = false,
    maxLength: Int? = nil
  ) -> String {
    let s = super.getTextContent(
      includeInert: includeInert,
      includeDirectionless: includeDirectionless,
      maxLength: maxLength)
    #if canImport(UIKit)
    if let ed = getActiveEditor(), ed.frontend is LexicalReadOnlyTextKitContext, s.hasPrefix("\n") {
      return String(s.dropFirst(1))
    }
    #elseif canImport(AppKit)
    if let ed = getActiveEditor(), ed.isReadOnlyFrontend, s.hasPrefix("\n") {
      return String(s.dropFirst(1))
    }
    #endif
    return s
  }

  // Root nodes cannot have a preamble. If they did, there would be no way to make a selection of the
  // beginning of the document. The same applies to postamble.
  override open func getPreamble() -> String {
    return ""
  }

  override open func getPostamble() -> String {
    return ""
  }

  override public func insertBefore(nodeToInsert: Node) throws -> Node {
    throw LexicalError.invariantViolation("insertBefore: cannot be called on root nodes")
  }

  override public func remove() throws {
    throw LexicalError.invariantViolation("remove: cannot be called on root nodes")
  }

  override public func replace<T: Node>(replaceWith: T, includeChildren: Bool = false) throws -> T {
    throw LexicalError.invariantViolation("replace: cannot be called on root nodes")
  }

  override public func insertAfter(nodeToInsert: Node) throws -> Node {
    throw LexicalError.invariantViolation("insertAfter: cannot be called on root nodes")
  }

  public override func accept<V>(visitor: V) throws where V : NodeVisitor {
    try visitor.visitRootNode(self)
  }
}

extension RootNode: CustomDebugStringConvertible {
  public var debugDescription: String {
    return "(RootNode: key '\(key)', id \(ObjectIdentifier(self))"
  }
}
