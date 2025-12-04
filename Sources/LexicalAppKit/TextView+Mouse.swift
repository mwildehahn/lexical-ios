/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical

// MARK: - Mouse Handling

/// Mouse handling extensions for TextViewAppKit.
///
/// NSTextView provides comprehensive mouse handling. This extension adds
/// Lexical-specific behaviors like link clicking and decorator interaction.
extension TextViewAppKit {

  // MARK: - Mouse Down

  /// Handle mouse down events.
  ///
  /// NSTextView handles selection, but we intercept for:
  /// - Link clicks
  /// - Decorator node interaction
  public override func mouseDown(with event: NSEvent) {
    // Let input context handle IME-related events
    if inputContext?.handleEvent(event) == true {
      return
    }

    guard isSelectable else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)

    // Check for link click (Cmd+click or regular click on link)
    if event.modifierFlags.contains(.command) || event.clickCount == 1 {
      if handleLinkClick(at: point, event: event) {
        return
      }
    }

    // Let NSTextView handle normal selection
    super.mouseDown(with: event)

    // Notify about selection change after mouse down
    handleSelectionChange()
  }

  // MARK: - Mouse Dragged

  /// Handle mouse drag for selection extension.
  public override func mouseDragged(with event: NSEvent) {
    if inputContext?.handleEvent(event) == true {
      return
    }

    super.mouseDragged(with: event)
  }

  // MARK: - Mouse Up

  /// Handle mouse up events.
  public override func mouseUp(with event: NSEvent) {
    if inputContext?.handleEvent(event) == true {
      return
    }

    super.mouseUp(with: event)

    // Notify about final selection after mouse up
    handleSelectionChange()
  }

  // MARK: - Double/Triple Click

  /// NSTextView handles double-click (select word) and triple-click (select paragraph)
  /// automatically. We just need to track selection changes.

  // MARK: - Right Click (Context Menu)

  /// Handle right-click for context menu.
  public override func rightMouseDown(with event: NSEvent) {
    // Position cursor at click if no selection
    if selectedRange().length == 0 {
      let point = convert(event.locationInWindow, from: nil)
      let characterIndex = characterIndexForInsertion(at: point)
      if characterIndex != NSNotFound {
        setSelectedRange(NSRange(location: characterIndex, length: 0))
      }
    }

    super.rightMouseDown(with: event)
  }

  // MARK: - Link Handling

  /// Handle a click on a link.
  ///
  /// - Parameters:
  ///   - point: The click location in view coordinates.
  ///   - event: The mouse event.
  /// - Returns: Whether a link was clicked and handled.
  private func handleLinkClick(at point: NSPoint, event: NSEvent) -> Bool {
    guard let textStorage = textStorage,
          let layoutManager = layoutManager,
          let textContainer = textContainer else {
      return false
    }

    // Adjust point for text container inset
    var adjustedPoint = point
    adjustedPoint.x -= textContainerInset.width
    adjustedPoint.y -= textContainerInset.height

    // Get character index at point
    let glyphIndex = layoutManager.glyphIndex(for: adjustedPoint, in: textContainer)
    let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

    guard charIndex < textStorage.length else {
      return false
    }

    // Check for link attribute
    var effectiveRange = NSRange()
    guard let linkValue = textStorage.attribute(.link, at: charIndex, effectiveRange: &effectiveRange) else {
      return false
    }

    // Get the URL
    let url: URL?
    switch linkValue {
    case let urlValue as URL:
      url = urlValue
    case let stringValue as String:
      url = URL(string: stringValue)
    default:
      url = nil
    }

    guard let url = url else {
      return false
    }

    // Open the link
    NSWorkspace.shared.open(url)
    return true
  }

  // MARK: - Cursor

  /// Reset the cursor rect for proper cursor display.
  public override func resetCursorRects() {
    super.resetCursorRects()

    // Add I-beam cursor for text area
    if isEditable || isSelectable {
      addCursorRect(bounds, cursor: .iBeam)
    }
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
