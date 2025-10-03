/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if canImport(UIKit)
import UIKit

// MARK: - iOS/UIKit Platform Types

public typealias PlatformView = UIView
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
public typealias PlatformImageView = UIImageView
public typealias PlatformEdgeInsets = UIEdgeInsets
public typealias PlatformPasteboard = UIPasteboard
public typealias PlatformResponder = UIResponder
public typealias PlatformViewController = UIViewController
public typealias PlatformScrollView = UIScrollView

// Text input specific types
public typealias PlatformTextView = UITextView
public typealias PlatformTextViewDelegate = UITextViewDelegate
public typealias PlatformTextRange = UITextRange
public typealias PlatformTextPosition = UITextPosition
public typealias PlatformTextInput = UITextInput
public typealias PlatformTextInputDelegate = UITextInputDelegate
public typealias PlatformTextInputTraits = UITextInputTraits
public typealias PlatformTextStorageDirection = UITextStorageDirection
public typealias PlatformTextGranularity = UITextGranularity
public typealias PlatformTextItemInteraction = UITextItemInteraction

// Gesture recognizers
public typealias PlatformTapGestureRecognizer = UITapGestureRecognizer
public typealias PlatformGestureRecognizer = UIGestureRecognizer
public typealias PlatformGestureRecognizerDelegate = UIGestureRecognizerDelegate

// Key commands and keyboard
public typealias PlatformKeyCommand = UIKeyCommand

// Alerts
public typealias PlatformAlertController = UIAlertController
public typealias PlatformAlertAction = UIAlertAction

#elseif canImport(AppKit)
import AppKit

// MARK: - macOS/AppKit Platform Types

public typealias PlatformView = NSView
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
public typealias PlatformImageView = NSImageView
public typealias PlatformEdgeInsets = NSEdgeInsets
public typealias PlatformPasteboard = NSPasteboard
public typealias PlatformResponder = NSResponder
public typealias PlatformViewController = NSViewController
public typealias PlatformScrollView = NSScrollView

// Text input specific types
public typealias PlatformTextView = NSTextView
public typealias PlatformTextViewDelegate = NSTextViewDelegate

// Note: macOS uses NSRange directly instead of opaque text ranges
// NSTextInput protocol exists but is different from UITextInput
// We'll need adapter types for these

// macOS doesn't have NSTextStorageDirection/NSTextGranularity - create compatibility enums
public enum PlatformTextStorageDirection: Int {
  case forward = 0
  case backward = 1
}

public enum PlatformTextGranularity: Int {
  case character = 0
  case word = 1
  case sentence = 2
  case paragraph = 3
  case line = 4
  case document = 5
}

// Gesture recognizers
public typealias PlatformTapGestureRecognizer = NSClickGestureRecognizer
public typealias PlatformGestureRecognizer = NSGestureRecognizer
public typealias PlatformGestureRecognizerDelegate = NSGestureRecognizerDelegate

// Alerts
public typealias PlatformAlert = NSAlert

#endif

// MARK: - Cross-Platform Helper Extensions

#if canImport(UIKit)
public extension PlatformEdgeInsets {
  // UIEdgeInsets already has .zero on UIKit, no need to redefine

  var leading: CGFloat { return left }
  var trailing: CGFloat { return right }
}
#elseif canImport(AppKit)
extension PlatformEdgeInsets: Equatable {
  public static func == (lhs: NSEdgeInsets, rhs: NSEdgeInsets) -> Bool {
    return lhs.top == rhs.top && lhs.left == rhs.left && lhs.bottom == rhs.bottom && lhs.right == rhs.right
  }
}

public extension PlatformEdgeInsets {
  static var zero: PlatformEdgeInsets {
    return NSEdgeInsetsZero
  }

  var leading: CGFloat { return left }
  var trailing: CGFloat { return right }
}
#endif

// MARK: - Platform-Specific Constants

#if canImport(UIKit)
public enum PlatformConstants {
  public static let isUIKit = true
  public static let isAppKit = false
}
#elseif canImport(AppKit)
public enum PlatformConstants {
  public static let isUIKit = false
  public static let isAppKit = true
}
#endif
