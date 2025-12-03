/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical
import LexicalCore

/// Custom NSLayoutManager for Lexical on macOS.
///
/// This class provides custom drawing support for:
/// - Background custom drawing handlers (e.g., highlights, decorations)
/// - Text custom drawing handlers
/// - Decorator view positioning
/// - Custom truncation
@MainActor
public class LayoutManagerAppKit: NSLayoutManager, @unchecked Sendable {

  // MARK: - Properties

  /// The Lexical editor instance.
  internal weak var editor: Editor? {
    if let textStorage = textStorage as? TextStorageAppKit {
      return textStorage.editor
    }
    return nil
  }

  // MARK: - Custom Drawing

  private var customDrawingBackground: [NSAttributedString.Key: Editor.CustomDrawingHandlerInfo] {
    return editor?.customDrawingBackground ?? [:]
  }

  private var customDrawingText: [NSAttributedString.Key: Editor.CustomDrawingHandlerInfo] {
    return editor?.customDrawingText ?? [:]
  }

  public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    draw(forGlyphRange: glyphsToShow, at: origin, handlers: customDrawingBackground)
  }

  public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    draw(forGlyphRange: glyphsToShow, at: origin, handlers: customDrawingText)
    positionAllDecorators()
  }

  private func draw(
    forGlyphRange drawingGlyphRange: NSRange, at origin: CGPoint,
    handlers: [NSAttributedString.Key: Editor.CustomDrawingHandlerInfo]
  ) {
    let characterRange = characterRange(forGlyphRange: drawingGlyphRange, actualGlyphRange: nil)
    guard let textStorage = textStorage as? TextStorageAppKit else {
      return
    }

    handlers.forEach { attribute, value in
      let handler = value.customDrawingHandler
      let granularity = value.granularity

      textStorage.enumerateAttribute(attribute, in: characterRange) { value, attributeRunRange, _ in
        guard let value else {
          // we only trigger when there is a non-nil value
          return
        }
        let glyphRangeForAttributeRun = glyphRange(
          forCharacterRange: attributeRunRange, actualCharacterRange: nil)
        ensureLayout(forGlyphRange: glyphRangeForAttributeRun)

        switch granularity {
        case .characterRuns:
          enumerateLineFragments(forGlyphRange: glyphRangeForAttributeRun) {
            rect, usedRect, textContainer, glyphRangeForGlyphRun, _ in
            let intersectionRange = NSIntersectionRange(
              glyphRangeForAttributeRun, glyphRangeForGlyphRun)
            let charRangeToDraw = self.characterRange(
              forGlyphRange: intersectionRange, actualGlyphRange: nil)
            let glyphBoundingRect = self.boundingRect(
              forGlyphRange: intersectionRange, in: textContainer)
            handler(
              attribute, value, self, attributeRunRange, charRangeToDraw, intersectionRange,
              glyphBoundingRect.offsetBy(dx: origin.x, dy: origin.y),
              rect.offsetBy(dx: origin.x, dy: origin.y))
          }
        case .singleParagraph:
          let paraGroupRange = textStorage.mutableString.paragraphRange(for: attributeRunRange)
          (textStorage.string as NSString).enumerateSubstrings(
            in: paraGroupRange, options: .byParagraphs
          ) { substring, substringRange, enclosingRange, _ in
            guard substringRange.length >= 1 else { return }
            let glyphRangeForParagraph = self.glyphRange(
              forCharacterRange: substringRange, actualCharacterRange: nil)
            let firstCharLineFragment = self.lineFragmentRect(
              forGlyphAt: glyphRangeForParagraph.location, effectiveRange: nil)
            let lastCharLineFragment = self.lineFragmentRect(
              forGlyphAt: glyphRangeForParagraph.upperBound - 1, effectiveRange: nil)
            let containingRect = firstCharLineFragment.union(lastCharLineFragment)
            handler(
              attribute, value, self, attributeRunRange, substringRange, glyphRangeForParagraph,
              containingRect.offsetBy(dx: origin.x, dy: origin.y),
              firstCharLineFragment.offsetBy(dx: origin.x, dy: origin.y))
          }
        case .contiguousParagraphs:
          let paraGroupRange = textStorage.mutableString.paragraphRange(for: attributeRunRange)
          guard paraGroupRange.length >= 1 else { return }
          let glyphRangeForParagraphs = self.glyphRange(
            forCharacterRange: paraGroupRange, actualCharacterRange: nil)
          let firstCharLineFragment = self.lineFragmentRect(
            forGlyphAt: glyphRangeForParagraphs.location, effectiveRange: nil)

          let lastCharLineFragment =
            (paraGroupRange.upperBound == textStorage.length
              && self.extraLineFragmentRect.height > 0)
            ? self.extraLineFragmentRect
            : self.lineFragmentRect(
              forGlyphAt: glyphRangeForParagraphs.upperBound - 1, effectiveRange: nil)

          var containingRect = firstCharLineFragment.union(lastCharLineFragment).offsetBy(
            dx: origin.x, dy: origin.y)

          // If there are block styles, subtract the margin here.
          if let blockStyle = textStorage.attribute(
            .appliedBlockLevelStyles_internal, at: paraGroupRange.location, effectiveRange: nil)
            as? BlockLevelAttributes
          {
            // first check to see if we should apply top margin.
            if paraGroupRange.location > 0 {
              containingRect.origin.y += blockStyle.marginTop
              containingRect.size.height -= blockStyle.marginTop
            }
            // next check for bottom margin
            if paraGroupRange.location + paraGroupRange.length
              < (textStorage.string as NSString).length
            {
              containingRect.size.height -= blockStyle.marginBottom
            }
          }

          handler(
            attribute, value, self, attributeRunRange, paraGroupRange, glyphRangeForParagraphs,
            containingRect, firstCharLineFragment.offsetBy(dx: origin.x, dy: origin.y))
        }
      }
    }
  }

  // MARK: - Decorator Positioning

  private func positionAllDecorators() {
    guard let textStorage = textStorage as? TextStorageAppKit else { return }

    if editor?.featureFlags.verboseLogging == true {
      let tsPtr = Unmanaged.passUnretained(textStorage).toOpaque()
      print("🔥 DEC-LM: positionAllDecorators count=\(textStorage.decoratorPositionCache.count) ts.ptr=\(tsPtr)")
    }

    for (key, location) in textStorage.decoratorPositionCache {
      positionDecorator(forKey: key, characterIndex: location)
    }
  }

  private func positionDecorator(forKey key: NodeKey, characterIndex: Int) {
    guard let textContainer = textContainers.first, let textStorage else {
      editor?.log(.TextView, .warning, "called with no container or storage")
      return
    }

    if textStorage.length == 0 { return }
    let clampedCharIndex = max(0, min(characterIndex, textStorage.length - 1))
    let glyphIndex = glyphIndexForCharacter(at: clampedCharIndex)
    var glyphIsInTextContainer = NSLocationInRange(glyphIndex, glyphRange(for: textContainer))

    // If the glyph isn't laid out yet (e.g., immediately after insertion and
    // before a draw pass), force layout for this glyph and re-check containment
    // to avoid transiently hiding the decorator view.
    if !glyphIsInTextContainer {
      ensureLayout(forGlyphRange: NSRange(location: glyphIndex, length: 1))
      glyphIsInTextContainer = NSLocationInRange(glyphIndex, glyphRange(for: textContainer))
    }

    var glyphBoundingRect: CGRect = .zero
    let shouldHideView: Bool = !glyphIsInTextContainer

    if glyphIsInTextContainer {
      glyphBoundingRect = boundingRect(
        forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
    }

    // Get attachment at character index
    var attribute: TextAttachmentAppKit?

    if NSLocationInRange(characterIndex, NSRange(location: 0, length: textStorage.length)) {
      attribute = textStorage.attribute(.attachment, at: characterIndex, effectiveRange: nil)
        as? TextAttachmentAppKit
    }

    guard let attr = attribute, let attachmentKey = attr.key, let attachmentEditor = attr.editor else {
      editor?.log(.TextView, .warning, "called with no attachment")
      return
    }

    let textContainerInset = attachmentEditor.frontendAppKit?.textContainerInsets ?? NSEdgeInsets()

    try? attachmentEditor.read {
      if attachmentEditor.featureFlags.verboseLogging {
        print("🔥 DEC-LM: key=\(attachmentKey) charIndex=\(characterIndex) glyphIndex=\(glyphIndex) inContainer=\(glyphIsInTextContainer) hide=\(shouldHideView) ts.len=\(textStorage.length)")
      }

      guard let decoratorView = decoratorView(forKey: attachmentKey, createIfNecessary: !shouldHideView)
      else {
        attachmentEditor.log(.TextView, .warning, "create decorator view failed")
        return
      }

      if shouldHideView {
        if attachmentEditor.featureFlags.verboseLogging {
          print("🔥 DEC-LM: hide view key=\(attachmentKey)")
        }
        decoratorView.isHidden = true
        return
      }

      // We have a valid location, make sure view is not hidden
      decoratorView.isHidden = false

      // Get decorator size - compute it if bounds is zero (attachmentBounds may not have been called)
      var decoratorSize = attr.bounds.size
      var needsLayoutInvalidation = false
      if decoratorSize.width == 0 && decoratorSize.height == 0 {
        // Compute size directly from the decorator node
        if let decoratorNode = getNodeByKey(key: attachmentKey) as? DecoratorNode {
          let textViewWidth = attachmentEditor.frontendAppKit?.textLayoutWidth ?? 0
          let attributes = textStorage.attributes(at: characterIndex, effectiveRange: nil)
          decoratorSize = decoratorNode.sizeForDecoratorView(textViewWidth: textViewWidth, attributes: attributes)
          // Cache the computed bounds on the attachment
          attr.bounds = NSRect(origin: .zero, size: decoratorSize)
          needsLayoutInvalidation = true
        }
      }

      // If we just computed new bounds, invalidate layout so text reflows around the image
      if needsLayoutInvalidation {
        let range = NSRange(location: characterIndex, length: 1)
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          self.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
          if let container = self.textContainers.first {
            self.ensureLayout(for: container)
          }
        }
      }

      // Calculate decorator origin: start at top-left of glyph rect, offset by container insets
      // In NSTextView's flipped coordinates, y=0 is at top, increasing downward
      let decoratorOrigin = CGPoint(
        x: glyphBoundingRect.origin.x + textContainerInset.left,
        y: glyphBoundingRect.origin.y + textContainerInset.top
      )

      decoratorView.frame = CGRect(origin: decoratorOrigin, size: decoratorSize)

      if attachmentEditor.featureFlags.verboseLogging {
        print("🔥 DEC-LM: positioned key=\(attachmentKey) frame=\(decoratorView.frame) glyphRect=\(glyphBoundingRect) attrSize=\(decoratorSize)")
      }
    }
  }

  // MARK: - Glyph Rendering

  /// Override to fix color rendering for links with custom colors.
  public override func showCGGlyphs(
    _ glyphs: UnsafePointer<CGGlyph>,
    positions: UnsafePointer<CGPoint>,
    count glyphCount: Int,
    font: NSFont,
    textMatrix: CGAffineTransform,
    attributes: [NSAttributedString.Key: Any] = [:],
    in context: CGContext
  ) {
    // Fix for links with custom colour -- AppKit has trouble with this!
    if attributes[.link] != nil, let colorAttr = attributes[.foregroundColor] as? NSColor {
      context.setFillColor(colorAttr.cgColor)
    }

    super.showCGGlyphs(
      glyphs,
      positions: positions,
      count: glyphCount,
      font: font,
      textMatrix: textMatrix,
      attributes: attributes,
      in: context
    )
  }
}

