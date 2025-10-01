/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Platform TextView Protocol

/// Common protocol for platform text views (UITextView/NSTextView)
/// This helps abstract the differences between UIKit and AppKit text input handling
@MainActor
public protocol PlatformTextViewProtocol: AnyObject {
  var text: String! { get set }
  var attributedText: NSAttributedString! { get set }
  var font: PlatformFont? { get set }
  var textColor: PlatformColor? { get set }
  var isEditable: Bool { get set }
  var isSelectable: Bool { get set }

  #if canImport(UIKit)
  var textContainerInset: UIEdgeInsets { get set }
  var selectedRange: NSRange { get set }
  var selectedTextRange: UITextRange? { get set }
  var markedTextRange: UITextRange? { get }
  var inputDelegate: UITextInputDelegate? { get set }
  var inputAccessoryView: UIView? { get set }
  #elseif canImport(AppKit)
  var textContainerInset: NSSize { get set }
  var selectedRange: NSRange { get set }
  var selectedRanges: [NSValue] { get set }
  var markedRange: NSRange { get }
  #endif

  func becomeFirstResponder() -> Bool
  func resignFirstResponder() -> Bool
}

#if canImport(UIKit)
extension UITextView: PlatformTextViewProtocol {}
#elseif canImport(AppKit)
extension NSTextView: PlatformTextViewProtocol {
  public var text: String! {
    get { string }
    set { string = newValue ?? "" }
  }

  public var attributedText: NSAttributedString! {
    get { attributedString() }
    set { textStorage?.setAttributedString(newValue ?? NSAttributedString()) }
  }

  public var markedRange: NSRange {
    // NSTextView doesn't have markedTextRange property
    // It has markedRange() method in NSTextInputClient protocol
    return NSRange(location: NSNotFound, length: 0)
  }

  public var textContainerInset: NSSize {
    get {
      // NSTextView uses textContainerOrigin for insets
      return NSSize(width: textContainerOrigin.x, height: textContainerOrigin.y)
    }
    set {
      // Best effort - NSTextView doesn't directly support setting insets like UITextView
      // This would require modifying textContainerOrigin which is read-only
    }
  }
}
#endif

// MARK: - Platform Alert Protocol

/// Protocol for presenting alerts across platforms
@MainActor
public protocol PlatformAlertPresenting {
  func presentError(title: String, message: String)
}

// MARK: - Platform Pasteboard Protocol

/// Common interface for pasteboard operations
@MainActor
public protocol PlatformPasteboardProtocol {
  func getString() -> String?
  func setString(_ string: String)
  func getData(forType type: String) -> Data?
  func setData(_ data: Data, forType type: String)
  func hasStrings() -> Bool
  func clear()
}

#if canImport(UIKit)
/// iOS Pasteboard Adapter
@MainActor
public struct IOSPasteboardAdapter: PlatformPasteboardProtocol {
  private let pasteboard: UIPasteboard

  public init(pasteboard: UIPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  public func getString() -> String? {
    return pasteboard.string
  }

  public func setString(_ string: String) {
    pasteboard.string = string
  }

  public func getData(forType type: String) -> Data? {
    return pasteboard.data(forPasteboardType: type)
  }

  public func setData(_ data: Data, forType type: String) {
    pasteboard.setData(data, forPasteboardType: type)
  }

  public func hasStrings() -> Bool {
    return pasteboard.hasStrings
  }

  public func clear() {
    pasteboard.items = []
  }
}
#elseif canImport(AppKit)
/// macOS Pasteboard Adapter
@MainActor
public struct MacOSPasteboardAdapter: PlatformPasteboardProtocol {
  private let pasteboard: NSPasteboard

  public init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  public func getString() -> String? {
    return pasteboard.string(forType: .string)
  }

  public func setString(_ string: String) {
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
  }

  public func getData(forType type: String) -> Data? {
    return pasteboard.data(forType: NSPasteboard.PasteboardType(type))
  }

  public func setData(_ data: Data, forType type: String) {
    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
  }

  public func hasStrings() -> Bool {
    return pasteboard.string(forType: .string) != nil
  }

  public func clear() {
    pasteboard.clearContents()
  }
}
#endif

// MARK: - Platform Gesture Protocol

/// Common protocol for gesture recognizers
@MainActor
public protocol PlatformGestureRecognizerProtocol: AnyObject {
  var isEnabled: Bool { get set }
  var view: PlatformView? { get }

  #if canImport(UIKit)
  var state: UIGestureRecognizer.State { get }
  #elseif canImport(AppKit)
  var state: NSGestureRecognizer.State { get }
  #endif
}

#if canImport(UIKit)
extension UIGestureRecognizer: PlatformGestureRecognizerProtocol {}
#elseif canImport(AppKit)
extension NSGestureRecognizer: PlatformGestureRecognizerProtocol {}
#endif

// MARK: - Platform View Helpers

public extension PlatformView {
  /// Add subview with platform-appropriate method
  func addPlatformSubview(_ subview: PlatformView) {
    #if canImport(UIKit)
    addSubview(subview)
    #elseif canImport(AppKit)
    addSubview(subview)
    #endif
  }

  /// Remove from superview
  func removeFromPlatformSuperview() {
    removeFromSuperview()
  }

  /// Get frame in platform-appropriate coordinates
  var platformFrame: CGRect {
    get { return frame }
    set { frame = newValue }
  }

  /// Get bounds
  var platformBounds: CGRect {
    return bounds
  }

  /// Set background color cross-platform
  func setPlatformBackgroundColor(_ color: PlatformColor?) {
    #if canImport(UIKit)
    backgroundColor = color
    #elseif canImport(AppKit)
    wantsLayer = true
    layer?.backgroundColor = color?.cgColor
    #endif
  }
}

// MARK: - Platform Color Extensions

public extension PlatformColor {
  /// Create color from RGB values (0-255)
  static func platformColor(red: Int, green: Int, blue: Int, alpha: CGFloat = 1.0) -> PlatformColor {
    return PlatformColor(
      red: CGFloat(red) / 255.0,
      green: CGFloat(green) / 255.0,
      blue: CGFloat(blue) / 255.0,
      alpha: alpha
    )
  }

  #if canImport(AppKit)
  /// Get RGB components (AppKit NSColor doesn't have direct RGB accessors)
  var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    guard let rgbColor = usingColorSpace(.deviceRGB) else {
      return (0, 0, 0, 0)
    }
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
  }
  #endif
}

// MARK: - Platform Font Extensions

public extension PlatformFont {
  /// Get font weight in a cross-platform way
  var platformWeight: CGFloat {
    #if canImport(UIKit)
    return (fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
    #elseif canImport(AppKit)
    let traits = fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any] ?? [:]
    return traits[.weight] as? CGFloat ?? 0
    #endif
  }
}
