//
//  DecoratorBlockNode.swift
//  Lexical
//
//  Created by Nemanja Kovacevic on 19.11.24..
//

import Foundation
import UIKit
import LexicalCore

open class DecoratorBlockNode: DecoratorNode {

  override public func isInline() -> Bool {
    return false
  }

  override open func accept<V>(visitor: V) throws where V : NodeVisitor {
    try visitor.visitDecoratorBlockNode(self)
  }

}
