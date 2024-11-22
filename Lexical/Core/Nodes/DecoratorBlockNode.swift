//
//  DecoratorBlockNode.swift
//  Lexical
//
//  Created by Nemanja Kovacevic on 19.11.24..
//

import Foundation
import UIKit

extension NodeType {
  static let block = NodeType(rawValue: "block")
  static let innerBlock = NodeType(rawValue: "innerBlock")
}

/*
 DecoratorBlockNode was originally subclass of a DecoratorNode.
 However there is a glitch with cursor position being falsly reported
 when DecoratorNode is directly in the RootNode and cursor is behind it.
 I tried to solve this with this somewhat strange construction.
 */
open class DecoratorBlockNode: ParagraphNode {
  
  override public class func getType() -> NodeType {
    return .block
  }
  
  override public init() {
    super.init()
  }

  public required init(_ key: NodeKey?) {
    super.init(key)
  }

  public required init(from decoder: Decoder) throws {
    try super.init(from: decoder)
  }

  override public func getAttributedStringAttributes(theme: Theme) -> [NSAttributedString.Key: Any] {
    return [:]
  }

}

open class InnerDecoratorBlockNode: DecoratorNode {
  
  override public class func getType() -> NodeType {
    return .innerBlock
  }
  
  override public func createView() -> UILabel {
    let view = UILabel(frame: CGRect(origin: CGPoint.zero, size: CGSizeMake(50, 50)))
    return view
  }

  override open func decorate(view: UIView) {
    view.backgroundColor = .lightGray
  }
  
  open override func sizeForDecoratorView(textViewWidth: CGFloat, attributes: [NSAttributedString.Key : Any]) -> CGSize {
    return CGSizeMake(textViewWidth, 50)
  }
  
  open override func isTopLevel() -> Bool {
    return false
  }

}
