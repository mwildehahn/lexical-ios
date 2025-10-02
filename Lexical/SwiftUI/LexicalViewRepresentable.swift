/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(SwiftUI)
import SwiftUI

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper for LexicalView providing cross-platform editor support.
///
/// `LexicalEditor` provides a unified SwiftUI API for using Lexical on both iOS and macOS.
/// On iOS, it wraps `LexicalView` (UIView-based), and on macOS it wraps `LexicalView` (NSView-based).
///
/// ## Usage
/// ```swift
/// struct ContentView: View {
///     @State private var text = ""
///
///     var body: some View {
///         LexicalEditor(
///             editorConfig: EditorConfig(theme: Theme(), plugins: []),
///             featureFlags: FeatureFlags(),
///             placeholderText: LexicalPlaceholderText(
///                 text: "Start typing...",
///                 font: .systemFont(ofSize: 14),
///                 color: .placeholderTextColor
///             ),
///             text: $text
///         )
///     }
/// }
/// ```
///
/// - Note: Available on iOS 17.0+ and macOS 14.0+. The same code works on both platforms.
@available(iOS 17.0, *)
public struct LexicalEditor: UIViewRepresentable {
  public typealias UIViewType = LexicalView

  private let editorConfig: EditorConfig
  private let featureFlags: FeatureFlags
  private let placeholderText: LexicalPlaceholderText?

  @Binding private var text: String

  /// Creates a LexicalEditor with the specified configuration
  ///
  /// - Parameters:
  ///   - editorConfig: Configuration for the editor (theme, plugins, etc.)
  ///   - featureFlags: Feature flags for experimental features
  ///   - placeholderText: Optional placeholder text shown when editor is empty
  ///   - text: Binding to the editor's text content
  public init(
    editorConfig: EditorConfig,
    featureFlags: FeatureFlags = FeatureFlags(),
    placeholderText: LexicalPlaceholderText? = nil,
    text: Binding<String> = .constant("")
  ) {
    self.editorConfig = editorConfig
    self.featureFlags = featureFlags
    self.placeholderText = placeholderText
    self._text = text
  }

  public func makeUIView(context: Context) -> LexicalView {
    let lexicalView = LexicalView(
      editorConfig: editorConfig,
      featureFlags: featureFlags,
      placeholderText: placeholderText
    )

    lexicalView.delegate = context.coordinator

    // Set initial text if provided
    if !text.isEmpty {
      do {
        try lexicalView.editor.update {
          guard let root = getRoot() else { return }
          let paragraph = ParagraphNode()
          let textNode = TextNode(text: text)
          try paragraph.append([textNode])
          try root.append([paragraph])
        }
      } catch {
        print("LexicalEditor: Error setting initial text: \(error)")
      }
    }

    return lexicalView
  }

  public func updateUIView(_ uiView: LexicalView, context: Context) {
    // Update view if needed
    // For now, we don't need to update anything as the editor manages its own state
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  public class Coordinator: NSObject, LexicalViewDelegate {
    @Binding var text: String

    init(text: Binding<String>) {
      self._text = text
    }

    public func textViewDidBeginEditing(textView: LexicalView) {
      // Handle begin editing
    }

    public func textViewDidEndEditing(textView: LexicalView) {
      // Handle end editing
      // Update text binding
      Task { @MainActor in
        text = textView.text
      }
    }

    public func textViewShouldChangeText(
      _ textView: LexicalView, range: NSRange, replacementText text: String
    ) -> Bool {
      return true
    }

    public func textView(
      _ textView: LexicalView, shouldInteractWith URL: URL, in selection: RangeSelection?,
      interaction: UITextItemInteraction
    ) -> Bool {
      return true
    }
  }
}

#elseif canImport(AppKit)
import AppKit

/// SwiftUI wrapper for LexicalView providing cross-platform editor support.
///
/// `LexicalEditor` provides a unified SwiftUI API for using Lexical on both iOS and macOS.
/// On iOS, it wraps `LexicalView` (UIView-based), and on macOS it wraps `LexicalView` (NSView-based).
///
/// ## Usage
/// ```swift
/// struct ContentView: View {
///     @State private var text = ""
///
///     var body: some View {
///         LexicalEditor(
///             editorConfig: EditorConfig(theme: Theme(), plugins: []),
///             featureFlags: FeatureFlags(),
///             placeholderText: LexicalPlaceholderText(
///                 text: "Start typing...",
///                 font: .systemFont(ofSize: 14),
///                 color: .placeholderTextColor
///             ),
///             text: $text
///         )
///     }
/// }
/// ```
///
/// - Note: Available on iOS 17.0+ and macOS 14.0+. The same code works on both platforms.
@available(macOS 14.0, *)
public struct LexicalEditor: NSViewRepresentable {
  public typealias NSViewType = LexicalView

  private let editorConfig: EditorConfig
  private let featureFlags: FeatureFlags
  private let placeholderText: LexicalPlaceholderText?

  @Binding private var text: String

  /// Creates a LexicalEditor with the specified configuration
  ///
  /// - Parameters:
  ///   - editorConfig: Configuration for the editor (theme, plugins, etc.)
  ///   - featureFlags: Feature flags for experimental features
  ///   - placeholderText: Optional placeholder text shown when editor is empty
  ///   - text: Binding to the editor's text content
  public init(
    editorConfig: EditorConfig,
    featureFlags: FeatureFlags = FeatureFlags(),
    placeholderText: LexicalPlaceholderText? = nil,
    text: Binding<String> = .constant("")
  ) {
    self.editorConfig = editorConfig
    self.featureFlags = featureFlags
    self.placeholderText = placeholderText
    self._text = text
  }

  public func makeNSView(context: Context) -> LexicalView {
    let lexicalView = LexicalView(
      editorConfig: editorConfig,
      featureFlags: featureFlags,
      placeholderText: placeholderText
    )

    lexicalView.delegate = context.coordinator

    // Set initial text if provided
    if !text.isEmpty {
      do {
        try lexicalView.editor.update {
          guard let root = getRoot() else { return }
          let paragraph = ParagraphNode()
          let textNode = TextNode(text: text)
          try paragraph.append([textNode])
          try root.append([paragraph])
        }
      } catch {
        print("LexicalEditor: Error setting initial text: \(error)")
      }
    }

    return lexicalView
  }

  public func updateNSView(_ nsView: LexicalView, context: Context) {
    // Update view if needed
    // For now, we don't need to update anything as the editor manages its own state
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  public class Coordinator: NSObject, LexicalViewDelegate {
    @Binding var text: String

    init(text: Binding<String>) {
      self._text = text
    }

    public func textViewDidBeginEditing(textView: LexicalView) {
      // Handle begin editing
    }

    public func textViewDidEndEditing(textView: LexicalView) {
      // Handle end editing
      // Update text binding
      Task { @MainActor in
        text = textView.text
      }
    }

    public func textViewShouldChangeText(
      _ textView: LexicalView, range: NSRange, replacementText text: String
    ) -> Bool {
      return true
    }

    public func textView(
      _ textView: LexicalView, shouldInteractWith URL: URL, in selection: RangeSelection?
    ) -> Bool {
      return true
    }
  }
}
#endif

#endif
