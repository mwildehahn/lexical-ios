/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

/// Cross-platform test view wrapper that provides access to an Editor for testing.
///
/// This abstraction allows tests to run on both iOS and macOS by using the
/// appropriate LexicalView implementation for each platform.
@MainActor
class TestEditorView {
  #if os(macOS) && !targetEnvironment(macCatalyst)
  private let lexicalView: LexicalAppKit.LexicalView

  init(editorConfig: EditorConfig = EditorConfig(theme: Theme(), plugins: []),
       featureFlags: FeatureFlags = FeatureFlags()) {
    self.lexicalView = LexicalAppKit.LexicalView(
      editorConfig: editorConfig,
      featureFlags: featureFlags
    )
  }

  var editor: Editor {
    lexicalView.editor
  }

  var view: LexicalAppKit.LexicalView {
    lexicalView
  }
  #else
  private let lexicalView: Lexical.LexicalView

  init(editorConfig: EditorConfig = EditorConfig(theme: Theme(), plugins: []),
       featureFlags: FeatureFlags = FeatureFlags()) {
    self.lexicalView = Lexical.LexicalView(
      editorConfig: editorConfig,
      featureFlags: featureFlags
    )
  }

  var editor: Editor {
    lexicalView.editor
  }

  var view: Lexical.LexicalView {
    lexicalView
  }
  #endif

  // MARK: - Composition/IME Helpers

  /// The current attributed text string from the text view.
  var attributedTextString: String {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    return lexicalView.textView.attributedString().string
    #else
    return lexicalView.textView.attributedText?.string ?? ""
    #endif
  }

  /// The length of the attributed text.
  var attributedTextLength: Int {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    return lexicalView.textView.attributedString().length
    #else
    return lexicalView.textView.attributedText?.length ?? 0
    #endif
  }

  /// Set the selected range in the text view.
  func setSelectedRange(_ range: NSRange) {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    lexicalView.textView.setSelectedRange(range)
    #else
    lexicalView.textView.selectedRange = range
    #endif
  }

  /// Get the current selected range.
  var selectedRange: NSRange {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    return lexicalView.textView.selectedRange()
    #else
    return lexicalView.textView.selectedRange
    #endif
  }

  /// Set marked text (IME composition).
  /// - Parameters:
  ///   - text: The marked text string
  ///   - selectedRange: The selection within the marked text
  func setMarkedText(_ text: String, selectedRange: NSRange) {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    // AppKit needs replacementRange - use the current selection or marked range
    let replacement = lexicalView.textView.markedRange().location != NSNotFound
      ? lexicalView.textView.markedRange()
      : lexicalView.textView.selectedRange()
    lexicalView.textView.setMarkedText(text, selectedRange: selectedRange, replacementRange: replacement)
    #else
    lexicalView.textView.setMarkedText(text, selectedRange: selectedRange)
    #endif
  }

  /// Unmark the currently marked text (end IME composition).
  func unmarkText() {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    lexicalView.textView.unmarkText()
    #else
    lexicalView.textView.unmarkText()
    #endif
  }

  /// Whether there is currently marked text (active IME composition).
  var hasMarkedText: Bool {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    return lexicalView.textView.markedRange().location != NSNotFound
    #else
    return lexicalView.markedTextRange != nil
    #endif
  }

  /// Insert text at the current selection, replacing any selected text.
  func insertText(_ text: String) {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    // On AppKit, use insertText with the current selection as replacement range
    // This properly goes through Lexical's text input handling
    lexicalView.textView.insertText(text, replacementRange: lexicalView.textView.selectedRange())
    #else
    lexicalView.textView.insertText(text)
    #endif
  }

  /// The plain text content of the text view.
  var text: String {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    return lexicalView.textView.string
    #else
    return lexicalView.textView.text ?? ""
    #endif
  }

  /// Delete backward (like pressing backspace).
  func deleteBackward() {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    lexicalView.textView.deleteBackward(nil)
    #else
    lexicalView.textView.deleteBackward()
    #endif
  }

  /// Delete forward (like pressing delete key).
  func deleteForward() {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    lexicalView.textView.deleteForward(nil)
    #else
    // UITextView doesn't have deleteForward, simulate with selection
    let range = lexicalView.textView.selectedRange
    if range.length == 0 && range.location < (lexicalView.textView.text?.count ?? 0) {
      lexicalView.textView.selectedRange = NSRange(location: range.location, length: 1)
      lexicalView.textView.insertText("")
    }
    #endif
  }

  /// The text storage length.
  var textStorageLength: Int {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    return lexicalView.textView.textStorage?.length ?? 0
    #else
    return lexicalView.textView.textStorage.length
    #endif
  }
}

/// Convenience function to create a test editor view with default configuration.
@MainActor
func createTestEditorView(
  theme: Theme = Theme(),
  plugins: [Plugin] = [],
  featureFlags: FeatureFlags = FeatureFlags()
) -> TestEditorView {
  return TestEditorView(
    editorConfig: EditorConfig(theme: theme, plugins: plugins),
    featureFlags: featureFlags
  )
}

/// Convenience function to create a test editor view with optimized reconciler.
@MainActor
func createOptimizedTestEditorView(
  theme: Theme = Theme(),
  plugins: [Plugin] = []
) -> TestEditorView {
  return TestEditorView(
    editorConfig: EditorConfig(theme: theme, plugins: plugins),
    featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor)
  )
}
