/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(AppKit)
import Foundation
import AppKit

/// The LexicalViewDelegate allows customisation of certain things, most of which correspond to
/// NSTextView delegate methods.
///
/// This protocol is somewhat a transitional thing. Eventually we would like to have every customisation point
/// for Lexical exposed through Lexical specific APIs, e.g. using Lexical commands and listeners as the customisation
/// mechanism.
///
/// - Note: macOS only. For iOS, use the iOS-specific `LexicalViewDelegate` protocol.
@available(macOS 14.0, *)
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
  public func textView(
    _ textView: LexicalView, shouldInteractWith URL: URL, in selection: RangeSelection?
  ) -> Bool {
    return true
  }
}

/// Placeholder text configuration for the Lexical editor.
///
/// - Note: macOS only. For iOS, use the iOS-specific `LexicalPlaceholderText` class.
@available(macOS 14.0, *)
@objc public class LexicalPlaceholderText: NSObject {
  public var text: String
  public var font: NSFont
  public var color: NSColor

  @objc public init(text: String, font: NSFont, color: NSColor) {
    self.text = text
    self.font = font
    self.color = color
  }
}

// MARK: -

/// A LexicalView is the view class that you interact with to use Lexical on macOS.
///
/// In order to avoid the possibility of accidentally using NSTextView methods that Lexical does not expect, we've
/// encapsulated our NSTextView subclass as a private property of LexicalView. The aim is to consider the NSTextView
/// as below the abstraction level for developers using Lexical.
///
/// - Note: macOS only. For iOS, use the iOS-specific `LexicalView` class in `LexicalView.swift`.
/// For cross-platform SwiftUI support, use `LexicalEditor` from `Lexical/SwiftUI/LexicalViewRepresentable.swift`.
@available(macOS 14.0, *)
@MainActor
@objc public class LexicalView: NSView, Frontend {
  var textLayoutWidth: CGFloat {
    return max(
      textView.bounds.width - textView.textContainerOrigin.x * 2
        - 2 * (textView.textContainer?.lineFragmentPadding ?? 0), 0)
  }

  /// The underlying NSTextView. Note that this should not be accessed unless there's no way to do what you want
  /// using the Lexical API.
  @objc public let textView: TextView
  private var scrollView: NSScrollView
  private var overlayView: LexicalOverlayView

  let responderForNodeSelection: ResponderForNodeSelection

