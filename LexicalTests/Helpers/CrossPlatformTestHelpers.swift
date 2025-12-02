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
