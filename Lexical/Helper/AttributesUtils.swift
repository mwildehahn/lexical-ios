/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import CoreGraphics
import LexicalCore
#if canImport(UIKit)
import UIKit
private typealias UXFontDescriptor = UIFontDescriptor
private typealias UXFontDescriptorAttributeName = UIFontDescriptor.AttributeName
#elseif canImport(AppKit)
import AppKit
private typealias UXFontDescriptor = NSFontDescriptor
private typealias UXFontDescriptorAttributeName = NSFontDescriptor.AttributeName
#endif

@MainActor
public enum AttributeUtils {
  public static func attributedStringByAddingStyles(
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

    let copiedAttributes = NSDictionary(dictionary: combinedAttributes)
    guard let copiedAttributesSwiftDict = copiedAttributes as? [NSAttributedString.Key: Any] else {
      return NSAttributedString()
    }

    mutableCopy.addAttributes(copiedAttributesSwiftDict, range: NSRange(location: 0, length: length))
    return mutableCopy.copy() as? NSAttributedString ?? NSAttributedString()
  }

  public static func attributedStringStyles(
    from node: Node,
    state: EditorState,
    theme: Theme
  ) -> [NSAttributedString.Key: Any] {
    let lexicalAttributes = getLexicalAttributes(from: node, state: state, theme: theme).reversed()
    var combinedAttributes = lexicalAttributes.reduce(into: [NSAttributedString.Key: Any]()) { result, dict in
      result.merge(dict) { _, new in new }
    }

    var font = combinedAttributes[.font] as? UXFont ?? LexicalConstants.defaultFont
    var fontDescriptor: UXFontDescriptor = font.fontDescriptor
    var symbolicTraits = fontDescriptor.symbolicTraits

    if let bold = combinedAttributes[.bold] as? Bool {
      if bold {
        symbolicTraits.insert(.traitBold)
      } else {
        symbolicTraits = symbolicTraits.remove(.traitBold) ?? symbolicTraits
      }
    }

    if let italic = combinedAttributes[.italic] as? Bool {
      if italic {
        symbolicTraits.insert(.traitItalic)
      } else {
        symbolicTraits = symbolicTraits.remove(.traitItalic) ?? symbolicTraits
      }
    }

    if let family = combinedAttributes[.fontFamily] as? String {
      fontDescriptor = fontDescriptor.withFamily(family)
    }

    if let size = coerceCGFloat(combinedAttributes[.fontSize]) {
      fontDescriptor = fontDescriptor.addingAttributes([UXFontDescriptorAttributeName.size: size])
    }

#if canImport(UIKit)
    if let traitAdjusted = fontDescriptor.withSymbolicTraits(symbolicTraits) {
      fontDescriptor = traitAdjusted
    }
#else
    fontDescriptor = fontDescriptor.withSymbolicTraits(symbolicTraits)
#endif

    font = makeFont(from: fontDescriptor, fallback: font)
    combinedAttributes[.font] = font

    if let paragraphStyle = getParagraphStyle(attributes: combinedAttributes, indentSize: CGFloat(theme.indentSize)) {
      combinedAttributes[.paragraphStyle] = paragraphStyle
      combinedAttributes[.paragraphSpacingBefore_internal] = paragraphStyle.paragraphSpacingBefore
      combinedAttributes[.paragraphSpacing_internal] = paragraphStyle.paragraphSpacing
    }

    if combinedAttributes[.foregroundColor] == nil {
      combinedAttributes[.foregroundColor] = LexicalConstants.defaultColor
    }

    return combinedAttributes
  }

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

    while let parent = node.parent, let parentNode = state.nodeMap[parent] {
      attributes.append(parentNode.getAttributedStringAttributes(theme: theme))
      if let elementNode = parentNode as? ElementNode, elementNode.isInline() == false {
        attributes.append([.indent_internal: elementNode.getIndent()])
      }
      node = parentNode
    }

