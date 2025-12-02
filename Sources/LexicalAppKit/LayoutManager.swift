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

  public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    // Custom drawing hooks can be added here when needed
  }

  public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    positionAllDecorators()
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

    // Force layout if glyph isn't laid out yet
    if !glyphIsInTextContainer {
      ensureLayout(forGlyphRange: NSRange(location: glyphIndex, length: 1))
      glyphIsInTextContainer = NSLocationInRange(glyphIndex, glyphRange(for: textContainer))
    }

    let shouldHideView: Bool = !glyphIsInTextContainer

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

    try? attachmentEditor.read {
      if attachmentEditor.featureFlags.verboseLogging {
        print("🔥 DEC-LM: key=\(attachmentKey) charIndex=\(characterIndex) glyphIndex=\(glyphIndex) inContainer=\(glyphIsInTextContainer) hide=\(shouldHideView) ts.len=\(textStorage.length)")
      }

      // Decorator view handling would go here
      // For now, this is a stub for when decorator views are implemented
      if attachmentEditor.featureFlags.verboseLogging {
        print("🔥 DEC-LM: decorator positioning stub for key=\(attachmentKey)")
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
