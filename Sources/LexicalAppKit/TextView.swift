/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical

// MARK: - TextViewAppKitDelegate

/// Internal delegate protocol for TextViewAppKit events.
@MainActor
protocol TextViewAppKitDelegate: AnyObject {
  func textViewDidBeginEditing(textView: TextViewAppKit)
  func textViewDidEndEditing(textView: TextViewAppKit)
  func textViewShouldChangeText(
    _ textView: TextViewAppKit,
    range: NSRange,
    replacementText text: String
  ) -> Bool
}

// MARK: - TextViewAppKit

/// Lexical's NSTextView subclass for macOS.
///
/// This class provides the AppKit equivalent of the UIKit TextView class,
/// handling text input, selection, and integration with the Lexical editor.
@MainActor
public class TextViewAppKit: NSTextView {

  // MARK: - Properties

  /// The Lexical editor instance.
  public let editor: Editor

  /// The custom text storage for Lexical.
  let lexicalTextStorage: TextStorageAppKit

  /// The custom layout manager.
  let lexicalLayoutManager: NSLayoutManager

  /// Flag indicating if we're programmatically updating selection.
  internal var isUpdatingNativeSelection = false

  /// Range to intercept next selection change with.
  internal var interceptNextSelectionChangeAndReplaceWithRange: NSRange?

  /// Internal delegate for forwarding events.
  weak var lexicalDelegate: TextViewAppKitDelegate?

  /// Placeholder label for empty state.
  private var placeholderTextField: NSTextField?

  /// Placeholder text configuration.
  private var placeholderTextValue: String = ""
  private var placeholderColor: NSColor = .placeholderTextColor
  private var placeholderFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)

  // MARK: - Initialization

  /// Creates a new TextViewAppKit with the specified configuration.
  ///
  /// - Parameters:
  ///   - editorConfig: Configuration for the Lexical editor.
  ///   - featureFlags: Feature flags controlling editor behavior.
  public init(editorConfig: EditorConfig, featureFlags: FeatureFlags) {
    // Create custom text storage
    self.lexicalTextStorage = TextStorageAppKit()

    // Create layout manager
    self.lexicalLayoutManager = NSLayoutManager()
    lexicalTextStorage.addLayoutManager(lexicalLayoutManager)

    // Create text container
    let textContainer = NSTextContainer(size: NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    ))
    textContainer.widthTracksTextView = true
    lexicalLayoutManager.addTextContainer(textContainer)

    // Create editor
    self.editor = Editor(editorConfig: editorConfig)
    self.editor.featureFlags = featureFlags

    // Connect editor to text storage
    lexicalTextStorage.editor = editor

    super.init(frame: .zero, textContainer: textContainer)

    // Configure the text view
    configureTextView()

    // Set up placeholder
    setupPlaceholder()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Configuration

  private func configureTextView() {
    // Basic configuration
    isEditable = true
    isSelectable = true
    isRichText = true
    allowsUndo = true
    usesFontPanel = false
    usesRuler = false

    // Appearance
    drawsBackground = true
    backgroundColor = .textBackgroundColor

    // Text container inset
    textContainerInset = NSSize(width: 5, height: 8)

    // Enable automatic spelling and grammar checking (optional)
    isContinuousSpellCheckingEnabled = false
    isGrammarCheckingEnabled = false

    // Delegate
    delegate = self
  }

  private func setupPlaceholder() {
    let placeholder = NSTextField(labelWithString: "")
    placeholder.isEditable = false
    placeholder.isSelectable = false
    placeholder.isBordered = false
    placeholder.drawsBackground = false
    placeholder.textColor = placeholderColor
    placeholder.font = placeholderFont
    placeholder.alphaValue = 0.0
    addSubview(placeholder)
    self.placeholderTextField = placeholder
  }

  // MARK: - Layout

  public override func layout() {
    super.layout()
    updatePlaceholderFrame()
  }

  private func updatePlaceholderFrame() {
    guard let placeholder = placeholderTextField,
          let textContainer = self.textContainer else { return }

    let padding = textContainer.lineFragmentPadding
    let inset = textContainerInset
    placeholder.frame.origin = CGPoint(
      x: padding + inset.width,
      y: inset.height
    )
    placeholder.sizeToFit()
  }

  // MARK: - Placeholder

  /// Configure placeholder text.
  public func setPlaceholderText(_ text: String, textColor: NSColor, font: NSFont) {
    placeholderTextValue = text
    placeholderColor = textColor
    placeholderFont = font

    placeholderTextField?.stringValue = text
    placeholderTextField?.textColor = textColor
    placeholderTextField?.font = font
    updatePlaceholderVisibility()
  }

  /// Show or hide placeholder based on content.
  public func showPlaceholderText() {
    updatePlaceholderVisibility()
  }

  internal func updatePlaceholderVisibility() {
    let isEmpty = string.isEmpty
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      placeholderTextField?.animator().alphaValue = isEmpty ? 1.0 : 0.0
    }
  }

  // MARK: - First Responder

  public override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    if result {
      lexicalDelegate?.textViewDidBeginEditing(textView: self)
    }
    return result
  }

  public override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result {
      lexicalDelegate?.textViewDidEndEditing(textView: self)
    }
    return result
  }

  // Text input and deletion overrides are in TextView+NSTextInputClient.swift
  // and TextView+Keyboard.swift extensions

  // MARK: - Selection

  public override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
    // Handle selection interception if needed
    if let interceptRange = interceptNextSelectionChangeAndReplaceWithRange {
      interceptNextSelectionChangeAndReplaceWithRange = nil
      super.setSelectedRange(interceptRange, affinity: affinity, stillSelecting: stillSelectingFlag)
      return
    }

    super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
  }
}

// MARK: - NSTextViewDelegate

extension TextViewAppKit: NSTextViewDelegate {
  public func textView(
    _ textView: NSTextView,
    shouldChangeTextIn affectedCharRange: NSRange,
    replacementString: String?
  ) -> Bool {
    let result = lexicalDelegate?.textViewShouldChangeText(
      self,
      range: affectedCharRange,
      replacementText: replacementString ?? ""
    ) ?? true

    if result {
      updatePlaceholderVisibility()
    }

    return result
  }

  public func textDidChange(_ notification: Notification) {
    updatePlaceholderVisibility()
  }

  public func textViewDidChangeSelection(_ notification: Notification) {
    // Selection change notifications for Lexical integration
    // This will be expanded when we integrate with Editor
  }
}

// MARK: - TextStorageAppKit

/// Custom NSTextStorage for Lexical on macOS.
///
/// This class bridges the Lexical editor with the AppKit text system.
public class TextStorageAppKit: NSTextStorage {

  /// The backing store for the attributed string.
  private let storage = NSMutableAttributedString()

  /// Reference to the Lexical editor.
  weak var editor: Editor?

  // MARK: - NSTextStorage Required Overrides

  public override var string: String {
    storage.string
  }

  public override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
    storage.attributes(at: location, effectiveRange: range)
  }

  public override func replaceCharacters(in range: NSRange, with str: String) {
    beginEditing()
    storage.replaceCharacters(in: range, with: str)
    edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
    endEditing()
  }

  public override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
    beginEditing()
    storage.setAttributes(attrs, range: range)
    edited(.editedAttributes, range: range, changeInLength: 0)
    endEditing()
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