  @objc public init(
    editorConfig: EditorConfig, featureFlags: FeatureFlags,
    placeholderText: LexicalPlaceholderText? = nil
  ) {
    self.scrollView = NSScrollView()
    self.textView = TextView(editorConfig: editorConfig, featureFlags: featureFlags)
    self.textView.isVerticallyResizable = true
    self.textView.isHorizontallyResizable = false
    self.textView.autoresizingMask = [.width]
    self.textView.textContainer?.widthTracksTextView = true
    self.placeholderText = placeholderText
    self.overlayView = LexicalOverlayView(textView: textView)

    guard let textStorage = textView.textStorage as? TextStorage else {
      fatalError()
    }
    self.responderForNodeSelection = ResponderForNodeSelection(
      editor: textView.editor, textStorage: textStorage, nextResponder: textView)

    super.init(frame: .zero)

    // Set up scroll view
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.autoresizingMask = [.width, .height]

    self.textView.editor.frontend = self

    self.textView.lexicalDelegate = self
    if let placeholderText {
      self.textView.setPlaceholderText(
        placeholderText.text, textColor: placeholderText.color, font: placeholderText.font)
    }

    addSubview(scrollView)
    let origin = textView.textContainerOrigin
    defaultViewMargins = NSEdgeInsets(top: origin.y, left: origin.x, bottom: origin.y, right: origin.x)
    addSubview(overlayView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Frontend protocol

  var textStorage: TextStorage {
    guard let textStorage = self.textView.textStorage as? TextStorage else {
      // this will never happen
      editor.log(.TextView, .error, "Text view had no text storage")
      fatalError()
    }
    return textStorage
  }

  @objc public var layoutManager: LayoutManager {
    guard let layoutManager = self.textView.layoutManager as? LayoutManager else {
      // this will never happen
      editor.log(.TextView, .error, "Text view had no layout manager")
      fatalError()
    }
    return layoutManager
  }

  @objc public var textContainerInsets: NSEdgeInsets {
    let origin = textView.textContainerOrigin
    return NSEdgeInsets(top: origin.y, left: origin.x, bottom: origin.y, right: origin.x)
  }

  var nativeSelection: NativeSelection {
    if responderForNodeSelection.isFirstResponder {
      return NativeSelection(
        range: nil, affinity: .forward, markedRange: nil,
        selectionIsNodeOrObject: true)
    }

    let selectionNSRange = textView.selectedRange()
    let nsAffinity = textView.selectionAffinity
    let platformAffinity: PlatformTextStorageDirection = (nsAffinity == .upstream) ? .backward : .forward

    var markedNSRange: NSRange?
    if textView.hasMarkedText() {
      markedNSRange = textView.markedRange()
    }
    return NativeSelection(
      range: selectionNSRange, affinity: platformAffinity,
      markedRange: markedNSRange,
      selectionIsNodeOrObject: false)
  }

  var isUpdatingNativeSelection: Bool {
    get {
      textView.isUpdatingNativeSelection
    }
    set {
      textView.isUpdatingNativeSelection = newValue
    }
  }

  var isEmpty: Bool {
    textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var viewForDecoratorSubviews: NSView? {
    textView
  }

  func moveNativeSelection(
    type: NativeSelectionModificationType, direction: PlatformTextStorageDirection,
    granularity: PlatformTextGranularity
  ) {
    textView.isUpdatingNativeSelection = true

    let selection = nativeSelection

    guard let range = selection.range else {
      textView.isUpdatingNativeSelection = false
      return
    }

    var start = range.location
    var end = range.location + range.length

    // On macOS, we use NSTextView's built-in movement methods
    // This is a simplified implementation - full implementation would use NSTextView movement APIs
    switch granularity {
    case .character:
      if direction == .forward {
        end = min(end + 1, (textView.string as NSString).length)
        if type == .move {
          start = end
        }
      } else {
        start = max(start - 1, 0)
        if type == .move {
          end = start
        }
      }
    case .word:
      // Use NSTextView's word boundary detection
      if direction == .forward {
        end = textView.selectionRange(forProposedRange: NSRange(location: end, length: 0), granularity: .selectByWord).upperBound
        if type == .move {
          start = end
        }
      } else {
        start = textView.selectionRange(forProposedRange: NSRange(location: start, length: 0), granularity: .selectByWord).lowerBound
        if type == .move {
          end = start
        }
      }
    default:
      break
    }

    textView.setSelectedRange(NSRange(location: start, length: end - start))
    textView.isUpdatingNativeSelection = false
  }

  func unmarkTextWithoutUpdate() {
    textView.unmarkTextWithoutUpdate()
  }

  func presentDeveloperFacingError(message: String) {
    textView.presentDeveloperFacingError(message: message)
  }

  func updateNativeSelection(from selection: BaseSelection) throws {
    guard let selection = selection as? RangeSelection else {
      // we don't have a range selection.
      _ = responderForNodeSelection.becomeFirstResponder()
      return
    }
    try textView.updateNativeSelection(from: selection)
  }

  func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange) {
    textView.setMarkedTextFromReconciler(markedText, selectedRange: selectedRange)
  }

  func resetSelectedRange() {
    textView.resetSelectedRange()
  }

  public func resetTypingAttributes(for selectedNode: Node) {
    textView.resetTypingAttributes(for: selectedNode)
  }

  var interceptNextSelectionChangeAndReplaceWithRange: NSRange? {
    get {
      textView.interceptNextSelectionChangeAndReplaceWithRange
    }
    set {
      textView.interceptNextSelectionChangeAndReplaceWithRange = newValue
    }
  }

  // MARK: - Other stuff

  public weak var delegate: LexicalViewDelegate?
  var defaultViewMargins: NSEdgeInsets = NSEdgeInsetsZero

  /// Sets the accessibility identifier of the underlying text view
  public var textViewAccessibilityIdentifier: String? {
    get {
      textView.identifier?.rawValue
    }
    set {
      textView.identifier = newValue.map { NSUserInterfaceItemIdentifier($0) }
    }
  }

  /// Sets the accessibility label of the underlying text view
  public var textViewAccessibilityLabel: String? {
    get {
      textView.accessibilityLabel()
    }
    set {
      textView.setAccessibilityLabel(newValue)
    }
  }

  /// Sets the background colour of the underlying text view
  public var textViewBackgroundColor: NSColor? {
    get {
      textView.backgroundColor
    }
    set {
      textView.backgroundColor = newValue ?? .textBackgroundColor
    }
  }

  /// Configure the placeholder text shown by this Lexical view when there is no text.
  ///
  /// This needs a refactor. Currently the LexicalView supports setting the placeholder text as part of the initialiser, which
  /// works correctly. However setting the placeholder text later through this property will not properly proxy it through to the
  /// TextView. This is a bug and should be fixed.
  public var placeholderText: LexicalPlaceholderText?

  /// Returns the current selected text range according to the underlying NSTextView.
  ///
  /// This needs a refactor. Probably this method should be deleted entirely (and the recommended approach for working with
  /// selections should be to go through the Lexical EditorState selection), unless a justification for its usefulness can be discovered.
  public var selectedTextRange: NSRange {
    textView.selectedRange()
  }

  /// Returns the attributed string fetched from the underlying text view's text storage.
  public var attributedText: NSAttributedString {
    textView.attributedString()
  }

  /// Returns the Lexical ``Editor`` owned by this LexicalView.
  ///
  /// This is the primary entry point for working with Lexical.
  @objc public var editor: Editor {
    textView.editor
  }

  public var text: String {
    textView.string
  }

  /// A proxy for the underlying `NSScrollView`'s vertical scroller visibility.
  public var isScrollEnabled: Bool {
    get {
      scrollView.hasVerticalScroller
    }

    set {
      scrollView.hasVerticalScroller = newValue
    }
  }

  /// A shortcut for getting the selection position.
  ///
  /// This method should maybe not exist, we should consider this holistically when auditing our
  /// selection APIs. Currently it exists in order to support a feature in Work Chat, but if that's the only
  /// reason, we could move this method into Work Chat specific code.
  public lazy var cursorPosition: UInt = {
    UInt(textView.selectedRange().location)
  }()

  /// Returns the marked text range from the underlying NSTextView.
  ///
  /// Marked Text corresponds to Lexical's `composition`.
  public var markedTextRange: NSRange {
    textView.markedRange()
  }

  /// Returns the current text input mode from the underlying NSTextView.
  ///
  /// This can be used to access the input language.
  public var textViewInputMode: NSTextInputContext? {
    textView.inputContext
  }

  /// A convenience method for working out if there is any text in the text view.
  public var isTextViewEmpty: Bool {
    textView.string.lengthAsNSString() == 0
  }

  /// A proxy for the underlying NSTextView's first responder status
  public var textViewIsFirstResponder: Bool {
    textView.window?.firstResponder == textView
  }

  /// A proxy for the underlying NSTextView's CALayer's `borderWidth` property
  public var textViewBorderWidth: CGFloat {
    get {
      textView.layer?.borderWidth ?? 0
    }

    set {
      textView.wantsLayer = true
      textView.layer?.borderWidth = newValue
    }
  }

  /// A proxy for the underlying NSTextView's CALayer's `borderColor` property.
  ///
  /// If refactoring, maybe we should make this API take a NSColor rather than a CGColor, to better
  /// match the rest of our AppKit-based APIs.
  public var textViewBorderColor: CGColor? {
    get {
      textView.layer?.borderColor
    }
    set {
      textView.wantsLayer = true
      textView.layer?.borderColor = newValue
    }
  }

  // MARK: - Layout

  override public func layout() {
    super.layout()

    scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    overlayView.frame = scrollView.documentVisibleRect  // Ensure overlay covers the visible textView
  }

  /// Convenience method to clear editor and show placeholder text
  public func clearLexicalView() throws {
    try textView.defaultClearEditor()
    textView.showPlaceholderText()
  }

  @discardableResult
  @objc public func textViewBecomeFirstResponder() -> Bool {
    return textView.becomeFirstResponder()
  }

  @discardableResult
  @objc public func textViewResignFirstResponder() -> Bool {
    return textView.resignFirstResponder()
  }

  // MARK: - TextView

  public func getTextViewSelectedRange() -> NSRange {
    textView.selectedRange()
  }

  public func scrollSelectionToVisible() {
    textView.scrollRangeToVisible(textView.selectedRange())
  }

  public func shouldInvalidateTextViewHeight(maxHeight: CGFloat) -> Bool {
    let textViewSize = textView.sizeThatFits(
      CGSize(width: textView.bounds.size.width, height: CGFloat.greatestFiniteMagnitude))
    let calculatedHeight = min(maxHeight, textViewSize.height)

    return calculatedHeight != textView.bounds.size.height
  }

  public func calculateTextViewHeight(for containerSize: CGSize, padding: NSEdgeInsets) -> CGFloat {
    let fullHeight = textView.sizeThatFits(
      CGSize(
        width: containerSize.width - padding.left - padding.right,
        height: containerSize.height - padding.top - padding.bottom)
    ).height

    return fullHeight
  }

  public func showPlaceholderText() {
    textView.showPlaceholderText()
  }

  public func setTextContainerInset(_ margins: NSEdgeInsets) {
    // NSTextView doesn't have direct textContainerInset like UITextView
    // This would require custom implementation or using textContainerOrigin
  }

  public func clearTextContainerInset() {
    // NSTextView doesn't have direct textContainerInset like UITextView
  }

  // MARK: - First Responder

  public var isFirstResponder: Bool {
    window?.firstResponder == textView
  }
}

// MARK: - LexicalTextViewDelegate

extension LexicalView: LexicalTextViewDelegate {
  func textView(
    _ textView: NSTextView, shouldInteractWith URL: URL, in characterRange: NSRange
  ) -> Bool {
    var selection: RangeSelection?

    do {
      try editor.read {
        selection = try getSelection() as? RangeSelection ?? createEmptyRangeSelection()
        try selection?.applySelectionRange(characterRange, affinity: .forward)
      }
    } catch {
      print("Error received in LexicalView(shouldInteractWith): \(error.localizedDescription)")
    }

    return delegate?.textView(self, shouldInteractWith: URL, in: selection) ?? false
  }

  func textViewDidBeginEditing(textView: TextView) {
    delegate?.textViewDidBeginEditing(textView: self)
  }

  func textViewDidEndEditing(textView: TextView) {
    delegate?.textViewDidEndEditing(textView: self)
  }

  func textViewShouldChangeText(
    _ textView: NSTextView, range: NSRange, replacementText text: String
  ) -> Bool {
    if let delegate {
      return delegate.textViewShouldChangeText(self, range: range, replacementText: text)
    }

    return true
  }
}
#endif
