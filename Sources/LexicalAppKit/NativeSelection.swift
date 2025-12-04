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
  public let nsAffinity: NSSelectionAffinity

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

  /// The selection affinity as LexicalTextStorageDirection for cross-platform compatibility.
  public var affinity: LexicalTextStorageDirection {
    switch nsAffinity {
    case .upstream:
      return .backward
    case .downstream:
      return .forward
    @unknown default:
      return .forward
    }
  }

  // MARK: - Initialization

  /// Creates a native selection from an NSTextView.
  public init(textView: NSTextView) {
    self.range = textView.selectedRange()
    self.nsAffinity = textView.selectionAffinity

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
    self.nsAffinity = affinity
    self.markedRange = markedRange
    self.selectionIsNodeOrObject = selectionIsNodeOrObject
  }

  /// Creates a native selection with LexicalTextStorageDirection affinity.
  public init(
    range: NSRange?,
    lexicalAffinity: LexicalTextStorageDirection,
    markedRange: NSRange? = nil,
    selectionIsNodeOrObject: Bool = false
  ) {
    self.range = range
    self.nsAffinity = lexicalAffinity == .backward ? .upstream : .downstream
    self.markedRange = markedRange
    self.selectionIsNodeOrObject = selectionIsNodeOrObject
  }

  /// Creates an empty selection.
  public init() {
    self.range = nil
    self.nsAffinity = .downstream
    self.markedRange = nil
    self.selectionIsNodeOrObject = false
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
  ///
  /// Note: This method sets `isUpdatingNativeSelection` to prevent the selection change
  /// from being synced back to Lexical. This is used both for reconciler-driven selection
  /// updates and for programmatic selection changes.
  public func applySelection(range: NSRange, affinity: NSSelectionAffinity = .downstream) {
    // Save current state and ensure flag is set during the update
    let wasUpdating = isUpdatingNativeSelection
    isUpdatingNativeSelection = true
    defer { isUpdatingNativeSelection = wasUpdating }

    setSelectedRange(range, affinity: affinity, stillSelecting: false)
  }

  /// Apply a selection from NativeSelectionAppKit.
  public func applySelection(_ selection: NativeSelectionAppKit) {
    guard let range = selection.range else { return }
    applySelection(range: range, affinity: selection.nsAffinity)
  }

  /// Apply a Lexical selection to the native text view.
  ///
  /// This method converts a Lexical RangeSelection to native selection coordinates
  /// and updates the text view's selection.
  ///
  /// Note: This method does NOT check `isUpdatingNativeSelection` because it's called
  /// by the reconciler to set the native selection. The `isUpdatingNativeSelection` flag
  /// is only used to prevent the `handleSelectionChange` callback from syncing the
  /// native selection back to Lexical during reconciliation.
  public func applyLexicalSelection(_ selection: RangeSelection, editor: Editor) {
    do {
      let nativeSelection = try createNativeSelectionAppKit(from: selection, editor: editor)
      if editor.featureFlags.verboseLogging {
        print("🔥 NATIVE_SEL: applyLexicalSelection anchor=\(selection.anchor.key):\(selection.anchor.offset) focus=\(selection.focus.key):\(selection.focus.offset) → native=\(nativeSelection.range?.description ?? "nil")")
      }
      applySelection(nativeSelection)
    } catch {
      if editor.featureFlags.verboseLogging {
        print("🔥 NATIVE_SEL: applyLexicalSelection FAILED: \(error)")
      }
      // Selection conversion failed - this can happen if nodes aren't in range cache yet
    }
  }
}

// MARK: - Native Selection Creation