// MARK: - LayoutManagerDelegateAppKit

/// NSLayoutManagerDelegate implementation for Lexical on macOS.
///
/// Handles glyph generation for text transforms (uppercase/lowercase).
@MainActor
class LayoutManagerDelegateAppKit: NSObject, @preconcurrency NSLayoutManagerDelegate {

  // MARK: - Line Fragment Adjustment for Decorators

  /// Adjusts line fragment height to accommodate decorator attachments.
  ///
  /// When a line contains a text attachment (decorator), this method ensures
  /// the line fragment is tall enough to fully contain the decorator view.
  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
    lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
    baselineOffset: UnsafeMutablePointer<CGFloat>,
    in textContainer: NSTextContainer,
    forGlyphRange glyphRange: NSRange
  ) -> Bool {
    guard let textStorage = layoutManager.textStorage else { return false }

    // Convert glyph range to character range
    let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    guard charRange.location != NSNotFound, charRange.length > 0 else { return false }

    // Check for attachments in this range
    var maxAttachmentHeight: CGFloat = 0

    textStorage.enumerateAttribute(.attachment, in: charRange, options: []) { value, _, _ in
      guard let attachment = value as? TextAttachmentAppKit else { return }

      // Get the attachment size from the cached bounds
      var attachmentSize = attachment.bounds.size

      // If bounds is zero, try to compute it
      if attachmentSize.width == 0 && attachmentSize.height == 0 {
        if let key = attachment.key, let editor = attachment.editor {
          try? editor.read {
            if let decoratorNode = getNodeByKey(key: key) as? DecoratorNode {
              let textViewWidth = editor.frontendAppKit?.textLayoutWidth ?? 0
              attachmentSize = decoratorNode.sizeForDecoratorView(textViewWidth: textViewWidth, attributes: [:])
              attachment.bounds = NSRect(origin: .zero, size: attachmentSize)
            }
          }
        }
      }

      if attachmentSize.height > maxAttachmentHeight {
        maxAttachmentHeight = attachmentSize.height
      }
    }

    // If no large attachments, let layout manager handle it normally
    if maxAttachmentHeight <= lineFragmentRect.pointee.height {
      return false
    }

    // Expand the line fragment to accommodate the attachment
    let currentHeight = lineFragmentRect.pointee.height
    let heightDelta = maxAttachmentHeight - currentHeight

    // Adjust rect heights
    lineFragmentRect.pointee.size.height = maxAttachmentHeight
    lineFragmentUsedRect.pointee.size.height = maxAttachmentHeight

    // Adjust baseline to keep text at bottom of expanded line
    baselineOffset.pointee += heightDelta

    return true
  }

  // MARK: - Glyph Generation for Text Transforms

  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
    properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
    characterIndexes: UnsafePointer<Int>,
    font: NSFont,
    forGlyphRange glyphRange: NSRange
  ) -> Int {

    guard let textStorage = layoutManager.textStorage else {
      return 0
    }

    let incomingGlyphsLength = glyphRange.length
    guard incomingGlyphsLength > 0 else { return 0 }

    let firstCharIndex = characterIndexes[0]
    let lastCharIndex = characterIndexes[glyphRange.length - 1]
    let charactersRange = NSRange(
      location: firstCharIndex, length: lastCharIndex - firstCharIndex + 1)

    var operationRanges: [(range: NSRange, operation: TextTransform)] = []
    var hasOperations = false

    textStorage.enumerateAttribute(.textTransform, in: charactersRange, options: []) {
      attributeValue, range, _ in
      let transform =
        TextTransform(rawValue: attributeValue as? String ?? TextTransform.none.rawValue) ?? .none
      operationRanges.append((range: range, operation: transform))
      if transform != .none {
        hasOperations = true
      }
    }

    // Bail if no operations. Returning 0 tells NSLayoutManager to use its default implementation
    if !hasOperations {
      return 0
    }

    var operationResults:
      [(glyphs: [CGGlyph], properties: [NSLayoutManager.GlyphProperty], characterIndexes: [Int])] =
        []
    var bufferLength = 0
    var locationWithinIncomingGlyphsRange = 0

    let textStorageString = textStorage.string as NSString
    let ctFont = font as CTFont

    for operationRange in operationRanges {
      // Derive the end location for the current string range in terms of the passed in glyph range
      var glyphSubrangeEnd = locationWithinIncomingGlyphsRange + operationRange.range.length
      while glyphSubrangeEnd < incomingGlyphsLength {
        let nextIndex = glyphSubrangeEnd + 1
        if nextIndex >= incomingGlyphsLength {
          break
        }
        let nextCharIndex = characterIndexes[nextIndex]
        if !operationRange.range.contains(nextCharIndex) {
          break
        }
        glyphSubrangeEnd += 1
      }
      let glyphSubrangeLength = glyphSubrangeEnd - locationWithinIncomingGlyphsRange

      if operationRange.operation == .none {
        // Copy the original glyphs from the input to this method
        let newGlyphs = Array(
          UnsafeBufferPointer(
            start: glyphs + locationWithinIncomingGlyphsRange, count: glyphSubrangeLength))
        let newProperties = Array(
          UnsafeBufferPointer(
            start: properties + locationWithinIncomingGlyphsRange, count: glyphSubrangeLength))
        let newCharIndexes = Array(
          UnsafeBufferPointer(
            start: characterIndexes + locationWithinIncomingGlyphsRange, count: glyphSubrangeLength)
        )

        operationResults.append(
          (glyphs: newGlyphs, properties: newProperties, characterIndexes: newCharIndexes))
        bufferLength += glyphSubrangeLength
      } else {
        // We now have a transform to do. Do it one character at a time.
        textStorageString.enumerateSubstrings(
          in: operationRange.range, options: .byComposedCharacterSequences
        ) { substring, substringRange, _, _ in
          guard let substring else {
            return
          }

          // Check if we are one half of a composed character
          let composedNormalisedRange = textStorageString.rangeOfComposedCharacterSequence(
            at: substringRange.location)
          if composedNormalisedRange != substringRange {
            // Can't upper or lower case half a character
            operationResults.append(
              (
                glyphs: [CGGlyph](repeating: CGGlyph(0), count: substringRange.length),
                properties: [NSLayoutManager.GlyphProperty](
                  repeating: .null, count: substringRange.length),
                characterIndexes: Array(
                  substringRange.location..<(substringRange.location + substringRange.length))
              ))
            bufferLength += substringRange.length
            return
          }

          // Apply case transform
          let modifiedSubstring =
            operationRange.operation == .lowercase ? substring.lowercased() : substring.uppercased()

          // Iterate through the new string
          let modifiedNSString = modifiedSubstring as NSString
          modifiedNSString.enumerateSubstrings(
            in: NSRange(location: 0, length: modifiedNSString.length),
            options: .byComposedCharacterSequences
          ) { innerSubstring, _, _, _ in
            guard let innerSubstring else {
              return
            }

            // Generate glyphs for the character
            let utf16 = Array(innerSubstring.utf16)
            var newGlyphs = [CGGlyph](repeating: 0, count: utf16.count)
            CTFontGetGlyphsForCharacters(ctFont, utf16, &newGlyphs, utf16.count)

            // Build glyph properties
            var newProperties = [NSLayoutManager.GlyphProperty](
              repeating: .init(rawValue: 0), count: utf16.count)
            if let firstChar = innerSubstring.first, firstChar.isWhitespace {
              newProperties = [NSLayoutManager.GlyphProperty](
                repeating: .elastic, count: utf16.count)
            }
            if utf16.count > 1 {
              for i in 1..<utf16.count {
                newProperties[i] = .nonBaseCharacter
              }
            }

            // Fill in character indexes
            var newCharIndexes = [Int](repeating: 0, count: newGlyphs.count)
            for i in 0..<min(substringRange.length, newGlyphs.count) {
              newCharIndexes[i] = i + substringRange.location
            }
            // If we have extra glyphs, repeat the last character index
            if substringRange.length < newGlyphs.count {
              for i in substringRange.length..<newGlyphs.count {
                newCharIndexes[i] = substringRange.upperBound - 1
              }
            }

            operationResults.append(
              (glyphs: newGlyphs, properties: newProperties, characterIndexes: newCharIndexes))
            bufferLength += newGlyphs.count
          }
        }
      }
      locationWithinIncomingGlyphsRange += glyphSubrangeLength
    }

    let sumGlyphs = operationResults.flatMap { $0.glyphs }
    let sumProps = operationResults.flatMap { $0.properties }
    let sumCharacterIndexes = operationResults.flatMap { $0.characterIndexes }

    guard !sumGlyphs.isEmpty else { return 0 }

    var fail = false
    sumGlyphs.withUnsafeBufferPointer { sumGlyphsBuffer in
      sumProps.withUnsafeBufferPointer { sumPropsBuffer in
        sumCharacterIndexes.withUnsafeBufferPointer { sumCharsBuffer in
          guard let sumGlyphsBaseAddress = sumGlyphsBuffer.baseAddress,
                let sumPropsBaseAddress = sumPropsBuffer.baseAddress,
                let sumCharsBaseAddress = sumCharsBuffer.baseAddress
          else {
            fail = true
            return
          }
          layoutManager.setGlyphs(
            sumGlyphsBaseAddress,
            properties: sumPropsBaseAddress,
            characterIndexes: sumCharsBaseAddress,
            font: font,
            forGlyphRange: NSRange(location: glyphRange.location, length: bufferLength)
          )
        }
      }
    }

    return fail ? 0 : bufferLength
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
