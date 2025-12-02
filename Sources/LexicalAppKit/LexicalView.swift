/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical

// MARK: - LexicalViewDelegate

/// The LexicalViewDelegate allows customization of certain behaviors.
///
/// This protocol mirrors the UIKit version's delegate to maintain API consistency.
@MainActor
public protocol LexicalViewDelegate: NSObjectProtocol {
  func textViewDidBeginEditing(textView: LexicalView)
  func textViewDidEndEditing(textView: LexicalView)
  func textViewShouldChangeText(
    _ textView: LexicalView, range: NSRange, replacementText text: String
  ) -> Bool
}

extension LexicalViewDelegate {
  public func textViewDidBeginEditing(textView: LexicalView) {}
  public func textViewDidEndEditing(textView: LexicalView) {}
  public func textViewShouldChangeText(
    _ textView: LexicalView, range: NSRange, replacementText text: String
  ) -> Bool {
    return true
  }
}

// MARK: - LexicalPlaceholderText

/// Configuration for placeholder text displayed when the editor is empty.
public class LexicalPlaceholderText: NSObject {
  public var text: String
  public var font: NSFont
  public var color: NSColor

  public init(text: String, font: NSFont, color: NSColor) {
    self.text = text
    self.font = font
    self.color = color
  }
}

// MARK: - LexicalView

/// A LexicalView is the view class that you interact with to use Lexical on macOS.
///
/// This class wraps an NSTextView-based implementation and provides the same
/// interface as the UIKit version for cross-platform compatibility.
@MainActor
public class LexicalView: NSView {

  // MARK: - Properties

  /// The underlying text view. Access this for advanced customization.
  public let textView: TextViewAppKit

  /// The scroll view containing the text view.
  public let scrollView: NSScrollView

  /// The delegate for view callbacks.
  public weak var delegate: LexicalViewDelegate?

  /// Placeholder text configuration.
  public var placeholderText: LexicalPlaceholderText?