/// Create a NativeSelectionAppKit from a Lexical RangeSelection.
///
/// This function converts Lexical selection points (node key + offset) to native
/// NSRange coordinates using the Editor's range cache.
@MainActor
public func createNativeSelectionAppKit(from selection: RangeSelection, editor: Editor) throws
  -> NativeSelectionAppKit
{
  let isBefore = try selection.anchor.isBefore(point: selection.focus)
  var affinity: LexicalTextStorageDirection = isBefore ? .forward : .backward

  if selection.anchor == selection.focus {
    affinity = .forward
  }

  let anchorLocation = try stringLocationForPoint(selection.anchor, editor: editor)
  let focusLocation = try stringLocationForPoint(selection.focus, editor: editor)

  guard let anchorLoc = anchorLocation, let focusLoc = focusLocation else {
    if editor.featureFlags.verboseLogging {
      let anchorInCache = editor.rangeCache[selection.anchor.key] != nil
      let focusInCache = editor.rangeCache[selection.focus.key] != nil
      print("🔥 NATIVE_SEL: createNativeSelectionAppKit FAILED - anchorLoc=\(anchorLocation?.description ?? "nil") focusLoc=\(focusLocation?.description ?? "nil") anchorInCache=\(anchorInCache) focusInCache=\(focusInCache)")
    }
    return NativeSelectionAppKit()
  }

  let location = isBefore ? anchorLoc : focusLoc

  return NativeSelectionAppKit(
    range: NSRange(location: location, length: abs(anchorLoc - focusLoc)),
    lexicalAffinity: affinity)
}

// MARK: - Selection Change Handling

extension TextViewAppKit {

  /// Called when the selection changes in the text view.
  ///
  /// Override point for tracking selection changes and syncing with Lexical.
  internal func handleSelectionChange() {
    if editor.featureFlags.verboseLogging {
      print("🎯 HANDLE-SEL: called, isUpdatingNativeSelection=\(isUpdatingNativeSelection)")
    }
    guard !isUpdatingNativeSelection else {
      if editor.featureFlags.verboseLogging {
        print("🎯 HANDLE-SEL: skipped due to isUpdatingNativeSelection")
      }
      return
    }

    // Get the current selection
    let selection = nativeSelection
    if editor.featureFlags.verboseLogging {
      print("🎯 HANDLE-SEL: proceeding with native range=\(selection.range?.description ?? "nil")")
    }

    // Notify Lexical about selection change
    notifyLexicalOfSelectionChange(selection)
  }

  /// Notify Lexical that the native selection has changed.
  private func notifyLexicalOfSelectionChange(_ selection: NativeSelectionAppKit) {
    guard let range = selection.range else { return }

    // Convert native range to Lexical selection points
    // This must be done inside a read block because pointAtStringLocation
    // internally uses getNodeByKey which requires an active Lexical context
    let affinity = selection.affinity
    let rangeCache = editor.rangeCache

    var anchor: Point?
    var focus: Point?

    do {
      try editor.read {
        anchor = try pointAtStringLocation(
          range.location, searchDirection: affinity, rangeCache: rangeCache)
        focus = try pointAtStringLocation(
          range.location + range.length, searchDirection: affinity, rangeCache: rangeCache)
      }
    } catch {
      // Conversion failed - this can happen if range cache is stale
      return
    }

    guard let anchor = anchor, let focus = focus else {
      return
    }

    // Apply the selection change
    try? editor.update {
      // Check if there's an existing NodeSelection - if so, preserve it
      // NodeSelection can't be represented in native selection, so we shouldn't
      // overwrite it when the native selection changes (e.g., during reconciliation)
      if let existingSelection = try? getSelection() {
        if existingSelection is NodeSelection {
          if editor.featureFlags.verboseLogging {
            print("🎯 SEL-SYNC: Preserving NodeSelection, not overwriting with RangeSelection")
          }
          // Keep the NodeSelection - don't overwrite with a RangeSelection
          return
        }
      }

      if editor.featureFlags.verboseLogging {
        let existingType = (try? getSelection()).map { String(describing: type(of: $0)) } ?? "nil"
        print("🎯 SEL-SYNC: Converting native range to RangeSelection (existing=\(existingType))")
      }

      // Get or create the RangeSelection
      if let existingSelection = try? getSelection() as? RangeSelection {
        // Update existing selection
        existingSelection.anchor.key = anchor.key
        existingSelection.anchor.offset = anchor.offset
        existingSelection.anchor.type = anchor.type
        existingSelection.focus.key = focus.key
        existingSelection.focus.offset = focus.offset
        existingSelection.focus.type = focus.type
        existingSelection.dirty = true
      } else {
        // Create new selection
        let newSelection = RangeSelection(anchor: anchor, focus: focus, format: TextFormat())
        try? setSelection(newSelection)
      }
    }

    // Dispatch selection change command so listeners are notified
    editor.dispatchCommand(type: .selectionChange, payload: nil)
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
