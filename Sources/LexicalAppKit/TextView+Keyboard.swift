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
    // Dispatch Lexical command
    editor.dispatchCommand(type: .deleteCharacter, payload: true)
    updatePlaceholderVisibility()
  }

  /// Delete forward (Delete key).
  public override func deleteForward(_ sender: Any?) {
    // Dispatch Lexical command (isBackwards: false)
    editor.dispatchCommand(type: .deleteCharacter, payload: false)
    updatePlaceholderVisibility()
  }

  /// Delete word backward (Option+Backspace).
  public override func deleteWordBackward(_ sender: Any?) {
    // Dispatch Lexical command
    editor.dispatchCommand(type: .deleteWord, payload: true)
    updatePlaceholderVisibility()
  }

  /// Delete word forward (Option+Delete).
  public override func deleteWordForward(_ sender: Any?) {
    // Dispatch Lexical command (isBackwards: false)
    editor.dispatchCommand(type: .deleteWord, payload: false)
    updatePlaceholderVisibility()
  }

  /// Delete to beginning of line (Cmd+Backspace).
  public override func deleteToBeginningOfLine(_ sender: Any?) {
    // Dispatch Lexical command
    editor.dispatchCommand(type: .deleteLine, payload: true)
    updatePlaceholderVisibility()
  }

  /// Delete to end of line (Cmd+Delete / Ctrl+K).
  public override func deleteToEndOfLine(_ sender: Any?) {
    // Dispatch Lexical command (isBackwards: false)
    editor.dispatchCommand(type: .deleteLine, payload: false)
    updatePlaceholderVisibility()
  }

  // MARK: - Newlines and Tabs

  /// Insert newline (Return/Enter key).
  public override func insertNewline(_ sender: Any?) {
    // Dispatch Lexical command for paragraph insertion
    editor.dispatchCommand(type: .insertParagraph, payload: nil)
    updatePlaceholderVisibility()
  }

  /// Insert newline ignoring field editor (Option+Return).
  public override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
    // Dispatch Lexical command for line break insertion
    editor.dispatchCommand(type: .insertLineBreak, payload: nil)
    updatePlaceholderVisibility()
  }

  /// Insert tab.
  public override func insertTab(_ sender: Any?) {
    // Dispatch indent command or insert tab character
    editor.dispatchCommand(type: .keyTab, payload: nil)
    updatePlaceholderVisibility()
  }

  /// Insert back tab (Shift+Tab).
  public override func insertBacktab(_ sender: Any?) {
    // Dispatch outdent command
    editor.dispatchCommand(type: .keyTab, payload: true) // payload=true for shift+tab
    updatePlaceholderVisibility()
  }

  // Cut/paste operations are in CopyPasteHelpers.swift
  // Text insertion is in TextView+NSTextInputClient.swift
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
