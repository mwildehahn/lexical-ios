/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical

// MARK: - NSTextInputClient Extensions

/// Extensions for NSTextInputClient support.
///
/// NSTextView already conforms to NSTextInputClient, so we override methods
/// where we need custom behavior for Lexical integration.
extension TextViewAppKit {

  // MARK: - Text Insertion

  /// Override insertText to integrate with Lexical's text handling.
  ///
  /// This is called when the user types text or completes IME input.
  public override func insertText(_ string: Any, replacementRange: NSRange) {
    // Get the string value
    let text: String
    switch string {
    case let s as String:
      text = s
    case let attr as NSAttributedString:
      text = attr.string
    default:
      return
    }

    // Check if delegate allows the change
    let range = replacementRange.location != NSNotFound
      ? replacementRange
      : selectedRange()

    guard lexicalDelegate?.textViewShouldChangeText(self, range: range, replacementText: text) ?? true else {
      return
    }

    // Dispatch Lexical command for text insertion
    editor.dispatchCommand(type: .insertText, payload: text)

    // Update placeholder visibility
    updatePlaceholderVisibility()
  }

  // MARK: - Marked Text (IME Composition)

  /// Override setMarkedText to track IME composition state.
  ///
  /// Marked text is displayed during IME composition (e.g., typing Japanese).
  public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)

    // Track composition state for Lexical
    // Editor's compositionKey handling will be integrated here
  }

  /// Override unmarkText to clear IME composition state.
  public override func unmarkText() {
    super.unmarkText()
    // Clear composition state
  }

  // MARK: - Attributed String Access

  /// Returns an attributed substring for the proposed range.
  ///
  /// Used by the input system to get context for IME and other input methods.
  public override func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
    // Validate range
    guard range.location != NSNotFound,
          let textStorage = textStorage,
          range.location + range.length <= textStorage.length else {
      return nil
    }

    actualRange?.pointee = range
    return textStorage.attributedSubstring(from: range)
  }

  /// Returns the valid attributes for marked text.
  ///
  /// These attributes can be applied to marked text during IME composition.
  public override func validAttributesForMarkedText() -> [NSAttributedString.Key] {
    return [
      .underlineStyle,
      .underlineColor,
      .backgroundColor,
      .foregroundColor
    ]
  }

  // MARK: - Geometry

  /// Returns the rect for a character range in screen coordinates.
  ///
  /// Used for positioning IME candidate windows and other UI elements.
  public override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    // Get the rect from the layout manager
    guard let layoutManager = layoutManager,
          let textContainer = textContainer else {
      return .zero
    }

    actualRange?.pointee = range

    // Get the glyph range for the character range
    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

    // Get the bounding rect
    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

    // Adjust for text container inset
    rect.origin.x += textContainerInset.width
    rect.origin.y += textContainerInset.height

    // Convert to window coordinates
    rect = convert(rect, to: nil)

    // Convert to screen coordinates
    if let window = window {
      rect = window.convertToScreen(rect)
    }

    return rect
  }

  /// Returns the character index for a point in screen coordinates.
  ///
  /// Used for positioning the cursor based on mouse or IME input.
  public override func characterIndex(for point: NSPoint) -> Int {
    guard let window = window,
          let layoutManager = layoutManager,
          let textContainer = textContainer else {
      return NSNotFound
    }

    // Convert from screen to window coordinates
    let windowPoint = window.convertPoint(fromScreen: point)

    // Convert to view coordinates
    var viewPoint = convert(windowPoint, from: nil)

    // Adjust for text container inset
    viewPoint.x -= textContainerInset.width
    viewPoint.y -= textContainerInset.height

    // Get the character index
    let glyphIndex = layoutManager.glyphIndex(for: viewPoint, in: textContainer)
    return layoutManager.characterIndexForGlyph(at: glyphIndex)
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
