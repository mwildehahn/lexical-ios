/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(UIKit) && !os(watchOS)

import Foundation
import SwiftUI
import UIKit
import Lexical

/// A SwiftUI view that wraps the Lexical rich text editor for iOS.
///
/// Example usage:
/// ```swift
/// struct ContentView: View {
///   @State private var editorState: EditorState?
///
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

// MARK: - UIViewRepresentable

private struct LexicalEditorViewRepresentable: UIViewRepresentable {
  @Environment(\.isEnabled) private var isEnabled

  let config: EditorConfig
  let featureFlags: FeatureFlags
  let options: LexicalEditorView.Options
  let placeholderText: LexicalPlaceholderText?
  let onEditorReady: ((Editor) -> Void)?

  func makeUIView(context: Context) -> LexicalView {
    let lexicalView = LexicalView(
      editorConfig: config,
      featureFlags: featureFlags
    )

    // Configure placeholder
    if let placeholder = placeholderText {
      lexicalView.placeholderText = placeholder
    }

    // Set initial editable state
    lexicalView.textView.isEditable = !options.contains(.readOnly) && isEnabled

    // Notify that editor is ready (deferred to allow view setup to complete)
    if let callback = onEditorReady {
      DispatchQueue.main.async {
        callback(lexicalView.editor)
      }
    }

    return lexicalView
  }

  func updateUIView(_ lexicalView: LexicalView, context: Context) {
    // Update editable state
    let shouldBeEditable = !options.contains(.readOnly) && isEnabled
    if lexicalView.textView.isEditable != shouldBeEditable {
      lexicalView.textView.isEditable = shouldBeEditable
    }
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
  }
}

#endif // canImport(UIKit) && !os(watchOS)
