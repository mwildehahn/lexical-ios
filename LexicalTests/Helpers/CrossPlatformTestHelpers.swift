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
