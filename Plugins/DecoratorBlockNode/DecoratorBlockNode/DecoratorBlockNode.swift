//
//  DecoratorBlockNode.swift
//  Lexical
//
//  Created by Nemanja Kovacevic on 19.11.24..
//

import Foundation
import Lexical
import UIKit

extension NodeType {
  static let block = NodeType(rawValue: "block")
}

open class DecoratorBlockNode: DecoratorNode {
  
  override public class func getType() -> NodeType {
    return .block
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
    return true
  }
  
  override open func getPostamble() -> String {
    return "\n"
  }

}
