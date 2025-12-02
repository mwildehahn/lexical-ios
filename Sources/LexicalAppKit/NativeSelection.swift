/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical
import LexicalCore

// MARK: - NativeSelectionAppKit

/// AppKit implementation of native selection state.
///
/// This struct captures the current selection state from NSTextView
/// and provides it in a format compatible with Lexical's selection system.
public struct NativeSelectionAppKit: NativeSelectionProtocol {

  // MARK: - Properties

  /// The selection range as NSRange.
  public let range: NSRange?

  /// The selection affinity (upstream or downstream).
  public let affinity: NSSelectionAffinity

  /// The marked text range (for IME composition).
  public let markedRange: NSRange?

  /// Whether the selection represents a node/object selection.
  public let selectionIsNodeOrObject: Bool

  // MARK: - NativeSelectionProtocol

  /// Whether there is currently marked text.
  public var hasMarkedText: Bool {
    guard let markedRange = markedRange else { return false }
    return markedRange.location != NSNotFound
  }

  // MARK: - Initialization

  /// Creates a native selection from an NSTextView.
  public init(textView: NSTextView) {
    self.range = textView.selectedRange()
    self.affinity = textView.selectionAffinity

    let marked = textView.markedRange()
    self.markedRange = marked.location != NSNotFound ? marked : nil

    self.selectionIsNodeOrObject = false
  }

  /// Creates a native selection with explicit values.
  public init(
    range: NSRange?,
    affinity: NSSelectionAffinity = .downstream,
    markedRange: NSRange? = nil,
    selectionIsNodeOrObject: Bool = false
  ) {
    self.range = range
    self.affinity = affinity
    self.markedRange = markedRange
    self.selectionIsNodeOrObject = selectionIsNodeOrObject
  }

  // MARK: - Convenience

  /// Whether the selection is collapsed (cursor position).
  public var isCollapsed: Bool {
    guard let range = range else { return true }
    return range.length == 0
  }

  /// The selection anchor (start) location.
  public var anchor: Int? {
    range?.location
  }

  /// The selection focus (end) location.
  public var focus: Int? {
    guard let range = range else { return nil }
    return range.location + range.length
  }
}

// MARK: - Selection Extensions

extension TextViewAppKit {

  /// Get the current native selection state.
  public var nativeSelection: NativeSelectionAppKit {
    NativeSelectionAppKit(textView: self)
  }

  /// Apply a selection range programmatically.
  ///
  /// - Parameters:
  ///   - range: The range to select.
  ///   - affinity: The selection affinity.
  public func applySelection(range: NSRange, affinity: NSSelectionAffinity = .downstream) {
    guard !isUpdatingNativeSelection else { return }

    isUpdatingNativeSelection = true
    defer { isUpdatingNativeSelection = false }

    setSelectedRange(range, affinity: affinity, stillSelecting: false)
  }

  /// Apply a Lexical selection to the native text view.
  ///
  /// This method converts a Lexical RangeSelection to native selection coordinates
  /// and updates the text view's selection.
  public func applyLexicalSelection(_ selection: RangeSelection) {
    // TODO: Convert Lexical selection coordinates to NSRange
    // This requires access to the reconciled text storage to map
    // node keys and offsets to character positions
  }
}

// MARK: - Selection Change Handling

extension TextViewAppKit {

  /// Called when the selection changes in the text view.
  ///
  /// Override point for tracking selection changes and syncing with Lexical.
  internal func handleSelectionChange() {
    guard !isUpdatingNativeSelection else { return }

    // Get the current selection
    let selection = nativeSelection

    // Notify Lexical about selection change
    // This will be expanded to update Lexical's selection state
    notifyLexicalOfSelectionChange(selection)
  }

  /// Notify Lexical that the native selection has changed.
  private func notifyLexicalOfSelectionChange(_ selection: NativeSelectionAppKit) {
    // TODO: Update Lexical's selection state
    // This requires:
    // 1. Converting NSRange to node key + offset
    // 2. Creating/updating a RangeSelection
    // 3. Calling editor.update to apply the selection change
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
