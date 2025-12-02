/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Foundation
import Lexical
import LexicalCore

/// Default constants for AppKit text rendering.
enum LexicalConstantsAppKit {
  static var defaultFont: NSFont {
    return NSFont.systemFont(ofSize: NSFont.systemFontSize)
  }

  static var defaultColor: NSColor {
    return NSColor.textColor
  }
}

/// Utility functions for applying Lexical attributes to NSAttributedString on macOS.
@MainActor
enum AttributeUtilsAppKit {

  /// Creates an attributed string with styles applied from a Lexical node.
  static func attributedStringByAddingStyles(
    _ attributedString: NSAttributedString,
    from node: Node,
    state: EditorState,
    theme: Theme
  ) -> NSAttributedString {

    let combinedAttributes = attributedStringStyles(from: node, state: state, theme: theme)
    let length = attributedString.length

    guard let mutableCopy = attributedString.mutableCopy() as? NSMutableAttributedString else {
      return NSAttributedString()
    }

    let copiedAttributes: NSDictionary = NSDictionary(dictionary: combinedAttributes)
    guard
      let copiedAttributesSwiftDict: [NSAttributedString.Key: Any] = copiedAttributes
        as? [NSAttributedString.Key: Any]
    else {
      return NSAttributedString()
    }

    // Update font and rest of the attributes
    mutableCopy.addAttributes(
      copiedAttributesSwiftDict, range: NSRange(location: 0, length: length))

    guard let copiedString: NSAttributedString = mutableCopy.copy() as? NSAttributedString else {
      return NSAttributedString()
    }
    return copiedString
  }

  /// Computes the combined attributed string styles for a node.
  internal static func attributedStringStyles(
    from node: Node,
    state: EditorState,
    theme: Theme
  ) -> [NSAttributedString.Key: Any] {
    let lexicalAttributes = getLexicalAttributes(from: node, state: state, theme: theme).reversed()

    // Combine all dictionaries and update the font style
    // Leaf node's attributes have a priority over element node's attributes
    // hence, they are applied last
    var combinedAttributes = lexicalAttributes.reduce([:]) { $0.merging($1) { $1 } }

    var font = combinedAttributes[.font] as? NSFont ?? LexicalConstantsAppKit.defaultFont
    var fontDescriptor = font.fontDescriptor
    var symbolicTraits = fontDescriptor.symbolicTraits

    // Update symbolic traits
    if let bold = combinedAttributes[.bold] as? Bool {
      if bold {
        symbolicTraits = symbolicTraits.union([.bold])
      } else {
        symbolicTraits.remove(.bold)
      }
    }

    if let italic = combinedAttributes[.italic] as? Bool {
      if italic {
        symbolicTraits = symbolicTraits.union([.italic])
      } else {
        symbolicTraits.remove(.italic)
      }
    }

    // Update font face, family and size
    if let family = combinedAttributes[.fontFamily] as? String {
      fontDescriptor = fontDescriptor.withFamily(family)
    }

    if let size = coerceCGFloat(combinedAttributes[.fontSize]) {
      fontDescriptor = fontDescriptor.addingAttributes([.size: size])
    }

    fontDescriptor = fontDescriptor.withSymbolicTraits(symbolicTraits)
    font = NSFont(descriptor: fontDescriptor, size: 0) ?? LexicalConstantsAppKit.defaultFont

    combinedAttributes[.font] = font

    if let paragraphStyle = getParagraphStyle(
      attributes: combinedAttributes, indentSize: CGFloat(theme.indentSize))
    {
      combinedAttributes[.paragraphStyle] = paragraphStyle
      combinedAttributes[.paragraphSpacingBefore_internal] = paragraphStyle.paragraphSpacingBefore
      combinedAttributes[.paragraphSpacing_internal] = paragraphStyle.paragraphSpacing
    }

    if combinedAttributes[.foregroundColor] == nil {
      combinedAttributes[.foregroundColor] = LexicalConstantsAppKit.defaultColor
    }

    return combinedAttributes
  }

