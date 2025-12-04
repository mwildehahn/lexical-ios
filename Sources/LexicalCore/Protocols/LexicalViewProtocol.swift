/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import CoreGraphics

// MARK: - Native Selection Protocol

/// Platform-agnostic representation of native text selection state.
///
/// This protocol abstracts the native selection information that varies between
/// UIKit (UITextRange) and AppKit (NSRange-based) implementations.
public protocol NativeSelectionProtocol {
  /// The selection range as NSRange, if available.
  var range: NSRange? { get }

  /// Whether the selection represents a node/object selection rather than text.
  var selectionIsNodeOrObject: Bool { get }

  /// The marked text range (for IME composition), if any.
  var markedRange: NSRange? { get }

  /// Whether there is currently marked text.
  var hasMarkedText: Bool { get }
}

// MARK: - Native Selection Modification

/// Type of selection modification operation.
public enum NativeSelectionModificationType {
  /// Move the selection (collapse to point).
  case move
  /// Extend the selection (keep anchor, move focus).
  case extend
}

// MARK: - Frontend Protocol

/// Protocol defining the interface between Editor and the platform-specific view layer.
///
/// This protocol abstracts the view-layer operations that Editor needs to perform,
/// allowing both UIKit and AppKit implementations to work with the same Editor code.
///
/// Implementations:
/// - UIKit: `LexicalView` conforms to this via the `Frontend` internal protocol
/// - AppKit: `LexicalViewAppKit` will conform to this
public protocol FrontendProtocol: AnyObject {
  /// The edge insets of the text container.
  var textContainerInsets: LexicalEdgeInsets { get }

  /// The current native selection state.
  var nativeSelection: any NativeSelectionProtocol { get }

  /// Whether the view is currently the first responder.
  var isFirstResponder: Bool { get }

  /// Whether the text content is empty.
  var isEmpty: Bool { get }

  /// Flag to track when programmatic selection updates are in progress.
  var isUpdatingNativeSelection: Bool { get set }

  /// Range to intercept next selection change with.
  var interceptNextSelectionChangeAndReplaceWithRange: NSRange? { get set }

  /// The width available for text layout.
  var textLayoutWidth: CGFloat { get }

  /// Move the native selection by direction and granularity.
  func moveNativeSelection(
    type: NativeSelectionModificationType,
    direction: LexicalTextStorageDirection,
    granularity: LexicalTextGranularity
  )

  /// Unmark text without triggering update callbacks.
  func unmarkTextWithoutUpdate()

  /// Present a developer-facing error message.
  func presentDeveloperFacingError(message: String)

  /// Set marked text from reconciler.
  func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange)

  /// Reset the selected range to a default state.
  func resetSelectedRange()

  /// Show placeholder text when editor is empty.
  func showPlaceholderText()
}

// MARK: - Lexical View Protocol

/// Protocol defining the public interface for a Lexical text editing view.
///
/// This protocol provides a platform-agnostic interface for the main Lexical view
/// that applications interact with. Both UIKit and AppKit implementations should
/// conform to this protocol to ensure API consistency across platforms.
public protocol LexicalViewProtocol: AnyObject {
  /// Associated type for platform-specific text range representation.
  associatedtype TextRange

  /// Associated type for platform-specific view type.
  associatedtype PlatformView

  /// Associated type for the delegate.
  associatedtype Delegate

  // MARK: - Core Properties

  /// The delegate for view callbacks.
  var delegate: Delegate? { get set }

  /// The attributed text content.
  var attributedText: NSAttributedString { get }

  /// The plain text content.
  var text: String { get }

  /// Whether the text view is currently empty.
  var isTextViewEmpty: Bool { get }

  /// Whether the text view is the first responder.
  var textViewIsFirstResponder: Bool { get }

  /// Whether scrolling is enabled.
  var isScrollEnabled: Bool { get set }

  // MARK: - Accessibility

  /// Accessibility identifier for the text view.
  var textViewAccessibilityIdentifier: String? { get set }

  /// Accessibility label for the text view.
  var textViewAccessibilityLabel: String? { get set }

  // MARK: - Appearance

  /// Background color of the text view.
  var textViewBackgroundColor: LexicalColor? { get set }

  /// Border width of the text view layer.
  var textViewBorderWidth: CGFloat { get set }

  /// Border color of the text view layer.
  var textViewBorderColor: CGColor? { get set }

  // MARK: - First Responder

  /// Make the text view become first responder.
  @discardableResult
  func textViewBecomeFirstResponder() -> Bool

  /// Make the text view resign first responder.
  @discardableResult
  func textViewResignFirstResponder() -> Bool

  // MARK: - Selection

  /// Get the current selected text range.
  func getTextViewSelectedRange() -> TextRange?

  /// Scroll the current selection into view.
  func scrollSelectionToVisible()

  // MARK: - Text Container

  /// Set the text container insets.
  func setTextContainerInset(_ margins: LexicalEdgeInsets)

  /// Clear the text container inset to default.
  func clearTextContainerInset()

  // MARK: - Placeholder

  /// Show placeholder text.
  func showPlaceholderText()

  // MARK: - Layout

  /// Update the content offset to scroll to bottom.
  func updateTextViewContentOffset()

  /// Check if the text view height should be invalidated.
  func shouldInvalidateTextViewHeight(maxHeight: CGFloat) -> Bool
}
