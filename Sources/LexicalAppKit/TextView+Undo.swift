/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import Lexical

// MARK: - Undo/Redo Support

/// Undo/redo extensions for TextViewAppKit.
///
/// NSTextView provides built-in undo support. This extension ensures proper
/// integration with Lexical's history plugin.
extension TextViewAppKit {

  // MARK: - Undo Manager

  /// The undo manager for this text view.
  ///
  /// NSTextView provides an undo manager automatically when `allowsUndo` is true.
  /// We override to potentially integrate with Lexical's history system.
  public override var undoManager: UndoManager? {
    guard allowsUndo else {
      return nil
    }

    // Use the window's undo manager if available, otherwise fall back to super
    return window?.undoManager ?? super.undoManager
  }

  // MARK: - Undo Actions

  /// Perform undo.
  @objc public func performUndo(_ sender: Any?) {
    guard allowsUndo else { return }
    undoManager?.undo()
  }

  /// Perform redo.
  @objc public func performRedo(_ sender: Any?) {
    guard allowsUndo else { return }
    undoManager?.redo()
  }

  // MARK: - Menu Validation

  /// Validate undo/redo menu items.
  public override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(performUndo(_:)) {
      return undoManager?.canUndo ?? false
    }
    if menuItem.action == #selector(performRedo(_:)) {
      return undoManager?.canRedo ?? false
    }
    return super.validateMenuItem(menuItem)
  }

  // MARK: - Undo Registration

  /// Begin an undo grouping.
  ///
  /// Call this before making multiple changes that should be undone together.
  public func beginUndoGrouping() {
    undoManager?.beginUndoGrouping()
  }

  /// End an undo grouping.
  public func endUndoGrouping() {
    undoManager?.endUndoGrouping()
  }

  /// Perform changes without registering undo.
  ///
  /// Use this for changes that shouldn't be undoable, like programmatic updates.
  public func withoutUndoRegistration(_ action: () -> Void) {
    let wasEnabled = undoManager?.isUndoRegistrationEnabled ?? false

    if wasEnabled {
      undoManager?.disableUndoRegistration()
    }

    action()

    if wasEnabled {
      undoManager?.enableUndoRegistration()
    }
  }
}

#endif // os(macOS) && !targetEnvironment(macCatalyst)
