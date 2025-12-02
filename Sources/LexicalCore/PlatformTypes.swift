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
public typealias LexicalNativeView = UIView
public typealias LexicalTextStorageDirection = UITextStorageDirection
public typealias LexicalTextGranularity = UITextGranularity

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
public typealias LexicalNativeView = NSView

/// Direction for text storage operations (AppKit equivalent)
public enum LexicalTextStorageDirection: Int {
  case forward = 0
  case backward = 1
}

/// Text granularity for selection operations (AppKit equivalent)
public enum LexicalTextGranularity: Int {
  case character = 0
  case word = 1
  case sentence = 2
  case paragraph = 3
  case line = 4
  case document = 5
}

@MainActor
public func lexicalRectFill(_ rect: CGRect) {
  NSBezierPath(rect: rect).fill()
}

@MainActor
public func lexicalGraphicsGetCurrentContext() -> CGContext? {
  NSGraphicsContext.current?.cgContext
}

// Extension to match UIBezierPath API
public extension NSBezierPath {
  /// Creates a bezier path with a rounded rectangle, matching UIBezierPath's API.
  convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
    self.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
  }
}

// NSEdgeInsets doesn't conform to Equatable on macOS, unlike UIEdgeInsets on iOS
extension NSEdgeInsets: @retroactive Equatable {
  public static func == (lhs: NSEdgeInsets, rhs: NSEdgeInsets) -> Bool {
    lhs.top == rhs.top && lhs.left == rhs.left && lhs.bottom == rhs.bottom && lhs.right == rhs.right
  }
}
#endif
