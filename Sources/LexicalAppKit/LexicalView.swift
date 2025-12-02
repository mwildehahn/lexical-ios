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
  func textView(
    _ textView: LexicalView, shouldInteractWith URL: URL, in selection: RangeSelection?
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
  public func textView(
    _ textView: LexicalView, shouldInteractWith URL: URL, in selection: RangeSelection?
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

    // Connect this view to the editor as the frontend
    textView.editor.frontendAppKit = self

    // Register rich text command handlers
    registerRichTextAppKit(editor: textView.editor)
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

// MARK: - FrontendAppKit Conformance

extension LexicalView: FrontendAppKit {

  public var textStorage: NSTextStorage {
    textView.lexicalTextStorage
  }

  public var layoutManager: NSLayoutManager {
    textView.lexicalLayoutManager
  }

  public var textContainerInsets: NSEdgeInsets {
    let inset = textView.textContainerInset
    return NSEdgeInsets(top: inset.height, left: inset.width, bottom: inset.height, right: inset.width)
  }

  public var nativeSelectionRange: NSRange {
    textView.selectedRange()
  }

  public var nativeSelectionAffinity: NSSelectionAffinity {
    textView.selectionAffinity
  }

  public var isFirstResponder: Bool {
    textViewIsFirstResponder
  }

  public var viewForDecoratorSubviews: NSView? {
    textView
  }

  public var isEmpty: Bool {
    isTextViewEmpty
  }

  public var isUpdatingNativeSelection: Bool {
    get { textView.isUpdatingNativeSelection }
    set { textView.isUpdatingNativeSelection = newValue }
  }

  public var interceptNextSelectionChangeAndReplaceWithRange: NSRange? {
    get { textView.interceptNextSelectionChangeAndReplaceWithRange }
    set { textView.interceptNextSelectionChangeAndReplaceWithRange = newValue }
  }

  public var textLayoutWidth: CGFloat {
    textView.textContainer?.containerSize.width ?? 0
  }

  public func moveNativeSelection(
    type: NativeSelectionModificationType,
    direction: LexicalTextStorageDirection,
    granularity: LexicalTextGranularity
  ) {
    // Convert to NSTextView selection operations
    let currentRange = textView.selectedRange()
    guard let textContainer = textView.textContainer,
          let layoutManager = textView.layoutManager else { return }

    // Calculate new selection based on direction and granularity
    var newRange = currentRange

    switch granularity {
    case .character:
      if direction == .forward {
        if currentRange.location + currentRange.length < (textView.string as NSString).length {
          if type == .move {
            newRange = NSRange(location: currentRange.location + 1, length: 0)
          } else {
            newRange = NSRange(location: currentRange.location, length: currentRange.length + 1)
          }
        }
      } else {
        if currentRange.location > 0 {
          if type == .move {
            newRange = NSRange(location: currentRange.location - 1, length: 0)
          } else {
            newRange = NSRange(location: currentRange.location - 1, length: currentRange.length + 1)
          }
        }
      }
    case .word:
      // Find word boundary
      let string = textView.string as NSString
      let wordRange = string.rangeOfCharacter(
        from: .whitespacesAndNewlines,
        options: direction == .forward ? [] : .backwards,
        range: NSRange(
          location: direction == .forward ? currentRange.location + currentRange.length : 0,
          length: direction == .forward
            ? string.length - (currentRange.location + currentRange.length)
            : currentRange.location
        )
      )
      if wordRange.location != NSNotFound {
        if type == .move {
          newRange = NSRange(location: wordRange.location, length: 0)
        } else {
          // Extend selection
          let newLocation = min(currentRange.location, wordRange.location)
          let newEnd = max(currentRange.location + currentRange.length, wordRange.location + wordRange.length)
          newRange = NSRange(location: newLocation, length: newEnd - newLocation)
        }
      }
    case .line:
      // Find line boundaries using layout manager
      var lineStart: Int = 0
      var lineEnd: Int = 0
      layoutManager.lineFragmentRect(forGlyphAt: currentRange.location, effectiveRange: nil)
      let glyphRange = layoutManager.glyphRange(for: textContainer)
      if direction == .forward {
        lineEnd = NSMaxRange(glyphRange)
        newRange = type == .move
          ? NSRange(location: lineEnd, length: 0)
          : NSRange(location: currentRange.location, length: lineEnd - currentRange.location)
      } else {
        lineStart = glyphRange.location
        newRange = type == .move
          ? NSRange(location: lineStart, length: 0)
          : NSRange(location: lineStart, length: currentRange.location + currentRange.length - lineStart)
      }
    case .paragraph, .sentence:
      // Treat similar to line for now
      break
    case .document:
      let length = (textView.string as NSString).length
      if direction == .forward {
        newRange = type == .move
          ? NSRange(location: length, length: 0)
          : NSRange(location: currentRange.location, length: length - currentRange.location)
      } else {
        newRange = type == .move
          ? NSRange(location: 0, length: 0)
          : NSRange(location: 0, length: currentRange.location + currentRange.length)
      }
    }

    textView.setSelectedRange(newRange)
  }

  public func unmarkTextWithoutUpdate() {
    // Clear any marked text from IME composition
    if textView.hasMarkedText() {
      textView.unmarkText()
    }
  }

  public func presentDeveloperFacingError(message: String) {
    // Show an alert for developer-facing errors during debugging
    #if DEBUG
    let alert = NSAlert()
    alert.messageText = "Lexical Error"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
    #endif
  }

  public func updateNativeSelection(from selection: BaseSelection) throws {
    guard let rangeSelection = selection as? RangeSelection else {
      // Handle other selection types (NodeSelection, etc.)
      return
    }

    textView.applyLexicalSelection(rangeSelection, editor: editor)
  }

  public func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
    // Set marked text for IME composition from the reconciler
    textView.setMarkedText(
      markedText,
      selectedRange: selectedRange,
      replacementRange: textView.selectedRange()
    )
  }

  public func resetSelectedRange() {
    // Reset selection to the end of the text
    let length = (textView.string as NSString).length
    textView.setSelectedRange(NSRange(location: length, length: 0))
  }

  public func resetTypingAttributes(for selectedNode: Node) {
    // Reset typing attributes based on the selected node's attributes
    // This ensures new text typed at this position uses the correct formatting
    let theme = editor.getTheme()
    var attrs: [NSAttributedString.Key: Any] = [:]

    // Start with default font and color
    attrs[.font] = LexicalConstantsAppKit.defaultFont
    attrs[.foregroundColor] = LexicalConstantsAppKit.defaultColor

    // Apply node-specific attributes
    if let textNode = selectedNode as? TextNode {
      let nodeAttrs = textNode.getAttributedStringAttributes(theme: theme)
      for (key, value) in nodeAttrs {
        attrs[key] = value
      }
    }

    textView.typingAttributes = attrs
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
