/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if canImport(UIKit)
import UIKit
public typealias LexicalColor = UIColor
public typealias LexicalFont = UIFont
public typealias LexicalEdgeInsets = UIEdgeInsets
public typealias LexicalBezierPath = UIBezierPath

@MainActor
public func lexicalRectFill(_ rect: CGRect) {
  UIRectFill(rect)
}

@MainActor
public func lexicalGraphicsGetCurrentContext() -> CGContext? {
  UIGraphicsGetCurrentContext()
}

#elseif canImport(AppKit)
import AppKit
public typealias LexicalColor = NSColor
public typealias LexicalFont = NSFont
public typealias LexicalEdgeInsets = NSEdgeInsets
public typealias LexicalBezierPath = NSBezierPath

@MainActor
public func lexicalRectFill(_ rect: CGRect) {
  NSBezierPath(rect: rect).fill()
}

@MainActor
public func lexicalGraphicsGetCurrentContext() -> CGContext? {
  NSGraphicsContext.current?.cgContext
}
#endif