  /// Collects Lexical attributes from a node and its ancestors.
  static func getLexicalAttributes(
    from node: Node,
    state: EditorState,
    theme: Theme
  ) -> [[NSAttributedString.Key: Any]] {
    var node = node
    var attributes = [[NSAttributedString.Key: Any]]()
    attributes.append(node.getAttributedStringAttributes(theme: theme))
    if let elementNode = node as? ElementNode, elementNode.isInline() == false {
      attributes.append([.indent_internal: elementNode.getIndent()])
    }

    // Use getNodeByKey to traverse parent chain
    while let parentKey = node.parent, let parentNode: Node = getNodeByKey(key: parentKey) {
      attributes.append(parentNode.getAttributedStringAttributes(theme: theme))
      if let elementNode = parentNode as? ElementNode, elementNode.isInline() == false {
        attributes.append([.indent_internal: elementNode.getIndent()])
      }
      node = parentNode
    }

    return attributes
  }

  /// Creates a paragraph style from the given attributes.
  private static func getParagraphStyle(
    attributes: [NSAttributedString.Key: Any], indentSize: CGFloat
  ) -> NSParagraphStyle? {
    let paragraphStyle = NSMutableParagraphStyle()
    var styleFound = false

    var leftPadding: CGFloat = 0
    if let newPaddingHead = coerceCGFloat(attributes[.paddingHead]) {
      leftPadding += newPaddingHead
    }
    if let indent = attributes[.indent_internal] as? Int {
      leftPadding += CGFloat(indent) * indentSize
    }

    if leftPadding > 0 {
      paragraphStyle.firstLineHeadIndent = leftPadding
      paragraphStyle.headIndent = leftPadding
      styleFound = true
    }

    if let newPaddingTail = coerceCGFloat(attributes[.paddingTail]) {
      paragraphStyle.tailIndent = newPaddingTail
      styleFound = true
    }

    if let newLineHeight = coerceCGFloat(attributes[.lineHeight]) {
      paragraphStyle.minimumLineHeight = newLineHeight
      styleFound = true
    }

    if let newLineSpacing = coerceCGFloat(attributes[.lineSpacing]) {
      paragraphStyle.lineSpacing = newLineSpacing
      styleFound = true
    }

    if let paragraphSpacingBefore = coerceCGFloat(attributes[.paragraphSpacingBefore]) {
      paragraphStyle.paragraphSpacingBefore = paragraphSpacingBefore
      styleFound = true
    }

    return styleFound ? paragraphStyle : nil
  }

  /// Coerces various numeric types to CGFloat.
  private static func coerceCGFloat(_ object: Any?) -> CGFloat? {
    if let object = object as? Int {
      return CGFloat(object)
    }
    if let object = object as? Float {
      return CGFloat(object)
    }
    if let object = object as? CGFloat {
      return object
    }
    if let object = object as? Double {
      return CGFloat(object)
    }
    return nil
  }

  /// Checks if the text storage ends with a newline (extra line fragment present).
  private static func extraLineFragmentIsPresent(_ textStorage: TextStorageAppKit) -> Bool {
    let textAsNSString: NSString = textStorage.string as NSString
    guard textAsNSString.length > 0 else { return true }

    guard let scalar = Unicode.Scalar(textAsNSString.character(at: textAsNSString.length - 1))
    else { return false }
    if NSCharacterSet.newlines.contains(scalar) { return true }
    return false
  }

  // Note: applyBlockLevelAttributes is not available on AppKit.
  // It requires RangeCacheItem which is UIKit-only.
  // Block-level styling will need to be implemented differently for AppKit.
}

// MARK: - NSAttributedString.Key Extensions for AppKit

extension NSAttributedString.Key {
  // Note: These keys are also defined in the UIKit version.
  // They need to match for cross-platform compatibility.

  internal static let indent_internal: NSAttributedString.Key = .init(rawValue: "indent_internal")

  internal static let paragraphSpacingBefore_internal: NSAttributedString.Key = .init(
    rawValue: "paragraphSpacingBefore_internal")
  internal static let paragraphSpacing_internal: NSAttributedString.Key = .init(
    rawValue: "paragraphSpacing_internal")

  internal static let appliedBlockLevelStyles_internal: NSAttributedString.Key = .init(
    rawValue: "appliedBlockLevelStyles_internal")
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
