#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(UIKit)
import UIKit

public typealias UXColor = UIColor
public typealias UXFont = UIFont
public typealias UXImage = UIImage
public typealias UXEdgeInsets = UIEdgeInsets
public typealias UXView = UIView
public typealias UXPasteboard = UIPasteboard

public typealias UXTextStorageDirection = UITextStorageDirection
public typealias UXTextGranularity = UITextGranularity
public typealias UXTextRange = UITextRange
public typealias UXKeyCommand = UIKeyCommand

@MainActor
public func UXPerformWithoutAnimation(_ updates: () -> Void) {
  UIView.performWithoutAnimation(updates)
}

public func UXGraphicsGetCurrentContext() -> CGContext? {
  UIGraphicsGetCurrentContext()
}

#elseif canImport(AppKit)
import AppKit

public typealias UXColor = NSColor
public typealias UXFont = NSFont
public typealias UXImage = NSImage
public typealias UXEdgeInsets = NSEdgeInsets
public typealias UXView = NSView
public typealias UXPasteboard = NSPasteboard

public class LexicalView: NSView {}
public class LexicalReadOnlyTextKitContext {}

public enum UXTextStorageDirection {
  case forward
  case backward
}

public enum UXTextGranularity {
  case character
  case word
  case sentence
  case line
  case paragraph
  case document
}

public extension NSEdgeInsets {
  static let zero = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}

public typealias UXTextRange = AnyObject
public typealias UXKeyCommand = AnyObject

@MainActor
public func UXPerformWithoutAnimation(_ updates: () -> Void) {
  updates()
}

public func UXGraphicsGetCurrentContext() -> CGContext? {
  NSGraphicsContext.current?.cgContext
}

#else
#error("Unsupported platform: Lexical requires either UIKit or AppKit")
#endif