    return attributes
  }

  private static func getParagraphStyle(
    attributes: [NSAttributedString.Key: Any],
    indentSize: CGFloat
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

  private static func coerceCGFloat(_ object: Any?) -> CGFloat? {
    switch object {
    case let value as Int:
      return CGFloat(value)
    case let value as Float:
      return CGFloat(value)
    case let value as CGFloat:
      return value
    case let value as Double:
      return CGFloat(value)
    default:
      return nil
    }
  }

  private static func extraLineFragmentIsPresent(_ textStorage: TextStorage) -> Bool {
    let textAsNSString: NSString = textStorage.string as NSString
    guard textAsNSString.length > 0 else { return true }

    guard let scalar = Unicode.Scalar(textAsNSString.character(at: textAsNSString.length - 1)) else {
      return false
    }
    return CharacterSet.newlines.contains(scalar)
  }

  private enum BlockParagraphLocation {
    case range(NSRange, NSRange)
    case extraLineFragment
  }

  internal static func applyBlockLevelAttributes(
    _ attributes: BlockLevelAttributes,
    cacheItem: RangeCacheItem,
    textStorage: TextStorage,
    nodeKey: NodeKey,
    lastDescendentAttributes: [NSAttributedString.Key: Any]
  ) {
    let extraLineFragmentIsPresent = extraLineFragmentIsPresent(textStorage)
    let startTouchesExtraLineFragment =
      extraLineFragmentIsPresent && cacheItem.range.length == 0 && cacheItem.range.location == textStorage.length
    let endTouchesExtraLineFragment = extraLineFragmentIsPresent &&
      (NSMaxRange(cacheItem.range) - cacheItem.postambleLength) == textStorage.length

    var extraLineFragmentAttributes = extraLineFragmentIsPresent ? lastDescendentAttributes : [:]
    var paragraphs: [BlockParagraphLocation] = []

    if startTouchesExtraLineFragment {
      paragraphs.append(.extraLineFragment)
    } else {
      textStorage.mutableString.enumerateSubstrings(in: cacheItem.range, options: .byParagraphs) {
        _, substringRange, enclosingRange, _ in
        paragraphs.append(.range(substringRange, enclosingRange))
      }
      if endTouchesExtraLineFragment {
        paragraphs.append(.extraLineFragment)
      }
    }

    guard let first = paragraphs.first, let last = paragraphs.last else {
      return
    }

    let firstResult = paragraphStyle(for: first, textStorage: textStorage, attributes: &extraLineFragmentAttributes)
    guard let firstMutable = firstResult.style.mutableCopy() as? NSMutableParagraphStyle else {
      return
    }
    var spacingBefore = firstResult.spacingBefore ?? firstMutable.paragraphSpacingBefore
    spacingBefore += attributes.marginTop + attributes.paddingTop
    firstMutable.paragraphSpacingBefore = spacingBefore
    apply(paragraphStyle: firstMutable, to: first, textStorage: textStorage, attributes: &extraLineFragmentAttributes)

    let lastResult = paragraphStyle(for: last, textStorage: textStorage, attributes: &extraLineFragmentAttributes)
    guard let lastMutable = lastResult.style.mutableCopy() as? NSMutableParagraphStyle else {
      return
    }
    var spacingAfter = lastResult.spacingAfter ?? lastMutable.paragraphSpacing
    spacingAfter += attributes.marginBottom + attributes.paddingBottom
    lastMutable.paragraphSpacing = spacingAfter
    apply(paragraphStyle: lastMutable, to: last, textStorage: textStorage, attributes: &extraLineFragmentAttributes)

    if extraLineFragmentIsPresent {
      textStorage.extraLineFragmentAttributes = extraLineFragmentAttributes
    } else {
      textStorage.extraLineFragmentAttributes = nil
    }

    if !startTouchesExtraLineFragment, case .range(_, let enclosing) = first {
      textStorage.addAttribute(.appliedBlockLevelStyles_internal, value: attributes, range: enclosing)
    }
  }

  private static func paragraphStyle(
    for location: BlockParagraphLocation,
    textStorage: TextStorage,
    attributes: inout [NSAttributedString.Key: Any]
  ) -> (style: NSParagraphStyle, spacingBefore: CGFloat?, spacingAfter: CGFloat?) {
    switch location {
    case .extraLineFragment:
      let style = attributes[.paragraphStyle] as? NSParagraphStyle ?? NSParagraphStyle()
      let spacingBefore = attributes[.paragraphSpacingBefore_internal] as? CGFloat
      let spacingAfter = attributes[.paragraphSpacing_internal] as? CGFloat
      return (style, spacingBefore, spacingAfter)
    case .range(let range, _):
      let style = textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle()
      let spacingBefore = textStorage.attribute(.paragraphSpacingBefore_internal, at: range.location, effectiveRange: nil) as? CGFloat
      let spacingAfter = textStorage.attribute(.paragraphSpacingBefore_internal, at: range.location, effectiveRange: nil) as? CGFloat
      return (style, spacingBefore, spacingAfter)
    }
  }

  private static func apply(
    paragraphStyle: NSMutableParagraphStyle,
    to location: BlockParagraphLocation,
    textStorage: TextStorage,
    attributes: inout [NSAttributedString.Key: Any]
  ) {
    switch location {
    case .extraLineFragment:
      attributes[.paragraphStyle] = paragraphStyle
    case .range(_, let enclosing):
      textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: enclosing)
    }
  }

  private static func makeFont(from descriptor: UXFontDescriptor, fallback: UXFont) -> UXFont {
#if canImport(UIKit)
    return UXFont(descriptor: descriptor, size: 0)
#else
    return UXFont(descriptor: descriptor, size: fallback.pointSize) ?? fallback
#endif
  }
}

extension NSAttributedString.Key {
  internal static let indent_internal: NSAttributedString.Key = .init(rawValue: "indent_internal")
  internal static let paragraphSpacingBefore_internal: NSAttributedString.Key = .init(rawValue: "paragraphSpacingBefore_internal")
  internal static let paragraphSpacing_internal: NSAttributedString.Key = .init(rawValue: "paragraphSpacing_internal")
  internal static let appliedBlockLevelStyles_internal: NSAttributedString.Key = .init(rawValue: "appliedBlockLevelStyles_internal")
}

#if canImport(AppKit)
extension NSFontDescriptor.SymbolicTraits {
  static let traitBold = NSFontDescriptor.SymbolicTraits.bold
  static let traitItalic = NSFontDescriptor.SymbolicTraits.italic
}
#endif
