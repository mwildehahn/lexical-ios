/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)

import AppKit
import Foundation
import LexicalCore

/// A Lexical Frontend for AppKit is an object that contains the TextKit stack used by Lexical,
/// along with handling user interactions, incoming events, etc.
///
/// This protocol mirrors the UIKit `Frontend` protocol, providing the same hard boundary
/// between the responsibilities of the Editor vs the Frontend on macOS.
///
/// Note: We use NSTextStorage/NSLayoutManager base classes here to avoid circular dependencies
/// between Lexical and LexicalAppKit modules. Implementations can cast to specific subclasses.
@MainActor
public protocol FrontendAppKit: AnyObject {
  /// The text storage backing the text view.
  var textStorage: NSTextStorage { get }

  /// The layout manager for text layout.
  var layoutManager: NSLayoutManager { get }

  /// Insets around the text container.
  var textContainerInsets: NSEdgeInsets { get }

  /// The editor instance.
  var editor: Editor { get }

  /// The current native selection as an NSRange and affinity.
  var nativeSelectionRange: NSRange { get }

  /// The native selection affinity.
  var nativeSelectionAffinity: NSSelectionAffinity { get }

  /// Whether the frontend is the first responder.
  var isFirstResponder: Bool { get }

  /// The view to use as the superview for decorator subviews.
  var viewForDecoratorSubviews: NSView? { get }

  /// Whether the frontend is empty (no content).
  var isEmpty: Bool { get }

  /// Flag to prevent selection change handling during programmatic updates.
  var isUpdatingNativeSelection: Bool { get set }

  /// If set, the next selection change will be intercepted and replaced with this range.
  var interceptNextSelectionChangeAndReplaceWithRange: NSRange? { get set }

  /// The width available for text layout.
  var textLayoutWidth: CGFloat { get }

  /// Move the native selection in a direction with a granularity.
  func moveNativeSelection(type: NativeSelectionModificationType, direction: LexicalTextStorageDirection, granularity: LexicalTextGranularity)

  /// Clear any marked text without triggering updates.
  func unmarkTextWithoutUpdate()

  /// Present an error to the developer during debugging.
  func presentDeveloperFacingError(message: String)

  /// Update the native selection to match a Lexical selection.
  func updateNativeSelection(from selection: BaseSelection) throws

  /// Set marked text from the reconciler during IME composition.
  func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange)

  /// Reset the selected range (clear selection).
  func resetSelectedRange()

  /// Show placeholder text if appropriate.
  func showPlaceholderText()

  /// Reset typing attributes based on the selected node.
  func resetTypingAttributes(for selectedNode: Node)
}

// MARK: - TextStorage Protocol

/// Protocol for accessing mode property on AppKit text storage.
/// TextStorageAppKit conforms to this to allow the Reconciler to set mode without
/// directly importing LexicalAppKit (which would cause circular dependency).
@MainActor
public protocol ReconcilerTextStorageAppKit: NSTextStorage {
  var mode: TextStorageEditingMode { get set }
  var decoratorPositionCache: [NodeKey: Int] { get set }
}

// MARK: - Supporting Types

/// Text granularity for AppKit selection operations.
public enum LexicalTextGranularity {
  case character
  case word
  case sentence
  case paragraph
  case line
  case document

  #if canImport(UIKit)
  init(from uiGranularity: UITextGranularity) {
    switch uiGranularity {
    case .character: self = .character
    case .word: self = .word
    case .sentence: self = .sentence
    case .paragraph: self = .paragraph
    case .line: self = .line
    case .document: self = .document
    @unknown default: self = .character
    }
  }

  var toUIKit: UITextGranularity {
    switch self {
    case .character: return .character
    case .word: return .word
    case .sentence: return .sentence
    case .paragraph: return .paragraph
    case .line: return .line
    case .document: return .document
    }
  }
  #endif
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
