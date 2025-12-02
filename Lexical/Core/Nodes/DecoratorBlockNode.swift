//
//  DecoratorBlockNode.swift
//  Lexical
//
//  Created by Nemanja Kovacevic on 19.11.24..
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation
import LexicalCore

open class DecoratorBlockNode: DecoratorNode {

  override public func isInline() -> Bool {
    return false
  }

  override open func accept<V>(visitor: V) throws where V : NodeVisitor {
    try visitor.visitDecoratorBlockNode(self)
  }

}