  /// Default view margins.
  var defaultViewMargins: NSEdgeInsets = NSEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)

  // MARK: - Initialization

  /// Creates a new LexicalView with the specified configuration.
  ///
  /// - Parameters:
  ///   - editorConfig: Configuration for the Lexical editor.
  ///   - featureFlags: Feature flags controlling editor behavior.
  ///   - placeholderText: Optional placeholder text to display when empty.
  public init(
    editorConfig: EditorConfig,
    featureFlags: FeatureFlags,
    placeholderText: LexicalPlaceholderText? = nil
  ) {
    self.placeholderText = placeholderText

    // Create the text view
    self.textView = TextViewAppKit(editorConfig: editorConfig, featureFlags: featureFlags)

    // Create scroll view to contain the text view
    self.scrollView = NSScrollView()
    self.scrollView.documentView = textView
    self.scrollView.hasVerticalScroller = true
    self.scrollView.hasHorizontalScroller = false
    self.scrollView.autohidesScrollers = true
    self.scrollView.borderType = .noBorder
    self.scrollView.drawsBackground = false

    super.init(frame: .zero)

    // Configure the text view
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true

    // Set up placeholder if provided
    if let placeholderText {
      textView.setPlaceholderText(placeholderText.text, textColor: placeholderText.color, font: placeholderText.font)
    }

    // Add scroll view as subview
    addSubview(scrollView)

    // Set up constraints
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    // Set the delegate
    textView.lexicalDelegate = self
  }

  /// Convenience initializer using default feature flags.
  public convenience init(
    editorConfig: EditorConfig,
    placeholderText: LexicalPlaceholderText? = nil
  ) {
    self.init(
      editorConfig: editorConfig,
      featureFlags: LexicalRuntime.defaultFeatureFlags,
      placeholderText: placeholderText
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Layout

  public override func layout() {
    super.layout()
    // Ensure text container tracks scroll view width
    textView.textContainer?.containerSize = NSSize(
      width: scrollView.contentSize.width,
      height: CGFloat.greatestFiniteMagnitude
    )
  }

  // MARK: - Public Properties

  /// The Lexical Editor owned by this view.
  public var editor: Editor {
    textView.editor
  }

  /// The attributed text content.
  public var attributedText: NSAttributedString {
    textView.attributedString()
  }

  /// The plain text content.
  public var text: String {
    textView.string
  }

  /// Whether the text view is empty.
  public var isTextViewEmpty: Bool {
    textView.string.isEmpty
  }

  /// Whether the text view is the first responder.
  public var textViewIsFirstResponder: Bool {
    window?.firstResponder === textView
  }

  /// Whether scrolling is enabled.
  public var isScrollEnabled: Bool {
    get { scrollView.hasVerticalScroller }
    set {
      scrollView.hasVerticalScroller = newValue
      scrollView.hasHorizontalScroller = false
    }
  }

  /// The marked text range (for IME composition).
  public var markedTextRange: NSRange? {
    let range = textView.markedRange()
    return range.location != NSNotFound ? range : nil
  }

  // MARK: - Accessibility

  /// Accessibility identifier for the text view.
  public var textViewAccessibilityIdentifier: String? {
    get { textView.accessibilityIdentifier() }
    set { textView.setAccessibilityIdentifier(newValue) }
  }

  /// Accessibility label for the text view.
  public var textViewAccessibilityLabel: String? {
    get { textView.accessibilityLabel() }
    set { textView.setAccessibilityLabel(newValue) }
  }

  // MARK: - Appearance

  /// Background color of the text view.
  public var textViewBackgroundColor: NSColor? {
    get { textView.backgroundColor }
    set {
      textView.backgroundColor = newValue ?? .textBackgroundColor
      textView.drawsBackground = newValue != nil
    }
  }

  /// Border width of the text view layer.
  public var textViewBorderWidth: CGFloat {
    get { textView.layer?.borderWidth ?? 0 }
    set {
      textView.wantsLayer = true
      textView.layer?.borderWidth = newValue
    }
  }

  /// Border color of the text view layer.
  public var textViewBorderColor: CGColor? {
    get { textView.layer?.borderColor }
    set {
      textView.wantsLayer = true
      textView.layer?.borderColor = newValue
    }
  }

  // MARK: - First Responder

  /// Make the text view become first responder.
  @discardableResult
  public func textViewBecomeFirstResponder() -> Bool {
    return window?.makeFirstResponder(textView) ?? false
  }

  /// Make the text view resign first responder.
  @discardableResult
  public func textViewResignFirstResponder() -> Bool {
    if textViewIsFirstResponder {
      return window?.makeFirstResponder(nil) ?? false
    }
    return true
  }

  // MARK: - Selection

  /// Get the current selected text range.
  public func getTextViewSelectedRange() -> NSRange {
    textView.selectedRange()
  }

  /// Scroll the current selection into view.
  public func scrollSelectionToVisible() {
    textView.scrollRangeToVisible(textView.selectedRange())
  }

  // MARK: - Text Container

  /// Set the text container insets.
  public func setTextContainerInset(_ margins: NSEdgeInsets) {
    textView.textContainerInset = NSSize(width: margins.left, height: margins.top)
  }

  /// Clear the text container inset to default.
  public func clearTextContainerInset() {
    textView.textContainerInset = NSSize(width: defaultViewMargins.left, height: defaultViewMargins.top)
  }

  // MARK: - Placeholder

  /// Show placeholder text.
  public func showPlaceholderText() {
    textView.showPlaceholderText()
  }

  // MARK: - Layout Helpers

  /// Update the content offset to scroll to bottom.
  public func updateTextViewContentOffset() {
    let documentHeight = scrollView.documentView?.frame.height ?? 0
    let visibleHeight = scrollView.contentView.bounds.height
    if documentHeight > visibleHeight {
      let bottomPoint = NSPoint(x: 0, y: documentHeight - visibleHeight)
      scrollView.contentView.scroll(to: bottomPoint)
    }
  }

  /// Check if the text view height should be invalidated.
  public func shouldInvalidateTextViewHeight(maxHeight: CGFloat) -> Bool {
    let textHeight = textView.frame.height
    return textHeight > maxHeight
  }

  /// Calculate the text view height for a given container size.
  public func calculateTextViewHeight(for containerSize: CGSize, padding: NSEdgeInsets) -> CGFloat {
    let availableWidth = containerSize.width - padding.left - padding.right
    textView.textContainer?.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    return textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
  }

  // MARK: - Clear

  /// Convenience method to clear editor and show placeholder text.
  public func clearLexicalView() throws {
    textView.string = ""
    showPlaceholderText()
  }
}

// MARK: - TextViewAppKitDelegate

extension LexicalView: TextViewAppKitDelegate {
  func textViewDidBeginEditing(textView: TextViewAppKit) {
    delegate?.textViewDidBeginEditing(textView: self)
  }

  func textViewDidEndEditing(textView: TextViewAppKit) {
    delegate?.textViewDidEndEditing(textView: self)
  }

  func textViewShouldChangeText(
    _ textView: TextViewAppKit,
    range: NSRange,
    replacementText text: String
  ) -> Bool {
    delegate?.textViewShouldChangeText(self, range: range, replacementText: text) ?? true
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
