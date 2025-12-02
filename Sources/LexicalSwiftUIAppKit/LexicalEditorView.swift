/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)

import Foundation
import SwiftUI
import AppKit
import Lexical
import LexicalAppKit

/// A SwiftUI view that wraps the Lexical rich text editor for macOS.
///
/// Example usage:
/// ```swift
/// struct ContentView: View {
///   var body: some View {
///     LexicalEditorView(
///       config: EditorConfig(theme: Theme(), plugins: []),
///       onEditorReady: { editor in
///         // Configure editor
///       }
///     )
///   }
/// }
/// ```
@MainActor @preconcurrency
public struct LexicalEditorView: SwiftUI.View {

  /// Configuration options for the editor.
  public struct Options: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    /// Makes the editor read-only.
    public static let readOnly = Options(rawValue: 1 << 0)
  }

  private let config: EditorConfig
  private let featureFlags: FeatureFlags
  private let options: Options
  private let onEditorReady: ((Editor) -> Void)?
  private let placeholderText: LexicalPlaceholderText?

  /// Creates a new Lexical editor view.
  ///
  /// - Parameters:
  ///   - config: The editor configuration including theme and plugins.
  ///   - featureFlags: Feature flags for editor behavior.
  ///   - options: Editor options like read-only mode.
  ///   - placeholderText: Optional placeholder text configuration.
  ///   - onEditorReady: Callback when the editor is initialized.
  public init(
    config: EditorConfig,
    featureFlags: FeatureFlags = FeatureFlags(),
    options: Options = [],
    placeholderText: LexicalPlaceholderText? = nil,
    onEditorReady: ((Editor) -> Void)? = nil
  ) {
    self.config = config
    self.featureFlags = featureFlags
    self.options = options
    self.placeholderText = placeholderText
    self.onEditorReady = onEditorReady
  }

  public var body: some View {
    LexicalEditorViewRepresentable(
      config: config,
      featureFlags: featureFlags,
      options: options,
      placeholderText: placeholderText,
      onEditorReady: onEditorReady
    )
  }
}

// MARK: - NSViewRepresentable

private struct LexicalEditorViewRepresentable: NSViewRepresentable {
  @Environment(\.isEnabled) private var isEnabled

  let config: EditorConfig
  let featureFlags: FeatureFlags
  let options: LexicalEditorView.Options
  let placeholderText: LexicalPlaceholderText?
  let onEditorReady: ((Editor) -> Void)?

  func makeNSView(context: Context) -> LexicalView {
    let lexicalView = LexicalView(
      editorConfig: config,
      featureFlags: featureFlags,
      placeholderText: placeholderText
    )

    // Set initial editable state
    let shouldBeEditable = !options.contains(.readOnly) && isEnabled
    lexicalView.textView.isEditable = shouldBeEditable

    // Set delegate
    lexicalView.delegate = context.coordinator

    // Notify that editor is ready
    onEditorReady?(lexicalView.editor)

    return lexicalView
  }

  func updateNSView(_ lexicalView: LexicalView, context: Context) {
    // Update editable state
    let shouldBeEditable = !options.contains(.readOnly) && isEnabled
    if lexicalView.textView.isEditable != shouldBeEditable {
      lexicalView.textView.isEditable = shouldBeEditable
    }

    // Request layout update
    lexicalView.needsLayout = true
    lexicalView.needsDisplay = true
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator: NSObject, LexicalViewDelegate {
    func textViewDidBeginEditing(textView: LexicalView) {}
    func textViewDidEndEditing(textView: LexicalView) {}
    func textViewShouldChangeText(_ textView: LexicalView, range: NSRange, replacementText text: String) -> Bool {
      return true
    }
    func textView(_ textView: LexicalView, shouldInteractWith URL: URL, in selection: RangeSelection?) -> Bool {
      return true
    }
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
