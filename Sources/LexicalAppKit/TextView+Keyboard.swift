/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical

// MARK: - Keyboard Handling

/// Keyboard handling extensions for TextViewAppKit.
///
/// NSTextView provides comprehensive keyboard handling through the responder chain.
/// This extension overrides key methods to integrate with Lexical and manage
/// placeholder visibility.
extension TextViewAppKit {

  // MARK: - Key Down

  /// Override keyDown to integrate with Lexical's input system.
  public override func keyDown(with event: NSEvent) {
    guard isEditable else {
      super.keyDown(with: event)
      return
    }

    // Hide cursor while typing
    NSCursor.setHiddenUntilMouseMoves(true)

    // Let the input context handle the event first (for IME)
    // If not handled, interpret the key event
    if inputContext?.handleEvent(event) == false {
      interpretKeyEvents([event])
    }
  }

  // MARK: - Key Equivalents

  /// Handle key equivalents (keyboard shortcuts).
  public override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isEditable else {
      return super.performKeyEquivalent(with: event)
    }

    // Let NSTextView handle standard shortcuts (Cmd+C, Cmd+V, etc.)
    return super.performKeyEquivalent(with: event)
  }

  // MARK: - Deletion

  /// Delete backward (Backspace key).
  public override func deleteBackward(_ sender: Any?) {
    super.deleteBackward(sender)
    updatePlaceholderVisibility()
  }

  /// Delete forward (Delete key).
  public override func deleteForward(_ sender: Any?) {
    super.deleteForward(sender)
    updatePlaceholderVisibility()
  }

  /// Delete word backward (Option+Backspace).
  public override func deleteWordBackward(_ sender: Any?) {
    super.deleteWordBackward(sender)
    updatePlaceholderVisibility()
  }

  /// Delete word forward (Option+Delete).
  public override func deleteWordForward(_ sender: Any?) {
    super.deleteWordForward(sender)
    updatePlaceholderVisibility()
  }

  /// Delete to beginning of line (Cmd+Backspace).
  public override func deleteToBeginningOfLine(_ sender: Any?) {
    super.deleteToBeginningOfLine(sender)
    updatePlaceholderVisibility()
  }

  /// Delete to end of line (Cmd+Delete / Ctrl+K).
  public override func deleteToEndOfLine(_ sender: Any?) {
    super.deleteToEndOfLine(sender)
    updatePlaceholderVisibility()
  }

  // MARK: - Newlines and Tabs

  /// Insert newline (Return/Enter key).
  public override func insertNewline(_ sender: Any?) {
    super.insertNewline(sender)
    updatePlaceholderVisibility()
  }

  /// Insert newline ignoring field editor (Option+Return).
  public override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
    super.insertNewlineIgnoringFieldEditor(sender)
    updatePlaceholderVisibility()
  }

  /// Insert tab.
  public override func insertTab(_ sender: Any?) {
    super.insertTab(sender)
    updatePlaceholderVisibility()
  }

  /// Insert back tab (Shift+Tab).
  public override func insertBacktab(_ sender: Any?) {
    super.insertBacktab(sender)
    updatePlaceholderVisibility()
  }

  // MARK: - Cut/Paste Operations

  /// Cut operation.
  public override func cut(_ sender: Any?) {
    super.cut(sender)
    updatePlaceholderVisibility()
  }

  /// Paste operation.
  public override func paste(_ sender: Any?) {
    super.paste(sender)
    updatePlaceholderVisibility()
  }

  /// Paste as plain text.
  public override func pasteAsPlainText(_ sender: Any?) {
    super.pasteAsPlainText(sender)
    updatePlaceholderVisibility()
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
